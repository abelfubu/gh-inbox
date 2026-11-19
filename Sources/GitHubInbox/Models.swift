import Foundation

struct PullRequest: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let headRef: String
    let baseRef: String
    let draft: Bool
    let createdAt: Date
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let decision: String?
    let mergeable: String?
    let mergeState: String?
    let unresolved: Int
    let approvedBy: [String]
    let changesBy: [String]
    let requested: [String]
    let checks: CheckCounts

    var reference: String { "#\(number)" }
}

struct PRDisplayState: Equatable, Sendable {
    enum Tone: Sendable { case dim, green, red, orange, yellow }
    let text: String
    let symbol: String
    let tone: Tone
}

enum PRDisplayStatus {
    static func resolve(_ pr: PullRequest, review: Bool) -> PRDisplayState {
        if pr.draft { return .init(text: "Draft", symbol: "arrow.triangle.pull", tone: .dim) }
        if pr.mergeable == "CONFLICTING" { return .init(text: "Conflicts", symbol: "exclamationmark.triangle.fill", tone: .red) }
        if pr.checks.failed > 0 {
            return .init(text: review ? "CI failing" : "\(pr.checks.failed) check\(pr.checks.failed == 1 ? "" : "s") failing",
                         symbol: "xmark.circle.fill", tone: .red)
        }
        if pr.checks.running > 0 {
            return .init(text: review ? "CI running" : "CI \(pr.checks.passed)/\(pr.checks.total)",
                         symbol: "arrow.triangle.2.circlepath", tone: .orange)
        }
        if pr.decision == "CHANGES_REQUESTED" {
            return .init(text: "Changes requested", symbol: "exclamationmark.bubble.fill", tone: .red)
        }
        if pr.decision == "REVIEW_REQUIRED" { return .init(text: "Needs review", symbol: "eye.fill", tone: .yellow) }
        if pr.mergeState == "BLOCKED" { return .init(text: "Blocked", symbol: "pause.circle.fill", tone: .yellow) }
        if pr.mergeState == "BEHIND" { return .init(text: "Behind base", symbol: "arrow.triangle.pull", tone: .yellow) }
        if pr.mergeState == "UNKNOWN" { return .init(text: "Checking mergeability", symbol: "arrow.triangle.2.circlepath", tone: .orange) }
        if review {
            return pr.decision == "APPROVED"
                ? .init(text: "Approved", symbol: "checkmark.seal.fill", tone: .green)
                : .init(text: "Ready for review", symbol: "arrow.triangle.pull", tone: .green)
        }
        return .init(text: "Ready to merge", symbol: "checkmark.circle.fill", tone: .green)
    }
}

struct CheckCounts: Hashable, Sendable {
    var passed = 0
    var failed = 0
    var running = 0
    var cancelled = 0
    var total = 0
}

struct SectionResult: Identifiable, Sendable {
    let id: String
    var prs: [PullRequest]?
    var error: String?
}

struct GraphQLResponse: Decodable {
    struct Payload: Decodable { let search: Search }
    struct Search: Decodable { let nodes: [Node?] }
    struct Node: Decodable {
        struct Repository: Decodable { let nameWithOwner: String }
        struct Author: Decodable { let login: String }
        struct Threads: Decodable { struct Thread: Decodable { let isResolved: Bool }; let nodes: [Thread] }
        struct ReviewRequests: Decodable {
            struct Node: Decodable {
                struct Reviewer: Decodable { let login: String?; let slug: String? }
                let requestedReviewer: Reviewer?
            }
            let nodes: [Node]
        }
        struct Reviews: Decodable {
            struct Node: Decodable { let state: String; let author: Author? }
            let nodes: [Node]
        }
        struct Commits: Decodable {
            struct Node: Decodable {
                struct Commit: Decodable { let statusCheckRollup: Rollup? }
                let commit: Commit
            }
            struct Rollup: Decodable {
                struct Contexts: Decodable {
                    struct Count: Decodable { let state: String; let count: Int }
                    let checkRunCountsByState: [Count]?
                    let statusContextCountsByState: [Count]?
                }
                let state: String?
                let contexts: Contexts?
            }
            let nodes: [Node]
        }
        let number: Int
        let title: String
        let url: String
        let isDraft: Bool
        let createdAt: String
        let updatedAt: String
        let additions: Int
        let deletions: Int
        let repository: Repository
        let author: Author?
        let headRefName: String
        let baseRefName: String
        let reviewDecision: String?
        let mergeable: String?
        let mergeStateStatus: String?
        let reviewThreads: Threads
        let reviewRequests: ReviewRequests?
        let latestOpinionatedReviews: Reviews?
        let commits: Commits
    }
    struct APIError: Decodable { let message: String }
    let data: Payload?
    let errors: [APIError]?
}

extension GraphQLResponse.Node {
    func pullRequest() -> PullRequest? {
        guard let url = URL(string: url), let updated = Date.iso8601Fractional(updatedAt),
              let created = Date.iso8601Fractional(createdAt) else { return nil }
        let counts = (commits.nodes.first?.commit.statusCheckRollup?.contexts?.checkRunCountsByState ?? []) +
            (commits.nodes.first?.commit.statusCheckRollup?.contexts?.statusContextCountsByState ?? [])
        let reviews = latestOpinionatedReviews?.nodes ?? []
        let requested = (reviewRequests?.nodes ?? []).compactMap { node -> String? in
            if let login = node.requestedReviewer?.login { return login }
            if let slug = node.requestedReviewer?.slug { return "@\(slug)" }
            return nil
        }
        return PullRequest(
            id: "\(repository.nameWithOwner)#\(number)", number: number, title: title, url: url,
            repository: repository.nameWithOwner, author: author?.login ?? "ghost",
            headRef: headRefName, baseRef: baseRefName, draft: isDraft, createdAt: created, updatedAt: updated,
            additions: additions, deletions: deletions, decision: reviewDecision,
            mergeable: mergeable, mergeState: mergeStateStatus,
            unresolved: reviewThreads.nodes.filter { !$0.isResolved }.count,
            approvedBy: reviews.filter { $0.state == "APPROVED" }.compactMap { $0.author?.login },
            changesBy: reviews.filter { $0.state == "CHANGES_REQUESTED" }.compactMap { $0.author?.login },
            requested: requested, checks: CheckCounts(counts: counts)
        )
    }
}

extension CheckCounts {
    init(counts: [GraphQLResponse.Node.Commits.Rollup.Contexts.Count]) {
        self.init()
        for item in counts where item.count > 0 {
            switch item.state {
            case "SUCCESS", "NEUTRAL": passed += item.count
            case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "ERROR": failed += item.count
            case "CANCELLED", "STALE": cancelled += item.count; continue
            case "IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "EXPECTED", "REQUESTED": running += item.count
            default: continue
            }
            total += item.count
        }
    }
}

extension Date {
    static func iso8601Fractional(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
