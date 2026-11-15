import Foundation

struct RexDiffviewLauncher {
    enum LaunchError: LocalizedError {
        case executableNotFound
        case serverUnavailable
        case ambiguousSessions
        case repositoryNotFound(String)
        case invalidRepository(path: String, expected: String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "Rex was not found. Start Herdr or install the Rex CLI."
            case .serverUnavailable:
                return "Neither Herdr nor a running Rex server is available."
            case .ambiguousSessions:
                return "More than one Rex session is active. Set \"rexSession\" in the GitHub Inbox config to a session ID or label."
            case let .repositoryNotFound(repository):
                return "No local checkout of \(repository) was found. Set \"repositories\": {\"\(repository)\": \"/path/to/checkout\"} in the GitHub Inbox config."
            case let .invalidRepository(path, expected):
                return "The configured checkout at \(path) is not \(expected)."
            case let .failed(message):
                return message
            }
        }
    }

    static func launch(_ pr: PullRequest, repositoryPaths: [String: String], rexSession: String?) throws {
        guard let executable = findRex() else { throw LaunchError.executableNotFound }
        guard let session = try resolveSession(executable: executable, configured: rexSession) else {
            throw LaunchError.serverUnavailable
        }
        let directory = try resolveRepository(pr, repositoryPaths: repositoryPaths)
        let result = try run(executable: executable, arguments: arguments(for: pr, session: session, directory: directory))
        guard result.status == 0 else {
            let message = (result.stderr + "\n" + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.failed(message.isEmpty ? "Rex exited with status \(result.status)." : message)
        }
        guard let window = try createdWindow(from: Data(result.stdout.utf8)) else {
            throw LaunchError.failed("Rex opened the diff but did not return its window and block IDs.")
        }
        let focused = try run(executable: executable, arguments: ["--autostart=false", "focus", "-s", session, window.blockID])
        guard focused.status == 0 else {
            throw LaunchError.failed("Rex opened the diff but focusing its pane failed.")
        }
        try focus(executable: executable, session: session, windowID: window.windowID)
    }

    static func createdWindow(from data: Data) throws -> (windowID: String, blockID: String)? {
        let window = try JSONDecoder().decode(RexWindow.self, from: data)
        guard let blockID = window.blockIDs.first else { return nil }
        return (window.windowID, blockID)
    }

    static func applicationPIDs(from data: Data, session: String) throws -> [pid_t] {
        try applicationClients(from: data, session: session).map(\.principal.pid)
    }

    static func applicationClientID(from data: Data, session: String) throws -> String? {
        try applicationClients(from: data, session: session).first?.clientID
    }

    private static func applicationClients(from data: Data, session: String) throws -> [Client] {
        try JSONDecoder().decode(Clients.self, from: data).clients.filter {
            $0.info?.kind == "app" && $0.sessionIDs?.contains(session) == true
        }
    }

    private static func focus(executable: URL, session: String, windowID: String) throws {
        let result = try run(executable: executable, arguments: ["--autostart=false", "client", "ls", "--json"])
        guard result.status == 0,
              let client = try applicationClients(from: Data(result.stdout.utf8), session: session).first else {
            throw LaunchError.failed("Rex opened the diff but no attached app client could focus it.")
        }
        let selected = try run(executable: executable, arguments: [
            "--autostart=false", "-C", client.clientID, "do", "session.select",
            "session_id=\(session)", "window_id=\(windowID)", "--json",
        ])
        guard selected.status == 0 else {
            let message = (selected.stderr + "\n" + selected.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.failed(message.isEmpty ? "Rex opened the diff but the app could not select its tab." : message)
        }
        ApplicationFocuser.focus(pid: client.principal.pid)
    }

    static func arguments(for pr: PullRequest, session: String, directory: String) -> [String] {
        [
            "--autostart=false", "window", "new",
            "-s", session, "PR #\(pr.number) · diff",
            "-c", directory, "--keep-open", "--json",
            "--", "/bin/zsh", "-lc", DiffviewLauncher.script(for: pr),
        ]
    }

    static func resolveRepository(_ pr: PullRequest, repositoryPaths: [String: String]) throws -> String {
        let fileManager = FileManager.default
        if let configured = repositoryPaths.first(where: { $0.key.caseInsensitiveCompare(pr.repository) == .orderedSame })?.value {
            let path = (configured as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let origin = originRepository(at: path), origin.caseInsensitiveCompare(pr.repository) == .orderedSame else {
                throw LaunchError.invalidRepository(path: path, expected: pr.repository)
            }
            return path
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let name = pr.repository.split(separator: "/").last.map(String.init) ?? pr.repository
        let candidates = ["dev", "code", "Projects", "work", "src"].map {
            home.appendingPathComponent("\($0)/\(name)").path
        }
        for path in candidates where fileManager.fileExists(atPath: path, isDirectory: nil) {
            if originRepository(at: path)?.caseInsensitiveCompare(pr.repository) == .orderedSame { return path }
        }
        throw LaunchError.repositoryNotFound(pr.repository)
    }

    static func repositoryName(fromRemote remote: String) -> String? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("/") { value.removeLast() }
        if value.lowercased().hasSuffix(".git") { value.removeLast(4) }
        let components = value.split(whereSeparator: { $0 == "/" || $0 == ":" }).map(String.init)
        guard components.count >= 2 else { return nil }
        return components.suffix(2).joined(separator: "/")
    }

    private static func originRepository(at path: String) -> String? {
        guard let result = try? run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", path, "remote", "get-url", "origin"]
        ), result.status == 0 else { return nil }
        return repositoryName(fromRemote: result.stdout)
    }

    private static func resolveSession(executable: URL, configured: String?) throws -> String? {
        if let configured = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !configured.isEmpty {
            return configured
        }
        let who = try run(executable: executable, arguments: ["--autostart=false", "whoami", "--json"])
        guard who.status == 0 else { return nil }
        if let session = try? JSONDecoder().decode(WhoAmI.self, from: Data(who.stdout.utf8)).sessionID,
           !session.isEmpty { return session }

        let list = try run(executable: executable, arguments: ["--autostart=false", "ls", "--json"])
        guard list.status == 0 else { return nil }
        let sessions = try JSONDecoder().decode(Sessions.self, from: Data(list.stdout.utf8)).sessions
        guard sessions.count == 1 else {
            if sessions.isEmpty { return nil }
            throw LaunchError.ambiguousSessions
        }
        return sessions[0].id
    }

    private static func findRex() -> URL? {
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["REX_CLI_PATH"] { candidates.append(explicit) }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/rex" })
        }
        candidates += [
            "\(NSHomeDirectory())/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
            "\(NSHomeDirectory())/.local/bin/rex",
            "/opt/homebrew/bin/rex",
            "/usr/local/bin/rex",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    private static func run(executable: URL, arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
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
        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private struct RexWindow: Decodable {
        let windowID: String
        let blockIDs: [String]
        enum CodingKeys: String, CodingKey { case windowID = "window_id", blockIDs = "block_ids" }
    }

    private struct Clients: Decodable {
        let clients: [Client]
    }

    private struct Client: Decodable {
        let clientID: String
        let info: Info?
        let principal: Principal
        let sessionIDs: [String]?
        enum CodingKeys: String, CodingKey { case clientID = "client_id", info, principal, sessionIDs = "session_ids" }
    }

    private struct Info: Decodable {
        let kind: String
    }

    private struct Principal: Decodable {
        let pid: pid_t
    }

    private struct WhoAmI: Decodable {
        let sessionID: String?
        enum CodingKeys: String, CodingKey { case sessionID = "session_id" }
    }

    private struct Sessions: Decodable {
        let sessions: [Session]
    }

    private struct Session: Decodable {
        let id: String
        enum CodingKeys: String, CodingKey { case id = "session_id" }
    }
}
