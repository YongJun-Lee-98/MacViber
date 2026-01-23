#!/usr/bin/env swift

import Foundation

typealias CoreHandle = OpaquePointer
typealias InitFunc = @convention(c) () -> CoreHandle?
typealias DestroyFunc = @convention(c) (CoreHandle) -> Void
typealias VersionFunc = @convention(c) () -> UnsafePointer<CChar>?
typealias CreateSessionFunc = @convention(c) (CoreHandle, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Int32
typealias SessionCountFunc = @convention(c) (CoreHandle) -> Int32
typealias CloseSessionFunc = @convention(c) (CoreHandle, UnsafeRawPointer) -> Int32

typealias PatternMatcherCreateFunc = @convention(c) () -> OpaquePointer?
typealias PatternMatcherDestroyFunc = @convention(c) (OpaquePointer) -> Void
typealias PatternMatcherAddFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafePointer<CChar>, UnsafePointer<CChar>, Bool, Bool, Bool) -> Int32
typealias PatternMatcherMatchFunc = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Int32

typealias NotificationDetectorCreateFunc = @convention(c) () -> OpaquePointer?
typealias NotificationDetectorDestroyFunc = @convention(c) (OpaquePointer) -> Void
typealias NotificationDetectorDetectFunc = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafeRawPointer, UnsafeMutableRawPointer) -> Int32
typealias NotificationDetectorResetFunc = @convention(c) (OpaquePointer) -> Void
typealias FreeStringFunc = @convention(c) (UnsafeMutablePointer<CChar>) -> Void

typealias SplitViewStateCreateFunc = @convention(c) () -> OpaquePointer?
typealias SplitViewStateDestroyFunc = @convention(c) (OpaquePointer) -> Void
typealias SplitViewStateIsActiveFunc = @convention(c) (OpaquePointer) -> Bool
typealias SplitViewStatePaneCountFunc = @convention(c) (OpaquePointer) -> Int32
typealias SplitViewStateCanSplitFunc = @convention(c) (OpaquePointer) -> Bool
typealias SplitViewStateEnterFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
typealias SplitViewStateExitFunc = @convention(c) (OpaquePointer) -> Void
typealias SplitViewStateSplitPaneFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, Int32, UnsafeRawPointer, Double, Double, UnsafeMutableRawPointer) -> Int32
typealias SplitViewStateClosePaneFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
typealias SplitViewStateGetFocusedFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer) -> Int32
typealias SplitViewStateNextPaneFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer) -> Int32

typealias CoreRenameSessionFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafePointer<CChar>) -> Int32
typealias CoreSetSessionAliasFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafePointer<CChar>?) -> Int32
typealias CoreToggleSessionLockFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
typealias CoreSetSessionStatusFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, Int32) -> Int32
typealias CoreGetSessionInfoFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafeMutableRawPointer) -> Int32
typealias CoreGetAllSessionIdsFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int32) -> Int32

struct PatternMatchResult {
    var matched: Bool
    var pattern_id: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    var auto_pin: Bool
}

struct DetectionResult {
    var detected: Bool
    var notification_type: Int32
    var message: UnsafeMutablePointer<CChar>?
    var notification_id: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
}

struct SessionInfoFFI {
    var id: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    var status: Int32
    var is_locked: Bool
    var has_unread_notification: Bool
}

var libHandle: UnsafeMutableRawPointer!

func loadSymbol<T>(_ name: String) -> T {
    guard let sym = dlsym(libHandle, name) else {
        print("FAIL: Symbol \(name) not found")
        exit(1)
    }
    return unsafeBitCast(sym, to: T.self)
}

func testCore() {
    print("\n--- Core Tests ---")
    
    let initFn: InitFunc = loadSymbol("core_init")
    guard let core = initFn() else {
        print("FAIL: core_init returned nil")
        exit(1)
    }
    print("OK: core_init() succeeded")
    
    let versionFn: VersionFunc = loadSymbol("core_version")
    if let versionPtr = versionFn() {
        print("OK: core_version() = \(String(cString: versionPtr))")
    }
    
    let countFn: SessionCountFunc = loadSymbol("core_session_count")
    print("OK: Initial session count = \(countFn(core))")
    
    let createFn: CreateSessionFunc = loadSymbol("core_create_session")
    var sessionId: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    
    let workingDir = FileManager.default.currentDirectoryPath
    let result = workingDir.withCString { cstr in
        withUnsafeMutablePointer(to: &sessionId) { ptr in
            createFn(core, cstr, ptr)
        }
    }
    
    if result == 0 {
        print("OK: core_create_session() succeeded, id = \(UUID(uuid: sessionId))")
    } else {
        print("FAIL: core_create_session returned \(result)")
        exit(1)
    }
    
    print("OK: Session count after create = \(countFn(core))")
    
    let renameFn: CoreRenameSessionFunc = loadSymbol("core_rename_session")
    let renameResult = "TestTerminal".withCString { name in
        withUnsafePointer(to: &sessionId) { ptr in
            renameFn(core, ptr, name)
        }
    }
    print("OK: core_rename_session() = \(renameResult)")
    
    let setAliasFn: CoreSetSessionAliasFunc = loadSymbol("core_set_session_alias")
    let aliasResult = "MyAlias".withCString { alias in
        withUnsafePointer(to: &sessionId) { ptr in
            setAliasFn(core, ptr, alias)
        }
    }
    print("OK: core_set_session_alias() = \(aliasResult)")
    
    let toggleLockFn: CoreToggleSessionLockFunc = loadSymbol("core_toggle_session_lock")
    let lockResult = withUnsafePointer(to: &sessionId) { ptr in
        toggleLockFn(core, ptr)
    }
    print("OK: core_toggle_session_lock() = \(lockResult)")
    
    let setStatusFn: CoreSetSessionStatusFunc = loadSymbol("core_set_session_status")
    let statusResult = withUnsafePointer(to: &sessionId) { ptr in
        setStatusFn(core, ptr, 2)
    }
    print("OK: core_set_session_status(WaitingForInput) = \(statusResult)")
    
    let getInfoFn: CoreGetSessionInfoFunc = loadSymbol("core_get_session_info")
    var info = SessionInfoFFI(
        id: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
        status: -1,
        is_locked: false,
        has_unread_notification: false
    )
    let infoResult = withUnsafePointer(to: &sessionId) { ptr in
        getInfoFn(core, ptr, &info)
    }
    if infoResult == 0 {
        let statusNames = ["Idle", "Running", "WaitingForInput", "Terminated"]
        let statusName = info.status >= 0 && info.status < 4 ? statusNames[Int(info.status)] : "Unknown"
        print("OK: core_get_session_info() - status=\(statusName), is_locked=\(info.is_locked)")
    }
    
    let getAllIdsFn: CoreGetAllSessionIdsFunc = loadSymbol("core_get_all_session_ids")
    var allIds = [(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                   UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)](
        repeating: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
        count: 10
    )
    let idsCount = allIds.withUnsafeMutableBufferPointer { buffer in
        getAllIdsFn(core, buffer.baseAddress!, 10)
    }
    print("OK: core_get_all_session_ids() returned \(idsCount) session(s)")
    
    let closeFn: CloseSessionFunc = loadSymbol("core_close_session")
    let closeResult = withUnsafePointer(to: &sessionId) { ptr in
        closeFn(core, ptr)
    }
    print("OK: core_close_session() = \(closeResult)")
    print("OK: Final session count = \(countFn(core))")
    
    let destroyFn: DestroyFunc = loadSymbol("core_destroy")
    destroyFn(core)
    print("OK: core_destroy() succeeded")
}

func testPatternMatcher() {
    print("\n--- PatternMatcher Tests ---")
    
    let createFn: PatternMatcherCreateFunc = loadSymbol("pattern_matcher_create")
    guard let matcher = createFn() else {
        print("FAIL: pattern_matcher_create returned nil")
        exit(1)
    }
    print("OK: pattern_matcher_create() succeeded")
    
    let addFn: PatternMatcherAddFunc = loadSymbol("pattern_matcher_add_pattern")
    var patternId = UUID().uuid
    
    let addResult = "test_pattern".withCString { name in
        "error|fail".withCString { pattern in
            withUnsafePointer(to: &patternId) { idPtr in
                addFn(matcher, idPtr, name, pattern, true, true, false)
            }
        }
    }
    print("OK: pattern_matcher_add_pattern() = \(addResult)")
    
    let matchFn: PatternMatcherMatchFunc = loadSymbol("pattern_matcher_match")
    var matchResult = PatternMatchResult(
        matched: false,
        pattern_id: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
        auto_pin: false
    )
    
    let matchStatus = "This is an error message".withCString { text in
        matchFn(matcher, text, &matchResult)
    }
    
    if matchStatus == 0 && matchResult.matched {
        print("OK: pattern_matcher_match() matched 'error' pattern")
    } else {
        print("FAIL: pattern_matcher_match() did not match, status=\(matchStatus), matched=\(matchResult.matched)")
        exit(1)
    }
    
    var noMatchResult = PatternMatchResult(
        matched: false,
        pattern_id: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
        auto_pin: false
    )
    _ = "This is a normal message".withCString { text in
        matchFn(matcher, text, &noMatchResult)
    }
    
    if !noMatchResult.matched {
        print("OK: pattern_matcher_match() correctly returned no match for normal text")
    } else {
        print("FAIL: pattern_matcher_match() incorrectly matched normal text")
        exit(1)
    }
    
    let destroyFn: PatternMatcherDestroyFunc = loadSymbol("pattern_matcher_destroy")
    destroyFn(matcher)
    print("OK: pattern_matcher_destroy() succeeded")
}

func testNotificationDetector() {
    print("\n--- NotificationDetector Tests ---")
    
    let createFn: NotificationDetectorCreateFunc = loadSymbol("notification_detector_create")
    guard let detector = createFn() else {
        print("FAIL: notification_detector_create returned nil")
        exit(1)
    }
    print("OK: notification_detector_create() succeeded")
    
    let detectFn: NotificationDetectorDetectFunc = loadSymbol("notification_detector_detect")
    let freeStringFn: FreeStringFunc = loadSymbol("free_string")
    
    var sessionId = UUID().uuid
    var detectionResult = DetectionResult(
        detected: false,
        notification_type: -1,
        message: nil,
        notification_id: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    )
    
    let detectStatus = "Do you want to proceed? (y/n)".withCString { text in
        withUnsafePointer(to: &sessionId) { sidPtr in
            detectFn(detector, text, sidPtr, &detectionResult)
        }
    }
    
    if detectStatus == 0 && detectionResult.detected {
        let typeNames = ["Question", "PermissionRequest", "Completion", "Error", "Custom"]
        let typeName = detectionResult.notification_type >= 0 && detectionResult.notification_type < 5
            ? typeNames[Int(detectionResult.notification_type)]
            : "Unknown"
        print("OK: notification_detector_detect() detected: type=\(typeName)")
        
        if let msg = detectionResult.message {
            print("OK: Message = \(String(cString: msg))")
            freeStringFn(msg)
        }
    } else {
        print("FAIL: notification_detector_detect() did not detect, status=\(detectStatus)")
        exit(1)
    }
    
    let resetFn: NotificationDetectorResetFunc = loadSymbol("notification_detector_reset")
    resetFn(detector)
    print("OK: notification_detector_reset() succeeded")
    
    let destroyFn: NotificationDetectorDestroyFunc = loadSymbol("notification_detector_destroy")
    destroyFn(detector)
    print("OK: notification_detector_destroy() succeeded")
}

func testSplitViewState() {
    print("\n--- SplitViewState Tests ---")
    
    let createFn: SplitViewStateCreateFunc = loadSymbol("split_view_state_create")
    guard let state = createFn() else {
        print("FAIL: split_view_state_create returned nil")
        exit(1)
    }
    print("OK: split_view_state_create() succeeded")
    
    let isActiveFn: SplitViewStateIsActiveFunc = loadSymbol("split_view_state_is_active")
    let paneCountFn: SplitViewStatePaneCountFunc = loadSymbol("split_view_state_pane_count")
    let canSplitFn: SplitViewStateCanSplitFunc = loadSymbol("split_view_state_can_split")
    
    print("OK: isActive = \(isActiveFn(state)), paneCount = \(paneCountFn(state)), canSplit = \(canSplitFn(state))")
    
    let enterFn: SplitViewStateEnterFunc = loadSymbol("split_view_state_enter")
    var sessionId = UUID().uuid
    let enterResult = withUnsafePointer(to: &sessionId) { ptr in
        enterFn(state, ptr)
    }
    print("OK: split_view_state_enter() = \(enterResult)")
    print("OK: After enter - isActive = \(isActiveFn(state)), paneCount = \(paneCountFn(state))")
    
    let getFocusedFn: SplitViewStateGetFocusedFunc = loadSymbol("split_view_state_get_focused_pane_id")
    var focusedPaneId: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    let getFocusedResult = withUnsafeMutablePointer(to: &focusedPaneId) { ptr in
        getFocusedFn(state, ptr)
    }
    if getFocusedResult == 0 {
        print("OK: Focused pane = \(UUID(uuid: focusedPaneId))")
    }
    
    let splitFn: SplitViewStateSplitPaneFunc = loadSymbol("split_view_state_split_pane")
    var newSessionId = UUID().uuid
    var newPaneId: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    
    let splitResult = withUnsafePointer(to: &focusedPaneId) { panePtr in
        withUnsafePointer(to: &newSessionId) { sessionPtr in
            withUnsafeMutablePointer(to: &newPaneId) { outPtr in
                splitFn(state, panePtr, 0, sessionPtr, 800.0, 600.0, outPtr)
            }
        }
    }
    
    if splitResult == 0 {
        print("OK: split_view_state_split_pane() succeeded, newPaneId = \(UUID(uuid: newPaneId))")
        print("OK: After split - paneCount = \(paneCountFn(state))")
    } else {
        print("FAIL: split_view_state_split_pane() returned \(splitResult)")
        exit(1)
    }
    
    let nextFn: SplitViewStateNextPaneFunc = loadSymbol("split_view_state_next_pane")
    var nextPaneId: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    let nextResult = withUnsafeMutablePointer(to: &nextPaneId) { ptr in
        nextFn(state, ptr)
    }
    if nextResult == 0 {
        print("OK: split_view_state_next_pane() = \(UUID(uuid: nextPaneId))")
    }
    
    let closeFn: SplitViewStateClosePaneFunc = loadSymbol("split_view_state_close_pane")
    let closeResult = withUnsafePointer(to: &newPaneId) { ptr in
        closeFn(state, ptr)
    }
    print("OK: split_view_state_close_pane() = \(closeResult), paneCount = \(paneCountFn(state))")
    
    let exitFn: SplitViewStateExitFunc = loadSymbol("split_view_state_exit")
    exitFn(state)
    print("OK: split_view_state_exit() - isActive = \(isActiveFn(state))")
    
    let destroyFn: SplitViewStateDestroyFunc = loadSymbol("split_view_state_destroy")
    destroyFn(state)
    print("OK: split_view_state_destroy() succeeded")
}

func main() {
    print("=== MacViber Rust FFI Test ===")
    
    let libPath = "core/target/release/libmacviber_core.dylib"
    
    guard let handle = dlopen(libPath, RTLD_NOW | RTLD_LOCAL) else {
        if let error = dlerror() {
            print("FAIL: Could not load library: \(String(cString: error))")
        }
        exit(1)
    }
    libHandle = handle
    print("OK: Library loaded from \(libPath)")
    
    testCore()
    testPatternMatcher()
    testNotificationDetector()
    testSplitViewState()
    
    dlclose(handle)
    
    print("\n=== All FFI Tests Passed ===")
}

main()
