import AppKit
import Foundation

struct CodexUsageWindow: Codable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Date?
}

struct CodexUsageLimit: Codable, Equatable {
    let id: String
    let name: String
    let planType: String?
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?
}

struct CodexUsageSnapshot: Codable, Equatable {
    let limits: [CodexUsageLimit]
    let resetCredits: Int
    let fetchedAt: Date
}

enum CodexUsageStatus: Equatable {
    case idle
    case loading
    case available(CodexUsageSnapshot)
    case unavailable(String)
}

private struct RateLimitsResult: Decodable {
    let rateLimitsByLimitId: [String: RateLimitPayload]?
    let rateLimits: RateLimitPayload?
    let rateLimitResetCredits: ResetCreditsPayload?
}

private struct RateLimitPayload: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: UsageWindowPayload?
    let secondary: UsageWindowPayload?
    let planType: String?
}

private struct UsageWindowPayload: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

private struct ResetCreditsPayload: Decodable {
    let availableCount: Int
}

func makeUsageSnapshot(from data: Data, fetchedAt: Date = Date()) -> CodexUsageSnapshot? {
    guard let result = try? JSONDecoder().decode(RateLimitsResult.self, from: data) else { return nil }
    var payloads = result.rateLimitsByLimitId ?? [:]
    if let main = result.rateLimits,
       main.limitId != nil || main.limitName != nil || main.planType != nil || main.primary != nil || main.secondary != nil {
        let mainID = main.limitId ?? "codex"
        if payloads[mainID] == nil {
            payloads[mainID] = main
        }
    }

    let limits = payloads.map { dictionaryID, payload in
        let limitID = payload.limitId ?? dictionaryID
        return CodexUsageLimit(
            id: limitID,
            name: payload.limitName ?? (limitID == "codex" ? "Codex" : limitID),
            planType: payload.planType,
            primary: payload.primary.map(makeUsageWindow),
            secondary: payload.secondary.map(makeUsageWindow)
        )
    }.sorted { left, right in
        if left.id == "codex" { return true }
        if right.id == "codex" { return false }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    guard !limits.isEmpty else { return nil }
    return CodexUsageSnapshot(
        limits: limits,
        resetCredits: result.rateLimitResetCredits?.availableCount ?? 0,
        fetchedAt: fetchedAt
    )
}

private func makeUsageWindow(_ payload: UsageWindowPayload) -> CodexUsageWindow {
    CodexUsageWindow(
        usedPercent: payload.usedPercent,
        windowDurationMins: payload.windowDurationMins,
        resetsAt: payload.resetsAt.map(Date.init(timeIntervalSince1970:))
    )
}

final class CodexUsageService {
    var onChange: (() -> Void)?
    private(set) var status: CodexUsageStatus = .idle
    private(set) var snapshot: CodexUsageSnapshot?

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var initialized = false
    private var refreshPending = false
    private var nextRequestID = 2
    private var refreshRequestIDs = Set<Int>()
    private var refreshTimer: Timer?

    func start() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        shutdownProcess()
    }

    func refresh() {
        if process?.isRunning != true {
            launchProcess()
            refreshPending = true
            return
        }
        guard initialized else {
            refreshPending = true
            return
        }

        status = .loading
        onChange?()
        let requestID = nextRequestID
        nextRequestID += 1
        refreshRequestIDs.insert(requestID)
        send(["id": requestID, "method": "account/rateLimits/read", "params": [:] as [String: Any]])
    }

    private func launchProcess() {
        guard let executable = findCodexExecutable() else {
            updateStatus(.unavailable("Codex CLI not found"))
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process === process else { return }
                self.shutdownProcess()
                if case .available = self.status { return }
                self.updateStatus(.unavailable("Codex usage service stopped"))
            }
        }

        do {
            try process.run()
            self.process = process
            inputHandle = input.fileHandleForWriting
            outputBuffer.removeAll(keepingCapacity: true)
            initialized = false
            status = .loading
            onChange?()
            send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-helper",
                        "title": "Codex Helper",
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
                    ]
                ]
            ])
        } catch {
            shutdownProcess()
            updateStatus(.unavailable(error.localizedDescription))
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            handle(object)
        }
    }

    private func handle(_ object: [String: Any]) {
        if let id = object["id"] as? Int, id == 1, object["result"] != nil {
            initialized = true
            send(["method": "initialized", "params": [:] as [String: Any]])
            if refreshPending {
                refreshPending = false
                refresh()
            }
            return
        }

        if let id = object["id"] as? Int, refreshRequestIDs.remove(id) != nil {
            guard let result = object["result"],
                  JSONSerialization.isValidJSONObject(result),
                  let data = try? JSONSerialization.data(withJSONObject: result),
                  let snapshot = makeUsageSnapshot(from: data) else {
                let message = ((object["error"] as? [String: Any])?["message"] as? String) ?? "Usage unavailable"
                updateStatus(.unavailable(message))
                return
            }
            updateStatus(.available(snapshot))
            return
        }

        if object["method"] as? String == "account/rateLimits/updated",
           initialized {
            // Rolling notifications are intentionally sparse. Refetch the complete
            // snapshot so missing fields never erase previously observed limits.
            refresh()
        }
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do {
            try inputHandle?.write(contentsOf: data)
        } catch {
            updateStatus(.unavailable(error.localizedDescription))
            shutdownProcess()
        }
    }

    private func updateStatus(_ newStatus: CodexUsageStatus) {
        status = newStatus
        if case let .available(value) = newStatus {
            snapshot = value
        }
        onChange?()
    }

    private func shutdownProcess() {
        let current = process
        process = nil
        inputHandle = nil
        initialized = false
        refreshPending = false
        refreshRequestIDs.removeAll()
        if current?.isRunning == true { current?.terminate() }
    }

    private func findCodexExecutable() -> URL? {
        var candidates: [URL] = []
        if let bundleURL = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first?.bundleURL {
            candidates.append(bundleURL.appendingPathComponent("Contents/Resources/codex"))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"))
        candidates.append(URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"))
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path) && isOfficialCodexExecutable($0)
        }
    }

    private func isOfficialCodexExecutable(_ url: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--verify",
            "--strict",
            "-R=anchor apple generic and identifier \"codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\"",
            url.path
        ]
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            _ = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
