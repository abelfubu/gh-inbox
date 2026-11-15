import AppKit
import Foundation

enum InboxForm: Equatable {
    case labels
    case reviewers
    case approve
}

enum FormOptionFilter {
    static func filter(_ candidates: [String], query: String) -> [String] {
        let query = normalize(query)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { normalize($0).contains(query) }
    }

    static func shouldInsertSpace(in candidates: [String], query: String) -> Bool {
        guard !query.isEmpty, query.last?.isWhitespace != true else { return false }
        let continuation = normalize(query) + " "
        return candidates.contains { normalize($0).contains(continuation) }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct RefreshPayload: Sendable {
    let login: String
    let results: [String: SectionResult]
}

@MainActor
final class InboxStore: ObservableObject {
    @Published var sections: [InboxSection] = InboxConfig.standard.validatedSections
    @Published var results: [String: SectionResult] = [:]
    @Published var selectedSectionID = "mine"
    @Published var selectedPRID: String?
    @Published var actionOpen = false
    @Published var actionIndex = 0
    @Published var activeForm: InboxForm?
    @Published var formText = ""
    @Published var formError: String?
    @Published var reviewerCandidates: [String] = []
    @Published var labelCandidates: [String] = []
    @Published var selectedFormItems: Set<String> = []
    @Published var reviewerIndex = 0
    @Published var reviewersLoading = false
    @Published var labelsLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var lastUpdated: Date?
    @Published var folded: Set<String> = []
    @Published private(set) var login = ""
    @Published private(set) var shortcuts = ShortcutMap.standard

    let configStore: ConfigStore
    private let defaults = UserDefaults.standard
    private var autoTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(configStore: ConfigStore = .standard) {
        self.configStore = configStore
        selectedSectionID = defaults.string(forKey: "selectedTab") ?? "mine"
        if let saved = defaults.array(forKey: "folded") as? [String] {
            folded = Set(saved)
        } else {
            folded = ["review:teams"]
        }
    }

    deinit {
        autoTask?.cancel()
        refreshTask?.cancel()
    }

    var selectedSection: InboxSection {
        sections.first { $0.id == selectedSectionID } ?? sections[0]
    }

    var currentPRs: [PullRequest]? {
        results[selectedSectionID]?.prs
    }

    var selectedPR: PullRequest? {
        guard let selectedPRID else { return nil }
        return currentPRs?.first { $0.id == selectedPRID }
    }

    var currentActions: [InboxAction] {
        guard let pr = selectedPR else { return [] }
        return actions(for: pr)
    }

    func actions(for pr: PullRequest) -> [InboxAction] {
        var actions = [
            InboxAction(id: "open", title: "Open on GitHub", symbol: "safari", detail: shortcuts.display(for: .openSelected)),
            InboxAction(id: "diff", title: "Open diff in Neovim", symbol: "doc.text.magnifyingglass", detail: shortcuts.display(for: .diff)),
            InboxAction(id: "copy", title: "Copy PR URL", symbol: "doc.on.doc", detail: shortcuts.display(for: .copy)),
        ]
        if pr.author != login {
            actions.append(InboxAction(id: "approve", title: "Approve pull request", symbol: "checkmark.circle", detail: shortcuts.display(for: .approve)))
        }
        if pr.draft {
            actions.append(InboxAction(id: "ready", title: "Mark as ready for review", symbol: "paperplane", detail: shortcuts.display(for: .ready)))
        } else {
            actions.append(InboxAction(id: "merge", title: "Merge with GitHub", symbol: "arrow.triangle.merge", detail: shortcuts.display(for: .merge)))
        }
        actions += [
            InboxAction(id: "labels", title: "Add labels", symbol: "tag", detail: shortcuts.display(for: .labels)),
            InboxAction(id: "reviewers", title: "Request reviewers", symbol: "person.badge.plus", detail: ""),
            InboxAction(id: "assign", title: "Assign to me", symbol: "person.crop.circle", detail: shortcuts.display(for: .assign)),
        ]
        return actions
    }

    func start() {
        refresh()
        guard autoTask == nil else { return }
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        autoTask?.cancel()
        autoTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRefreshing = false; self.refreshTask = nil }
            do {
                let config = try self.configStore.load()
                Theme.apply(config.colors ?? [:])
                Theme.applyFont(config.font)
                let validated = config.validatedSections
                self.sections = config.icons(for: validated)
                let mappings = config.labels(for: self.selectedSection)
                self.shortcuts = ShortcutMap(overrides: config.shortcuts, labels: mappings)
                if !self.sections.contains(where: { $0.id == self.selectedSectionID }) {
                    self.selectedSectionID = self.sections[0].id
                }
                let sections = self.sections
                let payload = try await Task.detached(priority: .userInitiated) { () throws -> RefreshPayload in
                    let client = try GitHubClient()
                    let results = await withTaskGroup(of: SectionResult.self, returning: [String: SectionResult].self) { group in
                        for section in sections {
                            group.addTask {
                                do {
                                    return SectionResult(id: section.id, prs: try await client.fetchSection(section))
                                } catch {
                                    return SectionResult(id: section.id, error: error.localizedDescription)
                                }
                            }
                        }
                        var results: [String: SectionResult] = [:]
                        for await result in group { results[result.id] = result }
                        return results
                    }
                    return RefreshPayload(login: client.login, results: results)
                }.value
                self.login = payload.login
                self.results = payload.results
                let errors = payload.results.values.compactMap(\.error)
                self.errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
                self.lastUpdated = Date()
                self.ensureSelection()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func selectTab(_ id: String) {
        guard sections.contains(where: { $0.id == id }) else { return }
        selectedSectionID = id
        defaults.set(id, forKey: "selectedTab")
        selectedPRID = nil
        actionOpen = false
        ensureSelection()
    }

    func moveTab(_ delta: Int) {
        guard let index = sections.firstIndex(where: { $0.id == selectedSectionID }), !sections.isEmpty else { return }
        selectTab(sections[(index + delta + sections.count) % sections.count].id)
    }

    var navigationPRs: [PullRequest] {
        guard let prs = currentPRs else { return [] }
        if selectedSection.effectiveView == "review" {
            let direct = prs.filter { $0.requested.contains(login) }.sorted { $0.updatedAt > $1.updatedAt }
            let teams = prs.filter { !$0.requested.contains(login) }.sorted { $0.updatedAt > $1.updatedAt }
            return (folded.contains("review:you") ? [] : direct) + (folded.contains("review:teams") ? [] : teams)
        }
        var output: [PullRequest] = []
        for group in PRGrouper.stacks(prs) {
            if group.members.count > 1, folded.contains("stack:\(group.id)") { continue }
            output.append(contentsOf: group.members.reversed())
        }
        return output
    }

    func ensureSelection() {
        guard !actionOpen else { return }
        let items = navigationPRs
        if !items.contains(where: { $0.id == selectedPRID }) { selectedPRID = items.first?.id }
    }

    func moveSelection(_ delta: Int) {
        if actionOpen {
            let count = currentActions.count
            guard count > 0 else { return }
            actionIndex = (actionIndex + delta + count) % count
            return
        }
        let items = navigationPRs
        guard !items.isEmpty else { selectedPRID = nil; return }
        guard let current = items.firstIndex(where: { $0.id == selectedPRID }) else {
            selectedPRID = items[delta >= 0 ? 0 : items.count - 1].id
            return
        }
        selectedPRID = items[(current + delta + items.count) % items.count].id
    }

    func selectPR(_ pr: PullRequest) {
        selectedPRID = pr.id
    }

    func toggleFold(_ id: String) {
        if folded.contains(id) { folded.remove(id) } else { folded.insert(id) }
        defaults.set(folded.sorted(), forKey: "folded")
        ensureSelection()
    }

    func toggleFoldForSelection() {
        guard let pr = selectedPR else { return }
        if selectedSection.effectiveView == "review" {
            toggleFold(pr.requested.contains(login) ? "review:you" : "review:teams")
        } else if let group = PRGrouper.stacks(currentPRs ?? []).first(where: { $0.members.contains(where: { $0.id == pr.id }) }), group.members.count > 1 {
            toggleFold("stack:\(group.id)")
        }
    }

    func showActions() {
        ensureSelection()
        guard selectedPR != nil else { return }
        actionOpen = true
        actionIndex = 0
    }

    func openSelected() {
        if actionOpen {
            let actions = currentActions
            guard actions.indices.contains(actionIndex) else { return }
            runAction(actions[actionIndex].id)
        } else if let pr = selectedPR {
            NSWorkspace.shared.open(pr.url)
        }
    }

    var filteredFormOptions: [String] {
        FormOptionFilter.filter(activeForm == .labels ? labelCandidates : reviewerCandidates, query: formText)
    }

    func handleOptionSpace() {
        let candidates = activeForm == .labels ? labelCandidates : reviewerCandidates
        if FormOptionFilter.shouldInsertSpace(in: candidates, query: formText) {
            formText += " "
        } else {
            toggleCurrentOption()
        }
    }

    var formOptionsLoading: Bool {
        activeForm == .labels ? labelsLoading : reviewersLoading
    }

    func escape() {
        if activeForm != nil { closeForm() } else if actionOpen { actionOpen = false } else { selectedPRID = nil }
    }

    func closeForm() {
        activeForm = nil
        formText = ""
        formError = nil
        selectedFormItems = []
        reviewersLoading = false
        labelsLoading = false
    }

    func moveOption(_ delta: Int) {
        let count = filteredFormOptions.count
        guard count > 0 else { return }
        reviewerIndex = (reviewerIndex + delta + count) % count
    }

    func toggleCurrentOption() {
        let options = filteredFormOptions
        guard options.indices.contains(reviewerIndex) else { return }
        let option = options[reviewerIndex]
        if selectedFormItems.contains(option) {
            selectedFormItems.remove(option)
        } else {
            selectedFormItems.insert(option)
        }
    }

    func submitForm() {
        guard let form = activeForm, let pr = selectedPR else { return }
        switch form {
        case .labels:
            let labels = selectedFormItems.sorted()
            guard !labels.isEmpty else { formError = "Select at least one label."; return }
            activeForm = nil
            perform(pr, arguments: ["pr", "edit", "\(pr.number)", "--repo", pr.repository] + labels.flatMap { ["--add-label", $0] }, success: "Added \(labels.count) label\(labels.count == 1 ? "" : "s") to \(pr.reference)")
        case .reviewers:
            let reviewers = selectedFormItems.sorted()
            guard !reviewers.isEmpty else { formError = "Select at least one reviewer."; return }
            activeForm = nil
            perform(pr, arguments: ["pr", "edit", "\(pr.number)", "--repo", pr.repository] + reviewers.flatMap { ["--add-reviewer", $0] }, success: "Requested \(reviewers.count) reviewer\(reviewers.count == 1 ? "" : "s") on \(pr.reference)")
        case .approve:
            let body = formText.trimmingCharacters(in: .whitespacesAndNewlines)
            activeForm = nil
            var arguments = ["pr", "review", "\(pr.number)", "--repo", pr.repository, "--approve"]
            if !body.isEmpty { arguments += ["--body", body] }
            perform(pr, arguments: arguments, success: "Approved \(pr.reference)")
        }
    }

    func runAction(_ id: String) {
        guard let pr = selectedPR else { return }
        actionOpen = false
        switch id {
        case "open": NSWorkspace.shared.open(pr.url)
        case "diff": openDiff(pr)
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            notice = "Copied \(pr.reference)"
        case "approve":
            formText = ""
            formError = nil
            activeForm = .approve
        case "ready": perform(pr, arguments: ["pr", "ready", "\(pr.number)", "--repo", pr.repository], success: "Marked \(pr.reference) ready")
        case "merge":
            guard confirm("Merge \(pr.reference)?", "\(pr.title)\n\nThis merges into \(pr.baseRef) using a merge commit.", button: "Merge") else { return }
            perform(pr, arguments: ["pr", "merge", "\(pr.number)", "--repo", pr.repository, "--merge"], success: "Merged \(pr.reference)")
        case "labels":
            formText = ""
            formError = nil
            selectedFormItems = []
            reviewerIndex = 0
            labelCandidates = []
            activeForm = .labels
            loadLabels(for: pr)
        case "reviewers":
            formText = ""
            formError = nil
            selectedFormItems = []
            reviewerIndex = 0
            reviewerCandidates = []
            activeForm = .reviewers
            loadReviewers(for: pr)
        case "assign":
            perform(pr, arguments: ["pr", "edit", "\(pr.number)", "--repo", pr.repository, "--add-assignee", login], success: "Assigned \(pr.reference) to you")
        default: break
        }
    }

    func hint(_ action: ShortcutAction) -> String {
        shortcuts.display(for: action)
    }

    func selectNumberedTab(_ number: Int) {
        guard sections.indices.contains(number - 1) else { return }
        selectTab(sections[number - 1].id)
    }

    func performShortcut(_ action: ShortcutAction) {
        switch action {
        case .nextPR: moveSelection(1)
        case .previousPR: moveSelection(-1)
        case .previousTab: moveTab(-1)
        case .nextTab: moveTab(1)
        case .openSelected: openSelected()
        case .actions: showActions()
        case .cancel: escape()
        case .fold: toggleFoldForSelection()
        case .refresh: refresh()
        case .copy, .diff, .merge, .approve, .ready, .assign, .labels:
            runAction(action.rawValue)
        case .openConfig: configStore.open()
        case .closeWindow: NSApp.keyWindow?.close()
        case .nextOption: moveOption(1)
        case .previousOption: moveOption(-1)
        case .toggleOption: handleOptionSpace()
        case .submitForm, .submitApproval: submitForm()
        }
    }

    func runSmokeTest() {
        Task {
            for _ in 0..<1200 {
                if lastUpdated != nil {
                    let missing = sections.filter { results[$0.id]?.prs == nil }
                    guard missing.isEmpty else {
                        FileHandle.standardError.write(Data("Missing sections: \(missing.map(\.id).joined(separator: ","))\n".utf8))
                        exit(1)
                    }
                    for section in sections {
                        print("\(section.id): \(results[section.id]?.prs?.count ?? 0) PRs")
                    }
                    print("GitHub smoke test passed")
                    exit(0)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            FileHandle.standardError.write(Data("GitHub smoke test timed out\n".utf8))
            exit(1)
        }
    }

    private func openDiff(_ pr: PullRequest) {
        do {
            let config = try configStore.load()
            notice = "Opening \(pr.reference) in Diffview…"
            Task {
                do {
                    let target = try await Task.detached {
                        try DiffviewLauncher.launch(pr, repositoryPaths: config.repositories ?? [:], rexSession: config.rexSession)
                    }.value
                    self.notice = target == .herdr
                        ? "Opened \(pr.reference) in the active Herdr space"
                        : "Opened \(pr.reference) in Rex"
                } catch {
                    self.notice = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ pr: PullRequest, arguments: [String], success: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GH_INBOX_DRY_RUN"] == "1" {
            notice = "DRY RUN: \(success)"
            return
        }
        #endif
        notice = "Working on \(pr.reference)…"
        Task {
            do {
                _ = try await Task.detached { try GitHubClient().perform(arguments) }.value
                self.notice = success
                self.refresh()
            } catch {
                self.notice = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func confirm(_ title: String, _ message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func loadLabels(for pr: PullRequest) {
        labelsLoading = true
        Task {
            do {
                let names = try await Task.detached {
                    let client = try GitHubClient()
                    let output = try client.perform(["label", "list", "--repo", pr.repository, "--limit", "200", "--json", "name"])
                    return try GitHubClient.decodeLabels(Data(output.utf8))
                }.value
                guard activeForm == .labels, selectedPRID == pr.id else { return }
                labelCandidates = names.sorted()
                reviewerIndex = 0
                labelsLoading = false
            } catch {
                guard activeForm == .labels else { return }
                labelsLoading = false
                formError = error.localizedDescription
            }
        }
    }

    private func loadReviewers(for pr: PullRequest) {
        reviewersLoading = true
        Task {
            do {
                let names = try await Task.detached {
                    let client = try GitHubClient()
                    let output = try client.perform(["api", "repos/\(pr.repository)/collaborators?per_page=100"])
                    return try GitHubClient.decodeCollaborators(Data(output.utf8))
                }.value
                guard activeForm == .reviewers, selectedPRID == pr.id else { return }
                reviewerCandidates = names.filter { $0 != pr.author && !pr.requested.contains($0) }.sorted()
                reviewerIndex = 0
                reviewersLoading = false
            } catch {
                guard activeForm == .reviewers else { return }
                reviewersLoading = false
                formError = error.localizedDescription
            }
        }
    }
}
