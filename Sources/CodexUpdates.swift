import Foundation

struct CodexUpdate: Codable, Equatable {
    let title: String
    let link: URL
    let source: CodexUpdateSource
    let publishedAt: Date?
}

enum CodexUpdateSource: String, Codable {
    case changelog
    case openAINews

    var displayName: String {
        switch self {
        case .changelog: return "Codex Changelog"
        case .openAINews: return "OpenAI News"
        }
    }
}

private struct UpdatesCache: Codable {
    let updates: [CodexUpdate]
    let lastCompleteRefresh: Date?
}

enum CodexResource {
    static let docs = URL(string: "https://learn.chatgpt.com/docs")!
    static let changelog = URL(string: "https://learn.chatgpt.com/docs/changelog")!
    static let changelogFeed = URL(string: "https://learn.chatgpt.com/docs/changelog/rss.xml")!
    static let openAINewsFeed = URL(string: "https://openai.com/news/rss.xml")!
    static let troubleshooting = URL(string: "https://learn.chatgpt.com/docs/reference/troubleshooting")!
    static let commands = URL(string: "https://learn.chatgpt.com/docs/reference/commands")!
    static let tibo = URL(string: "https://x.com/thsottiaux")!
}

private struct RSSItem {
    let title: String
    let link: URL
    let summary: String
    let publishedAt: Date?
}

private final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private var summary = ""
    private var date = ""
    private var insideItem = false

    static func parse(_ data: Data) -> [RSSItem] {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" || currentElement == "entry" {
            insideItem = true
            title = ""
            link = ""
            summary = ""
            date = ""
        } else if insideItem, currentElement == "link", let href = attributeDict["href"] {
            link = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "description", "summary", "content:encoded": summary += string
        case "pubdate", "published", "updated": date += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8) else { return }
        self.parser(parser, foundCharacters: text)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        if element == "item" || element == "entry" {
            insideItem = false
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty, let url = URL(string: cleanLink), isAllowedUpdateURL(url) {
                items.append(RSSItem(
                    title: cleanTitle,
                    link: url,
                    summary: summary,
                    publishedAt: Self.parseDate(date.trimmingCharacters(in: .whitespacesAndNewlines))
                ))
            }
        }
        currentElement = ""
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }

        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private func isAllowedUpdateURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
    return host == "openai.com"
        || host.hasSuffix(".openai.com")
        || host == "chatgpt.com"
        || host.hasSuffix(".chatgpt.com")
        || host == "github.com"
}

func parseCodexUpdates(changelogData: Data, newsData: Data) -> [CodexUpdate] {
    let changelog = RSSParser.parse(changelogData).map {
        CodexUpdate(title: $0.title, link: $0.link, source: .changelog, publishedAt: $0.publishedAt)
    }
    let news = RSSParser.parse(newsData)
        .filter {
            let searchable = "\($0.title) \($0.summary) \($0.link.absoluteString)".lowercased()
            return searchable.contains("codex")
        }
        .map {
            CodexUpdate(title: $0.title, link: $0.link, source: .openAINews, publishedAt: $0.publishedAt)
        }

    var seen = Set<String>()
    return (changelog + news)
        .filter { seen.insert($0.link.absoluteString).inserted }
        .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
}

final class CodexUpdatesService {
    private let cacheURL: URL
    private let session: URLSession
    private let refreshInterval: TimeInterval = 6 * 60 * 60
    private let failureRetryInterval: TimeInterval = 15 * 60
    private(set) var updates: [CodexUpdate] = []
    private(set) var isRefreshing = false
    private var lastRefresh: Date?
    private var lastAttempt: Date?

    init(cacheURL: URL, session: URLSession = .shared) {
        self.cacheURL = cacheURL
        self.session = session
        loadCache()
    }

    func refreshIfNeeded(force: Bool = false, completion: @escaping () -> Void) {
        guard !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < refreshInterval {
            return
        }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < failureRetryInterval {
            return
        }

        isRefreshing = true
        lastAttempt = Date()
        let group = DispatchGroup()
        let lock = NSLock()
        var changelogData = Data()
        var newsData = Data()

        for (url, isChangelog) in [(CodexResource.changelogFeed, true), (CodexResource.openAINewsFeed, false)] {
            group.enter()
            session.dataTask(with: url) { data, response, _ in
                defer { group.leave() }
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let data else { return }
                lock.lock()
                if isChangelog { changelogData = data } else { newsData = data }
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let fetched = parseCodexUpdates(changelogData: changelogData, newsData: newsData)
            let changelogSucceeded = fetched.contains { $0.source == .changelog }
            let newsSucceeded = !newsData.isEmpty && !RSSParser.parse(newsData).isEmpty
            var merged = self.updates

            if changelogSucceeded {
                merged.removeAll { $0.source == .changelog }
                merged.append(contentsOf: fetched.filter { $0.source == .changelog })
            }
            if newsSucceeded {
                merged.removeAll { $0.source == .openAINews }
                merged.append(contentsOf: fetched.filter { $0.source == .openAINews })
            }
            if changelogSucceeded || newsSucceeded {
                self.updates = self.sortedDeduplicated(merged)
                if changelogSucceeded && newsSucceeded {
                    self.lastRefresh = Date()
                }
                self.saveCache()
            }
            self.isRefreshing = false
            completion()
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(UpdatesCache.self, from: data) else { return }
        updates = cached.updates.filter { isAllowedUpdateURL($0.link) }
        lastRefresh = cached.lastCompleteRefresh
    }

    private func saveCache() {
        let cache = UpdatesCache(updates: updates, lastCompleteRefresh: lastRefresh)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func sortedDeduplicated(_ values: [CodexUpdate]) -> [CodexUpdate] {
        var seen = Set<String>()
        return values
            .filter { seen.insert($0.link.absoluteString).inserted }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }
}
