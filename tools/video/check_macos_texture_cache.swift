import Cocoa
import Darwin

// Compile with the selected plugin's actual TextureHW and the app's frameworks.
// An idle mpv instance renders opaque black through the same three-buffer path.
func footprint() -> UInt64 {
  var value = task_vm_info_data_t()
  var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
  let status = withUnsafeMutablePointer(to: &value) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
    }
  }
  precondition(status == KERN_SUCCESS)
  return value.phys_footprint
}

func checkPixels(_ pixel: CVPixelBuffer, _ width: Int, _ height: Int) {
  precondition(CVPixelBufferGetWidth(pixel) == width && CVPixelBufferGetHeight(pixel) == height)
  precondition(CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA)
  precondition(CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess)
  defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
  let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
  let stride = CVPixelBufferGetBytesPerRow(pixel)
  for y in [0, height / 2, height - 1] {
    for x in [0, width / 2, width - 1] {
      let offset = y * stride + x * 4
      precondition(base[offset] == 0 && base[offset + 1] == 0 && base[offset + 2] == 0 && base[offset + 3] == 255)
    }
  }
}

let handle = mpv_create()!
precondition(mpv_set_option_string(handle, "vo", "libmpv") >= 0)
precondition(mpv_initialize(handle) >= 0)
var texture: TextureHW? = TextureHW(handle: handle, updateCallback: {})
var heldPixel: CVPixelBuffer?
var initial: UInt64 = 0
for cycle in 0...60 {
  autoreleasepool {
    let width = cycle % 2 == 0 ? 3840 : 1920
    let height = cycle % 2 == 0 ? 2160 : 1080
    let size = CGSize(width: width, height: height)
    texture!.resize(size)
    for _ in 0..<3 { texture!.render(size) }
    let pixel = texture!.copyPixelBuffer()!.takeRetainedValue()
    checkPixels(pixel, width, height)
    // Flutter may still own a frame after its GL wrapper is retired.
    if cycle == 0 { heldPixel = pixel }
  }
  if cycle == 0 { initial = footprint() }
  if cycle % 10 == 0 { print("SAMPLE cycle=\(cycle) footprint=\(footprint())") }
}
let growth = Int64(footprint()) - Int64(initial)
checkPixels(heldPixel!, 3840, 2160)
heldPixel = nil
weak var retiringTexture = texture
texture = nil
// TextureHW schedules updates on the main queue. Drain them just as the real
// app's event loop does before destroying the mpv handle they retain.
let deadline = Date(timeIntervalSinceNow: 5)
while retiringTexture != nil && Date() < deadline {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
}
precondition(retiringTexture == nil)
mpv_terminate_destroy(handle)
print("RESULT growth=\(growth) finalFootprint=\(footprint())")
if CommandLine.arguments.contains("--expect-growth") {
  precondition(growth > 1_000_000_000)
} else {
  precondition(growth < 256_000_000)
}
print("PASS")
