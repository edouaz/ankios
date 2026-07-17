// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Minimal C FFI over `anki::backend::Backend`, modeled on
//! `pylib/rsbridge/lib.rs`. The backend is opaque; everything travels as
//! protobuf bytes, including errors (see `run_service_method`).

use anki::backend::init_backend;
use anki::backend::Backend;

#[repr(C)]
pub struct ByteBuf {
    ptr: *mut u8,
    len: usize,
}

fn to_buf(v: Vec<u8>) -> ByteBuf {
    let mut v = v;
    v.shrink_to_fit();
    let buf = ByteBuf {
        ptr: v.as_mut_ptr(),
        len: v.len(),
    };
    std::mem::forget(v);
    buf
}

/// Returns null on error (the init message failed to decode).
#[no_mangle]
pub unsafe extern "C" fn anki_open_backend(init: *const u8, len: usize) -> *mut Backend {
    let init_msg = unsafe { std::slice::from_raw_parts(init, len) };
    match init_backend(init_msg) {
        Ok(backend) => Box::into_raw(Box::new(backend)),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Returns 0 on success (output = protobuf response) or 1 on a backend error
/// (output = the encoded `BackendError`).
#[no_mangle]
pub unsafe extern "C" fn anki_run_command(
    backend: *mut Backend,
    service: u32,
    method: u32,
    input: *const u8,
    input_len: usize,
    output: *mut ByteBuf,
) -> i32 {
    let backend = unsafe { &*backend };
    let in_bytes = unsafe { std::slice::from_raw_parts(input, input_len) };
    let (buf, code) = match backend.run_service_method(service, method, in_bytes) {
        Ok(bytes) => (to_buf(bytes), 0),
        Err(bytes) => (to_buf(bytes), 1),
    };
    unsafe { *output = buf };
    code
}

#[no_mangle]
pub unsafe extern "C" fn anki_free_bytes(buf: ByteBuf) {
    if !buf.ptr.is_null() {
        drop(unsafe { Vec::from_raw_parts(buf.ptr, buf.len, buf.len) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn anki_close_backend(backend: *mut Backend) {
    if !backend.is_null() {
        drop(unsafe { Box::from_raw(backend) });
    }
}
