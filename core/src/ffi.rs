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

#[no_mangle]
pub extern "C" fn core_rename_session(
    handle: CoreHandle,
    session_id: *const SessionId,
    new_name: *const c_char,
) -> i32 {
    if handle.is_null() || session_id.is_null() || new_name.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });
    let name_str = unsafe { CStr::from_ptr(new_name).to_string_lossy().to_string() };

    if core.rename_session(uuid, name_str).is_ok() {
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn core_set_session_alias(
    handle: CoreHandle,
    session_id: *const SessionId,
    alias: *const c_char,
) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });
    let alias_opt = if alias.is_null() {
        None
    } else {
        let s = unsafe { CStr::from_ptr(alias).to_string_lossy().to_string() };
        if s.is_empty() {
            None
        } else {
            Some(s)
        }
    };

    if core.set_session_alias(uuid, alias_opt).is_ok() {
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn core_toggle_session_lock(
    handle: CoreHandle,
    session_id: *const SessionId,
) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });

    if core.toggle_session_lock(uuid).is_ok() {
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn core_set_session_status(
    handle: CoreHandle,
    session_id: *const SessionId,
    status: i32,
) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });
    let session_status = match status {
        0 => crate::models::SessionStatus::Idle,
        1 => crate::models::SessionStatus::Running,
        2 => crate::models::SessionStatus::WaitingForInput,
        3 => crate::models::SessionStatus::Terminated,
        _ => return -3,
    };

    if core.set_session_status(uuid, session_status).is_ok() {
        0
    } else {
        -2
    }
}

#[repr(C)]
pub struct SessionInfoFFI {
    pub id: SessionId,
    pub status: i32,
    pub is_locked: bool,
    pub has_unread_notification: bool,
}

#[no_mangle]
pub extern "C" fn core_get_session_info(
    handle: CoreHandle,
    session_id: *const SessionId,
    out_info: *mut SessionInfoFFI,
) -> i32 {
    if handle.is_null() || session_id.is_null() || out_info.is_null() {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });

    if let Some(session) = core.get_session(uuid) {
        unsafe {
            (*out_info).id = uuid_to_bytes(session.id);
            (*out_info).status = match session.status {
                crate::models::SessionStatus::Idle => 0,
                crate::models::SessionStatus::Running => 1,
                crate::models::SessionStatus::WaitingForInput => 2,
                crate::models::SessionStatus::Terminated => 3,
            };
            (*out_info).is_locked = session.is_locked;
            (*out_info).has_unread_notification = session.has_unread_notification;
        }
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn core_get_all_session_ids(
    handle: CoreHandle,
    out_ids: *mut SessionId,
    max_count: i32,
) -> i32 {
    if handle.is_null() || out_ids.is_null() || max_count <= 0 {
        return -1;
    }

    let core = unsafe { &*(handle as *const Core) };
    let session_ids = core.get_all_session_ids();
    let count = session_ids.len().min(max_count as usize);

    for (i, id) in session_ids.iter().take(count).enumerate() {
        unsafe {
            *out_ids.add(i) = uuid_to_bytes(*id);
        }
    }

    count as i32
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

use crate::models::{PaneSize, SplitDirection, SplitNode, SplitViewState};

pub type SplitViewStateHandle = *mut c_void;

#[no_mangle]
pub extern "C" fn split_view_state_create() -> SplitViewStateHandle {
    Box::into_raw(Box::new(SplitViewState::new())) as SplitViewStateHandle
}

#[no_mangle]
pub extern "C" fn split_view_state_destroy(handle: SplitViewStateHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle as *mut SplitViewState));
        }
    }
}

#[no_mangle]
pub extern "C" fn split_view_state_is_active(handle: SplitViewStateHandle) -> bool {
    if handle.is_null() {
        return false;
    }
    let state = unsafe { &*(handle as *const SplitViewState) };
    state.is_active()
}

#[no_mangle]
pub extern "C" fn split_view_state_pane_count(handle: SplitViewStateHandle) -> i32 {
    if handle.is_null() {
        return 0;
    }
    let state = unsafe { &*(handle as *const SplitViewState) };
    state.pane_count() as i32
}

#[no_mangle]
pub extern "C" fn split_view_state_can_split(handle: SplitViewStateHandle) -> bool {
    if handle.is_null() {
        return false;
    }
    let state = unsafe { &*(handle as *const SplitViewState) };
    state.can_split()
}

#[no_mangle]
pub extern "C" fn split_view_state_enter(
    handle: SplitViewStateHandle,
    session_id: *const SessionId,
) -> i32 {
    if handle.is_null() || session_id.is_null() {
        return -1;
    }

    let state = unsafe { &mut *(handle as *mut SplitViewState) };
    let uuid = bytes_to_uuid(unsafe { &*session_id });

    let node = SplitNode::terminal(uuid);
    let pane_id = node.id();
    state.root_node = Some(node);
    state.focused_pane_id = Some(pane_id);

    0
}

#[no_mangle]
pub extern "C" fn split_view_state_exit(handle: SplitViewStateHandle) {
    if handle.is_null() {
        return;
    }

    let state = unsafe { &mut *(handle as *mut SplitViewState) };
    state.root_node = None;
    state.focused_pane_id = None;
}

#[no_mangle]
pub extern "C" fn split_view_state_split_pane(
    handle: SplitViewStateHandle,
    pane_id: *const SessionId,
    direction: i32,
    new_session_id: *const SessionId,
    width: f64,
    height: f64,
    out_new_pane_id: *mut SessionId,
) -> i32 {
    if handle.is_null()
        || pane_id.is_null()
        || new_session_id.is_null()
        || out_new_pane_id.is_null()
    {
        return -1;
    }

    let state = unsafe { &mut *(handle as *mut SplitViewState) };

    if !state.can_split() {
        return -2;
    }

    let Some(root) = &state.root_node else {
        return -3;
    };

    let pane_uuid = bytes_to_uuid(unsafe { &*pane_id });
    let new_session_uuid = bytes_to_uuid(unsafe { &*new_session_id });
    let split_dir = if direction == 0 {
        SplitDirection::Horizontal
    } else {
        SplitDirection::Vertical
    };
    let size = PaneSize::new(width, height);

    let new_root = root.split(pane_uuid, split_dir, new_session_uuid, size);

    let new_pane_id = new_root
        .pane_id_for_session(new_session_uuid)
        .unwrap_or_else(Uuid::new_v4);

    unsafe {
        *out_new_pane_id = uuid_to_bytes(new_pane_id);
    }

    state.root_node = Some(new_root);
    state.focused_pane_id = Some(new_pane_id);

    0
}

#[no_mangle]
pub extern "C" fn split_view_state_close_pane(
    handle: SplitViewStateHandle,
    pane_id: *const SessionId,
) -> i32 {
    if handle.is_null() || pane_id.is_null() {
        return -1;
    }

    let state = unsafe { &mut *(handle as *mut SplitViewState) };
    let pane_uuid = bytes_to_uuid(unsafe { &*pane_id });

    let Some(root) = &state.root_node else {
        return -2;
    };

    state.root_node = root.removing_pane(pane_uuid);

    if state.focused_pane_id == Some(pane_uuid) {
        state.focused_pane_id = state.all_pane_ids().first().copied();
    }

    0
}

#[no_mangle]
pub extern "C" fn split_view_state_get_focused_pane_id(
    handle: SplitViewStateHandle,
    out_pane_id: *mut SessionId,
) -> i32 {
    if handle.is_null() || out_pane_id.is_null() {
        return -1;
    }

    let state = unsafe { &*(handle as *const SplitViewState) };

    if let Some(pane_id) = state.focused_pane_id {
        unsafe {
            *out_pane_id = uuid_to_bytes(pane_id);
        }
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn split_view_state_set_focused_pane_id(
    handle: SplitViewStateHandle,
    pane_id: *const SessionId,
) -> i32 {
    if handle.is_null() || pane_id.is_null() {
        return -1;
    }

    let state = unsafe { &mut *(handle as *mut SplitViewState) };
    let pane_uuid = bytes_to_uuid(unsafe { &*pane_id });

    state.focused_pane_id = Some(pane_uuid);
    0
}

#[no_mangle]
pub extern "C" fn split_view_state_next_pane(
    handle: SplitViewStateHandle,
    out_pane_id: *mut SessionId,
) -> i32 {
    if handle.is_null() || out_pane_id.is_null() {
        return -1;
    }

    let state = unsafe { &*(handle as *const SplitViewState) };

    if let Some(next_id) = state.next_pane_id(state.focused_pane_id) {
        unsafe {
            *out_pane_id = uuid_to_bytes(next_id);
        }
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn split_view_state_previous_pane(
    handle: SplitViewStateHandle,
    out_pane_id: *mut SessionId,
) -> i32 {
    if handle.is_null() || out_pane_id.is_null() {
        return -1;
    }

    let state = unsafe { &*(handle as *const SplitViewState) };

    if let Some(prev_id) = state.previous_pane_id(state.focused_pane_id) {
        unsafe {
            *out_pane_id = uuid_to_bytes(prev_id);
        }
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn split_view_state_get_session_for_pane(
    handle: SplitViewStateHandle,
    pane_id: *const SessionId,
    out_session_id: *mut SessionId,
) -> i32 {
    if handle.is_null() || pane_id.is_null() || out_session_id.is_null() {
        return -1;
    }

    let state = unsafe { &*(handle as *const SplitViewState) };
    let pane_uuid = bytes_to_uuid(unsafe { &*pane_id });

    let Some(root) = &state.root_node else {
        return -2;
    };

    if let Some(session_id) = root.session_id_for_pane(pane_uuid) {
        unsafe {
            *out_session_id = uuid_to_bytes(session_id);
        }
        0
    } else {
        -3
    }
}

#[no_mangle]
pub extern "C" fn split_view_state_get_all_pane_ids(
    handle: SplitViewStateHandle,
    out_ids: *mut SessionId,
    max_count: i32,
) -> i32 {
    if handle.is_null() || out_ids.is_null() || max_count <= 0 {
        return -1;
    }

    let state = unsafe { &*(handle as *const SplitViewState) };
    let pane_ids = state.all_pane_ids();
    let count = pane_ids.len().min(max_count as usize);

    for (i, id) in pane_ids.iter().take(count).enumerate() {
        unsafe {
            *out_ids.add(i) = uuid_to_bytes(*id);
        }
    }

    count as i32
}

use crate::terminal::PtyHandle;

pub type PtyHandlePtr = *mut c_void;

#[no_mangle]
pub extern "C" fn pty_spawn(working_dir: *const c_char, cols: u16, rows: u16) -> PtyHandlePtr {
    if working_dir.is_null() {
        return ptr::null_mut();
    }

    let dir_str = unsafe { CStr::from_ptr(working_dir).to_string_lossy() };

    match PtyHandle::spawn(&*dir_str, cols, rows) {
        Ok(pty) => Box::into_raw(Box::new(pty)) as PtyHandlePtr,
        Err(e) => {
            eprintln!("Failed to spawn PTY: {}", e);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn pty_destroy(handle: PtyHandlePtr) {
    if !handle.is_null() {
        unsafe {
            let mut pty = Box::from_raw(handle as *mut PtyHandle);
            let _ = pty.terminate();
        }
    }
}

#[no_mangle]
pub extern "C" fn pty_write(handle: PtyHandlePtr, data: *const u8, len: usize) -> i32 {
    if handle.is_null() || data.is_null() {
        return -1;
    }

    let pty = unsafe { &*(handle as *const PtyHandle) };
    let slice = unsafe { std::slice::from_raw_parts(data, len) };

    match pty.write(slice) {
        Ok(written) => written as i32,
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn pty_read(handle: PtyHandlePtr, buf: *mut u8, buf_len: usize) -> i32 {
    if handle.is_null() || buf.is_null() {
        return -1;
    }

    let pty = unsafe { &*(handle as *const PtyHandle) };
    let slice = unsafe { std::slice::from_raw_parts_mut(buf, buf_len) };

    match pty.read(slice) {
        Ok(read) => read as i32,
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn pty_resize(handle: PtyHandlePtr, cols: u16, rows: u16) -> i32 {
    if handle.is_null() {
        return -1;
    }

    let pty = unsafe { &*(handle as *const PtyHandle) };

    match pty.resize(cols, rows) {
        Ok(()) => 0,
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn pty_is_alive(handle: PtyHandlePtr) -> bool {
    if handle.is_null() {
        return false;
    }

    let pty = unsafe { &mut *(handle as *mut PtyHandle) };
    pty.is_alive()
}
