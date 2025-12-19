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

        // Make terminal first responder
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }

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
            DispatchQueue.main.async {
                if nsView.window?.firstResponder != terminalView {
                    nsView.window?.makeFirstResponder(terminalView)
                }
            }
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
        // Forward first responder to terminal view
        if let terminalView = terminalView {
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(terminalView)
            }
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
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
