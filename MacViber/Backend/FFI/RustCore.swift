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
}

// MARK: - Dynamic Library Loading

private var libraryHandle: UnsafeMutableRawPointer?

private func loadLibrary() -> UnsafeMutableRawPointer? {
    if let handle = libraryHandle {
        return handle
    }
    
    // Try multiple possible locations for the dylib
    let possiblePaths = [
        // Development: relative to project root
        "core/target/release/libmacviber_core.dylib",
        "core/target/debug/libmacviber_core.dylib",
        // Installed: next to app bundle
        Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("libmacviber_core.dylib").path,
        // Inside app bundle Resources
        Bundle.main.bundlePath + "/Contents/Resources/libmacviber_core.dylib",
        // Inside app bundle Frameworks
        Bundle.main.bundlePath + "/Contents/Frameworks/libmacviber_core.dylib",
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
