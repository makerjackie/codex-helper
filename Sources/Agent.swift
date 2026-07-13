import AppKit
import ApplicationServices
import Foundation

let capacityMessage = "Selected model is at capacity. Please try a different model."
let retryPromptEnglish = "Continue the unfinished task from the failed turn. Do not repeat completed work."
let retryPromptChinese = "继续刚才因模型容量不足而中断的任务。不要重复已经完成的工作。"
let retryDelays: [TimeInterval] = [8, 20, 45, 90, 180, 300]
let attemptResetInterval: TimeInterval = 30 * 60

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
    var retries: [String: RetryState] = [:]
}

private struct CapacityFailure {
    let threadID: String
    let timestamp: Date
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
    private var pollTimer: Timer?
    private var isRunning = false
    private let timestampFormatter = ISO8601DateFormatter()

    init(configStore: ConfigStore) {
        self.configStore = configStore
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    var running: Bool { isRunning }
    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        loadState()
        requestAccessibilityPermission()
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
        guard isRunning,
              let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
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

    private func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let combined = partialLine + text
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        partialLine = combined.hasSuffix("\n") ? "" : String(lines.last ?? "")
        let completedLines = combined.hasSuffix("\n") ? lines : lines.dropLast()

        for rawLine in completedLines {
            if let failure = parseCapacityFailure(String(rawLine)) {
                handle(failure)
            }
        }
    }

    private func parseCapacityFailure(_ line: String) -> CapacityFailure? {
        guard line.contains("Turn error: \(capacityMessage)"),
              let threadRange = line.range(of: #"thread_id=[0-9a-fA-F-]{36}"#, options: .regularExpression) else {
            return nil
        }

        let threadID = String(line[threadRange]).replacingOccurrences(of: "thread_id=", with: "")
        let timestampText = String(line.prefix(while: { !$0.isWhitespace }))
        let timestamp = timestampFormatter.date(from: timestampText) ?? Date()
        return CapacityFailure(threadID: threadID, timestamp: timestamp)
    }

    private func handle(_ failure: CapacityFailure) {
        guard isVisibleRootThread(failure.threadID) else {
            logger.write("ignored non-root or hidden thread \(failure.threadID)")
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

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.isRunning,
                  self.state.retries[failure.threadID]?.generation == generation else {
                return
            }
            if self.hasNewActivity(since: baseline) {
                self.logger.write("cancelled retry for \(failure.threadID): newer user or turn activity detected")
                self.state.retries.removeValue(forKey: failure.threadID)
                self.saveState()
                return
            }
            self.submitRetry(threadID: failure.threadID, attempt: attempt)
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

    private func submitRetry(threadID: String, attempt: Int) {
        guard AXIsProcessTrusted() else {
            logger.write("cannot retry \(threadID): Accessibility permission has not been granted")
            return
        }

        let previousApplication = NSWorkspace.shared.frontmostApplication
        guard let url = URL(string: "codex://threads/\(threadID)") else { return }
        NSWorkspace.shared.open(url)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isRunning else { return }
            guard let codex = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
                self.logger.write("cancelled retry for \(threadID): Codex is not running")
                return
            }
            codex.activate(options: [.activateAllWindows])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard self.isRunning,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" else {
                    self.logger.write("cancelled retry for \(threadID): Codex did not become the frontmost app")
                    return
                }
                self.postKey(code: 53, to: codex.processIdentifier)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard self.isRunning,
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" else {
                        self.logger.write("cancelled retry for \(threadID): focus left Codex before submission")
                        return
                    }
                    self.postText(self.localizedRetryPrompt(), to: codex.processIdentifier)
                    self.postKey(code: 36, to: codex.processIdentifier)
                    self.logger.write("submitted retry \(attempt)/\(retryDelays.count) for \(threadID)")

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

    private func postKey(code: CGKeyCode, to processID: pid_t) {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(processID)
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(processID)
    }

    private func postText(_ text: String, to processID: pid_t) {
        let utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            return
        }
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.postToPid(processID)
        up.postToPid(processID)
    }
}

func runSelfTest() -> Int32 {
    let sample = "2026-07-13T12:00:00.123456Z INFO session_loop{thread_id=019f59b0-c8ec-7cf1-88be-4e6247938d01}: Turn error: \(capacityMessage)"
    let threadMatch = sample.range(of: #"thread_id=[0-9a-fA-F-]{36}"#, options: .regularExpression)
    let activity = #"{"type":"event_msg","payload":{"type":"user_message"}}"#
    let legacyConfig = #"{"language":"zh"}"#.data(using: .utf8)!
    let decodedConfig = try? JSONDecoder().decode(AgentConfig.self, from: legacyConfig)
    guard threadMatch != nil,
          sample.contains("Turn error: \(capacityMessage)"),
          containsNewTurnActivity(activity),
          decodedConfig == AgentConfig(language: "zh"),
          !retryPromptEnglish.isEmpty,
          !retryPromptChinese.isEmpty,
          retryDelays.count == 6 else {
        FileHandle.standardError.write(Data("self-test failed\n".utf8))
        return 1
    }
    FileHandle.standardOutput.write(Data("self-test passed\n".utf8))
    return 0
}
