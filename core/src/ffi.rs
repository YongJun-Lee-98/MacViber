use crate::models::NotificationType;
use crate::services::{NotificationDetector, PatternMatcher};
use crate::Core;
use std::ffi::{c_char, c_void, CStr, CString};
use std::ptr;
use uuid::Uuid;

pub type CoreHandle = *mut c_void;
pub type SessionId = [u8; 16];
pub type PatternMatcherHandle = *mut c_void;
pub type NotificationDetectorHandle = *mut c_void;

fn uuid_to_bytes(uuid: Uuid) -> SessionId {
    *uuid.as_bytes()
}

fn bytes_to_uuid(bytes: &SessionId) -> Uuid {
    Uuid::from_bytes(*bytes)
}

#[no_mangle]
pub extern "C" fn core_init() -> CoreHandle {
    match Core::new() {
        Ok(core) => Box::into_raw(Box::new(core)) as CoreHandle,
        Err(e) => {
            eprintln!("Failed to initialize core: {}", e);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn core_destroy(handle: CoreHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle as *mut Core));
        }
    }
}

#[no_mangle]
pub extern "C" fn core_create_session(
    handle: CoreHandle,
    working_dir: *const c_char,
    out_session_id: *mut SessionId,
) -> i32 {
    if handle.is_null() || working_dir.is_null() || out_session_id.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let working_dir_str = unsafe {
        match CStr::from_ptr(working_dir).to_str() {
            Ok(s) => s,
            Err(_) => return -2,
        }
    };

    match core.create_session(working_dir_str) {
        Ok(session_id) => {
            unsafe {
                *out_session_id = uuid_to_bytes(session_id);
            }
            0
        }
        Err(e) => {
            eprintln!("Failed to create session: {}", e);
            -3
        }
    }
}

#[no_mangle]
pub extern "C" fn core_close_session(handle: CoreHandle, session_id: *const SessionId) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });

    match core.close_session(uuid) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("Failed to close session: {}", e);
            -2
        }
    }
}

#[no_mangle]
pub extern "C" fn core_session_count(handle: CoreHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    core.session_count() as i32
}

#[no_mangle]
pub extern "C" fn core_version() -> *const c_char {
    static VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");
    VERSION.as_ptr() as *const c_char
}

pub type OutputCallback = extern "C" fn(*const u8, usize, *mut c_void);

#[no_mangle]
pub extern "C" fn core_set_output_callback(
    _handle: CoreHandle,
    _session_id: *const SessionId,
    _callback: OutputCallback,
    _context: *mut c_void,
) -> i32 {
    0
}

#[no_mangle]
pub extern "C" fn core_send_input(
    _handle: CoreHandle,
    _session_id: *const SessionId,
    _input: *const u8,
    _len: usize,
) -> i32 {
    0
}

#[no_mangle]
pub extern "C" fn pattern_matcher_create() -> PatternMatcherHandle {
    Box::into_raw(Box::new(PatternMatcher::new())) as PatternMatcherHandle
}

#[no_mangle]
pub extern "C" fn pattern_matcher_destroy(handle: PatternMatcherHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle as *mut PatternMatcher));
        }
    }
}

#[no_mangle]
pub extern "C" fn pattern_matcher_add_pattern(
    handle: PatternMatcherHandle,
    pattern_id: *const SessionId,
    name: *const c_char,
    pattern: *const c_char,
    is_regex: bool,
    is_enabled: bool,
    auto_pin: bool,
) -> i32 {
    if handle.is_null() || pattern_id.is_null() || name.is_null() || pattern.is_null() {
        return -1;
    }

    let matcher = unsafe { &mut *(handle as *mut PatternMatcher) };
    let id = bytes_to_uuid(unsafe { &*pattern_id });
    let name_str = unsafe { CStr::from_ptr(name).to_string_lossy().to_string() };
    let pattern_str = unsafe { CStr::from_ptr(pattern).to_string_lossy().to_string() };

    let custom_pattern = crate::services::CustomPattern {
        id,
        name: name_str,
        pattern: pattern_str,
        is_regex,
        is_enabled,
        auto_pin,
    };

    matcher.add_pattern(custom_pattern);
    0
}

#[no_mangle]
pub extern "C" fn pattern_matcher_remove_pattern(
    handle: PatternMatcherHandle,
    pattern_id: *const SessionId,
) -> i32 {
    if handle.is_null() || pattern_id.is_null() {
        return -1;
    }

    let matcher = unsafe { &mut *(handle as *mut PatternMatcher) };
    let id = bytes_to_uuid(unsafe { &*pattern_id });
    matcher.remove_pattern(id);
    0
}

#[repr(C)]
pub struct PatternMatchResult {
    pub matched: bool,
    pub pattern_id: SessionId,
    pub auto_pin: bool,
}

#[no_mangle]
pub extern "C" fn pattern_matcher_match(
    handle: PatternMatcherHandle,
    text: *const c_char,
    out_result: *mut PatternMatchResult,
) -> i32 {
    if handle.is_null() || text.is_null() || out_result.is_null() {
        return -1;
    }

    let matcher = unsafe { &*(handle as *const PatternMatcher) };
    let text_str = unsafe { CStr::from_ptr(text).to_string_lossy() };

    unsafe {
        if let Some(pattern) = matcher.match_text(&text_str) {
            (*out_result).matched = true;
            (*out_result).pattern_id = uuid_to_bytes(pattern.id);
            (*out_result).auto_pin = pattern.auto_pin;
        } else {
            (*out_result).matched = false;
            (*out_result).pattern_id = [0u8; 16];
            (*out_result).auto_pin = false;
        }
    }

    0
}

#[no_mangle]
pub extern "C" fn pattern_matcher_invalidate_cache(handle: PatternMatcherHandle) {
    if !handle.is_null() {
        let matcher = unsafe { &mut *(handle as *mut PatternMatcher) };
        matcher.invalidate_cache();
    }
}

#[no_mangle]
pub extern "C" fn notification_detector_create() -> NotificationDetectorHandle {
    Box::into_raw(Box::new(NotificationDetector::new())) as NotificationDetectorHandle
}

#[no_mangle]
pub extern "C" fn notification_detector_destroy(handle: NotificationDetectorHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle as *mut NotificationDetector));
        }
    }
}

#[repr(C)]
pub struct DetectionResult {
    pub detected: bool,
    pub notification_type: i32,
    pub message: *mut c_char,
    pub notification_id: SessionId,
}

impl Default for DetectionResult {
    fn default() -> Self {
        Self {
            detected: false,
            notification_type: -1,
            message: ptr::null_mut(),
            notification_id: [0u8; 16],
        }
    }
}

#[no_mangle]
pub extern "C" fn notification_detector_detect(
    handle: NotificationDetectorHandle,
    text: *const c_char,
    session_id: *const SessionId,
    out_result: *mut DetectionResult,
) -> i32 {
    if handle.is_null() || text.is_null() || session_id.is_null() || out_result.is_null() {
        return -1;
    }

    let detector = unsafe { &mut *(handle as *mut NotificationDetector) };
    let text_str = unsafe { CStr::from_ptr(text).to_string_lossy() };
    let uuid = bytes_to_uuid(unsafe { &*session_id });

    unsafe {
        if let Some(notification) = detector.detect(&text_str, uuid) {
            (*out_result).detected = true;
            (*out_result).notification_type = match notification.notification_type {
                NotificationType::Question => 0,
                NotificationType::PermissionRequest => 1,
                NotificationType::Completion => 2,
                NotificationType::Error => 3,
                NotificationType::Custom => 4,
            };
            (*out_result).notification_id = uuid_to_bytes(notification.id);

            if let Ok(c_msg) = CString::new(notification.message) {
                (*out_result).message = c_msg.into_raw();
            } else {
                (*out_result).message = ptr::null_mut();
            }
        } else {
            *out_result = DetectionResult::default();
        }
    }

    0
}

#[no_mangle]
pub extern "C" fn notification_detector_reset(handle: NotificationDetectorHandle) {
    if !handle.is_null() {
        let detector = unsafe { &mut *(handle as *mut NotificationDetector) };
        detector.reset();
    }
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}
