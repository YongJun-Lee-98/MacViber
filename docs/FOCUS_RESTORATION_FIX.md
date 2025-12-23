# Focus Restoration Bug Fix (v1.3.1)

## Problem Description

When using Split View mode with multiple terminal panes, if a system permission dialog appeared (e.g., folder access permission), the keyboard focus would go to the wrong terminal pane after the dialog closed.

**Symptoms:**
- Visual focus indicator (blue border) showed Pane A as focused
- Keyboard input was being sent to Pane B instead

## Root Cause Analysis

The bug had two contributing factors:

### 1. One-Way State Synchronization
The `focusedPaneId` state was only synchronized in one direction:
- `SessionManager` → `MainViewModel`: ✓ Existed
- `MainViewModel` → `SessionManager`: ✗ Missing

When a user clicked on a pane:
1. `SplitTerminalView.onFocus` set `focusedPaneId = paneId` via SwiftUI binding
2. This updated `viewModel.focusedPaneId`
3. But `sessionManager.splitViewState.focusedPaneId` was **never updated**

### 2. No Focus Restoration After System Dialogs
When a macOS system dialog (like permission requests) appeared and closed:
- macOS would restore first responder to an **arbitrary** terminal view
- No event was triggered in our code (`updateNSView`, `becomeFirstResponder` were not called)
- The wrong terminal received keyboard focus

## Solution

### Fix 1: Bidirectional focusedPaneId Synchronization
Added a Combine subscriber to sync `viewModel.focusedPaneId` changes back to `SessionManager`:

```swift
// MainViewModel.swift
$focusedPaneId
    .dropFirst()
    .removeDuplicates()
    .sink { [weak self] paneId in
        guard let self = self else { return }
        if self.sessionManager.splitViewState.focusedPaneId != paneId {
            self.sessionManager.setFocusedPane(paneId)
        }
    }
    .store(in: &cancellables)
```

### Fix 2: Window Activation Focus Restoration
Added `NSWindow.didBecomeKeyNotification` observer to restore focus when the window becomes active again:

```swift
// MainViewModel.swift
private func setupWindowObserver() {
    NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.restoreFocusToActivePane()
        }
        .store(in: &cancellables)
}

private func restoreFocusToActivePane() {
    guard sessionManager.splitViewState.isActive,
          let focusedPaneId = sessionManager.splitViewState.focusedPaneId,
          let sessionId = sessionManager.splitViewState.rootNode?.sessionId(for: focusedPaneId),
          let controller = sessionManager.controller(for: sessionId) else {
        return
    }
    controller.requestFocus()
}
```

### Fix 3: Conditional First Responder Setting
Modified `TerminalView` and `TerminalContainerNSView` to only set first responder when the pane is actually focused:

```swift
// TerminalView.swift
struct TerminalView: NSViewRepresentable {
    let isFocused: Bool  // New parameter

    func updateNSView(_ nsView: TerminalContainerNSView, context: Context) {
        nsView.isFocused = isFocused

        // Only set first responder if this pane is focused
        if isFocused, let terminalView = nsView.terminalView {
            // ... make first responder
        }
    }
}

class TerminalContainerNSView: NSView {
    var isFocused: Bool = false

    override func becomeFirstResponder() -> Bool {
        // Only forward if this pane should be focused
        if isFocused, let terminalView = terminalView {
            // ... forward to terminal
        }
        return true
    }
}
```

## Files Modified

| File | Changes |
|------|---------|
| `MainViewModel.swift` | Added `setupWindowObserver()`, `restoreFocusToActivePane()`, bidirectional focusedPaneId sync |
| `TerminalView.swift` | Added `isFocused` parameter, conditional first responder logic |
| `TerminalPaneView.swift` | Pass `isFocused` to `TerminalView` |
| `MainView.swift` | Pass `isFocused: true` for single terminal view |
| `TerminalController.swift` | Added debug logging for focus operations |

## Testing

1. Open MacViber with Split View (2+ terminal panes)
2. Click on LEFT pane to focus it
3. Navigate to a folder that triggers a permission dialog
4. After dialog closes, verify keyboard input goes to LEFT pane (the one with blue border)
