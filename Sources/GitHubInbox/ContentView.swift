import AppKit
import SwiftUI

private enum FocusTarget {
    case panel
    case formInput
}

struct ContentView: View {
    @ObservedObject var store: InboxStore
    @FocusState private var focusTarget: FocusTarget?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width < 160 {
                    rail
                } else {
                    VStack(spacing: 0) {
                        header
                        listBody
                        statusBar
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Theme.background)
            .overlay {
                if let form = store.activeForm {
                    formPopup(form, availableSize: geometry.size)
                } else if store.actionOpen {
                    actionPopup(availableSize: geometry.size)
                }
            }
            .focusable()
            .focused($focusTarget, equals: .panel)
            .focusEffectDisabled()
            .onKeyPress { press in
                if store.activeForm != nil && press.modifiers.isEmpty && press.key != .escape { return .ignored }
                let allowed = store.activeForm == nil ? ShortcutAction.globalCases : ShortcutAction.formGlobalCases
                if store.activeForm == nil, let number = store.shortcuts.numberedAction(for: press) {
                    focusTarget = .panel
                    store.selectNumberedTab(number)
                    return .handled
                }
                guard let action = store.shortcuts.action(for: press, in: allowed) else { return .ignored }
                if store.activeForm == nil { focusTarget = .panel }
                store.performShortcut(action)
                return .handled
            }
            .simultaneousGesture(TapGesture().onEnded {
                if store.activeForm == nil { focusTarget = .panel }
            })
        }
        .onAppear {
            focusTarget = .panel
            if let tab = ProcessInfo.processInfo.environment["GH_INBOX_TAB"] { store.selectTab(tab) }
            store.start()
            if ProcessInfo.processInfo.environment["GH_INBOX_SMOKE"] == "1" { store.runSmokeTest() }
            if let path = ProcessInfo.processInfo.environment["GH_INBOX_SCREENSHOT"] { captureOwnView(at: path) }
            if ProcessInfo.processInfo.environment["GH_INBOX_KEY_SMOKE"] == "1" { runKeySmoke() }
            #if DEBUG
            if ProcessInfo.processInfo.environment["GH_INBOX_FORM_SMOKE"] == "1" { runFormFocusSmoke() }
            #endif
        }
        .onChange(of: store.activeForm) { _, form in
            if form == nil {
                focusTarget = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if store.activeForm == nil { focusTarget = .panel }
                }
            }
        }
        .onChange(of: store.actionOpen) { _, open in
            if !open && store.activeForm == nil {
                focusTarget = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if store.activeForm == nil && !store.actionOpen { focusTarget = .panel }
                }
            }
        }
        .onDisappear { store.stop() }
    }

    private func sendKey(_ character: String, keyCode: UInt16) {
        guard let window = NSApp.windows.first,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: character,
                                           charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode) else { return }
        NSApp.sendEvent(event)
    }

    private func runKeySmoke() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            store.folded = []
            guard let testSection = store.sections.first(where: { (store.results[$0.id]?.prs?.count ?? 0) >= 2 }) else {
                preconditionFailure("Key smoke needs a section with at least two PRs")
            }
            store.selectTab(testSection.id)
            sendKey("2", keyCode: 19)
            precondition(store.selectedSectionID == store.sections[1].id, "2 did not select the second tab")
            store.selectTab(testSection.id)
            let items = store.navigationPRs
            precondition(items.count >= 2, "Key smoke section has fewer than two visible PRs")
            sendKey("j", keyCode: 38)
            precondition(store.selectedPRID == items[1].id, "j did not move to the second PR")
            sendKey("k", keyCode: 40)
            precondition(store.selectedPRID == items[0].id, "k did not move to the first PR")
            sendKey("l", keyCode: 37)
            precondition(store.selectedSectionID != testSection.id, "l did not move to the next tab")
            sendKey("h", keyCode: 4)
            precondition(store.selectedSectionID == testSection.id, "h did not return to the previous tab")
            sendKey("o", keyCode: 31)
            precondition(store.actionOpen, "o did not open actions")
            sendKey("j", keyCode: 38)
            precondition(store.actionIndex == 1, "j did not navigate the action popup")
            sendKey("k", keyCode: 40)
            precondition(store.actionIndex == 0, "k did not navigate the action popup")
            sendKey("\u{1b}", keyCode: 53)
            precondition(!store.actionOpen, "Escape did not close actions")
            let foldID: String?
            if store.selectedSection.effectiveView == "review", let pr = store.selectedPR {
                foldID = pr.requested.contains(store.login) ? "review:you" : "review:teams"
            } else if let group = PRGrouper.stacks(store.currentPRs ?? []).first(where: { $0.members.count > 1 }) {
                foldID = "stack:\(group.id)"
                store.selectPR(group.members[0])
            } else {
                foldID = nil
            }
            let foldPR = store.selectedPR
            if let foldID {
                sendKey("f", keyCode: 3)
                precondition(store.folded.contains(foldID), "f did not fold")
                if let foldPR { store.selectPR(foldPR) }
                sendKey("f", keyCode: 3)
                precondition(!store.folded.contains(foldID), "f did not unfold")
            }
            print("native key smoke: PASS")
            exit(0)
        }
    }

    #if DEBUG
    private func runFormFocusSmoke() {
        setenv("GH_INBOX_DRY_RUN", "1", 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard let section = store.sections.first(where: { store.results[$0.id]?.prs?.isEmpty == false }) else {
                preconditionFailure("No configured tab contained PRs for the form test")
            }
            store.selectTab(section.id)
            precondition(store.selectedPR != nil, "No PR was available for the form test")
            store.showActions()
            guard let reviewerAction = store.currentActions.firstIndex(where: { $0.id == "reviewers" }) else {
                preconditionFailure("Reviewer action was unavailable")
            }
            store.actionIndex = reviewerAction
            store.openSelected()
            precondition(store.activeForm == .reviewers && !store.actionOpen, "Action popup did not transition to the reviewer popup")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                precondition(focusTarget == .formInput, "Reviewer input did not receive focus")
                precondition(!store.reviewersLoading && !store.reviewerCandidates.isEmpty, "Reviewers did not load")
                sendKey("f", keyCode: 3)
                precondition(store.formText == "f" && focusTarget == .formInput, "Focus was lost after the first character")
                sendKey("p", keyCode: 35)
                precondition(store.formText == "fp" && focusTarget == .formInput, "Focus was lost after the second character")
                sendKey("r", keyCode: 15)
                precondition(store.formText == "fpr" && focusTarget == .formInput, "Focus was lost after the third character")
                store.formText = ""
                store.reviewerIndex = 0
                precondition(store.filteredFormOptions.count >= 2, "Reviewer test needs at least two selectable collaborators")
                sendKey(" ", keyCode: 49)
                precondition(store.selectedFormItems.count == 1, "Space did not select the first reviewer")
                store.moveOption(1)
                sendKey(" ", keyCode: 49)
                precondition(store.selectedFormItems.count == 2, "Space did not select a second reviewer")
                sendKey("\r", keyCode: 36)
                precondition(store.activeForm == nil, "Enter did not submit the selected reviewers")
                precondition(store.notice?.contains("DRY RUN") == true, "Reviewer selection did not reach the dry-run action")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    precondition(focusTarget == .panel, "List focus was not restored after Enter")
                    store.runAction("approve")
                    precondition(store.activeForm == .approve, "Approve did not open its review form")
                    store.formText = "Looks good!\nShip it."
                    store.submitForm()
                    precondition(store.activeForm == nil && store.notice?.contains("DRY RUN") == true, "Approval message was not submitted")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        precondition(focusTarget == .panel, "List focus was not restored after approval")
                        store.runAction("reviewers")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sendKey("\u{1b}", keyCode: 53)
                            precondition(store.activeForm == nil, "Escape did not close the form")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                precondition(focusTarget == .panel, "List focus was not restored after Escape")
                                sendKey("o", keyCode: 31)
                                precondition(store.actionOpen, "Shortcuts did not resume after closing the form")
                                sendKey("\u{1b}", keyCode: 53)
                                precondition(!store.actionOpen, "Escape did not close actions")
                                store.activeForm = .labels
                                store.labelCandidates = ["needs review", "bug"]
                                store.formText = "needs"
                                store.reviewerIndex = 0
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    precondition(focusTarget == .formInput, "Label filter did not receive focus")
                                    sendKey(" ", keyCode: 49)
                                    precondition(store.formText == "needs ", "Space did not continue a multi-word label search: \(store.formText)")
                                    precondition(store.filteredFormOptions == ["needs review"], "Multi-word label filter returned incorrect results")
                                    precondition(store.selectedFormItems.isEmpty, "Typing a filter space unexpectedly selected a label")
                                    store.formText = "bug"
                                    store.reviewerIndex = 0
                                    sendKey(" ", keyCode: 49)
                                    precondition(store.selectedFormItems == ["bug"], "Space no longer toggled a single-word option")
                                    store.closeForm()
                                    print("native multi-select, filtering, focus and approval smoke: PASS")
                                    exit(0)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #endif

    private func captureOwnView(at path: String) {
        let form = ProcessInfo.processInfo.environment["GH_INBOX_FORM"]
        #if DEBUG
        if let width = ProcessInfo.processInfo.environment["GH_INBOX_WIDTH"].flatMap(Double.init),
           let height = ProcessInfo.processInfo.environment["GH_INBOX_HEIGHT"].flatMap(Double.init),
           width > 0, height > 0 {
            DispatchQueue.main.async {
                NSApp.windows.first?.setContentSize(NSSize(width: width, height: height))
            }
        }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if let tab = ProcessInfo.processInfo.environment["GH_INBOX_TAB"] { store.selectTab(tab) }
            if let form {
                if form == "actions" { store.showActions() } else { store.runAction(form) }
                if let filter = ProcessInfo.processInfo.environment["GH_INBOX_FILTER"] {
                    if ProcessInfo.processInfo.environment["GH_INBOX_TYPE"] == "1" {
                        let keyCodes: [Character: UInt16] = ["a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6]
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            for character in filter.lowercased() {
                                sendKey(String(character), keyCode: keyCodes[character] ?? 0)
                            }
                        }
                    } else {
                        store.formText = filter
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (form == nil ? 0 : 2)) {
                if ProcessInfo.processInfo.environment["GH_INBOX_FILTER"] != nil {
                    print("Filter '\(store.formText)' → \(store.filteredFormOptions)")
                }
                guard let view = NSApp.windows.first?.contentView,
                      let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: representation)
                guard let data = representation.representation(using: .png, properties: [:]) else { exit(1) }
                do {
                    try data.write(to: URL(fileURLWithPath: path))
                    print(path)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("\(error)\n".utf8))
                    exit(1)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 12, weight: .semibold))
                Text("GITHUB INBOX")
                    .inboxFont(12, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                Text("\(store.currentPRs?.count ?? 0)")
                    .inboxFont(10.5)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.raised, in: Capsule())
                Spacer()
                refreshButton
            }
            tabStrip
            Text(selectedQuery)
                .inboxFont(10)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(selectedQuery)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(height: 88)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var selectedQuery: String {
        store.selectedSection.effectiveQueries
            .map(GitHubClient.qualifiedQuery)
            .joined(separator: " OR ")
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(Array(store.sections.enumerated()), id: \.element.id) { index, section in
                let selected = section.id == store.selectedSectionID
                Button { store.selectTab(section.id) } label: {
                    HStack(spacing: 5) {
                        if index < 9 { Text("\(index + 1)").foregroundStyle(selected ? Theme.foreground : Theme.dim) }
                        Text(section.effectiveLabel)
                        if let count = store.results[section.id]?.prs?.count {
                            Text("\(count)").font(.system(size: 10.5)).foregroundStyle(selected ? Theme.muted : Theme.dim)
                        }
                    }
                    .inboxFont(10.5, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Theme.foreground : Theme.dim)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(selected ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var refreshButton: some View {
        Button { store.refresh() } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.isRefreshing ? Theme.accent : Theme.muted)
        }
        .buttonStyle(.plain)
        .help(store.lastUpdated.map { "Updated \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())). Click to refresh." } ?? "Refresh (r)")
    }

    private var rail: some View {
        VStack(spacing: 12) {
            ForEach(store.sections) { section in
                Button { store.selectTab(section.id) } label: {
                    VStack(spacing: 2) {
                        InboxIcon(section.effectiveIcons.first ?? (section.effectiveView == "review" ? "eye" : "pr"), size: 15, fallback: section.symbol)
                        Text(countText(section.id)).font(.system(size: 10))
                    }
                    .foregroundStyle(section.id == store.selectedSectionID ? Theme.foreground : Theme.dim)
                }.buttonStyle(.plain).help(section.effectiveLabel)
            }
            Spacer()
            Button { store.refresh() } label: { InboxIcon("refresh", size: 12, fallback: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim).padding(.bottom, 12)
        }
        .padding(.top, 14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if let error = store.errorMessage { errorLine(error) }
                    if let prs = store.currentPRs {
                        if prs.isEmpty {
                            Text(store.selectedSection.effectiveView == "review" ? "Nothing is waiting on your review." : "No open pull requests.")
                                .inboxFont(12).foregroundStyle(Theme.dim).padding(10)
                        } else if store.selectedSection.effectiveView == "review" {
                            reviewGroups(prs)
                        } else {
                            stackGroups(prs)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading \(store.selectedSection.label) pull requests…")
                        }.inboxFont(12).foregroundStyle(Theme.dim).padding(10)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: store.selectedPRID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stackGroups(_ prs: [PullRequest]) -> some View {
        let groups = PRGrouper.stacks(prs)
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            if index == 0 || groups[index - 1].repository != group.repository {
                Text(group.repository).inboxFont(10.5, weight: .medium).foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
            }
            if group.members.count > 1 {
                let id = "stack:\(group.id)"
                let open = !store.folded.contains(id)
                Button { store.toggleFold(id) } label: {
                    HStack(spacing: 6) {
                        InboxIcon("stack", size: 12, fallback: "arrow.triangle.pull")
                        Text("Stack of \(group.members.count) · \(group.members.last?.headRef ?? "")").lineLimit(1)
                        Spacer()
                        Text("\(group.members.count) ready").foregroundStyle(Theme.dim)
                        InboxIcon(open ? "chevron-down" : "chevron-right", size: 10, fallback: open ? "chevron.down" : "chevron.right")
                    }
                    .inboxFont(10.5, weight: .medium).foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if open {
                    ForEach(group.members.reversed()) { pr in
                        PRRow(pr: pr, store: store, depth: 1, onHoverExit: { focusTarget = .panel })
                    }
                }
            } else if let pr = group.members.first {
                PRRow(pr: pr, store: store, onHoverExit: { focusTarget = .panel })
            }
        }
    }

    @ViewBuilder
    private func reviewGroups(_ prs: [PullRequest]) -> some View {
        let direct = prs.filter { $0.requested.contains(store.login) }.sorted { $0.updatedAt > $1.updatedAt }
        let teams = prs.filter { !$0.requested.contains(store.login) }.sorted { $0.updatedAt > $1.updatedAt }
        reviewSection(id: "review:you", title: "Requested from you", prs: direct)
        reviewSection(id: "review:teams", title: "Your teams", prs: teams)
    }

    @ViewBuilder
    private func reviewSection(id: String, title: String, prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            let open = !store.folded.contains(id)
            Button { store.toggleFold(id) } label: {
                HStack(spacing: 6) {
                    InboxIcon(open ? "chevron-down" : "chevron-right", size: 10, fallback: open ? "chevron.down" : "chevron.right")
                    Text(title)
                    Text("\(prs.count)")
                    Spacer()
                }
                .inboxFont(11, weight: .medium).foregroundStyle(Theme.dim)
                .padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open { ForEach(prs) { pr in PRRow(pr: pr, store: store, review: true, onHoverExit: { focusTarget = .panel }) } }
        }
    }

    @ViewBuilder
    private func formPopup(_ form: InboxForm, availableSize: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { store.closeForm() }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formTitle(form))
                            .inboxFont(12, weight: .semibold)
                            .foregroundStyle(Theme.foreground)
                        if let pr = store.selectedPR {
                            Text("\(pr.repository)\(pr.reference)")
                                .inboxFont(10.5)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { store.closeForm() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, -12)

                if form == .approve {
                Text("Add an optional review message").inboxFont(11).foregroundStyle(Theme.dim)
                TextField("Looks good!", text: $store.formText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .inboxFont(12).foregroundStyle(Theme.foreground)
                    .lineLimit(6...10)
                    .focused($focusTarget, equals: .formInput)
                    .onKeyPress { press in
                        if press.key == .return && press.modifiers.contains(.command) { store.submitForm(); return .handled }
                        if press.key == .escape { store.closeForm(); return .handled }
                        return .ignored
                    }
                    .padding(10)
                    .frame(minHeight: 130, maxHeight: 220, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Approve") { store.submitForm() }
                        .buttonStyle(.plain).inboxFont(11, weight: .medium).foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
                }
            } else {
                TextField(form == .labels ? "Filter labels…" : "Filter collaborators…", text: $store.formText)
                    .textFieldStyle(.plain).inboxFont(12).foregroundStyle(Theme.foreground)
                    .focused($focusTarget, equals: .formInput)
                    .onKeyPress { press in
                        if press.key == .space { store.handleOptionSpace(); return .handled }
                        if press.key == .return { store.submitForm(); return .handled }
                        if press.key == .downArrow { store.moveOption(1); return .handled }
                        if press.key == .upArrow { store.moveOption(-1); return .handled }
                        if press.key == .escape { store.closeForm(); return .handled }
                        return .ignored
                    }
                    .onChange(of: store.formText) { _, _ in store.reviewerIndex = 0 }
                    .padding(9).background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                if store.formOptionsLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(form == .labels ? "Loading labels…" : "Loading collaborators…")
                    }
                    .inboxFont(11).foregroundStyle(Theme.dim).padding(8)
                } else if store.filteredFormOptions.isEmpty {
                    Text(store.formError == nil ? (form == .labels ? "No matching labels." : "No matching collaborators.") : "")
                        .inboxFont(11).foregroundStyle(Theme.dim).padding(8)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(store.filteredFormOptions.enumerated()), id: \.element) { index, option in
                                    Button {
                                        store.reviewerIndex = index
                                        store.toggleCurrentOption()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: store.selectedFormItems.contains(option) ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 12))
                                                .foregroundStyle(store.selectedFormItems.contains(option) ? Theme.accent : Theme.dim)
                                            Text(option).lineLimit(1)
                                            Spacer()
                                            if index == store.reviewerIndex { Text(store.hint(.toggleOption)).inboxFont(9).foregroundStyle(Theme.dim) }
                                        }
                                        .inboxFont(12).foregroundStyle(Theme.foreground)
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(index == store.reviewerIndex ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .id(option)
                                }
                            }
                        }
                        .frame(height: min(CGFloat(store.filteredFormOptions.count) * 34,
                                           max(68, min(360, availableSize.height - 250))))
                        .onChange(of: store.reviewerIndex) { _, index in
                            let options = store.filteredFormOptions
                            if options.indices.contains(index) { proxy.scrollTo(options[index], anchor: .center) }
                        }
                        .onChange(of: store.formText) { _, _ in
                            if let first = store.filteredFormOptions.first { proxy.scrollTo(first, anchor: .top) }
                        }
                    }
                    HStack {
                        Text("\(store.selectedFormItems.count) selected").inboxFont(10.5).foregroundStyle(Theme.dim)
                        Spacer()
                        Button(form == .labels ? "Add labels" : "Request reviewers") { store.submitForm() }
                            .buttonStyle(.plain).inboxFont(11, weight: .medium).foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
                            .disabled(store.selectedFormItems.isEmpty)
                    }
                }
            }
                if let error = store.formError {
                    Text(error).inboxFont(10.5).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, -12)
                Text(formFooter(form)).inboxFont(9.5).foregroundStyle(Theme.dim)
            }
            .padding(12)
            .frame(width: min(360, max(120, availableSize.width - 24)))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { DispatchQueue.main.async { focusTarget = .formInput } }
        .onKeyPress { press in
            let allowed = form == .approve ? ShortcutAction.approvalCases : ShortcutAction.pickerCases
            guard let action = store.shortcuts.action(for: press, in: allowed) else { return .ignored }
            store.performShortcut(action)
            return .handled
        }
    }

    private func actionPopup(availableSize: CGSize) -> some View {
        let rowHeight: CGFloat = 34
        let maximumRowsHeight = max(68, availableSize.height - 150)
        let rowsHeight = min(CGFloat(store.currentActions.count) * rowHeight, maximumRowsHeight)
        return ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { store.escape() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PR actions")
                            .inboxFont(12, weight: .semibold)
                            .foregroundStyle(Theme.foreground)
                        if let pr = store.selectedPR {
                            Text(pr.reference)
                                .inboxFont(10.5)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    Button { store.escape() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(12)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                        ForEach(Array(store.currentActions.enumerated()), id: \.element.id) { index, action in
                            Button { store.actionIndex = index; store.runAction(action.id) } label: {
                                HStack(spacing: 10) {
                                    InboxIcon(actionIcon(action.id), size: 13, fallback: action.symbol)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 17)
                                    Text(action.title)
                                        .inboxFont(11.5)
                                        .foregroundStyle(Theme.foreground)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 4)
                                    Text(action.detail)
                                        .inboxMono(10)
                                        .foregroundStyle(Theme.dim)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == store.actionIndex ? Theme.raised : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .id(index)
                        }
                        }
                    }
                    .frame(height: rowsHeight)
                    .onChange(of: store.actionIndex) { _, index in
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                Text("\(store.hint(.nextPR))/\(store.hint(.previousPR)) navigate · ↵ run · \(store.hint(.cancel)) back")
                    .inboxFont(9.5)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(width: min(340, max(96, availableSize.width - 24)))
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            if let notice = store.notice {
                Text(notice).inboxFont(10.5).foregroundStyle(Theme.muted)
                    .lineLimit(1).padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface)
            }
            HStack(spacing: 8) {
                if store.activeForm != nil {
                    Text("\(store.hint(.cancel)) cancel")
                } else if store.actionOpen {
                    Text("\(store.hint(.nextPR))/\(store.hint(.previousPR)) navigate")
                    Text("·")
                    Text("\(store.hint(.openSelected)) run")
                    Text("·")
                    Text("\(store.hint(.cancel)) back")
                } else {
                    Text("\(store.hint(.previousTab))/\(store.hint(.nextTab)) tabs")
                    Text("·")
                    Text("\(store.hint(.nextPR))/\(store.hint(.previousPR)) navigate")
                    Text("·")
                    Text("\(store.hint(.actions)) actions")
                    Text("·")
                    Text("\(store.hint(.copy)) copy")
                }
                Spacer()
                if let updated = store.lastUpdated {
                    Text(updated.formatted(date: .omitted, time: .shortened))
                }
            }
            .inboxFont(10)
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.chrome)
        }
    }

    private func formTitle(_ form: InboxForm) -> String {
        switch form {
        case .labels: "Add labels"
        case .reviewers: "Request reviewers"
        case .approve: "Approve pull request"
        }
    }

    private func formFooter(_ form: InboxForm) -> String {
        switch form {
        case .labels, .reviewers:
            "\(store.hint(.previousOption))/\(store.hint(.nextOption)) navigate · \(store.hint(.toggleOption)) toggle · \(store.hint(.submitForm)) submit · \(store.hint(.cancel)) cancel"
        case .approve: "\(store.hint(.submitApproval)) approve · ↵ new line · \(store.hint(.cancel)) cancel"
        }
    }

    private func actionIcon(_ id: String) -> String {
        ["open": "external", "diff": "pr", "copy": "copy", "approve": "approved", "ready": "pr", "merge": "rocket", "labels": "tag", "reviewers": "eye", "assign": "pr"][id] ?? "pr"
    }

    private func countText(_ id: String) -> String {
        guard let count = store.results[id]?.prs?.count else { return "" }
        return String(count)
    }

    private func errorLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .inboxFont(11).foregroundStyle(Theme.red).padding(.horizontal, 10).padding(.vertical, 5)
    }
}

private struct PRRow: View {
    let pr: PullRequest
    @ObservedObject var store: InboxStore
    var depth = 0
    var review = false
    var onHoverExit: () -> Void = {}
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            InboxIcon(pr.draft ? "pr-draft" : "pr", size: 13, fallback: "arrow.triangle.pull")
                .foregroundStyle(pr.draft ? Theme.dim : review ? Theme.muted : status.color)
                .frame(width: 15).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(pr.reference).inboxFont(11).foregroundStyle(Theme.dim)
                    if review { Text("\(pr.author) · \(relative(pr.createdAt))").foregroundStyle(Theme.muted) }
                    else { Text(pr.author).foregroundStyle(Theme.muted) }
                    chip(status.text, symbol: status.symbol, color: status.color)
                    if shouldShowCI {
                        chip(pr.checks.failed > 0 ? "\(pr.checks.failed)" : pr.checks.running > 0 ? "\(pr.checks.passed)/\(pr.checks.total)" : "",
                             symbol: pr.checks.failed > 0 ? "xmark.circle.fill" : pr.checks.running > 0 ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill",
                             color: pr.checks.failed > 0 ? Theme.red : pr.checks.running > 0 ? Theme.orange : Theme.green)
                    }
                    if !pr.approvedBy.isEmpty, !["checkmark.circle.fill", "checkmark.seal.fill"].contains(status.symbol) {
                        chip("\(pr.approvedBy.count)", symbol: "checkmark.seal.fill", color: Theme.green)
                    }
                    if pr.unresolved > 0 { chip("\(pr.unresolved)", symbol: "bubble.left.fill", color: Theme.yellow) }
                    Spacer(minLength: 0)
                }.inboxFont(10.5).lineLimit(1)
                Text(pr.title).inboxFont(12.5, weight: .light).foregroundStyle(pr.draft ? Theme.muted : Theme.foreground)
                    .lineLimit(2).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .padding(.leading, depth > 0 ? 14 : 0)
        .background(store.selectedPRID == pr.id ? Theme.raised : hovered ? Theme.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onContinuousHover { phase in
            if case .ended = phase { onHoverExit() }
        }
        .onTapGesture(count: 2) {
            store.selectPR(pr)
            NSWorkspace.shared.open(pr.url)
        }
        .onTapGesture(count: 1) { store.selectPR(pr) }
        .contextMenu {
            ForEach(store.actions(for: pr)) { action in
                Button(action.title) {
                    store.selectPR(pr)
                    store.runAction(action.id)
                }
            }
        }
        .id(pr.id)
    }

    private var status: (text: String, symbol: String, color: Color) {
        let state = PRDisplayStatus.resolve(pr, review: review)
        let color = switch state.tone {
        case .dim: Theme.dim
        case .green: Theme.green
        case .red: Theme.red
        case .orange: Theme.orange
        case .yellow: Theme.yellow
        }
        return (state.text, state.symbol, color)
    }

    private var shouldShowCI: Bool {
        pr.checks.total > 0 && !["arrow.triangle.2.circlepath", "xmark.circle.fill", "checkmark.circle.fill"].contains(status.symbol)
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 3) {
            if symbol == "arrow.triangle.2.circlepath" {
                SpinningInboxIcon(statusIcon(symbol), size: 10, fallback: symbol)
            } else {
                InboxIcon(statusIcon(symbol), size: 10, fallback: symbol)
            }
            if !text.isEmpty { Text(text) }
        }.foregroundStyle(color)
    }

    private func statusIcon(_ symbol: String) -> String {
        [
            "xmark.circle.fill": "fail", "arrow.triangle.2.circlepath": "spinner",
            "checkmark.circle.fill": "check", "exclamationmark.triangle.fill": "conflict",
            "exclamationmark.bubble.fill": "changes", "eye.fill": "eye",
            "checkmark.seal.fill": "approved", "bubble.left.fill": "comment", "pause.circle.fill": "paused",
            "arrow.triangle.pull": "pr",
        ][symbol] ?? "pr"
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, -date.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        if seconds < 604800 { return "\(Int(seconds / 86400))d" }
        return "\(Int(seconds / 604800))w"
    }
}
