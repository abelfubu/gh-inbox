import Foundation

struct DiffviewLauncher {
    enum Target: String {
        case herdr = "Herdr"
        case rex = "Rex"
    }

    enum LaunchError: LocalizedError {
        case executableNotFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "herdr-app was not found. Install Herdr or add it to PATH."
            case let .failed(message):
                return message
            }
        }
    }

    static func launch(_ pr: PullRequest, repositoryPaths: [String: String] = [:], rexSession: String? = nil) throws -> Target {
        if let executable = findHerdrApp(), isHerdrRunning(executable) {
            try launchHerdr(pr, executable: executable)
            ApplicationFocuser.focus(applicationNamed: "Herdr")
            return .herdr
        }
        try RexDiffviewLauncher.launch(pr, repositoryPaths: repositoryPaths, rexSession: rexSession)
        return .rex
    }

    private static func launchHerdr(_ pr: PullRequest, executable: URL) throws {
        let result = try run(executable: executable, arguments: arguments(for: pr))
        guard result.status == 0 else {
            let message = (result.stderr + "\n" + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.failed(message.isEmpty ? "herdr-app exited with status \(result.status)." : message)
        }
        guard let terminal = try createdTerminal(from: Data(result.stdout.utf8)) else {
            throw LaunchError.failed("Herdr opened the diff but did not return its terminal ID.")
        }
        let focused = try run(executable: executable, arguments: ["do", "pane.focus", "--terminal", terminal])
        guard focused.status == 0 else {
            throw LaunchError.failed("Herdr opened the diff but focusing its pane failed.")
        }
    }

    static func createdTerminal(from data: Data) throws -> String? {
        try JSONDecoder().decode(HerdrTab.self, from: data).terminal
    }

    private struct HerdrTab: Decodable {
        let terminal: String
    }

    private static func isHerdrRunning(_ executable: URL) -> Bool {
        guard let result = try? run(executable: executable, arguments: ["status"]) else { return false }
        return result.status == 0
    }

    static func arguments(for pr: PullRequest) throws -> [String] {
        // Omit space and folder: Herdr deliberately uses its active space and
        // the focused terminal's current repository, just like the inbox mod.
        let argv = ["/bin/zsh", "-lc", script(for: pr)]
        let data = try JSONEncoder().encode(argv)
        return [
            "do", "tab.new",
            "--name", "PR #\(pr.number) · diff",
            "--argv", String(decoding: data, as: UTF8.self),
        ]
    }

    static func script(for pr: PullRequest) -> String {
        let expectedRepo = shellQuote(pr.repository)
        let base = "origin/\(pr.baseRef)"
        let head = "origin/pr/\(pr.number)/head"
        let fetchBase = shellQuote("+refs/heads/\(pr.baseRef):refs/remotes/\(base)")
        let fetchHead = shellQuote("+refs/pull/\(pr.number)/head:refs/remotes/\(head)")
        let diffCommand = shellQuote("DiffviewOpen \(base)...\(head)")
        let httpsRemote = shellQuote("https://github.com/\(pr.repository).git")
        let credentialHelper = shellQuote(#"!f() { if [ "$1" = get ]; then printf "username=x-access-token\npassword=%s\n\n" "$(gh auth token)"; fi; }; f"#)
        return """
        expected_repo=\(expectedRepo)
        remote="$(git remote get-url origin 2>/dev/null)" || { print -u2 "Focus a terminal in \(pr.repository), then try again."; exit 1 }
        repo="$(printf '%s\\n' "$remote" | sed -E 's#\\.git/?$##' | awk -F'[/:]' '{print $(NF-1) "/" $NF}')"
        if [[ "${repo:l}" != "${expected_repo:l}" ]]; then
          print -u2 "Wrong repository: $repo. Focus a terminal in $expected_repo, then try again."
          exit 1
        fi
        print "Fetching PR #\(pr.number) for Diffview…"
        if ! git fetch --no-tags origin \(fetchBase) \(fetchHead) >/dev/null 2>&1; then
          print "SSH fetch unavailable; retrying with gh authentication…"
          git -c credential.helper= -c credential.helper=\(credentialHelper) fetch --no-tags \(httpsRemote) \(fetchBase) \(fetchHead) || exit $?
        fi
        exec nvim -c \(diffCommand)
        """
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func findHerdrApp() -> URL? {
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["HERDR_APP_PATH"] { candidates.append(explicit) }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/herdr-app" })
        }
        candidates += [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/herdr-app").path,
            "/opt/homebrew/bin/herdr-app",
            "/usr/local/bin/herdr-app",
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
}
