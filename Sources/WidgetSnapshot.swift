import Foundation

let codexHelperAppGroupIdentifier = "PCJ84YD7HQ.com.makerjackie.codex-helper"
let codexHelperWidgetKind = "CodexHelperQuotaWidget"

struct WidgetQuotaWindow: Codable, Equatable {
    let id: String
    let name: String
    let planType: String?
    let remainingPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Date?
}

struct WidgetQuotaSnapshot: Codable, Equatable {
    let windows: [WidgetQuotaWindow]
    let resetCredits: Int
    let fetchedAt: Date
}

enum WidgetSnapshotStore {
    private static let fileName = "quota-widget.json"

    static func load() -> WidgetQuotaSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(WidgetQuotaSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: WidgetQuotaSnapshot) -> Bool {
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: snapshotURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static var snapshotURL: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: codexHelperAppGroupIdentifier
        ) {
            return groupURL.appendingPathComponent(fileName)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexHelper", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
