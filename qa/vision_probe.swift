// xiaolu-motion · qa/vision_probe.swift
// On-device frame analysis with Apple Vision (no network, no model downloads):
//   faces (+ outer-lips box from landmarks), text lines (zh-Hans / en), rectangles.
// Used by qa/pixel_qa.py (videos without bbox data) and qa/check.py (face/mouth track of
// the base footage). Built on demand by qa/vision.py into .cache/bin/vision_probe.
//
//   vision_probe <video> --frames 0,15,30 [--faces] [--text] [--rects] [--dump DIR] [--start-frame N]
// Output (stdout): {"size":[w,h],"fps":f,"frames":[{"n":0,"t":0,"faces":[...],"texts":[...],"rects":[...]}]}
// Boxes are in pixels, origin top-left: {"x","y","w","h"}.
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

func arg(_ name: String) -> String? {
  let a = CommandLine.arguments
  if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
  return nil
}
let args = CommandLine.arguments
guard args.count > 1 else { FileHandle.standardError.write("usage: vision_probe <video> --frames 0,1,2 [--faces] [--text] [--rects]\n".data(using: .utf8)!); exit(2) }
let url = URL(fileURLWithPath: args[1])
let want = Set((arg("--frames") ?? "").split(separator: ",").compactMap { Int($0) })
let doFaces = args.contains("--faces"), doText = args.contains("--text"), doRects = args.contains("--rects")
let dumpDir = arg("--dump")
let startFrameArg = arg("--start-frame").flatMap { Int($0) }

let asset = AVURLAsset(url: url)
let sema = DispatchSemaphore(value: 0)
var track: AVAssetTrack?
var fps: Float = 30
var natural = CGSize.zero
Task {
  track = try? await asset.loadTracks(withMediaType: .video).first
  if let t = track { fps = (try? await t.load(.nominalFrameRate)) ?? 30; natural = (try? await t.load(.naturalSize)) ?? .zero }
  sema.signal()
}
sema.wait()
guard let vt = track else { print("{\"error\":\"no video track\"}"); exit(1) }
let reader = try! AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
out.alwaysCopiesSampleData = false
reader.add(out)
// Seek near the wanted range instead of always decoding from frame 0: callers that only want a
// few frames deep into a long video (qa/vision.py splits requests into <= max_span-wide segments)
// would otherwise force AVAssetReader to decode the entire prefix every time. AVAssetReader seeks
// to the nearest sync sample at/before this time, so a few extra frames near a GOP boundary may
// still be decoded (harmless) — atN below is derived from each sample's own timestamp, not a
// counter, so it stays correct regardless of exactly where the seek lands.
if let sf = startFrameArg {
  reader.timeRange = CMTimeRange(start: CMTime(seconds: Double(sf) / Double(fps), preferredTimescale: 600), duration: .positiveInfinity)
}
reader.startReading()

func box(_ r: CGRect, _ W: Double, _ H: Double) -> [String: Double] {
  return ["x": Double(r.minX) * W, "y": (1 - Double(r.maxY)) * H, "w": Double(r.width) * W, "h": Double(r.height) * H]
}
var frames: [[String: Any]] = []
let maxWant = want.max() ?? -1
let ciContext = CIContext()
// Each sample is processed inside its own autoreleasepool: Vision requests, CIImage/CGImage
// temporaries and the sample/pixel buffers otherwise accumulate for the life of the process (this
// is a flat top-level script, so nothing else ever drains the autorelease pool) — on a long video
// that is what turns "decode a handful of frames" into several GB of resident memory.
var reachedEnd = false
while !reachedEnd, let sb = out.copyNextSampleBuffer() {
  autoreleasepool {
    let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
    let atN = Int((pts * Double(fps)).rounded())
    guard want.contains(atN) else { if atN > maxWant { reachedEnd = true }; return }
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
    let W = Double(CVPixelBufferGetWidth(pb)), H = Double(CVPixelBufferGetHeight(pb))
    var rec: [String: Any] = ["n": atN, "t": pts]
    var reqs: [VNRequest] = []
    let faceReq = VNDetectFaceLandmarksRequest()
    let textReq = VNRecognizeTextRequest()
    textReq.recognitionLevel = .accurate
    textReq.recognitionLanguages = ["zh-Hans", "en-US"]
    textReq.usesLanguageCorrection = false
    textReq.minimumTextHeight = 0.012
    let rectReq = VNDetectRectanglesRequest()
    rectReq.minimumSize = 0.06
    rectReq.maximumObservations = 24
    rectReq.minimumConfidence = 0.5
    rectReq.minimumAspectRatio = 0.1
    rectReq.quadratureTolerance = 6
    if doFaces { reqs.append(faceReq) }
    if doText { reqs.append(textReq) }
    if doRects { reqs.append(rectReq) }
    let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
    try? handler.perform(reqs)
    if doFaces {
      var fs: [[String: Any]] = []
      for f in faceReq.results ?? [] {
        var d: [String: Any] = ["box": box(f.boundingBox, W, H), "conf": f.confidence]
        if let lips = f.landmarks?.outerLips {
          let p = lips.pointsInImage(imageSize: CGSize(width: W, height: H))
          if !p.isEmpty {
            let xs = p.map { Double($0.x) }, ys = p.map { H - Double($0.y) }
            d["mouth"] = ["x": xs.min()!, "y": ys.min()!, "w": xs.max()! - xs.min()!, "h": ys.max()! - ys.min()!]
          }
        }
        fs.append(d)
      }
      rec["faces"] = fs
    }
    if doText {
      var ts: [[String: Any]] = []
      for o in textReq.results ?? [] {
        guard let c = o.topCandidates(1).first else { continue }
        ts.append(["box": box(o.boundingBox, W, H), "text": c.string, "conf": c.confidence])
      }
      rec["texts"] = ts
    }
    if doRects {
      rec["rects"] = (rectReq.results ?? []).map { ["box": box($0.boundingBox, W, H), "conf": $0.confidence] as [String: Any] }
    }
    if let dir = dumpDir {
      let ci = CIImage(cvPixelBuffer: pb)
      if let cg = ciContext.createCGImage(ci, from: ci.extent) {
        let dst = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "f%06d.png", atN))
        if let d = CGImageDestinationCreateWithURL(dst as CFURL, UTType.png.identifier as CFString, 1, nil) { CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d) }
      }
    }
    frames.append(rec)
  }
}
let result: [String: Any] = ["size": [Double(natural.width), Double(natural.height)], "fps": Double(fps), "frames": frames]
let data = try! JSONSerialization.data(withJSONObject: result, options: [])
FileHandle.standardOutput.write(data)
