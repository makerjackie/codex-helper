import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import SQLite3

let capacityMessage = "Selected model is at capacity. Please try a different model."
let retryPromptEnglish = "Continue the unfinished task from the failed turn. Do not repeat completed work."
let retryPromptChinese = "继续刚才因模型容量不足而中断的任务。不要重复已经完成的工作。"
let testPromptEnglish = "Codex Helper end-to-end test. Reply exactly: Codex Helper test passed."
let testPromptChinese = "这是 Codex Helper 的端到端测试。请只回复：Codex Helper 测试通过。"
let retryDelays: [TimeInterval] = [8, 20, 45, 90, 180, 300]
let attemptResetInterval: TimeInterval = 30 * 60

struct CodexThreadSummary: Equatable {
    let id: String
    let name: String
}

private struct SessionIndexEntry: Decodable {
    let id: String
    let threadName: String

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}

func parseRecentThreads(_ data: Data, limit: Int = 2_000) -> [CodexThreadSummary] {
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    let decoder = JSONDecoder()
    var seen = Set<String>()
    var results: [CodexThreadSummary] = []

    for line in text.split(separator: "\n").reversed() {
        guard let lineData = String(line).data(using: .utf8),
              let entry = try? decoder.decode(SessionIndexEntry.self, from: lineData),
              seen.insert(entry.id).inserted else { continue }
        results.append(CodexThreadSummary(
            id: entry.id,
            name: entry.threadName
        ))
        if results.count == limit { break }
    }
    return results
}

private let codexComposerPlaceholders: Set<String> = [
    "Ask for follow-up changes",
    "Ask for follow up changes or @ to tag an agent",
    "要求后续变更",
    "要求提供后续变更或 @ 提及智能体",
    "要求後續跟進變更",
    "要求後續跟進變更或 @ 以標記代理程式"
]

func isCodexComposerEffectivelyEmpty(_ value: String) -> Bool {
    let normalized = value
        .replacingOccurrences(of: "\u{200B}", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty || codexComposerPlaceholders.contains(normalized)
}

private struct CursorState: Codable {
    var fileID: UInt64?
    var offset: UInt64
}

private struct RetryState: Codable {
    var attempts: Int
    var lastErrorAt: Date
    var generation: Int
}

private struct PersistedState: Codable {
    var cursor = CursorState(fileID: nil, offset: 0)
    var databaseFileID: UInt64?
    var databaseCursor: Int64?
    var retries: [String: RetryState] = [:]
}

struct CapacityFailure: Equatable {
    let threadID: String
    let timestamp: Date
}

func parseCapacityFailureLine(_ line: String) -> CapacityFailure? {
    guard line.contains("Turn error: \(capacityMessage)"),
          let threadRange = line.range(of: #"thread_id=[0-9a-fA-F-]{36}"#, options: .regularExpression) else {
        return nil
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let threadID = String(line[threadRange]).replacingOccurrences(of: "thread_id=", with: "")
    let timestampText = String(line.prefix(while: { !$0.isWhitespace }))
    let timestamp = formatter.date(from: timestampText) ?? Date()
    return CapacityFailure(threadID: threadID, timestamp: timestamp)
}

func parseCapacityFailureRecord(_ body: String, threadID: String?, timestamp: Date) -> CapacityFailure? {
    guard body.contains("Turn error: \(capacityMessage)") else { return nil }

    if let threadID, threadID.range(of: #"^[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil {
        return CapacityFailure(threadID: threadID, timestamp: timestamp)
    }

    let patterns = [#"thread\.id=[0-9a-fA-F-]{36}"#, #"thread_id=[0-9a-fA-F-]{36}"#]
    for pattern in patterns {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = expression.matches(in: body, range: range).last,
              let matchRange = Range(match.range, in: body) else { continue }
        let token = String(body[matchRange])
        guard let separator = token.firstIndex(of: "=") else { continue }
        return CapacityFailure(threadID: String(token[token.index(after: separator)...]), timestamp: timestamp)
    }
    return nil
}

private struct SessionBaseline {
    let path: URL?
    let offset: UInt64
}

func containsNewTurnActivity(_ text: String) -> Bool {
    text.contains(#""type":"user_message""#)
        || text.contains(#""type": "user_message""#)
        || text.contains(#""type":"task_started""#)
        || text.contains(#""type": "task_started""#)
}

final class AgentLogger {
    private let formatter = ISO8601DateFormatter()
    private let logURL: URL
    private let fileManager = FileManager.default

    init(logURL: URL) {
        self.logURL = logURL
    }

    func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        try? fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
        FileHandle.standardError.write(data)
    }
}

final class AutoRetryAgent {
    private let configStore: ConfigStore
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private lazy var codexHome = home.appendingPathComponent(".codex", isDirectory: true)
    private lazy var logURL = codexHome.appendingPathComponent("log/codex-tui.log")
    private lazy var sessionIndexURL = codexHome.appendingPathComponent("session_index.jsonl")
    private lazy var sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
    private lazy var stateURL = configStore.supportURL.appendingPathComponent("state.json")
    private lazy var logger = AgentLogger(logURL: configStore.supportURL.appendingPathComponent("agent.log"))
    private var state = PersistedState()
    private var partialLine = ""
    private var lastDatabaseCursorSaveAt = Date.distantPast
    private var pollTimer: Timer?
    private var isRunning = false

    var onActivityChange: (() -> Void)?
    private(set) var activity: AutoRetryActivity = .watching {
        didSet {
            guard activity != oldValue else { return }
            onActivityChange?()
        }
    }

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    var running: Bool { isRunning }
    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func recentVisibleThreads(limit: Int = 2_000) -> [CodexThreadSummary] {
        guard let data = try? Data(contentsOf: sessionIndexURL) else { return [] }
        return parseRecentThreads(data, limit: limit)
    }

    @discardableResult
    func runEndToEndTest(threadID: String, completion: @escaping (Bool, String) -> Void) -> Bool {
        let syntheticLine = "\(ISO8601DateFormatter().string(from: Date())) INFO session_loop{thread_id=\(threadID)}: codex_core::session::turn: Turn error: \(capacityMessage)"
        guard accessibilityGranted,
              let failure = parseCapacityFailureLine(syntheticLine),
              isVisibleRootThread(failure.threadID) else { return false }
        let baseline = sessionBaseline(for: failure.threadID)
        guard baseline.path != nil else { return false }
        logger.write("synthetic capacity failure identified \(failure.threadID); scheduled end-to-end test in 3s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            guard !self.hasNewActivity(since: baseline) else {
                self.logger.write("cancelled end-to-end test for \(failure.threadID): newer user or turn activity detected")
                completion(false, "newActivity")
                return
            }
            self.submitPrompt(
                threadID: failure.threadID,
                prompt: self.localizedTestPrompt(),
                logDescription: "end-to-end test",
                requiresAgentRunning: false,
                activityBaseline: baseline,
                completion: completion
            )
        }
        return true
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        activity = .watching
        loadState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
        logger.write("auto retry started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        for threadID in state.retries.keys {
            state.retries[threadID]?.generation += 1
        }
        saveState()
        logger.write("auto retry stopped")
    }

    func promptForAccessibility() {
        guard ProcessInfo.processInfo.environment["CODEX_HELPER_DISABLE_ACCESSIBILITY_PROMPTS"] != "1" else {
            logger.write("Accessibility prompt suppressed by test environment")
            return
        }
        requestAccessibilityPermission()
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            logger.write("Accessibility permission is required; waiting for approval in System Settings")
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        state = decoded
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let temporaryURL = stateURL.appendingPathExtension("tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            _ = try fileManager.replaceItemAt(stateURL, withItemAt: temporaryURL)
        } catch {
            do {
                try data.write(to: stateURL, options: .atomic)
                try? fileManager.removeItem(at: temporaryURL)
            } catch {
                logger.write("failed to save state: \(error.localizedDescription)")
            }
        }
    }

    private func poll() {
        guard isRunning else { return }
        pollDatabase()
        pollLegacyLog()
    }

    private func pollLegacyLog() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return
        }

        let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let size = sizeNumber.uint64Value

        if state.cursor.fileID == nil {
            state.cursor = CursorState(fileID: fileID, offset: size)
            saveState()
            return
        }

        if state.cursor.fileID != fileID || size < state.cursor.offset {
            state.cursor = CursorState(fileID: fileID, offset: 0)
            partialLine = ""
        }

        guard size > state.cursor.offset,
              let handle = try? FileHandle(forReadingFrom: logURL) else {
            return
        }

        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: state.cursor.offset)
            let data = try handle.readToEnd() ?? Data()
            state.cursor.offset += UInt64(data.count)
            saveState()
            consume(data)
        } catch {
            logger.write("failed to read Codex log: \(error.localizedDescription)")
        }
    }

    private func pollDatabase() {
        guard let databaseURL = currentLogsDatabase(),
              let attributes = try? fileManager.attributesOfItem(atPath: databaseURL.path),
              let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let database = openReadOnlyDatabase(at: databaseURL) else { return }
        defer { sqlite3_close(database) }

        guard let highWatermark = databaseHighWatermark(database) else { return }
        if state.databaseFileID == nil {
            state.databaseFileID = fileID
            state.databaseCursor = highWatermark
            lastDatabaseCursorSaveAt = Date()
            saveState()
            logger.write("monitoring current Codex event database \(databaseURL.lastPathComponent)")
            return
        }
        if state.databaseFileID != fileID || highWatermark < (state.databaseCursor ?? 0) {
            state.databaseFileID = fileID
            state.databaseCursor = 0
        }

        let cursor = state.databaseCursor ?? highWatermark
        guard highWatermark > cursor else { return }
        let failures = databaseCapacityFailures(database, after: cursor, through: highWatermark)
        state.databaseCursor = highWatermark

        let now = Date()
        if !failures.isEmpty || now.timeIntervalSince(lastDatabaseCursorSaveAt) >= 60 {
            lastDatabaseCursorSaveAt = now
            saveState()
        }
        for failure in failures {
            handle(failure)
        }
    }

    private func currentLogsDatabase() -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return urls.compactMap { url -> (URL, Int)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("logs_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst(5).dropLast(7)) else { return nil }
            return (url, version)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private func openReadOnlyDatabase(at url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        sqlite3_busy_timeout(database, 150)
        return database
    }

    private func databaseHighWatermark(_ database: OpaquePointer) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COALESCE(MAX(id), 0) FROM logs", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func databaseCapacityFailures(
        _ database: OpaquePointer,
        after cursor: Int64,
        through highWatermark: Int64
    ) -> [CapacityFailure] {
        let sql = """
        SELECT ts, thread_id, feedback_log_body
        FROM logs
        WHERE id > ? AND id <= ? AND target = 'codex_core::session::turn'
        ORDER BY id ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cursor)
        sqlite3_bind_int64(statement, 2, highWatermark)

        var failures: [CapacityFailure] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bodyPointer = sqlite3_column_text(statement, 2) else { continue }
            let body = String(cString: bodyPointer)
            let threadID = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0)))
            if let failure = parseCapacityFailureRecord(body, threadID: threadID, timestamp: timestamp) {
                failures.append(failure)
            }
        }
        return failures
    }

    private func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let combined = partialLine + text
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        partialLine = combined.hasSuffix("\n") ? "" : String(lines.last ?? "")
        let completedLines = combined.hasSuffix("\n") ? lines : lines.dropLast()

        for rawLine in completedLines {
            if let failure = parseCapacityFailureLine(String(rawLine)) {
                handle(failure)
            }
        }
    }

    private func handle(_ failure: CapacityFailure) {
        guard isVisibleRootThread(failure.threadID) else {
            logger.write("ignored non-root or hidden thread \(failure.threadID)")
            return
        }

        if let existing = state.retries[failure.threadID],
           abs(failure.timestamp.timeIntervalSince(existing.lastErrorAt)) < 1 {
            logger.write("ignored duplicate capacity failure for \(failure.threadID)")
            return
        }

        var retryState = state.retries[failure.threadID] ?? RetryState(attempts: 0, lastErrorAt: failure.timestamp, generation: 0)
        if failure.timestamp.timeIntervalSince(retryState.lastErrorAt) > attemptResetInterval {
            retryState.attempts = 0
        }

        guard retryState.attempts < retryDelays.count else {
            logger.write("retry limit reached for \(failure.threadID)")
            return
        }

        let attempt = retryState.attempts + 1
        let delay = retryDelays[retryState.attempts]
        retryState.attempts = attempt
        retryState.lastErrorAt = failure.timestamp
        retryState.generation += 1
        let generation = retryState.generation
        state.retries[failure.threadID] = retryState
        saveState()

        let baseline = sessionBaseline(for: failure.threadID)
        logger.write("scheduled retry \(attempt)/\(retryDelays.count) for \(failure.threadID) in \(Int(delay))s")
        activity = .scheduled(attempt: attempt, delaySeconds: Int(delay))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.isRunning,
                  self.state.retries[failure.threadID]?.generation == generation else {
                return
            }
            if self.hasNewActivity(since: baseline) {
                self.logger.write("cancelled retry for \(failure.threadID): newer user or turn activity detected")
                self.activity = .cancelledForNewActivity
                self.state.retries.removeValue(forKey: failure.threadID)
                self.saveState()
                return
            }
            self.submitRetry(threadID: failure.threadID, attempt: attempt, activityBaseline: baseline)
        }
    }

    private func isVisibleRootThread(_ threadID: String) -> Bool {
        guard let data = try? Data(contentsOf: sessionIndexURL),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains("\"id\":\"\(threadID)\"") || text.contains("\"id\": \"\(threadID)\"")
    }

    private func sessionBaseline(for threadID: String) -> SessionBaseline {
        guard let path = findSessionFile(threadID: threadID),
              let attributes = try? fileManager.attributesOfItem(atPath: path.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return SessionBaseline(path: nil, offset: 0)
        }
        return SessionBaseline(path: path, offset: size)
    }

    private func findSessionFile(threadID: String) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator where url.lastPathComponent.contains(threadID) && url.pathExtension == "jsonl" {
            return url
        }
        return nil
    }

    private func hasNewActivity(since baseline: SessionBaseline) -> Bool {
        guard let path = baseline.path,
              let handle = try? FileHandle(forReadingFrom: path) else {
            return false
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: baseline.offset)
            guard let data = try handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else {
                return false
            }
            return containsNewTurnActivity(text)
        } catch {
            logger.write("failed to inspect session activity: \(error.localizedDescription)")
            return false
        }
    }

    private func submitRetry(threadID: String, attempt: Int, activityBaseline: SessionBaseline) {
        submitPrompt(
            threadID: threadID,
            prompt: localizedRetryPrompt(),
            logDescription: "retry \(attempt)/\(retryDelays.count)",
            requiresAgentRunning: true,
            activityBaseline: activityBaseline,
            retryAttempt: attempt,
            completion: nil
        )
    }

    private func submitPrompt(
        threadID: String,
        prompt: String,
        logDescription: String,
        requiresAgentRunning: Bool,
        activityBaseline: SessionBaseline,
        retryAttempt: Int? = nil,
        completion: ((Bool, String) -> Void)?
    ) {
        guard AXIsProcessTrusted() else {
            logger.write("cannot submit \(logDescription) for \(threadID): Accessibility permission has not been granted")
            if retryAttempt != nil { activity = .submissionBlocked }
            completion?(false, "accessibility")
            return
        }

        let previousApplication = NSWorkspace.shared.frontmostApplication
        guard let url = URL(string: "codex://threads/\(threadID)") else {
            completion?(false, "invalidTask")
            return
        }
        NSWorkspace.shared.open(url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self, !requiresAgentRunning || self.isRunning else { return }
            guard let codex = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
                self.logger.write("cancelled \(logDescription) for \(threadID): Codex is not running")
                if retryAttempt != nil { self.activity = .submissionBlocked }
                completion?(false, "codexNotRunning")
                return
            }
            codex.activate(options: [.activateAllWindows])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                guard !requiresAgentRunning || self.isRunning else { return }
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" else {
                    self.logger.write("cancelled \(logDescription) for \(threadID): Codex did not become the frontmost app")
                    if retryAttempt != nil { self.activity = .submissionBlocked }
                    completion?(false, "codexNotFrontmost")
                    return
                }
                guard !self.hasNewActivity(since: activityBaseline) else {
                    self.logger.write("cancelled \(logDescription) for \(threadID): newer user or turn activity detected")
                    if retryAttempt != nil { self.activity = .cancelledForNewActivity }
                    completion?(false, "newActivity")
                    return
                }
                self.postKey(code: 53, to: codex.processIdentifier)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard (!requiresAgentRunning || self.isRunning),
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" else {
                        self.logger.write("cancelled \(logDescription) for \(threadID): focus left Codex before submission")
                        if retryAttempt != nil { self.activity = .submissionBlocked }
                        completion?(false, "focusChanged")
                        return
                    }
                    guard let targetWindow = self.targetTaskWindow(threadID: threadID, processID: codex.processIdentifier) else {
                        self.logger.write("cancelled \(logDescription) for \(threadID): target task selection could not be verified")
                        if retryAttempt != nil { self.activity = .submissionBlocked }
                        completion?(false, "targetNotSelected")
                        return
                    }
                    let preparation = self.preparePrompt(prompt, in: targetWindow, processID: codex.processIdentifier)
                    guard case let .ready(composer) = preparation else {
                        switch preparation {
                        case .notEmpty:
                            self.logger.write("cancelled \(logDescription) for \(threadID): target composer contains a draft")
                            if retryAttempt != nil { self.activity = .pausedForDraft }
                            completion?(false, "composerNotEmpty")
                        case .notFound:
                            self.logger.write("cancelled \(logDescription) for \(threadID): target Codex composer was not found")
                            if retryAttempt != nil { self.activity = .submissionBlocked }
                            completion?(false, "composerNotFound")
                        case .writeFailed:
                            self.logger.write("cancelled \(logDescription) for \(threadID): target Codex composer could not be controlled")
                            if retryAttempt != nil { self.activity = .submissionBlocked }
                            completion?(false, "composerWriteFailed")
                        case .ready:
                            break
                        }
                        return
                    }
                    guard !self.hasNewActivity(since: activityBaseline) else {
                        AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, "" as CFString)
                        self.logger.write("cancelled \(logDescription) for \(threadID): newer activity appeared before submission")
                        if retryAttempt != nil { self.activity = .cancelledForNewActivity }
                        completion?(false, "newActivity")
                        return
                    }
                    self.postKey(code: 36, to: codex.processIdentifier)
                    self.logger.write("submitted \(logDescription) for \(threadID)")
                    if let retryAttempt { self.activity = .submitted(attempt: retryAttempt) }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let confirmed = self.sessionContains(prompt, since: activityBaseline)
                        if confirmed {
                            self.logger.write("confirmed \(logDescription) in target task \(threadID)")
                        } else {
                            self.logger.write("could not confirm \(logDescription) in target task \(threadID)")
                        }
                        completion?(confirmed, confirmed ? "passed" : "targetNotConfirmed")
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if let previousApplication, previousApplication.bundleIdentifier != "com.openai.codex" {
                            previousApplication.activate(options: [])
                        }
                    }
                }
            }
        }
    }

    private func localizedRetryPrompt() -> String {
        configStore.isChinese() ? retryPromptChinese : retryPromptEnglish
    }

    private func localizedTestPrompt() -> String {
        configStore.isChinese() ? testPromptChinese : testPromptEnglish
    }

    private func postKey(code: CGKeyCode, to processID: pid_t) {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(processID)
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(processID)
    }

    private enum ComposerPreparation {
        case ready(AXUIElement)
        case notFound
        case notEmpty
        case writeFailed
    }

    private func preparePrompt(_ prompt: String, in targetWindow: AXUIElement, processID: pid_t) -> ComposerPreparation {
        var visited = 0
        guard let composer = findComposer(in: targetWindow, visited: &visited) else { return .notFound }

        var existingValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(composer, kAXValueAttribute as CFString, &existingValue) == .success,
              let existing = existingValue as? String else { return .writeFailed }
        guard isCodexComposerEffectivelyEmpty(existing) else { return .notEmpty }

        let application = AXUIElementCreateApplication(processID)
        guard AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
              AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, prompt as CFString) == .success else {
            return .writeFailed
        }

        var focusedValue: CFTypeRef?
        var verificationValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        let valueResult = AXUIElementCopyAttributeValue(composer, kAXValueAttribute as CFString, &verificationValue)
        guard focusedResult == .success,
              let focused = axElement(from: focusedValue),
              CFEqual(focused, composer),
              valueResult == .success,
              (verificationValue as? String) == prompt else {
            AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, "" as CFString)
            return .writeFailed
        }
        return .ready(composer)
    }

    private func findComposer(in element: AXUIElement, visited: inout Int) -> AXUIElement? {
        guard visited < 12_000 else { return nil }
        visited += 1

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           (roleValue as? String) == kAXTextAreaRole,
           hasComposerSurfaceAncestor(element) {
            return element
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        for child in children {
            if let composer = findComposer(in: child, visited: &visited) { return composer }
        }
        return nil
    }

    private func hasComposerSurfaceAncestor(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<8 {
            var classesValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, "AXDOMClassList" as CFString, &classesValue) == .success,
               let classes = classesValue as? [String],
               classes.contains("composer-surface-chrome") {
                return true
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = axElement(from: parentValue) else { return false }
            current = parent
        }
        return false
    }

    private func targetTaskWindow(threadID: String, processID: pid_t) -> AXUIElement? {
        let threads = recentVisibleThreads(limit: 2_000)
        guard let target = threads.first(where: { $0.id == threadID }),
              threads.filter({ $0.name == target.name }).count == 1 else { return nil }

        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        var visited = 0
        guard let selectedTask = findSelectedTask(named: target.name, in: application, visited: &visited) else { return nil }
        return containingWindow(of: selectedTask)
    }

    private func findSelectedTask(named targetName: String, in element: AXUIElement, visited: inout Int) -> AXUIElement? {
        guard visited < 12_000 else { return nil }
        visited += 1

        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           (value as? String) == targetName,
           let selectedTask = selectedTaskButton(from: element) {
            return selectedTask
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        for child in children {
            if let selectedTask = findSelectedTask(named: targetName, in: child, visited: &visited) { return selectedTask }
        }
        return nil
    }

    private func containingWindow(of element: AXUIElement) -> AXUIElement? {
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
           let window = axElement(from: windowValue) {
            return window
        }

        var current = element
        for _ in 0..<16 {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
               (roleValue as? String) == kAXWindowRole {
                return current
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = axElement(from: parentValue) else { return nil }
            current = parent
        }
        return nil
    }

    private func selectedTaskButton(from element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<4 {
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = axElement(from: parentValue) else { return nil }
            current = parent

            var roleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
                  (roleValue as? String) == kAXButtonRole else { continue }
            var classesValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, "AXDOMClassList" as CFString, &classesValue) == .success,
                  let classes = classesValue as? [String],
                  classes.contains("bg-token-list-hover-background") else { continue }
            return current
        }
        return nil
    }

    private func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func sessionContains(_ expected: String, since baseline: SessionBaseline) -> Bool {
        guard let path = baseline.path,
              let handle = try? FileHandle(forReadingFrom: path) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: baseline.offset)
            guard let data = try handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { return false }
            return text.contains(expected)
        } catch {
            return false
        }
    }
}

func runSelfTest() -> Int32 {
    let sample = "2026-07-13T12:00:00.123456Z INFO session_loop{thread_id=019f59b0-c8ec-7cf1-88be-4e6247938d01}: Turn error: \(capacityMessage)"
    let failure = parseCapacityFailureLine(sample)
    let databaseFailure = parseCapacityFailureRecord(
        "turn{thread.id=019f6017-6542-7c50-a6b9-b87406def81a}:run_turn: Turn error: \(capacityMessage)",
        threadID: nil,
        timestamp: Date(timeIntervalSince1970: 100)
    )
    let activity = #"{"type":"event_msg","payload":{"type":"user_message"}}"#
    let legacyConfig = #"{"language":"zh"}"#.data(using: .utf8)!
    let decodedConfig = try? JSONDecoder().decode(AgentConfig.self, from: legacyConfig)
    let hiddenQuotaConfig = #"{"showQuotaInMenuBar":false}"#.data(using: .utf8)!
    let decodedHiddenQuotaConfig = try? JSONDecoder().decode(AgentConfig.self, from: hiddenQuotaConfig)
    let widgetConfig = #"{"showQuotaWidget":true}"#.data(using: .utf8)!
    let decodedWidgetConfig = try? JSONDecoder().decode(AgentConfig.self, from: widgetConfig)
    let sparkConfig = #"{"showSparkQuota":true}"#.data(using: .utf8)!
    let decodedSparkConfig = try? JSONDecoder().decode(AgentConfig.self, from: sparkConfig)
    let widgetSnapshot = WidgetQuotaSnapshot(
        windows: [
            WidgetQuotaWindow(
                id: "codex-primary",
                name: "Codex",
                planType: "pro",
                remainingPercent: 77,
                windowDurationMins: 10080,
                resetsAt: Date(timeIntervalSince1970: 1784508971)
            )
        ],
        resetCredits: 1,
        fetchedAt: Date(timeIntervalSince1970: 0)
    )
    let widgetSnapshotRoundTrip = try? JSONDecoder().decode(
        WidgetQuotaSnapshot.self,
        from: JSONEncoder().encode(widgetSnapshot)
    )
    let index = """
    {"id":"019f59b0-c8ec-7cf1-88be-4e6247938d01","thread_name":"Older name","updated_at":"2026-07-13T04:00:00.000000Z"}
    {"id":"019f59b0-c8ec-7cf1-88be-4e6247938d01","thread_name":"Latest name","updated_at":"2026-07-13T04:16:59.439270Z"}
    {"id":"019f59e7-fec8-70a1-a8fa-2edd3c02ed67","thread_name":"Another task","updated_at":"2026-07-13T05:36:24.477262Z"}
    """.data(using: .utf8)!
    let threads = parseRecentThreads(index)
    let changelog = """
    <rss><channel><item><title>Codex release</title><link>https://developers.openai.com/codex-release</link><pubDate>Sun, 13 Jul 2026 10:00:00 +0000</pubDate></item></channel></rss>
    """.data(using: .utf8)!
    let news = """
    <rss><channel>
      <item><title><![CDATA[Codex news]]></title><link>https://openai.com/codex-news</link><description><![CDATA[Codex update]]></description></item>
      <item><title><![CDATA[Unrelated news]]></title><link>https://openai.com/other</link><description><![CDATA[Other product]]></description></item>
      <item><title><![CDATA[Unsafe Codex link]]></title><link>file:///tmp/not-allowed</link><description><![CDATA[Codex update]]></description></item>
    </channel></rss>
    """.data(using: .utf8)!
    let updates = parseCodexUpdates(changelogData: changelog, newsData: news)
    let usageData = """
    {"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":15,"windowDurationMins":10080,"resetsAt":1784508971},"secondary":null,"planType":"pro"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":15,"windowDurationMins":10080,"resetsAt":1784508971},"secondary":null,"planType":"pro"}},"rateLimitResetCredits":{"availableCount":1}}
    """.data(using: .utf8)!
    let usage = makeUsageSnapshot(from: usageData, fetchedAt: Date(timeIntervalSince1970: 0))
    let sparseUsageData = """
    {"rateLimits":{},"rateLimitsByLimitId":{"spark":{"limitId":null,"limitName":"Spark","primary":{"usedPercent":0,"windowDurationMins":null,"resetsAt":null}}}}
    """.data(using: .utf8)!
    let sparseUsage = makeUsageSnapshot(from: sparseUsageData, fetchedAt: Date(timeIntervalSince1970: 0))
    let checksumData = Data("codex-helper".utf8)
    let checksum = SHA256.hash(data: checksumData).map { String(format: "%02x", $0) }.joined()
    guard failure?.threadID == "019f59b0-c8ec-7cf1-88be-4e6247938d01",
          databaseFailure == CapacityFailure(
              threadID: "019f6017-6542-7c50-a6b9-b87406def81a",
              timestamp: Date(timeIntervalSince1970: 100)
          ),
          containsNewTurnActivity(activity),
          decodedConfig == AgentConfig(language: "zh"),
          decodedHiddenQuotaConfig?.showQuotaInMenuBar == false,
          decodedWidgetConfig?.showQuotaWidget == true,
          decodedSparkConfig?.showSparkQuota == true,
          widgetSnapshotRoundTrip == widgetSnapshot,
          threads.count == 2,
          threads[0].name == "Another task",
          threads[1].name == "Latest name",
          updates.count == 2,
          updates.contains(where: { $0.title == "Codex release" }),
          updates.contains(where: { $0.title == "Codex news" }),
          usage?.limits.first?.primary?.usedPercent == 15,
          CodexUsageWindow(usedPercent: 23, windowDurationMins: nil, resetsAt: nil).remainingPercent == 77,
          CodexUsageWindow(usedPercent: -5, windowDurationMins: nil, resetsAt: nil).remainingPercent == 100,
          CodexUsageWindow(usedPercent: 105, windowDurationMins: nil, resetsAt: nil).remainingPercent == 0,
          quotaLevel(for: 50) == .healthy,
          quotaLevel(for: 49.9) == .attention,
          quotaLevel(for: 10) == .attention,
          quotaLevel(for: 9.9) == .critical,
          quotaLevel(for: nil) == .unavailable,
          formatCompactResetDistance(
              until: Date(timeIntervalSince1970: 100_000),
              from: Date(timeIntervalSince1970: 10_000),
              isChinese: true
          ) == "1天1时",
          formatResetCountdown(
              until: Date(timeIntervalSince1970: 13_661),
              from: Date(timeIntervalSince1970: 10_000),
              isChinese: true
          ) == "01:01:01",
          usage?.resetCredits == 1,
          sparseUsage?.limits.first?.id == "spark",
          sparseUsage?.limits.first?.primary?.windowDurationMins == nil,
          sparseUsage?.limits.first?.primary?.resetsAt == nil,
          visibleUsageLimits(sparseUsage?.limits ?? [], showSparkQuota: false).isEmpty,
          visibleUsageLimits(sparseUsage?.limits ?? [], showSparkQuota: true).count == 1,
          isVersion("0.3.0", newerThan: "0.2.9"),
          !isVersion("0.2.0", newerThan: "0.2.0"),
          checksumMatches(data: checksumData, checksumText: "\(checksum)  Codex-Helper.dmg"),
          isCodexComposerEffectivelyEmpty("\nAsk for follow-up changes"),
          isCodexComposerEffectivelyEmpty("要求后续变更"),
          !isCodexComposerEffectivelyEmpty("另外帮我做"),
          !retryPromptEnglish.isEmpty,
          !retryPromptChinese.isEmpty,
          !testPromptEnglish.isEmpty,
          !testPromptChinese.isEmpty,
          retryDelays.count == 6 else {
        FileHandle.standardError.write(Data("self-test failed\n".utf8))
        return 1
    }
    FileHandle.standardOutput.write(Data("self-test passed\n".utf8))
    return 0
}
