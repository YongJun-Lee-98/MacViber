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

private func core_init() -> OpaquePointer? {
    typealias InitFunc = @convention(c) () -> OpaquePointer?
    guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
    guard let sym = dlsym(handle, "core_init") else { return nil }
    let fn = unsafeBitCast(sym, to: InitFunc.self)
    return fn()
}

private func core_destroy(_ handle: OpaquePointer) {
    typealias DestroyFunc = @convention(c) (OpaquePointer) -> Void
    guard let dl = dlopen(nil, RTLD_NOW) else { return }
    guard let sym = dlsym(dl, "core_destroy") else { return }
    let fn = unsafeBitCast(sym, to: DestroyFunc.self)
    fn(handle)
}

private func core_version() -> UnsafePointer<CChar>? {
    typealias VersionFunc = @convention(c) () -> UnsafePointer<CChar>?
    guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
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
    guard let dl = dlopen(nil, RTLD_NOW) else { return -1 }
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
    guard let dl = dlopen(nil, RTLD_NOW) else { return -1 }
    guard let sym = dlsym(dl, "core_close_session") else { return -1 }
    let fn = unsafeBitCast(sym, to: CloseFunc.self)
    return fn(handle, sessionId)
}

private func core_session_count(_ handle: OpaquePointer) -> Int32 {
    typealias CountFunc = @convention(c) (OpaquePointer) -> Int32
    guard let dl = dlopen(nil, RTLD_NOW) else { return -1 }
    guard let sym = dlsym(dl, "core_session_count") else { return -1 }
    let fn = unsafeBitCast(sym, to: CountFunc.self)
    return fn(handle)
}
