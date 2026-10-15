import SwiftUI
import PatchNodeCore
import TerminalKit

/// Every open session: tabs on iPad and Mac (regular width), a menu on
/// iPhone. "Done" hides the workspace; sessions keep running until closed or
/// the app stays in the background.
struct TerminalWorkspaceView: View {
    @Environment(TerminalSessionStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            Group {
                if let session = store.selected {
                    SessionPane(session: session)
                        .id(session.id)
                } else {
                    ContentUnavailableView("No open session", systemImage: "terminal")
                }
            }
            .navigationTitle(store.selected?.title ?? String(localized: "Terminal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .top, spacing: 0) {
                if sizeClass == .regular, store.sessions.count > 1 {
                    SessionTabs()
                }
            }
        }
        .modifier(SSHPasswordPrompt(isActive: true))
        .privacyCover()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { store.isPresented = false }
                .keyboardShortcut(.escape, modifiers: [.command])
        }
        if sizeClass != .regular, store.sessions.count > 1 {
            ToolbarItem(placement: .principal) {
                Menu {
                    Picker("Session", selection: Binding(
                        get: { store.selected?.id },
                        set: { store.selectedID = $0 }
                    )) {
                        ForEach(store.sessions, id: \.id) { session in
                            Label(session.title, systemImage: session.isLive ? "terminal" : "terminal.fill")
                                .tag(Optional(session.id))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: store.selected?.title ?? "")
                            .font(.headline)
                            .lineLimit(1)
                        Image(systemName: "chevron.down.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        if let session = store.selected {
            ToolbarItem(placement: .primaryAction) {
                SessionMenu(session: session, store: store)
            }
        }
    }
}

/// One session: its terminal or graphical console, and what to do once it
/// ended.
private struct SessionPane: View {
    let session: any WorkspaceSession

    var body: some View {
        VStack(spacing: 0) {
            if let terminal = session as? TerminalSession {
                TerminalSurface(screen: terminal.screen, focused: terminal.isLive)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .accessibilityLabel(Text("Terminal \(session.title)"))
            } else if let graphical = session as? GraphicalConsoleSession {
                GraphicalPane(session: graphical)
            }
            if !session.isLive {
                EndedBar(session: session)
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct GraphicalPane: View {
    let session: GraphicalConsoleSession

    var body: some View {
        ZStack {
            Color.black
            if session.isDemo {
                DemoGraphicalScreen(hostname: session.title)
            } else if let controller = session.controller {
                VNCWebSurface(controller: controller)
            }
            if session.state == .connecting {
                ProgressView("Connecting…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityLabel(Text("Graphical console \(session.title)"))
    }
}

/// The demo's graphical console: a VM waiting for a login, drawn locally.
private struct DemoGraphicalScreen: View {
    let hostname: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Debian GNU/Linux 13 \(hostname) tty1")
            Text(verbatim: "")
            Text(verbatim: "\(hostname) login: _")
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(Color(white: 0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .environment(\.colorScheme, .dark)
    }
}

private struct EndedBar: View {
    let session: any WorkspaceSession
    @Environment(TerminalSessionStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                if let message = session.failureMessage {
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            Button("Reconnect", systemImage: "arrow.clockwise") {
                Task { await store.reconnect(session) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.bar)
    }

    private var title: LocalizedStringKey {
        if case .ended(.failed) = session.state { "Connection failed or lost" } else { "Session ended" }
    }

    private var icon: String {
        if case .ended(.failed) = session.state { "exclamationmark.triangle.fill" } else { "stop.circle" }
    }

    private var tint: Color {
        if case .ended(.failed) = session.state { .orange } else { .secondary }
    }
}

/// Font size, copy/paste or console keys, reconnect, close — with the
/// Mac/iPad keyboard shortcuts.
///
/// Hosted in the toolbar, which may not carry the environment: the store
/// comes from the workspace.
private struct SessionMenu: View {
    let session: any WorkspaceSession
    let store: TerminalSessionStore
    @State private var showsSerialGuide = false

    var body: some View {
        Menu {
            if let terminal = session as? TerminalSession {
                Section {
                    Button("Copy", systemImage: "doc.on.doc") { terminal.screen.copySelection() }
                    Button("Paste", systemImage: "doc.on.clipboard") { terminal.screen.paste() }
                        .disabled(!terminal.isLive)
                }
                Section {
                    Button("Larger text", systemImage: "textformat.size.larger") {
                        terminal.screen.setFontSize(terminal.screen.fontSize + 1)
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    Button("Smaller text", systemImage: "textformat.size.smaller") {
                        terminal.screen.setFontSize(terminal.screen.fontSize - 1)
                    }
                    .keyboardShortcut("-", modifiers: .command)
                }
            }
            if let graphical = session as? GraphicalConsoleSession, let controller = graphical.controller {
                Section {
                    Button("Keyboard", systemImage: "keyboard") { controller.showKeyboard() }
                    Button("Send Ctrl+Alt+Del", systemImage: "command") { controller.sendCtrlAltDel() }
                    Menu("Keys") {
                        Button("Esc") { controller.sendKey("escape") }
                        Button("Tab") { controller.sendKey("tab") }
                        Button("Enter") { controller.sendKey("enter") }
                        Button("Up arrow") { controller.sendKey("up") }
                        Button("Down arrow") { controller.sendKey("down") }
                        Button("Left arrow") { controller.sendKey("left") }
                        Button("Right arrow") { controller.sendKey("right") }
                    }
                    Toggle("Fit to window", systemImage: "arrow.down.right.and.arrow.up.left", isOn: Binding(
                        get: { graphical.scalesToFit },
                        set: { graphical.scalesToFit = $0 }
                    ))
                }
            }
            if session is GraphicalConsoleSession {
                Button("Text terminal for this VM", systemImage: "questionmark.circle") { showsSerialGuide = true }
            }
            if store.sessions.count > 1 {
                Section {
                    Button("Next session", systemImage: "chevron.right") { store.select(offset: 1) }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                    Button("Previous session", systemImage: "chevron.left") { store.select(offset: -1) }
                        .keyboardShortcut("[", modifiers: [.command, .shift])
                }
            }
            Section {
                if !session.isLive {
                    Button("Reconnect", systemImage: "arrow.clockwise") {
                        Task { await store.reconnect(session) }
                    }
                }
                Button("Close session", systemImage: "xmark", role: .destructive) { store.close(session) }
                    .keyboardShortcut("w", modifiers: .command)
            }
        } label: {
            Label("Session", systemImage: "ellipsis.circle")
        }
        .sheet(isPresented: $showsSerialGuide) {
            NavigationStack {
                GuideView(topic: .service(.proxmoxVE), anchor: GuideLibrary.serialConsoleAnchor)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSerialGuide = false }
                        }
                    }
            }
            .presentationSizing(.page)
        }
    }
}

/// iPad and Mac: one tab per session.
private struct SessionTabs: View {
    @Environment(TerminalSessionStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.sessions, id: \.id) { session in
                    let isSelected = session.id == store.selected?.id
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isLive ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(verbatim: session.title)
                            .lineLimit(1)
                        Button {
                            store.close(session)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Close \(session.title)"))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: .capsule)
                    .contentShape(.capsule)
                    .onTapGesture { store.selectedID = session.id }
                    .hoverEffect(.highlight)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

/// Back to the sessions while the workspace is hidden.
struct TerminalReturnButton: View {
    @Environment(TerminalSessionStore.self) private var store

    var body: some View {
        if !store.sessions.isEmpty, !store.isPresented {
            Button {
                store.isPresented = true
            } label: {
                Label {
                    Text("Terminals (\(store.liveCount))")
                } icon: {
                    Image(systemName: "terminal.fill")
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .padding(.trailing, 16)
            .padding(.bottom, 72)
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}
