// xiaolu-motion · render/avf_probe.swift
// AVFoundation view of an alpha video: format extensions (ContainsAlphaChannel, AlphaChannelMode,
// colour tags), decoded alpha stats of one frame, optional raw RGBA dump (from premultiplied BGRA).
//   avf_probe <movie> <frame> [out.rgba]      (built on demand by render/probe_alpha.py)
import AVFoundation
import CoreVideo
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let asset = AVURLAsset(url: url)
let sema = DispatchSemaphore(value: 0)
var tracks: [AVAssetTrack] = []
Task { tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []; sema.signal() }
sema.wait()
guard let track = tracks.first else { print("{\"error\":\"no video track\"}"); exit(1) }
var hasAlpha = false
var fmtDesc: [String: Any] = [:]
Task {
  if let descs = try? await track.load(.formatDescriptions) {
    for d in descs {
      let ext = CMFormatDescriptionGetExtensions(d) as? [String: Any] ?? [:]
      for (k, v) in ext where k.lowercased().contains("alpha") || k.contains("Depth") || k.contains("ColorPrimaries") || k.contains("TransferFunction") || k.contains("YCbCrMatrix") { fmtDesc[k] = "\(v)" }
      let sub = CMFormatDescriptionGetMediaSubType(d)
      fmtDesc["codec"] = String(format: "%c%c%c%c", (sub >> 24) & 255, (sub >> 16) & 255, (sub >> 8) & 255, sub & 255)
    }
  }
  if let chars = try? await track.load(.mediaCharacteristics) { hasAlpha = chars.contains(.containsAlphaChannel) }
  sema.signal()
}
sema.wait()
let reader = try! AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(out); reader.startReading()
let want = args.count > 2 ? Int(args[2])! : 0
var n = 0
var result: [String: Any] = ["containsAlphaChannel": hasAlpha, "format": fmtDesc]
while let sb = out.copyNextSampleBuffer() {
  if n == want, let pb = CMSampleBufferGetImageBuffer(sb) {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    if args.count > 3 {  // dump raw RGBA (converted from BGRA) to file
      var buf = [UInt8](repeating: 0, count: w * h * 4)
      for y in 0..<h { for x in 0..<w { let s = y * bpr + x * 4, d = (y * w + x) * 4
        buf[d] = base[s + 2]; buf[d + 1] = base[s + 1]; buf[d + 2] = base[s]; buf[d + 3] = base[s + 3] } }
      FileManager.default.createFile(atPath: args[3], contents: Data(buf))
    }
    var amin = 255, amax = 0
    for y in stride(from: 0, to: h, by: 4) { for x in stride(from: 0, to: w, by: 4) { let a = Int(base[y * bpr + x * 4 + 3]); amin = min(amin, a); amax = max(amax, a) } }
    let c = (h / 2) * bpr + (w / 2) * 4
    result["frame"] = n; result["size"] = [w, h]; result["alpha_min"] = amin; result["alpha_max"] = amax
    result["center_bgra"] = [base[c], base[c + 1], base[c + 2], base[c + 3]]
    if let att = CVBufferCopyAttachment(pb, kCVImageBufferAlphaChannelModeKey, nil) { result["buffer_alpha_mode"] = "\(att)" }
    CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    break
  }
  n += 1
}
result["reader_status"] = reader.status.rawValue; if let e = reader.error { result["reader_error"] = "\(e)" }
let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
