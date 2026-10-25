// Benchmark-only alternative to the former Swift packet deinterleaving loop.
// Not linked into GLoop. The caller validates all pointer extents.
#![no_std]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gloop_copy_channel(src: *const f32, dst: *mut f32, count: usize, stride: usize) {
    let mut i = 0;
    while i < count {
        unsafe { *dst.add(i) = *src.add(i * stride); }
        i += 1;
    }
}
