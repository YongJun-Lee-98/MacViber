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
