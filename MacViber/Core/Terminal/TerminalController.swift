import Foundation
import SwiftTerm
import Combine
import AppKit

class TerminalController: ObservableObject {
    let sessionId: UUID
    private let notificationDetector = ClaudeNotificationDetector()
    private var terminalDelegate: TerminalControllerDelegate?
    private var themeSubscription: AnyCancellable?
    private var colorsSubscription: AnyCancellable?

    @Published var isRunning: Bool = false
    @Published var terminalView: CustomTerminalView?

    let notificationPublisher = PassthroughSubject<ClaudeNotification, Never>()
    let outputPublisher = PassthroughSubject<String, Never>()

    init(sessionId: UUID) {
        self.sessionId = sessionId
        setupThemeObserver()
        setupColorsObserver()
    }

    private func setupThemeObserver() {
        themeSubscription = ThemeManager.shared.themeChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] theme in
                self?.applyColors()
            }
    }

    private func setupColorsObserver() {
        colorsSubscription = ThemeManager.shared.colorsChanged
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyColors()
            }
    }

    func applyColors() {
        let themeManager = ThemeManager.shared
        let theme = themeManager.currentTheme
        let effectiveBg = themeManager.effectiveBackgroundColor
        let effectiveFg = themeManager.effectiveForegroundColor

        guard let termView = terminalView else {
            return
        }
        // Order matters: ANSI colors first, then background, then foreground last
        termView.installColors(theme.ansiSwiftTermColors)
        termView.nativeBackgroundColor = effectiveBg
        termView.nativeForegroundColor = effectiveFg

        // Request redraw on next display cycle (avoid synchronous forced redraw)
        termView.needsDisplay = true
    }

    func applyTheme(_ theme: TerminalTheme) {
        applyColors()
    }

    func createTerminalView(workingDirectory: URL) -> CustomTerminalView {
        // Reuse existing terminal view if already created
        if let existingView = terminalView {
            return existingView
        }

        let termView = CustomTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // Configure terminal appearance
        termView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Apply colors from ThemeManager (uses effective colors which respect custom settings)
        // Order matters: ANSI colors first, then background, then foreground last
        let themeManager = ThemeManager.shared
        let theme = themeManager.currentTheme
        termView.installColors(theme.ansiSwiftTermColors)
        termView.nativeBackgroundColor = themeManager.effectiveBackgroundColor
        termView.nativeForegroundColor = themeManager.effectiveForegroundColor

        // Set up output capture callback
        termView.onOutput = { [weak self] output in
            self?.handleOutput(output)
        }

        // Create and set delegate
        let delegate = TerminalControllerDelegate()
        delegate.onProcessTerminated = { [weak self] exitCode in
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
        self.terminalDelegate = delegate
        termView.processDelegate = delegate

        // Start shell process with working directory in environment
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LC_ALL"] = "en_US.UTF-8"
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["PWD"] = workingDirectory.path

        let envArray = env.map { "\($0.key)=\($0.value)" }

        // Start process
        termView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: envArray,
            execName: shell
        )

        // Change to working directory
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            termView.send(txt: "cd \"\(workingDirectory.path)\" && clear\n")
        }

        self.terminalView = termView
        self.isRunning = true

        return termView
    }

    private func handleOutput(_ output: String) {
        outputPublisher.send(output)

        // Detect Claude notifications
        if let notification = notificationDetector.detect(in: output, sessionId: sessionId) {
            DispatchQueue.main.async { [weak self] in
                self?.notificationPublisher.send(notification)
            }
        }
    }

    func sendInput(_ text: String) {
        terminalView?.send(txt: text)
    }

    func requestFocus() {
        Logger.shared.debug("[FOCUS] TerminalController.requestFocus - sessionId: \(sessionId)")
        guard let termView = terminalView else {
            Logger.shared.debug("[FOCUS] → terminalView is nil, returning")
            return
        }
        DispatchQueue.main.async {
            Logger.shared.debug("[FOCUS] → making termView first responder, current: \(String(describing: termView.window?.firstResponder))")
            termView.window?.makeFirstResponder(termView)
            Logger.shared.debug("[FOCUS] → after makeFirstResponder: \(String(describing: termView.window?.firstResponder))")
        }
    }

    func sendKey(_ key: UInt8) {
        terminalView?.send([key])
    }

    func resize(cols: Int, rows: Int) {
        terminalView?.getTerminal().resize(cols: cols, rows: rows)
    }

    func terminate() {
        // Send exit command to gracefully terminate the shell
        terminalView?.send(txt: "exit\n")
        isRunning = false
        terminalView = nil
    }

    // MARK: - Copy/Paste Support

    func copySelection() {
        guard let termView = terminalView else {
            return
        }

        // Call copy directly - CustomTerminalView.copy() handles caching logic
        termView.copy(self)
    }

    func pasteFromClipboard() {
        guard let termView = terminalView else {
            return
        }

        termView.paste(self)
    }

    func selectAllText() {
        guard let termView = terminalView else {
            return
        }

        termView.selectAll(self)
    }

    deinit {
        terminate()
    }
}

// MARK: - Custom Terminal View with output capture
class CustomTerminalView: LocalProcessTerminalView {
    var onOutput: ((String) -> Void)?

    // Manual selection tracking
    private var cachedSelection: String?
    private var mouseMonitor: Any?
    private var selectionStart: CGPoint?
    private var selectionEnd: CGPoint?
    private var isDragging = false

    // Mouse drag throttling (16ms = ~60fps)
    private var lastDragTime: Date?
    private let dragThrottleInterval: TimeInterval = 0.016

    // Output buffering for reduced CPU usage
    private var outputBuffer: [UInt8] = []
    private var outputFlushTask: DispatchWorkItem?
    private var outputFlushDelay: TimeInterval {
        TerminalSettingsManager.shared.outputFlushDelay
    }

    // IME (Korean input) support
    private var markedTextString: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMouseMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMouseMonitor()
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard let window = self.window, window == event.window else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return }

        switch event.type {
        case .leftMouseDown:
            isDragging = true
            selectionStart = localPoint
            selectionEnd = localPoint
            cachedSelection = nil
            lastDragTime = nil

        case .leftMouseDragged:
            guard isDragging else { return }

            // Throttle drag events to reduce CPU usage (~60fps)
            let now = Date()
            if let lastTime = lastDragTime, now.timeIntervalSince(lastTime) < dragThrottleInterval {
                return
            }
            lastDragTime = now
            selectionEnd = localPoint

        case .leftMouseUp:
            guard isDragging else { return }
            isDragging = false
            selectionEnd = localPoint

            if let start = selectionStart, let end = selectionEnd {
                extractTextFromPoints(start: start, end: end)
            }

        default:
            break
        }
    }

    // Convert screen point to terminal row/col
    private func pointToTerminalPosition(_ point: CGPoint) -> (col: Int, row: Int) {
        let terminal = getTerminal()

        // Calculate cell size from frame and terminal dimensions
        let cellWidth = bounds.width / CGFloat(terminal.cols)
        let cellHeight = bounds.height / CGFloat(terminal.rows)

        // macOS: origin at bottom-left, terminal: origin at top-left
        let col = Int(point.x / cellWidth)
        let row = Int((bounds.height - point.y) / cellHeight)

        return (
            col: max(0, min(col, terminal.cols - 1)),
            row: max(0, min(row, terminal.rows - 1))
        )
    }

    private func extractTextFromPoints(start: CGPoint, end: CGPoint) {
        let terminal = getTerminal()
        let startPos = pointToTerminalPosition(start)
        let endPos = pointToTerminalPosition(end)

        // Order positions
        var minRow = startPos.row
        var maxRow = endPos.row
        var minCol = startPos.col
        var maxCol = endPos.col

        if minRow > maxRow || (minRow == maxRow && minCol > maxCol) {
            swap(&minRow, &maxRow)
            swap(&minCol, &maxCol)
        }

        // Add yDisp offset to convert screen row to buffer row
        let bufferOffset = terminal.buffer.yDisp
        let bufStartRow = minRow + bufferOffset
        let bufEndRow = maxRow + bufferOffset

        // Get text from terminal buffer
        let text = terminal.getText(
            start: Position(col: minCol, row: bufStartRow),
            end: Position(col: maxCol, row: bufEndRow)
        )

        if !text.isEmpty {
            cachedSelection = text
        }
    }

    // MARK: - Copy Override

    override func copy(_ sender: Any) {
        // Try cached selection first (from manual tracking)
        if let cached = cachedSelection, !cached.isEmpty {
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            clipboard.setString(cached, forType: .string)
            return
        }

        // Fall back to SwiftTerm's selection
        if let selectedText = getSelection(), !selectedText.isEmpty {
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            clipboard.setString(selectedText, forType: .string)
            return
        }

        super.copy(sender)
    }

    // MARK: - Data Received Override

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)

        // Buffer output and flush periodically to reduce CPU usage
        outputBuffer.append(contentsOf: slice)

        // Cancel pending flush and schedule a new one
        outputFlushTask?.cancel()
        outputFlushTask = DispatchWorkItem { [weak self] in
            self?.flushOutputBuffer()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + outputFlushDelay, execute: outputFlushTask!)
    }

    private func flushOutputBuffer() {
        guard !outputBuffer.isEmpty else { return }

        if let output = String(bytes: outputBuffer, encoding: .utf8) {
            onOutput?(output)
        }
        outputBuffer.removeAll(keepingCapacity: true)
    }

    // MARK: - NSTextInputClient Override (Korean IME Support)

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let str = string as? String {
            markedTextString = str
        } else if let attrStr = string as? NSAttributedString {
            markedTextString = attrStr.string
        }
        needsDisplay = true
    }

    override func unmarkText() {
        markedTextString = ""
        needsDisplay = true
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Clear marked text overlay before inserting
        markedTextString = ""
        needsDisplay = true
        super.insertText(string, replacementRange: replacementRange)
    }

    override func hasMarkedText() -> Bool {
        return !markedTextString.isEmpty
    }

    override func markedRange() -> NSRange {
        if markedTextString.isEmpty {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedTextString.count)
    }

    // MARK: - Korean Composition Display

    private var fontDescent: CGFloat {
        return CTFontGetDescent(self.font)
    }

    /// Returns column width for a unicode scalar (Korean/CJK = 2, others = 1)
    private func columnWidth(for scalar: UnicodeScalar) -> Int {
        let value = scalar.value
        // Hangul Jamo
        if value >= 0x1100 && value <= 0x115F { return 2 }
        // Hangul Compatibility Jamo
        if value >= 0x3130 && value <= 0x318F { return 2 }
        // Hangul Syllables
        if value >= 0xAC00 && value <= 0xD7A3 { return 2 }
        // CJK ranges
        if value >= 0x2E80 && value <= 0xA4CF { return 2 }
        if value >= 0xF900 && value <= 0xFAFF { return 2 }
        if value >= 0xFE30 && value <= 0xFE4F { return 2 }
        if value >= 0xFF00 && value <= 0xFF60 { return 2 }
        if value >= 0x20000 && value <= 0x2FFFF { return 2 }
        return 1
    }

    private func getCursorScreenPosition() -> CGPoint {
        let terminal = getTerminal()
        let buffer = terminal.buffer

        let cellWidth = bounds.width / CGFloat(terminal.cols)
        let cellHeight = bounds.height / CGFloat(terminal.rows)

        // macOS coordinate system: origin at bottom-left
        let cursorX = CGFloat(buffer.x) * cellWidth
        let cursorY = bounds.height - (CGFloat(buffer.y + 1) * cellHeight)

        return CGPoint(x: cursorX, y: cursorY)
    }

    private func drawMarkedTextOverlay(in context: CGContext) {
        guard !markedTextString.isEmpty else { return }

        let terminal = getTerminal()
        let cellWidth = bounds.width / CGFloat(terminal.cols)
        let cellHeight = bounds.height / CGFloat(terminal.rows)

        let cursorPos = getCursorScreenPosition()

        // Calculate total width for Korean characters (2 columns each)
        var totalWidth: CGFloat = 0
        for scalar in markedTextString.unicodeScalars {
            let charWidth = columnWidth(for: scalar)
            totalWidth += CGFloat(charWidth) * cellWidth
        }

        // Draw background to cover cursor and existing content
        let bgRect = CGRect(x: cursorPos.x, y: cursorPos.y, width: totalWidth, height: cellHeight)
        context.saveGState()
        context.setFillColor(nativeBackgroundColor.cgColor)
        context.fill(bgRect)
        context.restoreGState()

        // Create attributed string with underline
        let termFont = self.font
        let attributes: [NSAttributedString.Key: Any] = [
            .font: termFont,
            .foregroundColor: nativeForegroundColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: nativeForegroundColor
        ]

        let attrString = NSAttributedString(string: markedTextString, attributes: attributes)
        let ctLine = CTLineCreateWithAttributedString(attrString)

        // Draw marked text at cursor position
        context.saveGState()
        context.textPosition = CGPoint(x: cursorPos.x, y: cursorPos.y + fontDescent)
        CTLineDraw(ctLine, context)
        context.restoreGState()

        // Move cursor (CaretView) to the right side of marked text
        for subview in subviews {
            if String(describing: type(of: subview)).contains("CaretView") {
                var newFrame = subview.frame
                newFrame.origin.x = cursorPos.x + totalWidth
                subview.frame = newFrame
                break
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawMarkedTextOverlay(in: context)
    }
}

// MARK: - Terminal Controller Delegate
class TerminalControllerDelegate: NSObject, LocalProcessTerminalViewDelegate {
    var onProcessTerminated: ((Int32?) -> Void)?
    var onSizeChanged: ((Int, Int) -> Void)?
    var onTitleChanged: ((String) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        onSizeChanged?(newCols, newRows)
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChanged?(title)
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        // Current directory changed
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
}

