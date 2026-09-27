// vision.swift — Apple Vision probes for the fusion shots (macOS 12+).
//
//   faces : VNDetectFaceLandmarksRequest   -> one JSON line per frame: face boxes + outer-lip boxes
//   hands : VNDetectHumanHandPoseRequest    -> one JSON line per frame: up to 2 hands, 21 joints each
//   matte : VNGeneratePersonSegmentationRequest (.accurate) -> one 8-bit gray PNG per frame (255 = person)
//
// Memory rules (same as the video-20 A2 tools, after the decoder-XPC runaway):
//   * --start and --end are REQUIRED and one process handles at most 300 frames (the caller chunks);
//   * every frame is processed inside autoreleasepool {} and nothing decoded is kept;
//   * the reader is cancelled as soon as the range is done.
// Coordinates are image pixels, origin top-left. Frame index = round(pts * fps).
//
// build:  swiftc -O vision.swift -o vision
// usage:  vision faces|hands <video> --start N --end N
//         vision matte <video> <outDir> --start N --end N [--quality accurate|balanced|fast]
//         --step K (faces / hands): analyse every K-th frame of the range (default 1)

import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let MAX_FRAMES = 300

func fail(_ m: String) -> Never {
    FileHandle.standardError.write(("vision: " + m + "\nusage: vision faces|hands <video> --start N --end N\n       vision matte <video> <outDir> --start N --end N [--quality accurate|balanced|fast]\n").data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first, ["faces", "hands", "matte"].contains(mode) else { fail("first argument must be faces, hands or matte") }
args.removeFirst()
var start: Int? = nil, end: Int? = nil, step = 1
var quality: VNGeneratePersonSegmentationRequest.QualityLevel = .accurate
var pos: [String] = []
while !args.isEmpty {
    let k = args.removeFirst()
    switch k {
    case "--start": guard let v = args.first, let n = Int(v) else { fail("--start needs an int") }; start = n; args.removeFirst()
    case "--end": guard let v = args.first, let n = Int(v) else { fail("--end needs an int") }; end = n; args.removeFirst()
    case "--step": guard let v = args.first, let n = Int(v), n >= 1 else { fail("--step needs an int >= 1") }; step = n; args.removeFirst()
    case "--quality":
        guard let v = args.first else { fail("--quality needs a value") }
        args.removeFirst()
        switch v {
        case "accurate": quality = .accurate
        case "balanced": quality = .balanced
        case "fast": quality = .fast
        default: fail("unknown quality \(v)")
        }
    default: pos.append(k)
    }
}
guard let s0 = start, let s1 = end else { fail("--start and --end are required") }
if s1 <= s0 { fail("empty range") }
if s1 - s0 > MAX_FRAMES { fail("range \(s0)..\(s1) is more than \(MAX_FRAMES) frames; split it") }
if mode == "matte" { if pos.count != 2 { fail("matte needs <video> <outDir>") } } else if pos.count != 1 { fail("\(mode) needs <video>") }
let video = pos[0]
let outDir = mode == "matte" ? pos[1] : ""

func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

func writeGrayPNG(_ pb: CVPixelBuffer, to url: URL) throws {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { throw NSError(domain: "vision", code: 1) }
    let data = Data(bytes: base, count: bpr * h)
    guard let provider = CGDataProvider(data: data as CFData),
          let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "vision", code: 2) }
    CGImageDestinationAddImage(dest, img, nil)
    if !CGImageDestinationFinalize(dest) { throw NSError(domain: "vision", code: 3) }
}

// joint names -> short keys
let JOINTS: [(VNHumanHandPoseObservation.JointName, String)] = [
    (.wrist, "wrist"),
    (.thumbCMC, "thumbCMC"), (.thumbMP, "thumbMP"), (.thumbIP, "thumbIP"), (.thumbTip, "thumbTip"),
    (.indexMCP, "indexMCP"), (.indexPIP, "indexPIP"), (.indexDIP, "indexDIP"), (.indexTip, "indexTip"),
    (.middleMCP, "middleMCP"), (.middlePIP, "middlePIP"), (.middleDIP, "middleDIP"), (.middleTip, "middleTip"),
    (.ringMCP, "ringMCP"), (.ringPIP, "ringPIP"), (.ringDIP, "ringDIP"), (.ringTip, "ringTip"),
    (.littleMCP, "littleMCP"), (.littlePIP, "littlePIP"), (.littleDIP, "littleDIP"), (.littleTip, "littleTip"),
]

if mode == "matte" { try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true) }
let asset = AVURLAsset(url: URL(fileURLWithPath: video))
guard let track = asset.tracks(withMediaType: .video).first else { fail("no video track") }
let fps = Double(track.nominalFrameRate)
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
output.alwaysCopiesSampleData = false
reader.add(output)
// start half a frame early so the first requested frame is never dropped by rounding
let t0 = max(0, (Double(s0) - 0.5) / fps)
reader.timeRange = CMTimeRange(start: CMTime(seconds: t0, preferredTimescale: 600000),
                               duration: CMTime(seconds: (Double(s1 - s0) + 1.0) / fps, preferredTimescale: 600000))
reader.startReading()

let faceReq = VNDetectFaceLandmarksRequest()
let handReq = VNDetectHumanHandPoseRequest()
handReq.maximumHandCount = 2
let segReq = VNGeneratePersonSegmentationRequest()
segReq.qualityLevel = quality
segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8
let seq = VNSequenceRequestHandler()

var n = 0, lastIdx = Int.min
var visionTime = 0.0
var failure: String? = nil
var done = false
var maskSize = (0, 0)
let tAll = Date()
while !done {
    autoreleasepool {
        guard let sb = output.copyNextSampleBuffer() else { done = true; return }
        let idx = Int((CMSampleBufferGetPresentationTimeStamp(sb).seconds * fps).rounded())
        if idx >= s1 { done = true; return }
        if idx < s0 || idx <= lastIdx { return }
        lastIdx = idx
        if mode != "matte" && (idx - s0) % step != 0 { return }
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let W = Double(CVPixelBufferGetWidth(pb)), H = Double(CVPixelBufferGetHeight(pb))
        let t = Date()
        do {
            switch mode {
            case "faces":
                let h = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
                try h.perform([faceReq])
                var faces: [[String: Any]] = []
                for f in faceReq.results ?? [] {
                    let b = f.boundingBox
                    var d: [String: Any] = ["box": [r3(b.minX * W), r3((1 - b.maxY) * H), r3(b.width * W), r3(b.height * H)], "conf": r3(Double(f.confidence))]
                    if let lips = f.landmarks?.outerLips {
                        let pts = lips.pointsInImage(imageSize: CGSize(width: W, height: H))
                        if !pts.isEmpty {
                            let xs = pts.map { Double($0.x) }, ys = pts.map { H - Double($0.y) }
                            d["lips"] = [r3(xs.min()!), r3(ys.min()!), r3(xs.max()! - xs.min()!), r3(ys.max()! - ys.min()!)]
                        }
                    }
                    faces.append(d)
                }
                let js = try JSONSerialization.data(withJSONObject: ["frame": idx, "faces": faces])
                print(String(data: js, encoding: .utf8)!)
            case "hands":
                let h = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
                try h.perform([handReq])
                var hands: [[String: Any]] = []
                for o in handReq.results ?? [] {
                    var pts: [String: Any] = [:]
                    for (jn, key) in JOINTS {
                        if let p = try? o.recognizedPoint(jn), p.confidence > 0 {
                            pts[key] = [r3(p.location.x * W), r3((1 - p.location.y) * H), r3(Double(p.confidence))]
                        }
                    }
                    var chir = "?"
                    if #available(macOS 12.0, *) { chir = o.chirality == .left ? "left" : (o.chirality == .right ? "right" : "?") }
                    hands.append(["chir": chir, "conf": r3(Double(o.confidence)), "pts": pts])
                }
                let js = try JSONSerialization.data(withJSONObject: ["frame": idx, "hands": hands])
                print(String(data: js, encoding: .utf8)!)
            default:
                try seq.perform([segReq], on: pb, orientation: .up)
                guard let res = segReq.results?.first else { FileHandle.standardError.write("vision: no matte for frame \(idx)\n".data(using: .utf8)!); return }
                let mpb = res.pixelBuffer
                maskSize = (CVPixelBufferGetWidth(mpb), CVPixelBufferGetHeight(mpb))
                try writeGrayPNG(mpb, to: URL(fileURLWithPath: outDir).appendingPathComponent(String(format: "%06d.png", idx)))
            }
        } catch {
            failure = "frame \(idx): \(error)"; done = true; return
        }
        visionTime += Date().timeIntervalSince(t)
        n += 1
        if n >= MAX_FRAMES { done = true }
    }
}
reader.cancelReading()
if let f = failure { FileHandle.standardError.write(("vision: " + f + "\n").data(using: .utf8)!); exit(1) }
if reader.status == .failed { FileHandle.standardError.write("vision: reader failed: \(String(describing: reader.error))\n".data(using: .utf8)!); exit(1) }
let total = Date().timeIntervalSince(tAll)
FileHandle.standardError.write(String(format: "{\"mode\": \"%@\", \"frames\": %d, \"mask_w\": %d, \"mask_h\": %d, \"vision_ms_per_frame\": %.1f, \"total_s\": %.2f}\n",
                                      mode, n, maskSize.0, maskSize.1, n > 0 ? 1000 * visionTime / Double(n) : 0, total).data(using: .utf8)!)
