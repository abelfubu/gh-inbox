import Foundation

enum MergeStrategy: String, Sendable {
    case merge
    case squash
    case rebase

    var flag: String { "--\(rawValue)" }
}

struct RepositoryMergeMethods: Decodable, Sendable {
    let mergeCommitAllowed: Bool
    let squashMergeAllowed: Bool
    let rebaseMergeAllowed: Bool
}

struct GitHubClient: Sendable {
    enum ClientError: LocalizedError {
        case executableNotFound
        case api(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound: return "GitHub CLI (gh) was not found. Install it with `brew install gh`."
            case let .api(message): return message
            case let .failed(message): return message
            }
        }
    }

    static let graphQuery = """
    query($q:String!) {
      search(query:$q,type:ISSUE,first:60) { nodes { ... on PullRequest {
        number title url isDraft createdAt updatedAt additions deletions
        repository { nameWithOwner }
        author { login }
        headRefName baseRefName reviewDecision mergeable mergeStateStatus
        reviewThreads(first:100) { nodes { isResolved } }
        reviewRequests(first:20) { nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
        latestOpinionatedReviews(first:20) { nodes { state author { login } } }
        commits(last:1) { nodes { commit { statusCheckRollup { state contexts(first:1) {
          totalCount checkRunCountsByState { state count }
          statusContextCountsByState { state count }
        } } } } }
      } } }
    }
    """

    let executable: URL
    let login: String

    init() throws {
        guard let executable = Self.findExecutable() else { throw ClientError.executableNotFound }
        self.executable = executable
        login = try Self.run(executable: executable, arguments: ["api", "user", "--jq", ".login"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchSection(_ section: InboxSection) async throws -> [PullRequest] {
        try await withThrowingTaskGroup(of: [PullRequest].self) { group in
            for query in section.effectiveQueries {
                group.addTask {
                    let arguments = ["api", "graphql", "-f", "query=\(Self.graphQuery)", "-f", "q=\(Self.qualifiedQuery(query))"]
                    let output = try Self.run(executable: self.executable, arguments: arguments)
                    return try Self.decodeSearch(Data(output.utf8))
                }
            }
            var unique: [String: PullRequest] = [:]
            for try await prs in group {
                for pr in prs {
                    if let existing = unique[pr.id] {
                        unique[pr.id] = Self.newest(existing, pr)
                    } else {
                        unique[pr.id] = pr
                    }
                }
            }
            return unique.values.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func perform(_ arguments: [String]) throws -> String {
        try Self.run(executable: executable, arguments: arguments)
    }

    func mergeStrategy(repository: String) throws -> MergeStrategy {
        let output = try perform(["repo", "view", repository, "--json",
                                  "mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed"])
        let methods = try Self.decodeMergeMethods(Data(output.utf8))
        return try Self.preferredMergeStrategy(methods)
    }

    static func preferredMergeStrategy(_ methods: RepositoryMergeMethods) throws -> MergeStrategy {
        if methods.mergeCommitAllowed { return .merge }
        if methods.squashMergeAllowed { return .squash }
        if methods.rebaseMergeAllowed { return .rebase }
        throw ClientError.failed("Repository does not allow merge, squash, or rebase merges.")
    }

    static func decodeMergeMethods(_ data: Data) throws -> RepositoryMergeMethods {
        try JSONDecoder().decode(RepositoryMergeMethods.self, from: data)
    }

    static func newest(_ first: PullRequest, _ second: PullRequest) -> PullRequest {
        second.updatedAt > first.updatedAt ? second : first
    }

    static func qualifiedQuery(_ query: String) -> String {
        "\(query) is:pr is:open archived:false"
    }

    static func decodeSearch(_ data: Data) throws -> [PullRequest] {
        let response = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw ClientError.api(errors.map(\.message).joined(separator: "\n"))
        }
        return response.data?.search.nodes.compactMap { $0?.pullRequest() } ?? []
    }

    static func decodeCollaborators(_ data: Data) throws -> [String] {
        struct Collaborator: Decodable { let login: String }
        return try JSONDecoder().decode([Collaborator].self, from: data).map(\.login)
    }

    static func decodeLabels(_ data: Data) throws -> [String] {
        struct Label: Decodable { let name: String }
        return try JSONDecoder().decode([Label].self, from: data).map(\.name)
    }

    private static func findExecutable() -> URL? {
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["GH_PATH"] { candidates.append(explicit) }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/gh" })
        }
        candidates += ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/gh").path)
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    private static func run(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClientError.failed(message.isEmpty ? "gh exited with status \(process.terminationStatus)." : message)
        }
        return String(decoding: output, as: UTF8.self)
    }
}
