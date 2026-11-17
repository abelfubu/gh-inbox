import Foundation

struct PRGroup: Identifiable {
    let id: String
    let members: [PullRequest]
    var updated: Date { members.map(\.updatedAt).max() ?? .distantPast }
    var repository: String { members[0].repository }
}

enum PRGrouper {
    static func stacks(_ prs: [PullRequest]) -> [PRGroup] {
        var seen: Set<String> = []
        let unique = prs.filter { seen.insert($0.id).inserted }
        let byHead = Dictionary(unique.map { ("\($0.repository):\($0.headRef)", $0) },
                                uniquingKeysWith: { first, _ in first })
        var parents: [String: PullRequest] = [:]
        for pr in unique {
            if let below = byHead["\(pr.repository):\(pr.baseRef)"], below.id != pr.id { parents[pr.id] = below }
        }
        var children: [String: [PullRequest]] = [:]
        for pr in unique {
            if let parent = parents[pr.id] { children[parent.id, default: []].append(pr) }
        }
        var groups: [PRGroup] = []
        for root in unique where parents[root.id] == nil {
            var members: [PullRequest] = []
            func walk(_ pr: PullRequest) {
                members.append(pr)
                for child in (children[pr.id] ?? []).sorted(by: { $0.number < $1.number }) { walk(child) }
            }
            walk(root)
            groups.append(PRGroup(id: root.id, members: members))
        }
        return groups.sorted { $0.updated > $1.updated }
    }
}
