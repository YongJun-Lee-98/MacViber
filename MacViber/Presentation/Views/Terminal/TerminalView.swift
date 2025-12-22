import SwiftUI
import SwiftTerm
import AppKit

struct TerminalView: NSViewRepresentable {
    let controller: TerminalController
    let workingDirectory: URL
    @ObservedObject var themeManager = ThemeManager.shared

    func makeNSView(context: Context) -> TerminalContainerNSView {
        let containerView = TerminalContainerNSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = themeManager.effectiveBackgroundColor.cgColor

        let terminalView = controller.createTerminalView(workingDirectory: workingDirectory)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(terminalView)
        containerView.terminalView = terminalView

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        // Make terminal first responder with retry logic
        // Window may not be ready immediately, especially for the first terminal
        func attemptFocus(retries: Int = 10) {
            if let window = terminalView.window {
                Logger.shared.debug("[FOCUS] makeNSView: window ready, calling makeFirstResponder")
                window.makeFirstResponder(terminalView)
            } else if retries > 0 {
                Logger.shared.debug("[FOCUS] makeNSView: window nil, retrying... (\(retries) left)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    attemptFocus(retries: retries - 1)
                }
            } else {
                Logger.shared.debug("[FOCUS] makeNSView: failed to get window after all retries")
            }
        }
        attemptFocus()

        return containerView
    }

    func updateNSView(_ nsView: TerminalContainerNSView, context: Context) {
        let theme = themeManager.currentTheme
        let effectiveBg = themeManager.effectiveBackgroundColor
        let effectiveFg = themeManager.effectiveForegroundColor

        nsView.layer?.backgroundColor = effectiveBg.cgColor

        // Apply colors to terminal view
        // Order matters: ANSI colors first, then background, then foreground last
        if let terminalView = nsView.terminalView as? CustomTerminalView {
            terminalView.installColors(theme.ansiSwiftTermColors)
            terminalView.nativeBackgroundColor = effectiveBg
            terminalView.nativeForegroundColor = effectiveFg

            // Request redraw on next display cycle (avoid synchronous forced redraw)
            terminalView.needsDisplay = true
        }

        // Ensure terminal is first responder when view updates
        if let terminalView = nsView.terminalView {
            func attemptFocus(retries: Int = 5) {
                if let window = nsView.window {
                    if window.firstResponder != terminalView {
                        Logger.shared.debug("[FOCUS] updateNSView: calling makeFirstResponder")
                        window.makeFirstResponder(terminalView)
                    }
                } else if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        attemptFocus(retries: retries - 1)
                    }
                }
            }
            attemptFocus()
        }
    }

    static func dismantleNSView(_ nsView: TerminalContainerNSView, coordinator: ()) {
        // Cleanup if needed
    }
}

// Container view that forwards first responder to terminal
class TerminalContainerNSView: NSView {
    weak var terminalView: NSView?

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        Logger.shared.debug("[FOCUS] Container.becomeFirstResponder called")
        // Forward first responder to terminal view with retry logic
        if let terminalView = terminalView {
            func attemptFocus(retries: Int = 5) {
                if let window = self.window {
                    Logger.shared.debug("[FOCUS] Container.becomeFirstResponder: forwarding to terminalView")
                    window.makeFirstResponder(terminalView)
                } else if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        attemptFocus(retries: retries - 1)
                    }
                }
            }
            attemptFocus()
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        Logger.shared.debug("[FOCUS] Container.mouseDown: setting terminalView as first responder")
        // Make terminal first responder when clicked
        if let terminalView = terminalView {
            window?.makeFirstResponder(terminalView)
        }
    }
}

// Alternative: Standalone terminal view for previews
struct StandaloneTerminalView: View {
    let session: TerminalSession
    @State private var controller: TerminalController?

    var body: some View {
        Group {
            if let ctrl = controller {
                TerminalView(controller: ctrl, workingDirectory: session.workingDirectory)
            } else {
                ProgressView("Starting terminal...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .onAppear {
            if controller == nil {
                controller = TerminalController(sessionId: session.id)
            }
        }
        .onDisappear {
            controller?.terminate()
        }
    }
}

#Preview {
    let session = TerminalSession(
        name: "Preview",
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    return StandaloneTerminalView(session: session)
        .frame(width: 800, height: 600)
}
