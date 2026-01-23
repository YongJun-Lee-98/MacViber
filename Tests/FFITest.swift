#!/usr/bin/env swift

import Foundation

typealias CoreHandle = OpaquePointer
typealias InitFunc = @convention(c) () -> CoreHandle?
typealias DestroyFunc = @convention(c) (CoreHandle) -> Void
typealias VersionFunc = @convention(c) () -> UnsafePointer<CChar>?
typealias CreateSessionFunc = @convention(c) (CoreHandle, UnsafePointer<CChar>, UnsafeMutableRawPointer) -> Int32
typealias SessionCountFunc = @convention(c) (CoreHandle) -> Int32
typealias CloseSessionFunc = @convention(c) (CoreHandle, UnsafeRawPointer) -> Int32

func main() {
    print("=== MacViber Rust FFI Test ===\n")
    
    let libPath = "core/target/release/libmacviber_core.dylib"
    
    guard let handle = dlopen(libPath, RTLD_NOW | RTLD_LOCAL) else {
        if let error = dlerror() {
            print("FAIL: Could not load library: \(String(cString: error))")
        }
        exit(1)
    }
    print("OK: Library loaded from \(libPath)")
    
    guard let versionSym = dlsym(handle, "core_version") else {
        print("FAIL: core_version symbol not found")
        exit(1)
    }
    let versionFn = unsafeBitCast(versionSym, to: VersionFunc.self)
    if let versionPtr = versionFn() {
        print("OK: core_version() = \(String(cString: versionPtr))")
    } else {
        print("FAIL: core_version returned nil")
        exit(1)
    }
    
    guard let initSym = dlsym(handle, "core_init") else {
        print("FAIL: core_init symbol not found")
        exit(1)
    }
    let initFn = unsafeBitCast(initSym, to: InitFunc.self)
    guard let core = initFn() else {
        print("FAIL: core_init returned nil")
        exit(1)
    }
    print("OK: core_init() succeeded")
    
    guard let countSym = dlsym(handle, "core_session_count") else {
        print("FAIL: core_session_count symbol not found")
        exit(1)
    }
    let countFn = unsafeBitCast(countSym, to: SessionCountFunc.self)
    let initialCount = countFn(core)
    print("OK: Initial session count = \(initialCount)")
    
    guard let createSym = dlsym(handle, "core_create_session") else {
        print("FAIL: core_create_session symbol not found")
        exit(1)
    }
    let createFn = unsafeBitCast(createSym, to: CreateSessionFunc.self)
    
    var sessionId: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    
    let workingDir = FileManager.default.currentDirectoryPath
    let result = workingDir.withCString { cstr in
        withUnsafeMutablePointer(to: &sessionId) { ptr in
            createFn(core, cstr, ptr)
        }
    }
    
    if result == 0 {
        let uuid = UUID(uuid: sessionId)
        print("OK: core_create_session() succeeded, id = \(uuid)")
    } else {
        print("FAIL: core_create_session returned \(result)")
        exit(1)
    }
    
    let newCount = countFn(core)
    print("OK: Session count after create = \(newCount)")
    
    guard let closeSym = dlsym(handle, "core_close_session") else {
        print("FAIL: core_close_session symbol not found")
        exit(1)
    }
    let closeFn = unsafeBitCast(closeSym, to: CloseSessionFunc.self)
    
    let closeResult = withUnsafePointer(to: &sessionId) { ptr in
        closeFn(core, ptr)
    }
    
    if closeResult == 0 {
        print("OK: core_close_session() succeeded")
    } else {
        print("FAIL: core_close_session returned \(closeResult)")
    }
    
    let finalCount = countFn(core)
    print("OK: Final session count = \(finalCount)")
    
    guard let destroySym = dlsym(handle, "core_destroy") else {
        print("FAIL: core_destroy symbol not found")
        exit(1)
    }
    let destroyFn = unsafeBitCast(destroySym, to: DestroyFunc.self)
    destroyFn(core)
    print("OK: core_destroy() succeeded")
    
    dlclose(handle)
    
    print("\n=== All FFI Tests Passed ===")
}

main()
