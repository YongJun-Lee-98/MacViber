import Foundation

public final class RustCore {
    public static let shared = RustCore()
    
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.macviber.rustcore", qos: .userInitiated)
    
    public var isInitialized: Bool {
        handle != nil
    }
    
    public var version: String {
        guard let ptr = core_version() else { return "unknown" }
        return String(cString: ptr)
    }
    
    private init() {
        initialize()
    }
    
    deinit {
        shutdown()
    }
    
    @discardableResult
    public func initialize() -> Bool {
        guard handle == nil else { return true }
        
        handle = core_init()
        
        if handle == nil {
            print("[RustCore] Failed to initialize")
            return false
        }
        
        print("[RustCore] Initialized successfully, version: \(version)")
        return true
    }
    
    public func shutdown() {
        guard let h = handle else { return }
        core_destroy(h)
        handle = nil
        print("[RustCore] Shutdown complete")
    }
    
    public func createSession(workingDirectory: String) -> UUID? {
        guard let h = handle else {
            print("[RustCore] Not initialized")
            return nil
        }
        
        var sessionIdBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        
        let result = workingDirectory.withCString { cstr in
            withUnsafeMutablePointer(to: &sessionIdBytes) { ptr in
                core_create_session(h, cstr, ptr)
            }
        }
        
        guard result == 0 else {
            print("[RustCore] Failed to create session, error: \(result)")
            return nil
        }
        
        let uuid = UUID(uuid: sessionIdBytes)
        print("[RustCore] Created session: \(uuid)")
        return uuid
    }
    
    public func closeSession(_ sessionId: UUID) -> Bool {
        guard let h = handle else { return false }
        
        var bytes = sessionId.uuid
        let result = withUnsafePointer(to: &bytes) { ptr in
            core_close_session(h, ptr)
        }
        
        if result == 0 {
            print("[RustCore] Closed session: \(sessionId)")
            return true
        } else {
            print("[RustCore] Failed to close session: \(sessionId), error: \(result)")
            return false
        }
    }
    
    public var sessionCount: Int {
        guard let h = handle else { return 0 }
        let count = core_session_count(h)
        return max(0, Int(count))
    }
    
    public func renameSession(_ sessionId: UUID, newName: String) -> Bool {
        guard let h = handle else { return false }
        var bytes = sessionId.uuid
        return newName.withCString { nameCStr in
            withUnsafePointer(to: &bytes) { ptr in
                core_rename_session(h, ptr, nameCStr) == 0
            }
        }
    }
    
    public func setSessionAlias(_ sessionId: UUID, alias: String?) -> Bool {
        guard let h = handle else { return false }
        var bytes = sessionId.uuid
        
        if let alias = alias, !alias.isEmpty {
            return alias.withCString { aliasCStr in
                withUnsafePointer(to: &bytes) { ptr in
                    core_set_session_alias(h, ptr, aliasCStr) == 0
                }
            }
        } else {
            return withUnsafePointer(to: &bytes) { ptr in
                core_set_session_alias(h, ptr, nil) == 0
            }
        }
    }
    
    public func toggleSessionLock(_ sessionId: UUID) -> Bool {
        guard let h = handle else { return false }
        var bytes = sessionId.uuid
        return withUnsafePointer(to: &bytes) { ptr in
            core_toggle_session_lock(h, ptr) == 0
        }
    }
    
    func setSessionStatus(_ sessionId: UUID, status: SessionStatus) -> Bool {
        guard let h = handle else { return false }
        var bytes = sessionId.uuid
        let statusInt: Int32 = {
            switch status {
            case .idle: return 0
            case .running: return 1
            case .waitingForInput: return 2
            case .terminated: return 3
            }
        }()
        return withUnsafePointer(to: &bytes) { ptr in
            core_set_session_status(h, ptr, statusInt) == 0
        }
    }
    
    struct SessionInfo {
        let id: UUID
        let status: SessionStatus
        let isLocked: Bool
        let hasUnreadNotification: Bool
    }
    
    func getSessionInfo(_ sessionId: UUID) -> SessionInfo? {
        guard let h = handle else { return nil }
        var bytes = sessionId.uuid
        var info = SessionInfoFFI()
        
        let result = withUnsafePointer(to: &bytes) { ptr in
            core_get_session_info(h, ptr, &info)
        }
        
        guard result == 0 else { return nil }
        
        let status: SessionStatus = {
            switch info.status {
            case 0: return .idle
            case 1: return .running
            case 2: return .waitingForInput
            case 3: return .terminated
            default: return .idle
            }
        }()
        
        return SessionInfo(
            id: UUID(uuid: info.id),
            status: status,
            isLocked: info.is_locked,
            hasUnreadNotification: info.has_unread_notification
        )
    }
    
    public var allSessionIds: [UUID] {
        guard let h = handle else { return [] }
        
        let maxCount: Int32 = 64
        var idBuffer = [(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)](
            repeating: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
            count: Int(maxCount)
        )
        
        let count = idBuffer.withUnsafeMutableBufferPointer { buffer in
            core_get_all_session_ids(h, buffer.baseAddress!, maxCount)
        }
        
        guard count > 0 else { return [] }
        
        return (0..<Int(count)).map { i in
            UUID(uuid: idBuffer[i])
        }
    }
}

private struct SessionInfoFFI {
    var id: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var status: Int32 = -1
    var is_locked: Bool = false
    var has_unread_notification: Bool = false
}

// MARK: - Dynamic Library Loading

private var libraryHandle: UnsafeMutableRawPointer?

private func loadLibrary() -> UnsafeMutableRawPointer? {
    if let handle = libraryHandle {
        return handle
    }
    
    let possiblePaths = [
        Bundle.main.bundlePath + "/Contents/Frameworks/libmacviber_core.dylib",
        Bundle.main.bundlePath + "/Contents/Resources/libmacviber_core.dylib",
        Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("libmacviber_core.dylib").path,
        "core/target/release/libmacviber_core.dylib",
        "core/target/debug/libmacviber_core.dylib",
    ]
    
    for path in possiblePaths {
        if let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
            print("[RustCore] Loaded library from: \(path)")
            libraryHandle = handle
            return handle
        }
    }
    
    // Try environment variable
    if let envPath = ProcessInfo.processInfo.environment["MACVIBER_CORE_LIB"] {
        if let handle = dlopen(envPath, RTLD_NOW | RTLD_LOCAL) {
            print("[RustCore] Loaded library from env: \(envPath)")
            libraryHandle = handle
            return handle
        }
    }
    
    // Print error for debugging
    if let error = dlerror() {
        print("[RustCore] dlopen error: \(String(cString: error))")
    }
    
    return nil
}

private func core_init() -> OpaquePointer? {
    typealias InitFunc = @convention(c) () -> OpaquePointer?
    guard let handle = loadLibrary() else {
        print("[RustCore] Failed to load library")
        return nil
    }
    guard let sym = dlsym(handle, "core_init") else {
        print("[RustCore] Symbol core_init not found")
        return nil
    }
    let fn = unsafeBitCast(sym, to: InitFunc.self)
    return fn()
}

private func core_destroy(_ handle: OpaquePointer) {
    typealias DestroyFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "core_destroy") else { return }
    let fn = unsafeBitCast(sym, to: DestroyFunc.self)
    fn(handle)
}

private func core_version() -> UnsafePointer<CChar>? {
    typealias VersionFunc = @convention(c) () -> UnsafePointer<CChar>?
    guard let handle = loadLibrary() else { return nil }
    guard let sym = dlsym(handle, "core_version") else { return nil }
    let fn = unsafeBitCast(sym, to: VersionFunc.self)
    return fn()
}

private func core_create_session(
    _ handle: OpaquePointer,
    _ workingDir: UnsafePointer<CChar>,
    _ outSessionId: UnsafeMutablePointer<(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)>
) -> Int32 {
    typealias CreateFunc = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_create_session") else { return -1 }
    let fn = unsafeBitCast(sym, to: CreateFunc.self)
    return fn(handle, workingDir, outSessionId)
}

private func core_close_session(
    _ handle: OpaquePointer,
    _ sessionId: UnsafePointer<(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)>
) -> Int32 {
    typealias CloseFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_close_session") else { return -1 }
    let fn = unsafeBitCast(sym, to: CloseFunc.self)
    return fn(handle, sessionId)
}

private func core_session_count(_ handle: OpaquePointer) -> Int32 {
    typealias CountFunc = @convention(c) (OpaquePointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_session_count") else { return -1 }
    let fn = unsafeBitCast(sym, to: CountFunc.self)
    return fn(handle)
}

private func core_rename_session(_ handle: OpaquePointer, _ sessionId: UnsafeRawPointer, _ newName: UnsafePointer<CChar>) -> Int32 {
    typealias RenameFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafePointer<CChar>) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_rename_session") else { return -1 }
    return unsafeBitCast(sym, to: RenameFunc.self)(handle, sessionId, newName)
}

private func core_set_session_alias(_ handle: OpaquePointer, _ sessionId: UnsafeRawPointer, _ alias: UnsafePointer<CChar>?) -> Int32 {
    typealias AliasFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafePointer<CChar>?) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_set_session_alias") else { return -1 }
    return unsafeBitCast(sym, to: AliasFunc.self)(handle, sessionId, alias)
}

private func core_toggle_session_lock(_ handle: OpaquePointer, _ sessionId: UnsafeRawPointer) -> Int32 {
    typealias ToggleLockFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_toggle_session_lock") else { return -1 }
    return unsafeBitCast(sym, to: ToggleLockFunc.self)(handle, sessionId)
}

private func core_set_session_status(_ handle: OpaquePointer, _ sessionId: UnsafeRawPointer, _ status: Int32) -> Int32 {
    typealias SetStatusFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, Int32) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_set_session_status") else { return -1 }
    return unsafeBitCast(sym, to: SetStatusFunc.self)(handle, sessionId, status)
}

private func core_get_session_info(_ handle: OpaquePointer, _ sessionId: UnsafeRawPointer, _ outInfo: UnsafeMutablePointer<SessionInfoFFI>) -> Int32 {
    typealias GetInfoFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "core_get_session_info") else { return -1 }
    return unsafeBitCast(sym, to: GetInfoFunc.self)(handle, sessionId, outInfo)
}

private func core_get_all_session_ids(_ handle: OpaquePointer, _ outIds: UnsafeMutableRawPointer, _ maxCount: Int32) -> Int32 {
    typealias GetAllIdsFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int32) -> Int32
    guard let dl = loadLibrary() else { return 0 }
    guard let sym = dlsym(dl, "core_get_all_session_ids") else { return 0 }
    return unsafeBitCast(sym, to: GetAllIdsFunc.self)(handle, outIds, maxCount)
}

public final class RustPatternMatcher {
    private var handle: OpaquePointer?
    
    public init() {
        handle = pattern_matcher_create()
    }
    
    deinit {
        if let h = handle {
            pattern_matcher_destroy(h)
        }
    }
    
    public func addPattern(
        id: UUID,
        name: String,
        pattern: String,
        isRegex: Bool,
        isEnabled: Bool,
        autoPin: Bool
    ) {
        guard let h = handle else { return }
        var idBytes = id.uuid
        
        name.withCString { nameCStr in
            pattern.withCString { patternCStr in
                withUnsafePointer(to: &idBytes) { idPtr in
                    _ = pattern_matcher_add_pattern(h, idPtr, nameCStr, patternCStr, isRegex, isEnabled, autoPin)
                }
            }
        }
    }
    
    public func removePattern(id: UUID) {
        guard let h = handle else { return }
        var idBytes = id.uuid
        withUnsafePointer(to: &idBytes) { ptr in
            _ = pattern_matcher_remove_pattern(h, ptr)
        }
    }
    
    public struct MatchResult {
        public let patternId: UUID
        public let autoPin: Bool
    }
    
    public func match(text: String) -> MatchResult? {
        guard let h = handle else { return nil }
        
        var result = PatternMatchResultFFI()
        
        let status = text.withCString { cstr in
            pattern_matcher_match(h, cstr, &result)
        }
        
        guard status == 0, result.matched else { return nil }
        
        return MatchResult(
            patternId: UUID(uuid: result.pattern_id),
            autoPin: result.auto_pin
        )
    }
    
    public func invalidateCache() {
        guard let h = handle else { return }
        pattern_matcher_invalidate_cache(h)
    }
}

public final class RustNotificationDetector {
    private var handle: OpaquePointer?
    
    public init() {
        handle = notification_detector_create()
    }
    
    deinit {
        if let h = handle {
            notification_detector_destroy(h)
        }
    }
    
    public enum RustNotificationType: Int32 {
        case question = 0
        case permissionRequest = 1
        case completion = 2
        case error = 3
        case custom = 4
        
        func toSwiftType() -> NotificationType {
            switch self {
            case .question: return .question
            case .permissionRequest: return .permissionRequest
            case .completion: return .completion
            case .error: return .error
            case .custom: return .custom
            }
        }
    }
    
    public struct DetectionResult {
        let notificationType: NotificationType
        public let message: String
        public let notificationId: UUID
    }
    
    public func detect(text: String, sessionId: UUID) -> DetectionResult? {
        guard let h = handle else { return nil }
        
        var sessionIdBytes = sessionId.uuid
        var result = DetectionResultFFI()
        
        let status = text.withCString { cstr in
            withUnsafePointer(to: &sessionIdBytes) { sidPtr in
                notification_detector_detect(h, cstr, sidPtr, &result)
            }
        }
        
        guard status == 0, result.detected else { return nil }
        
        let message: String
        if let msgPtr = result.message {
            message = String(cString: msgPtr)
            free_string(msgPtr)
        } else {
            message = ""
        }
        
        guard let rustType = RustNotificationType(rawValue: result.notification_type) else {
            return nil
        }
        
        return DetectionResult(
            notificationType: rustType.toSwiftType(),
            message: message,
            notificationId: UUID(uuid: result.notification_id)
        )
    }
    
    public func reset() {
        guard let h = handle else { return }
        notification_detector_reset(h)
    }
}

private struct PatternMatchResultFFI {
    var matched: Bool = false
    var pattern_id: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var auto_pin: Bool = false
}

private struct DetectionResultFFI {
    var detected: Bool = false
    var notification_type: Int32 = -1
    var message: UnsafeMutablePointer<CChar>? = nil
    var notification_id: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private func pattern_matcher_create() -> OpaquePointer? {
    typealias CreateFunc = @convention(c) () -> OpaquePointer?
    guard let dl = loadLibrary() else { return nil }
    guard let sym = dlsym(dl, "pattern_matcher_create") else { return nil }
    return unsafeBitCast(sym, to: CreateFunc.self)()
}

private func pattern_matcher_destroy(_ handle: OpaquePointer) {
    typealias DestroyFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "pattern_matcher_destroy") else { return }
    unsafeBitCast(sym, to: DestroyFunc.self)(handle)
}

private func pattern_matcher_add_pattern(
    _ handle: OpaquePointer,
    _ patternId: UnsafeRawPointer,
    _ name: UnsafePointer<CChar>,
    _ pattern: UnsafePointer<CChar>,
    _ isRegex: Bool,
    _ isEnabled: Bool,
    _ autoPin: Bool
) -> Int32 {
    typealias AddFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafePointer<CChar>, UnsafePointer<CChar>, Bool, Bool, Bool) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "pattern_matcher_add_pattern") else { return -1 }
    return unsafeBitCast(sym, to: AddFunc.self)(handle, patternId, name, pattern, isRegex, isEnabled, autoPin)
}

private func pattern_matcher_remove_pattern(
    _ handle: OpaquePointer,
    _ patternId: UnsafeRawPointer
) -> Int32 {
    typealias RemoveFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "pattern_matcher_remove_pattern") else { return -1 }
    return unsafeBitCast(sym, to: RemoveFunc.self)(handle, patternId)
}

private func pattern_matcher_match(
    _ handle: OpaquePointer,
    _ text: UnsafePointer<CChar>,
    _ result: UnsafeMutablePointer<PatternMatchResultFFI>
) -> Int32 {
    typealias MatchFunc = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "pattern_matcher_match") else { return -1 }
    return unsafeBitCast(sym, to: MatchFunc.self)(handle, text, result)
}

private func pattern_matcher_invalidate_cache(_ handle: OpaquePointer) {
    typealias InvalidateFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "pattern_matcher_invalidate_cache") else { return }
    unsafeBitCast(sym, to: InvalidateFunc.self)(handle)
}

private func notification_detector_create() -> OpaquePointer? {
    typealias CreateFunc = @convention(c) () -> OpaquePointer?
    guard let dl = loadLibrary() else { return nil }
    guard let sym = dlsym(dl, "notification_detector_create") else { return nil }
    return unsafeBitCast(sym, to: CreateFunc.self)()
}

private func notification_detector_destroy(_ handle: OpaquePointer) {
    typealias DestroyFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "notification_detector_destroy") else { return }
    unsafeBitCast(sym, to: DestroyFunc.self)(handle)
}

private func notification_detector_detect(
    _ handle: OpaquePointer,
    _ text: UnsafePointer<CChar>,
    _ sessionId: UnsafeRawPointer,
    _ result: UnsafeMutablePointer<DetectionResultFFI>
) -> Int32 {
    typealias DetectFunc = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafeRawPointer, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "notification_detector_detect") else { return -1 }
    return unsafeBitCast(sym, to: DetectFunc.self)(handle, text, sessionId, result)
}

private func notification_detector_reset(_ handle: OpaquePointer) {
    typealias ResetFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "notification_detector_reset") else { return }
    unsafeBitCast(sym, to: ResetFunc.self)(handle)
}

private func free_string(_ s: UnsafeMutablePointer<CChar>) {
    typealias FreeFunc = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "free_string") else { return }
    unsafeBitCast(sym, to: FreeFunc.self)(s)
}

public final class RustSplitViewState {
    private var handle: OpaquePointer?
    
    public init() {
        handle = split_view_state_create()
    }
    
    deinit {
        if let h = handle {
            split_view_state_destroy(h)
        }
    }
    
    public var isActive: Bool {
        guard let h = handle else { return false }
        return split_view_state_is_active(h)
    }
    
    public var paneCount: Int {
        guard let h = handle else { return 0 }
        return Int(split_view_state_pane_count(h))
    }
    
    public var canSplit: Bool {
        guard let h = handle else { return false }
        return split_view_state_can_split(h)
    }
    
    public var focusedPaneId: UUID? {
        guard let h = handle else { return nil }
        var idBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        let result = withUnsafeMutablePointer(to: &idBytes) { ptr in
            split_view_state_get_focused_pane_id(h, ptr)
        }
        guard result == 0 else { return nil }
        return UUID(uuid: idBytes)
    }
    
    public func enter(sessionId: UUID) -> Bool {
        guard let h = handle else { return false }
        var idBytes = sessionId.uuid
        let result = withUnsafePointer(to: &idBytes) { ptr in
            split_view_state_enter(h, ptr)
        }
        return result == 0
    }
    
    public func exit() {
        guard let h = handle else { return }
        split_view_state_exit(h)
    }
    
    func splitPane(
        paneId: UUID,
        direction: SplitDirection,
        newSessionId: UUID,
        width: CGFloat,
        height: CGFloat
    ) -> UUID? {
        guard let h = handle else { return nil }
        
        var paneIdBytes = paneId.uuid
        var sessionIdBytes = newSessionId.uuid
        var outPaneIdBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        
        let directionInt: Int32 = direction == .horizontal ? 0 : 1
        
        let result = withUnsafePointer(to: &paneIdBytes) { panePtr in
            withUnsafePointer(to: &sessionIdBytes) { sessionPtr in
                withUnsafeMutablePointer(to: &outPaneIdBytes) { outPtr in
                    split_view_state_split_pane(h, panePtr, directionInt, sessionPtr, Double(width), Double(height), outPtr)
                }
            }
        }
        
        guard result == 0 else { return nil }
        return UUID(uuid: outPaneIdBytes)
    }
    
    public func closePane(_ paneId: UUID) -> Bool {
        guard let h = handle else { return false }
        var idBytes = paneId.uuid
        let result = withUnsafePointer(to: &idBytes) { ptr in
            split_view_state_close_pane(h, ptr)
        }
        return result == 0
    }
    
    public func setFocusedPaneId(_ paneId: UUID) {
        guard let h = handle else { return }
        var idBytes = paneId.uuid
        withUnsafePointer(to: &idBytes) { ptr in
            _ = split_view_state_set_focused_pane_id(h, ptr)
        }
    }
    
    public func nextPaneId() -> UUID? {
        guard let h = handle else { return nil }
        var idBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        let result = withUnsafeMutablePointer(to: &idBytes) { ptr in
            split_view_state_next_pane(h, ptr)
        }
        guard result == 0 else { return nil }
        return UUID(uuid: idBytes)
    }
    
    public func previousPaneId() -> UUID? {
        guard let h = handle else { return nil }
        var idBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        let result = withUnsafeMutablePointer(to: &idBytes) { ptr in
            split_view_state_previous_pane(h, ptr)
        }
        guard result == 0 else { return nil }
        return UUID(uuid: idBytes)
    }
    
    public func sessionId(for paneId: UUID) -> UUID? {
        guard let h = handle else { return nil }
        var paneIdBytes = paneId.uuid
        var sessionIdBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                             UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        
        let result = withUnsafePointer(to: &paneIdBytes) { panePtr in
            withUnsafeMutablePointer(to: &sessionIdBytes) { sessionPtr in
                split_view_state_get_session_for_pane(h, panePtr, sessionPtr)
            }
        }
        
        guard result == 0 else { return nil }
        return UUID(uuid: sessionIdBytes)
    }
    
    public var allPaneIds: [UUID] {
        guard let h = handle else { return [] }
        
        let maxCount: Int32 = 16
        var idBuffer = [(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                         UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)](
            repeating: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
            count: Int(maxCount)
        )
        
        let count = idBuffer.withUnsafeMutableBufferPointer { buffer in
            split_view_state_get_all_pane_ids(h, buffer.baseAddress!, maxCount)
        }
        
        guard count > 0 else { return [] }
        
        return (0..<Int(count)).map { i in
            UUID(uuid: idBuffer[i])
        }
    }
}

private func split_view_state_create() -> OpaquePointer? {
    typealias CreateFunc = @convention(c) () -> OpaquePointer?
    guard let dl = loadLibrary() else { return nil }
    guard let sym = dlsym(dl, "split_view_state_create") else { return nil }
    return unsafeBitCast(sym, to: CreateFunc.self)()
}

private func split_view_state_destroy(_ handle: OpaquePointer) {
    typealias DestroyFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "split_view_state_destroy") else { return }
    unsafeBitCast(sym, to: DestroyFunc.self)(handle)
}

private func split_view_state_is_active(_ handle: OpaquePointer) -> Bool {
    typealias IsActiveFunc = @convention(c) (OpaquePointer) -> Bool
    guard let dl = loadLibrary() else { return false }
    guard let sym = dlsym(dl, "split_view_state_is_active") else { return false }
    return unsafeBitCast(sym, to: IsActiveFunc.self)(handle)
}

private func split_view_state_pane_count(_ handle: OpaquePointer) -> Int32 {
    typealias CountFunc = @convention(c) (OpaquePointer) -> Int32
    guard let dl = loadLibrary() else { return 0 }
    guard let sym = dlsym(dl, "split_view_state_pane_count") else { return 0 }
    return unsafeBitCast(sym, to: CountFunc.self)(handle)
}

private func split_view_state_can_split(_ handle: OpaquePointer) -> Bool {
    typealias CanSplitFunc = @convention(c) (OpaquePointer) -> Bool
    guard let dl = loadLibrary() else { return false }
    guard let sym = dlsym(dl, "split_view_state_can_split") else { return false }
    return unsafeBitCast(sym, to: CanSplitFunc.self)(handle)
}

private func split_view_state_enter(_ handle: OpaquePointer, _ sessionId: UnsafeRawPointer) -> Int32 {
    typealias EnterFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_enter") else { return -1 }
    return unsafeBitCast(sym, to: EnterFunc.self)(handle, sessionId)
}

private func split_view_state_exit(_ handle: OpaquePointer) {
    typealias ExitFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "split_view_state_exit") else { return }
    unsafeBitCast(sym, to: ExitFunc.self)(handle)
}

private func split_view_state_split_pane(
    _ handle: OpaquePointer,
    _ paneId: UnsafeRawPointer,
    _ direction: Int32,
    _ newSessionId: UnsafeRawPointer,
    _ width: Double,
    _ height: Double,
    _ outNewPaneId: UnsafeMutableRawPointer
) -> Int32 {
    typealias SplitFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, Int32, UnsafeRawPointer, Double, Double, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_split_pane") else { return -1 }
    return unsafeBitCast(sym, to: SplitFunc.self)(handle, paneId, direction, newSessionId, width, height, outNewPaneId)
}

private func split_view_state_close_pane(_ handle: OpaquePointer, _ paneId: UnsafeRawPointer) -> Int32 {
    typealias CloseFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_close_pane") else { return -1 }
    return unsafeBitCast(sym, to: CloseFunc.self)(handle, paneId)
}

private func split_view_state_get_focused_pane_id(_ handle: OpaquePointer, _ outPaneId: UnsafeMutableRawPointer) -> Int32 {
    typealias GetFocusedFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_get_focused_pane_id") else { return -1 }
    return unsafeBitCast(sym, to: GetFocusedFunc.self)(handle, outPaneId)
}

private func split_view_state_set_focused_pane_id(_ handle: OpaquePointer, _ paneId: UnsafeRawPointer) -> Int32 {
    typealias SetFocusedFunc = @convention(c) (OpaquePointer, UnsafeRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_set_focused_pane_id") else { return -1 }
    return unsafeBitCast(sym, to: SetFocusedFunc.self)(handle, paneId)
}

private func split_view_state_next_pane(_ handle: OpaquePointer, _ outPaneId: UnsafeMutableRawPointer) -> Int32 {
    typealias NextFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_next_pane") else { return -1 }
    return unsafeBitCast(sym, to: NextFunc.self)(handle, outPaneId)
}

private func split_view_state_previous_pane(_ handle: OpaquePointer, _ outPaneId: UnsafeMutableRawPointer) -> Int32 {
    typealias PrevFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_previous_pane") else { return -1 }
    return unsafeBitCast(sym, to: PrevFunc.self)(handle, outPaneId)
}

private func split_view_state_get_session_for_pane(_ handle: OpaquePointer, _ paneId: UnsafeRawPointer, _ outSessionId: UnsafeMutableRawPointer) -> Int32 {
    typealias GetSessionFunc = @convention(c) (OpaquePointer, UnsafeRawPointer, UnsafeMutableRawPointer) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "split_view_state_get_session_for_pane") else { return -1 }
    return unsafeBitCast(sym, to: GetSessionFunc.self)(handle, paneId, outSessionId)
}

private func split_view_state_get_all_pane_ids(_ handle: OpaquePointer, _ outIds: UnsafeMutableRawPointer, _ maxCount: Int32) -> Int32 {
    typealias GetAllFunc = @convention(c) (OpaquePointer, UnsafeMutableRawPointer, Int32) -> Int32
    guard let dl = loadLibrary() else { return 0 }
    guard let sym = dlsym(dl, "split_view_state_get_all_pane_ids") else { return 0 }
    return unsafeBitCast(sym, to: GetAllFunc.self)(handle, outIds, maxCount)
}

public final class RustPty {
    private var handle: OpaquePointer?
    private let readQueue = DispatchQueue(label: "com.macviber.pty.read", qos: .userInteractive)
    private var isReading = false
    
    public var isAlive: Bool {
        guard let h = handle else { return false }
        return pty_is_alive(h)
    }
    
    public init?(workingDirectory: String, cols: UInt16 = 80, rows: UInt16 = 24) {
        handle = workingDirectory.withCString { cstr in
            pty_spawn(cstr, cols, rows)
        }
        
        if handle == nil {
            return nil
        }
    }
    
    deinit {
        terminate()
    }
    
    public func write(_ data: Data) -> Int {
        guard let h = handle else { return -1 }
        return data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return Int(pty_write(h, ptr, buffer.count))
        }
    }
    
    public func write(_ string: String) -> Int {
        guard let data = string.data(using: .utf8) else { return -1 }
        return write(data)
    }
    
    public func read(maxBytes: Int = 4096) -> Data? {
        guard let h = handle else { return nil }
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let bytesRead = buffer.withUnsafeMutableBufferPointer { bufPtr in
            pty_read(h, bufPtr.baseAddress!, maxBytes)
        }
        
        if bytesRead > 0 {
            return Data(buffer.prefix(Int(bytesRead)))
        }
        return nil
    }
    
    public func resize(cols: UInt16, rows: UInt16) -> Bool {
        guard let h = handle else { return false }
        return pty_resize(h, cols, rows) == 0
    }
    
    public func terminate() {
        isReading = false
        if let h = handle {
            pty_destroy(h)
            handle = nil
        }
    }
    
    public func startAsyncRead(onData: @escaping (Data) -> Void, onError: @escaping (Error?) -> Void) {
        guard handle != nil else {
            onError(nil)
            return
        }
        
        isReading = true
        
        readQueue.async { [weak self] in
            while self?.isReading == true {
                guard let data = self?.read(maxBytes: 8192) else {
                    if self?.isAlive == false {
                        self?.isReading = false
                        DispatchQueue.main.async {
                            onError(nil)
                        }
                        break
                    }
                    usleep(10000)
                    continue
                }
                
                DispatchQueue.main.async {
                    onData(data)
                }
            }
        }
    }
    
    public func stopAsyncRead() {
        isReading = false
    }
}

private func pty_spawn(_ workingDir: UnsafePointer<CChar>, _ cols: UInt16, _ rows: UInt16) -> OpaquePointer? {
    typealias SpawnFunc = @convention(c) (UnsafePointer<CChar>, UInt16, UInt16) -> OpaquePointer?
    guard let dl = loadLibrary() else { return nil }
    guard let sym = dlsym(dl, "pty_spawn") else { return nil }
    return unsafeBitCast(sym, to: SpawnFunc.self)(workingDir, cols, rows)
}

private func pty_destroy(_ handle: OpaquePointer) {
    typealias DestroyFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = loadLibrary() else { return }
    guard let sym = dlsym(dl, "pty_destroy") else { return }
    unsafeBitCast(sym, to: DestroyFunc.self)(handle)
}

private func pty_write(_ handle: OpaquePointer, _ data: UnsafePointer<UInt8>, _ len: Int) -> Int32 {
    typealias WriteFunc = @convention(c) (OpaquePointer, UnsafePointer<UInt8>, Int) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "pty_write") else { return -1 }
    return unsafeBitCast(sym, to: WriteFunc.self)(handle, data, len)
}

private func pty_read(_ handle: OpaquePointer, _ buf: UnsafeMutablePointer<UInt8>, _ bufLen: Int) -> Int32 {
    typealias ReadFunc = @convention(c) (OpaquePointer, UnsafeMutablePointer<UInt8>, Int) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "pty_read") else { return -1 }
    return unsafeBitCast(sym, to: ReadFunc.self)(handle, buf, bufLen)
}

private func pty_resize(_ handle: OpaquePointer, _ cols: UInt16, _ rows: UInt16) -> Int32 {
    typealias ResizeFunc = @convention(c) (OpaquePointer, UInt16, UInt16) -> Int32
    guard let dl = loadLibrary() else { return -1 }
    guard let sym = dlsym(dl, "pty_resize") else { return -1 }
    return unsafeBitCast(sym, to: ResizeFunc.self)(handle, cols, rows)
}

private func pty_is_alive(_ handle: OpaquePointer) -> Bool {
    typealias IsAliveFunc = @convention(c) (OpaquePointer) -> Bool
    guard let dl = loadLibrary() else { return false }
    guard let sym = dlsym(dl, "pty_is_alive") else { return false }
    return unsafeBitCast(sym, to: IsAliveFunc.self)(handle)
}
