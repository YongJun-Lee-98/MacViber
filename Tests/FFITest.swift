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
    
    dlclose(handle)
    
    print("\n=== All FFI Tests Passed ===")
}

main()
