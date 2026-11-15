import AppKit
import Foundation

struct InboxSection: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var icon: String?
    var view: String?
    var queries: [String]
    var query: String?
    var labels: [String: String]?
    var icons: [String]?
    fileprivate(set) var resolvedLabel: String?
    fileprivate(set) var resolvedIcons: [String]?

    init(id: String, label: String, icon: String? = nil, view: String? = nil, queries: [String], query: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.view = view
        self.queries = queries
        self.query = query
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? id
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        view = try values.decodeIfPresent(String.self, forKey: .view)
        queries = try values.decodeIfPresent([String].self, forKey: .queries) ?? []
        query = try values.decodeIfPresent(String.self, forKey: .query)
        labels = try values.decodeIfPresent([String: String].self, forKey: .labels)
        icons = try values.decodeIfPresent([String].self, forKey: .icons)
    }

    var effectiveLabel: String { resolvedLabel ?? label }
    var effectiveIcons: [String] { resolvedIcons ?? [] }
    var effectiveLabels: [String: String] { labels ?? [:] }

    var effectiveView: String {
        view ?? (["mine", "review", "queue"].contains(id) ? id : "list")
    }

    var effectiveQueries: [String] {
        let values = queries + [query].compactMap { $0 }
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var symbol: String {
        switch icon ?? effectiveView {
        case "eye": return "eye"
        case "tag": return "tag"
        case "queue": return "tray.full"
        default: return "arrow.triangle.pull"
        }
    }
}

struct InboxConfig: Codable, Sendable {
    var sections: [InboxSection]
    var customTabs: [InboxSection]?
    var colors: [String: String]?
    var font: String?
    var shortcuts: [String: [String]]?
    var labels: [String: String]?
    var repositories: [String: String]?
    var rexSession: String?

    static let standard = InboxConfig(sections: [
        InboxSection(id: "mine", label: "Mine", icon: "pr", view: "mine", queries: ["author:@me"]),
        InboxSection(id: "review", label: "Review", icon: "eye", view: "review", queries: ["review-requested:@me -author:@me"]),
    ])

    var validatedSections: [InboxSection] {
        var used = Set<String>()
        return (sections + (customTabs ?? [])).filter { section in
            guard section.id.range(of: #"^[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil,
                  !used.contains(section.id), !section.effectiveQueries.isEmpty,
                  ["mine", "review", "list"].contains(section.effectiveView) else { return false }
            used.insert(section.id)
            return true
        }
    }

    func labels(for section: InboxSection) -> [String: String] {
        (self.labels ?? [:]).merging(section.labels ?? [:]) { _, local in local }
    }

    func icons(for sections: [InboxSection]) -> [InboxSection] {
        sections.map { section in
            var copy = section
            copy.resolvedIcons = (section.icons ?? []).compactMap { icon in
                switch icon {
                case "pr", "eye", "stack": return icon
                case "custom": return "pr"
                default: return nil
                }
            }
            return copy
        }
    }
}

final class ConfigStore {
    static let standard = ConfigStore()
    let url: URL
    private let decoder = JSONDecoder()

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gh-inbox/config.json")
    }

    func load() throws -> InboxConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            try save(InboxConfig.standard)
            return .standard
        }
        let data = try Data(contentsOf: url)
        let config = try decoder.decode(InboxConfig.self, from: data)
        guard !config.validatedSections.isEmpty else { throw ConfigError.noValidSections }
        return config
    }

    func open() {
        do {
            if !FileManager.default.fileExists(atPath: url.path) { try save(.standard) }
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("Could not create config: \(error.localizedDescription)")
        }
    }

    private func save(_ config: InboxConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

enum ConfigError: LocalizedError {
    case noValidSections
    var errorDescription: String? { "No valid sections in \(ConfigStore.standard.url.path)." }
}
