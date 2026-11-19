import AppKit
import Foundation
import SwiftUI

#if DEBUG
enum SelfTests {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(description: message) }
    }

    static func run() {
        do {
            if ProcessInfo.processInfo.environment["GH_INBOX_REX_DIFF_SMOKE"] == "1" {
                try runRexDiffSmoke()
                print("Rex diff smoke passed")
                exit(0)
            }
            try testQualifiedQuery()
            try testConfig()
            try testConfigStore()
            try testDecoding()
            try testCollaborators()
            try testLabels()
            try testFormOptionFilter()
            try testLabelConfig()
            try testStacks()
            try testThemeAndShortcuts()
            try testDiffviewLauncher()
            print("Self-tests passed (43 checks)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Self-test failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func runRexDiffSmoke() throws {
        let pr = PullRequest(
            id: "smoke", number: 10854, title: "Diff focus smoke",
            url: URL(string: "https://github.com/nomoapp/nomo-server-app/pull/10854")!,
            repository: "nomoapp/nomo-server-app", author: "smoke", headRef: "smoke", baseRef: "main",
            draft: false, createdAt: Date(), updatedAt: Date(), additions: 0, deletions: 0,
            decision: nil, mergeable: nil, mergeState: nil, unresolved: 0,
            approvedBy: [], changesBy: [], requested: [], checks: CheckCounts()
        )
        try RexDiffviewLauncher.launch(
            pr,
            repositoryPaths: ["nomoapp/nomo-server-app": "/Users/abelfubu/dev/nomo-server-app"],
            rexSession: ProcessInfo.processInfo.environment["REX_SESSION"]
        )
    }

    private static func testQualifiedQuery() throws {
        try expect(GitHubClient.qualifiedQuery("label:italy") == "label:italy is:pr is:open archived:false", "Query qualification")
    }

    private static func testConfig() throws {
        let json = ##"{"sections":[{"id":"mine","label":"Mine","query":"author:@me"}],"customTabs":[{"id":"italy","label":"Italy","queries":["label:italy"]}],"colors":{"background":"#0D1117"},"shortcuts":{"nextPR":["x"]}}"##
        let config = try JSONDecoder().decode(InboxConfig.self, from: Data(json.utf8))
        try expect(config.validatedSections.map(\.id) == ["mine", "italy"], "Section and custom tab decoding")
        try expect(config.validatedSections[0].effectiveQueries == ["author:@me"], "Single query decoding")
        try expect(config.colors?["background"] == "#0D1117" && config.shortcuts?["nextPR"] == ["x"], "Color and shortcut decoding")
        let invalid = InboxConfig(sections: [
            InboxSection(id: "mine", label: "Mine", queries: ["author:@me"]),
            InboxSection(id: "mine", label: "Duplicate", queries: ["author:someone"]),
            InboxSection(id: "Invalid ID", label: "Invalid", queries: ["author:someone"]),
        ])
        try expect(invalid.validatedSections.map(\.id) == ["mine"], "Section validation")
    }

    private static func testConfigStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        let config = try ConfigStore(url: url).load()
        try expect(config.sections.map(\.id) == ["mine", "review"], "Default sections")
        try expect(FileManager.default.fileExists(atPath: url.path), "Default config creation")
    }

    private static func testDecoding() throws {
        let json = """
        {"data":{"search":{"nodes":[{
          "number":42,"title":"Test native inbox","url":"https://github.com/example/repo/pull/42",
          "isDraft":false,"createdAt":"2026-11-10T11:00:00Z","updatedAt":"2026-11-10T12:00:00Z","additions":10,"deletions":2,
          "repository":{"nameWithOwner":"example/repo"},"author":{"login":"abelfubu"},
          "headRefName":"feature/native","baseRefName":"main","reviewDecision":"APPROVED",
          "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
          "reviewThreads":{"nodes":[{"isResolved":false},{"isResolved":true}]},
          "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE","contexts":{
            "checkRunCountsByState":[{"state":"SUCCESS","count":1},{"state":"IN_PROGRESS","count":1}],
            "statusContextCountsByState":[{"state":"FAILURE","count":1}]
          }}}}]}
        }]}},"errors":null}
        """
        let prs = try GitHubClient.decodeSearch(Data(json.utf8))
        guard let pr = prs.first else { throw Failure(description: "Missing decoded PR") }
        try expect(prs.count == 1 && pr.id == "example/repo#42", "PR identity")
        try expect(pr.unresolved == 1 && pr.decision == "APPROVED", "Review metadata")
        try expect(pr.checks.passed == 1 && pr.checks.failed == 1 && pr.checks.running == 1 && pr.checks.total == 3, "Check counts")
        try expect(pr.createdAt < pr.updatedAt && pr.approvedBy.isEmpty && pr.requested.isEmpty, "PR dates and optional metadata")
    }

    private static func testCollaborators() throws {
        let data = Data(#"[{"login":"octocat"},{"login":"hubot"}]"#.utf8)
        let names = try GitHubClient.decodeCollaborators(data)
        try expect(names == ["octocat", "hubot"], "Collaborator decoding")
    }

    private static func testLabels() throws {
        let data = Data(#"[{"name":"italy"},{"name":"needs review"}]"#.utf8)
        let names = try GitHubClient.decodeLabels(data)
        try expect(names == ["italy", "needs review"], "Label decoding")
    }

    private static func testFormOptionFilter() throws {
        let options = ["needs review", "Needs-analysis", "Café", "fprod", "fp-runner"]
        try expect(FormOptionFilter.filter(options, query: "NEEDS") == ["needs review", "Needs-analysis"], "Case-insensitive option filtering")
        try expect(FormOptionFilter.filter(options, query: "cafe") == ["Café"], "Diacritic-insensitive option filtering")
        try expect(FormOptionFilter.filter(options, query: "  needs   rev ") == ["needs review"], "Whitespace-normalized option filtering")
        try expect(FormOptionFilter.filter(options, query: "fpr") == ["fprod"], "Reviewer substring filtering")
        try expect(FormOptionFilter.shouldInsertSpace(in: options, query: "needs") && FormOptionFilter.shouldInsertSpace(in: ["Status: needs review"], query: "needs"), "Space continues a matching multi-word option")
        try expect(!FormOptionFilter.shouldInsertSpace(in: options, query: "fpr") && !FormOptionFilter.shouldInsertSpace(in: options, query: "needs "), "Space still toggles ordinary single-word matches")
    }

    private static func testLabelConfig() throws {
        let json = ##"{"sections":[{"id":"mine","label":"Mine","query":"author:@me","labels":{"4":"label:urgent"},"icons":["custom","also-unknown"]}],"labels":{"3":"label:priority"}}"##
        let config = try JSONDecoder().decode(InboxConfig.self, from: Data(json.utf8))
        let section = config.icons(for: config.validatedSections)[0]
        try expect(section.effectiveLabel == "Mine" && config.labels(for: section) == ["3":"label:priority","4":"label:urgent"] && section.effectiveIcons.count == 1, "Numbered tab config")
        let binding = try shortcutBinding(action: "tab4", string: "cmd-4")
        try expect(binding?.action == "tab4" && binding?.shortcut == "cmd-4" && LabelShortcutParser.parse("tab10") == nil, "Numbered shortcut parsing")
    }

    private static func testThemeAndShortcuts() throws {
        try expect(Color(inboxHex: "#0D1117") != nil, "RGB color parsing")
        try expect(Color(inboxHex: "#FFFFFF80") != nil, "RGBA color parsing")
        let orange = NSColor(Color(inboxHex: "#FFA657")!).usingColorSpace(.sRGB)
        try expect(orange != nil && abs(orange!.redComponent - 1) < 0.001 && abs(orange!.greenComponent - 166.0 / 255) < 0.001 && abs(orange!.blueComponent - 87.0 / 255) < 0.001, "RGB channel values")
        let translucent = NSColor(Color(inboxHex: "#FFFFFF80")!).usingColorSpace(.sRGB)
        try expect(translucent != nil && abs(translucent!.alphaComponent - 128.0 / 255) < 0.001, "RGBA alpha value")
        try expect(Color(inboxHex: "not-a-color") == nil, "Invalid color rejection")
        Theme.applyFont("Geist Mono")
        try expect(Theme.fontFamily == "Geist Mono", "Custom font family")
        Theme.applyFont("   ")
        try expect(Theme.fontFamily == "JetBrains Mono", "Blank font restores the default")
        let upper = ShortcutBinding.parse("K")
        try expect(upper?.key == "k" && upper?.shift == true, "Uppercase shortcut parsing")
        let command = ShortcutBinding.parse("cmd-shift-o")
        try expect(command?.key == "o" && command?.command == true && command?.shift == true, "Modified shortcut parsing")
        let custom = ShortcutMap(overrides: ["nextPR": ["x"]])
        try expect(custom.display(for: .nextPR) == "x" && custom.display(for: .previousPR) == "k" && custom.display(for: .refresh) == "⌘r", "Shortcut overrides preserve unspecified defaults")
    }

    private static func testDiffviewLauncher() throws {
        let pr = PullRequest(
            id: "nomoapp/nomo-server-app#42", number: 42, title: "Test diff",
            url: URL(string: "https://github.com/nomoapp/nomo-server-app/pull/42")!,
            repository: "nomoapp/nomo-server-app", author: "test", headRef: "feature/test", baseRef: "main",
            draft: false, createdAt: Date(), updatedAt: Date(), additions: 0, deletions: 0,
            decision: nil, mergeable: nil, mergeState: nil, unresolved: 0,
            approvedBy: [], changesBy: [], requested: [], checks: CheckCounts())
        let arguments = try DiffviewLauncher.arguments(for: pr)
        try expect(!arguments.contains("--space") && !arguments.contains("--folder") && arguments.contains("PR #42 · diff"), "Diffview inherits the active Herdr context")
        let argv = try JSONDecoder().decode([String].self, from: Data(arguments.last!.utf8))
        let script = argv.last ?? ""
        try expect(argv.first == "/bin/zsh" && script.contains("+refs/pull/42/head:refs/remotes/origin/pr/42/head") && script.contains("DiffviewOpen origin/main...origin/pr/42/head") && script.contains("Wrong repository") && script.contains("gh auth token") && script.contains("--no-tags"), "Diffview fetch, gh fallback, validation and launch script")
        let syntax = Process()
        syntax.executableURL = URL(fileURLWithPath: "/bin/zsh")
        syntax.arguments = ["-n", "-c", script]
        try syntax.run()
        syntax.waitUntilExit()
        try expect(syntax.terminationStatus == 0, "Diffview script has valid zsh syntax")
        try expect(DiffviewLauncher.shellQuote("a'b") == "'a'\\''b'", "Diffview shell quoting")
        let rexArguments = RexDiffviewLauncher.arguments(for: pr, session: "session:test", directory: "/tmp/nomo-server-app")
        try expect(rexArguments.contains("--autostart=false") && rexArguments.contains("window") && rexArguments.contains("session:test") && rexArguments.contains("/tmp/nomo-server-app") && rexArguments.contains("--keep-open"), "Rex named Diff tab in the selected session and checkout")
        try expect(RexDiffviewLauncher.repositoryName(fromRemote: "git@github.com:nomoapp/nomo-server-app.git") == "nomoapp/nomo-server-app" && RexDiffviewLauncher.repositoryName(fromRemote: "https://github.com/nomoapp/nomo-server-app") == "nomoapp/nomo-server-app" && RexDiffviewLauncher.repositoryName(fromRemote: "ssh://git@github.com/nomoapp/nomo-server-app.git") == "nomoapp/nomo-server-app", "Rex repository remote parsing")
        let integrationConfig = try JSONDecoder().decode(InboxConfig.self, from: Data("{\"sections\":[],\"repositories\":{\"nomoapp/nomo-server-app\":\"~/dev/nomo-server-app\"},\"rexSession\":\"Dashboard\"}".utf8))
        try expect(integrationConfig.repositories?["nomoapp/nomo-server-app"] == "~/dev/nomo-server-app" && integrationConfig.rexSession == "Dashboard", "Rex session and repository config decoding")
        let clients = Data(#"{"clients":[{"client_id":"client:app","info":{"kind":"app"},"principal":{"pid":44932},"session_ids":["session:test"]},{"client_id":"client:cli","info":{"kind":"cli"},"principal":{"pid":1}}]}"#.utf8)
        let pids = try RexDiffviewLauncher.applicationPIDs(from: clients, session: "session:test")
        try expect(pids == [44932], "Rex app client used to focus the Diff tab")
        let clientID = try RexDiffviewLauncher.applicationClientID(from: clients, session: "session:test")
        try expect(clientID == "client:app", "Rex client receives the real UI tab selection")
        let rexWindow = try RexDiffviewLauncher.createdWindow(from: Data(#"{"window_id":"window:test","block_ids":["block:diff"]}"#.utf8))
        try expect(rexWindow?.windowID == "window:test" && rexWindow?.blockID == "block:diff", "Rex exact window and block focus targets")
        let herdrTerminal = try DiffviewLauncher.createdTerminal(from: Data(#"{"space":"s1","tab":"t1","terminal":"term:diff"}"#.utf8))
        try expect(herdrTerminal == "term:diff", "Herdr exact terminal focus target")
    }

    private static func testStacks() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        func pr(_ number: Int, _ head: String, _ baseRef: String,
                decision: String? = nil, mergeState: String? = nil) -> PullRequest {
            PullRequest(id: "example/repo#\(number)", number: number, title: "PR \(number)",
                        url: URL(string: "https://github.com/example/repo/pull/\(number)")!,
                        repository: "example/repo", author: "test", headRef: head, baseRef: baseRef,
                        draft: false, createdAt: base, updatedAt: base, additions: 0, deletions: 0,
                        decision: decision, mergeable: nil, mergeState: mergeState, unresolved: 0,
                        approvedBy: [], changesBy: [], requested: [], checks: CheckCounts())
        }
        let groups = PRGrouper.stacks([pr(2, "top", "bottom"), pr(1, "bottom", "main")])
        try expect(groups.count == 1 && groups[0].members.map(\.number) == [1, 2], "Stack grouping")
        try expect(PRGrouper.stacks([pr(3, "feature", "main")]).count == 1, "Independent PR grouping")
        let sameHead = PRGrouper.stacks([pr(3, "feature", "main"), pr(4, "feature", "main")])
        try expect(sameHead.flatMap(\.members).map(\.number) == [3, 4],
                   "Different PRs sharing a head ref do not crash or disappear")
        let sameID = PRGrouper.stacks([pr(3, "feature", "main"), pr(3, "feature-copy", "main")])
        try expect(sameID.flatMap(\.members).map(\.number) == [3],
                   "Duplicate stable PR identities are grouped only once")
        try expect(PRActionArguments.merge(pr(3, "feature", "main")) ==
                   ["pr", "merge", "3", "--repo", "example/repo", "--squash"],
                   "Merge action always uses the repository-required squash strategy")
        let clean = pr(5, "clean", "main", decision: "APPROVED", mergeState: "CLEAN")
        try expect(PRDisplayStatus.resolve(clean, review: false).text == "Ready to merge",
                   "Approved clean PRs transition visibly to ready to merge")
        let blocked = pr(6, "blocked", "main", decision: "APPROVED", mergeState: "BLOCKED")
        try expect(PRDisplayStatus.resolve(blocked, review: false).text == "Blocked",
                   "Branch-protection blocking is visible instead of a stale approved state")
        let behind = pr(7, "behind", "main", decision: "APPROVED", mergeState: "BEHIND")
        try expect(PRDisplayStatus.resolve(behind, review: false).text == "Behind base",
                   "Behind-base state is visible")
        try expect(PRDisplayStatus.resolve(clean, review: true).text == "Approved",
                   "Review view retains its approved status")
    }
}
#endif
