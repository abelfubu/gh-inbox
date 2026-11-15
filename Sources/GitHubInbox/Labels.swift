import Foundation

func labels(from sources: [Any], for action: String) throws -> [Int: String]? {
    guard !sources.isEmpty else { return nil }
    var result: [Int: String] = [:]
    for source in sources {
        if let string = source as? String {
            guard let number = Int(string), (1...9).contains(number), let action = LabelShortcutParser.parse(action) else { return nil }
            result[number] = action
            continue
        }
        guard let object = source as? [String: Any] else { return nil }
        for (key, value) in object {
            guard let number = Int(key), (1...9).contains(number), let string = value as? String, let action = LabelShortcutParser.parse(string) else { return nil }
            result[number] = action
        }
    }
    return result
}

func shortcutBinding(action: String, string: String) throws -> (action: String, shortcut: String)? {
    guard LabelShortcutParser.parse(action) != nil, ShortcutBinding.parse(string) != nil else { return nil }
    return (action, string)
}

enum LabelShortcutParser {
    private static let pattern = try! NSRegularExpression(pattern: #"^(?:tab|label:)([1-9])$"#)

    static func parse(_ source: String) -> String? {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = pattern.firstMatch(in: source, range: range), let digit = Range(match.range(at: 1), in: source) else { return nil }
        return "label:\(source[digit])"
    }
}
