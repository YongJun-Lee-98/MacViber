import SwiftUI
import AppKit

@main
struct MacViberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var updateChecker = UpdateChecker.shared
    @State private var showingShortcuts = false
    @State private var showingThemePicker = false
    @State private var showingColorSettings = false
    @State private var showingNotificationSettings = false

    init() {
        Logger.shared.info("MacViber app started")
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(sessionManager)
                .sheet(isPresented: $showingShortcuts) {
                    KeyboardShortcutsView()
                }
                .sheet(isPresented: $showingThemePicker) {
                    ThemePickerView()
                }
                .sheet(isPresented: $showingColorSettings) {
                    ColorSettingsView()
                }
                .sheet(isPresented: $showingNotificationSettings) {
                    NotificationSettingsView()
                }
                .onReceive(NotificationCenter.default.publisher(for: .showThemePicker)) { _ in
                    showingThemePicker = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .showColorSettings)) { _ in
                    showingColorSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .showNotificationSettings)) { _ in
                    showingNotificationSettings = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .checkForUpdatesRequested)) { _ in
                    Task {
                        await updateChecker.checkForUpdatesManually()
                    }
                }
                .sheet(isPresented: $updateChecker.showUpdateSheet) {
                    UpdateAlertView(updateChecker: updateChecker)
                }
                .alert("You're up to date!", isPresented: $updateChecker.showUpToDateAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("MacViber \(updateChecker.currentVersion) is the latest version.")
                }
                .task {
                    // 앱 시작 시 자동 업데이트 체크 (백그라운드)
                    await updateChecker.checkForUpdatesAutomatically()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Terminal") {
                    NotificationCenter.default.post(name: .newTerminalRequested, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Close Terminal") {
                    NotificationCenter.default.post(name: .closeTerminalRequested, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Split Horizontal") {
                    NotificationCenter.default.post(name: .splitHorizontalRequested, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Vertical") {
                    NotificationCenter.default.post(name: .splitVerticalRequested, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Close Pane") {
                    NotificationCenter.default.post(name: .closePaneRequested, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Divider()

                Button("Focus Next Pane") {
                    NotificationCenter.default.post(name: .focusNextPaneRequested, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])

                Button("Focus Previous Pane") {
                    NotificationCenter.default.post(name: .focusPreviousPaneRequested, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
            }

            // Explicitly route Copy/Paste through SessionManager
            // (responder chain doesn't reach CustomTerminalView)
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    SessionManager.shared.copyFromActiveTerminal()
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    SessionManager.shared.pasteToActiveTerminal()
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("Select All") {
                    SessionManager.shared.selectAllInActiveTerminal()
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            // Theme menu
            CommandMenu("Theme") {
                ForEach(TerminalTheme.allThemes) { theme in
                    Button {
                        ThemeManager.shared.selectTheme(theme)
                    } label: {
                        if theme.id == themeManager.currentTheme.id {
                            Text("✓ \(theme.name)")
                        } else {
                            Text("    \(theme.name)")
                        }
                    }
                }

                Divider()

                Button("Theme Settings...") {
                    NotificationCenter.default.post(name: .showThemePicker, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])

                Button("Color Settings...") {
                    NotificationCenter.default.post(name: .showColorSettings, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            // View menu
            CommandMenu("View") {
                Button("Toggle Notes Sidebar") {
                    NotificationCenter.default.post(name: .toggleRightSidebar, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            // Settings menu
            CommandMenu("Settings") {
                Button("Notification Settings...") {
                    NotificationCenter.default.post(name: .showNotificationSettings, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)

                Divider()

                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: .checkForUpdatesRequested, object: nil)
                }

                Divider()

                Button("Open Log File") {
                    let logPath = Logger.shared.logFilePath
                    let logURL = URL(fileURLWithPath: logPath)
                    NSWorkspace.shared.open(logURL)
                }

                Button("Open Log Folder") {
                    let logPath = Logger.shared.logFilePath
                    let logURL = URL(fileURLWithPath: logPath)
                    NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: logURL.deletingLastPathComponent().path)
                }

                Divider()

                Button("Open Source Licenses") {
                    let projectPath = URL(fileURLWithPath: #file)
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .deletingLastPathComponent()
                        .appendingPathComponent("docs/LICENSES.md")
                    NSWorkspace.shared.open(projectPath)
                }
            }
        }
    }
}

extension Notification.Name {
    static let newTerminalRequested = Notification.Name("newTerminalRequested")
    static let closeTerminalRequested = Notification.Name("closeTerminalRequested")
    static let splitHorizontalRequested = Notification.Name("splitHorizontalRequested")
    static let splitVerticalRequested = Notification.Name("splitVerticalRequested")
    static let closePaneRequested = Notification.Name("closePaneRequested")
    static let focusNextPaneRequested = Notification.Name("focusNextPaneRequested")
    static let focusPreviousPaneRequested = Notification.Name("focusPreviousPaneRequested")
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")
    static let showThemePicker = Notification.Name("showThemePicker")
    static let showColorSettings = Notification.Name("showColorSettings")
    static let showNotificationSettings = Notification.Name("showNotificationSettings")
    static let hideNotificationGrid = Notification.Name("hideNotificationGrid")
    static let toggleRightSidebar = Notification.Name("toggleRightSidebar")
    static let checkForUpdatesRequested = Notification.Name("checkForUpdatesRequested")
}

// MARK: - Keyboard Shortcuts View

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Terminal Management
                    ShortcutSection(title: "Terminal", shortcuts: [
                        ShortcutItem(keys: "⌘ T", description: "New Terminal"),
                        ShortcutItem(keys: "⌘ W", description: "Close Terminal"),
                    ])

                    // Split View
                    ShortcutSection(title: "Split View", shortcuts: [
                        ShortcutItem(keys: "⌘ D", description: "Split Horizontal"),
                        ShortcutItem(keys: "⇧⌘ D", description: "Split Vertical"),
                        ShortcutItem(keys: "⇧⌘ W", description: "Close Pane"),
                    ])

                    // Navigation
                    ShortcutSection(title: "Navigation", shortcuts: [
                        ShortcutItem(keys: "⌥⌘ ]", description: "Focus Next Pane"),
                        ShortcutItem(keys: "⌥⌘ [", description: "Focus Previous Pane"),
                    ])

                    // View
                    ShortcutSection(title: "View", shortcuts: [
                        ShortcutItem(keys: "⇧⌘ M", description: "Toggle Notes Sidebar"),
                    ])

                    // Help
                    ShortcutSection(title: "Help", shortcuts: [
                        ShortcutItem(keys: "⌘ /", description: "Show Keyboard Shortcuts"),
                    ])
                }
                .padding()
            }
        }
        .frame(width: 400, height: 450)
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [ShortcutItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(shortcuts) { shortcut in
                    HStack {
                        Text(shortcut.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(shortcut.keys)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // 모든 터미널 세션 종료
        Logger.shared.info("Application terminating - closing all terminal sessions")
        SessionManager.shared.terminateAllSessions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
