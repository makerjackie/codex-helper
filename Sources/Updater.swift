import AppKit
import CryptoKit
import Darwin
import Foundation

private let updateBundleIdentifier = "com.makerjackie.codex-helper"
private let updateTeamIdentifier = "PCJ84YD7HQ"
private let lastAutomaticCheckKey = "CodexHelper.lastAutomaticUpdateCheck"

struct GitHubReleaseAsset: Decodable, Equatable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    var version: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) }
}

struct PreparedUpdate: Equatable {
    let release: GitHubRelease
    let dmgURL: URL
    let stagedAppURL: URL
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(GitHubRelease)
    case downloading(GitHubRelease)
    case ready(PreparedUpdate)
    case failed(String)
}

func isVersion(_ candidate: String, newerThan current: String) -> Bool {
    let candidateParts = candidate.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    let currentParts = current.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    let count = max(candidateParts.count, currentParts.count)
    for index in 0..<count {
        let left = candidateParts.indices.contains(index) ? candidateParts[index] : 0
        let right = currentParts.indices.contains(index) ? currentParts[index] : 0
        if left != right { return left > right }
    }
    return false
}

func checksumMatches(data: Data, checksumText: String) -> Bool {
    guard let expected = checksumText.split(whereSeparator: { $0.isWhitespace }).first?.lowercased(),
          expected.count == 64,
          expected.allSatisfy({ $0.isHexDigit }) else { return false }
    let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return actual == expected
}

private func makeUpdateError(_ message: String) -> NSError {
    NSError(domain: "CodexHelperUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
}

private func runUpdateProcess(
    _ executable: String,
    _ arguments: [String],
    mergeError: Bool = false,
    timeout: TimeInterval = 60
) throws -> (status: Int32, output: Data) {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error
    try process.run()

    let group = DispatchGroup()
    let lock = NSLock()
    var outputData = Data()
    var errorData = Data()
    group.enter()
    DispatchQueue.global(qos: .utility).async {
        let data = output.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); outputData = data; lock.unlock()
        group.leave()
    }
    group.enter()
    DispatchQueue.global(qos: .utility).async {
        let data = error.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); errorData = data; lock.unlock()
        group.leave()
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline { usleep(50_000) }
    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        group.wait()
        throw makeUpdateError("Update verification timed out")
    }
    process.waitUntilExit()
    group.wait()
    if mergeError { outputData.append(errorData) }
    return (process.terminationStatus, outputData)
}

private func verifyAppBundle(at appURL: URL, expectedVersion: String) throws {
    let requirement = "-R=anchor apple generic and identifier \"\(updateBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(updateTeamIdentifier)\""
    let signature = try runUpdateProcess(
        "/usr/bin/codesign",
        ["--verify", "--deep", "--strict", requirement, appURL.path]
    )
    guard signature.status == 0 else { throw makeUpdateError("Update signature verification failed") }

    let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
    let plistData = try Data(contentsOf: plistURL)
    let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
    guard plist?["CFBundleIdentifier"] as? String == updateBundleIdentifier,
          plist?["CFBundleShortVersionString"] as? String == expectedVersion else {
        throw makeUpdateError("Update identity or version does not match the release")
    }

    let gatekeeper = try runUpdateProcess("/usr/sbin/spctl", ["--assess", "--type", "execute", appURL.path])
    guard gatekeeper.status == 0 else { throw makeUpdateError("Update was not accepted by Gatekeeper") }
}

private func verifyDiskImage(at dmgURL: URL) throws {
    let requirement = "-R=anchor apple generic and certificate leaf[subject.OU] = \"\(updateTeamIdentifier)\""
    let signature = try runUpdateProcess("/usr/bin/codesign", ["--verify", "--strict", requirement, dmgURL.path])
    guard signature.status == 0 else { throw makeUpdateError("Update disk image signature verification failed") }
    let gatekeeper = try runUpdateProcess(
        "/usr/sbin/spctl",
        ["--assess", "--type", "open", "--context", "context:primary-signature", dmgURL.path]
    )
    guard gatekeeper.status == 0 else { throw makeUpdateError("Update disk image was not accepted by Gatekeeper") }
}

final class UpdateService {
    var onChange: (() -> Void)?
    private(set) var state: UpdateState = .idle

    private let supportURL: URL
    private let session: URLSession
    private let fileManager = FileManager.default
    private var timer: Timer?
    private var automaticDownload = true

    init(supportURL: URL, session: URLSession = .shared) {
        self.supportURL = supportURL.appendingPathComponent("Updates", isDirectory: true)
        self.session = session
        try? fileManager.createDirectory(at: self.supportURL, withIntermediateDirectories: true)
    }

    func start(automaticDownload: Bool) {
        self.automaticDownload = automaticDownload
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            guard let self, self.automaticDownload else { return }
            self.checkAutomaticallyIfDue()
        }
        if automaticDownload {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.checkAutomaticallyIfDue()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setAutomaticDownload(_ enabled: Bool) {
        automaticDownload = enabled
    }

    private func checkAutomaticallyIfDue() {
        let lastCheck = UserDefaults.standard.object(forKey: lastAutomaticCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= 24 * 60 * 60 else { return }
        UserDefaults.standard.set(Date(), forKey: lastAutomaticCheckKey)
        check(automaticDownload: true)
    }

    func check(automaticDownload: Bool = false) {
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        updateState(.checking)
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/makerjackie/codex-helper/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Helper", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil,
                      let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                      self.isTrustedReleaseURL(release.htmlURL),
                      release.assets.allSatisfy({ self.isTrustedReleaseURL($0.browserDownloadURL) }) else {
                    self.updateState(.failed(error?.localizedDescription ?? "Update check failed"))
                    return
                }
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                guard isVersion(release.version, newerThan: current) else {
                    self.updateState(.upToDate)
                    return
                }
                self.updateState(.available(release))
                if automaticDownload { self.download(release) }
            }
        }.resume()
    }

    func downloadAvailableUpdate() {
        guard case let .available(release) = state else { return }
        download(release)
    }

    func installReadyUpdate() -> Bool {
        guard case let .ready(update) = state,
              Bundle.main.bundleURL.pathExtension == "app",
              let executable = Bundle.main.executableURL,
              fileManager.isWritableFile(atPath: Bundle.main.bundleURL.path),
              fileManager.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path) else { return false }

        do {
            try verifyAppBundle(at: update.stagedAppURL, expectedVersion: update.release.version)
        } catch {
            updateState(.failed(error.localizedDescription))
            return false
        }

        let helperURL = supportURL.appendingPathComponent("CodexHelperUpdater-\(UUID().uuidString)")
        do {
            try fileManager.copyItem(at: executable, to: helperURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
            let process = Process()
            process.executableURL = helperURL
            process.arguments = [
                "--apply-update",
                update.stagedAppURL.path,
                Bundle.main.bundleURL.path,
                update.release.version,
                String(ProcessInfo.processInfo.processIdentifier),
                supportURL.appendingPathComponent("update-install.log").path
            ]
            try process.run()
            return true
        } catch {
            updateState(.failed(error.localizedDescription))
            return false
        }
    }

    func openReleasePage() {
        let release: GitHubRelease?
        switch state {
        case let .available(value), let .downloading(value): release = value
        case let .ready(value): release = value.release
        default: release = nil
        }
        if let release { NSWorkspace.shared.open(release.htmlURL) }
    }

    private func download(_ release: GitHubRelease) {
        if case .downloading = state { return }
        let expectedDMG = "Codex-Helper-\(release.version).dmg"
        guard let dmgAsset = release.assets.first(where: { $0.name == expectedDMG }),
              let checksumAsset = release.assets.first(where: { $0.name == "\(expectedDMG).sha256" }) else {
            updateState(.failed("Release assets are incomplete"))
            return
        }

        updateState(.downloading(release))
        let group = DispatchGroup()
        let lock = NSLock()
        var dmgData: Data?
        var checksumText: String?
        var downloadError: Error?

        for (asset, isDMG) in [(dmgAsset, true), (checksumAsset, false)] {
            group.enter()
            session.dataTask(with: asset.browserDownloadURL) { data, response, error in
                defer { group.leave() }
                lock.lock()
                defer { lock.unlock() }
                guard error == nil,
                      let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let data else {
                    downloadError = error ?? NSError(domain: "CodexHelperUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update download failed"])
                    return
                }
                if isDMG { dmgData = data } else { checksumText = String(data: data, encoding: .utf8) }
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            guard downloadError == nil,
                  let dmgData,
                  let checksumText,
                  checksumMatches(data: dmgData, checksumText: checksumText) else {
                self.updateState(.failed(downloadError?.localizedDescription ?? "Update checksum verification failed"))
                return
            }
            let dmgURL = self.supportURL.appendingPathComponent(expectedDMG)
            do {
                try dmgData.write(to: dmgURL, options: .atomic)
            } catch {
                self.updateState(.failed(error.localizedDescription))
                return
            }
            self.prepare(release: release, dmgURL: dmgURL)
        }
    }

    private func prepare(release: GitHubRelease, dmgURL: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let update = try self.mountVerifyAndStage(release: release, dmgURL: dmgURL)
                DispatchQueue.main.async { self.updateState(.ready(update)) }
            } catch {
                DispatchQueue.main.async { self.updateState(.failed(error.localizedDescription)) }
            }
        }
    }

    private func mountVerifyAndStage(release: GitHubRelease, dmgURL: URL) throws -> PreparedUpdate {
        try verifyDiskImage(at: dmgURL)
        let attach = try runUpdateProcess("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-plist", dmgURL.path])
        guard attach.status == 0,
              let plist = try PropertyListSerialization.propertyList(from: attach.output, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw makeUpdateError("Could not mount the update")
        }

        defer { _ = try? runUpdateProcess("/usr/bin/hdiutil", ["detach", mountPath]) }
        let mountedApp = URL(fileURLWithPath: mountPath).appendingPathComponent("Codex Helper.app")
        guard fileManager.fileExists(atPath: mountedApp.path) else { throw makeUpdateError("Update app is missing") }
        try verifyAppBundle(at: mountedApp, expectedVersion: release.version)

        let stagedApp = supportURL.appendingPathComponent("Codex Helper-\(release.version).app")
        try? fileManager.removeItem(at: stagedApp)
        try fileManager.copyItem(at: mountedApp, to: stagedApp)
        try verifyAppBundle(at: stagedApp, expectedVersion: release.version)
        return PreparedUpdate(release: release, dmgURL: dmgURL, stagedAppURL: stagedApp)
    }

    private func updateState(_ newState: UpdateState) {
        state = newState
        onChange?()
    }

    private func isTrustedReleaseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }
}

func runUpdateInstaller(arguments: [String]) -> Int32 {
    guard arguments.count == 7,
          let parentPID = pid_t(arguments[5]) else { return 2 }
    let helperURL = URL(fileURLWithPath: arguments[0])
    let staged = URL(fileURLWithPath: arguments[2])
    let destination = URL(fileURLWithPath: arguments[3])
    let expectedVersion = arguments[4]
    let logURL = URL(fileURLWithPath: arguments[6])
    let fileManager = FileManager.default
    defer { try? fileManager.removeItem(at: helperURL) }

    for _ in 0..<150 where kill(parentPID, 0) == 0 { usleep(200_000) }
    guard kill(parentPID, 0) != 0 else {
        writeUpdateLog("Update cancelled because Codex Helper did not quit", to: logURL)
        return 3
    }
    let temporary = destination.deletingLastPathComponent()
        .appendingPathComponent(".Codex-Helper-update-\(UUID().uuidString).app")
    let backupName = ".Codex-Helper-backup-\(UUID().uuidString).app"
    let backup = destination.deletingLastPathComponent().appendingPathComponent(backupName)

    do {
        try verifyAppBundle(at: staged, expectedVersion: expectedVersion)
        try fileManager.copyItem(at: staged, to: temporary)
        try verifyAppBundle(at: temporary, expectedVersion: expectedVersion)
        _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: temporary,
            backupItemName: backupName,
            options: []
        )
        try verifyAppBundle(at: destination, expectedVersion: expectedVersion)
        try? fileManager.removeItem(at: backup)
        try? fileManager.removeItem(at: staged)
        try openUpdatedApp(destination)
        return 0
    } catch {
        if fileManager.fileExists(atPath: backup.path) {
            try? fileManager.removeItem(at: destination)
            try? fileManager.moveItem(at: backup, to: destination)
        }
        writeUpdateLog("Update failed: \(error.localizedDescription)", to: logURL)
        try? fileManager.removeItem(at: temporary)
        if fileManager.fileExists(atPath: destination.path) { try? openUpdatedApp(destination) }
        return 1
    }
}

private func openUpdatedApp(_ destination: URL) throws {
    if ProcessInfo.processInfo.environment["CODEX_HELPER_UPDATE_TEST_NO_RELAUNCH"] == "1" { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [destination.path]
    try process.run()
}

private func writeUpdateLog(_ message: String, to url: URL) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    try? Data(line.utf8).write(to: url, options: .atomic)
}
