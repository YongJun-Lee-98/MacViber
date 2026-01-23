use crate::Core;
use std::ffi::{c_char, c_void, CStr};
use std::ptr;
use uuid::Uuid;

pub type CoreHandle = *mut c_void;
pub type SessionId = [u8; 16];

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
