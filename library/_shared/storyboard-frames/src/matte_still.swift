// matte_still — person matte + face / lip boxes for still frames, with Apple Vision (macOS 12+).
//
// Adapted from scratchpad/motion-tests/src/personmatte/personmatte.swift (same Vision request,
// quality .accurate), but it reads PNG stills instead of a video so single storyboard frames can be
// matted without seeking. For each input PNG it writes <outDir>/<stem>_matte.png (8-bit, 255 = person,
// Vision's native mask resolution) and prints one JSON line with the face box and the outer-lip box
// in top-left pixel coordinates of the input image.
//
// build:  swiftc -O matte_still.swift -o matte_still
// usage:  matte_still <outDir> <frame.png> [<frame.png> ...]

import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import CoreVideo

func loadCG(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func writeGrayPNG(_ pb: CVPixelBuffer, to url: URL) throws {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { throw NSError(domain: "matte_still", code: 1) }
    let data = Data(bytes: base, count: bpr * h)
    guard let provider = CGDataProvider(data: data as CFData),
          let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: bpr,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "matte_still", code: 2) }
    CGImageDestinationAddImage(dest, img, nil)
    if !CGImageDestinationFinalize(dest) { throw NSError(domain: "matte_still", code: 3) }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.count < 2 {
    FileHandle.standardError.write("usage: matte_still <outDir> <frame.png> ...\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[0])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for path in args.dropFirst() {
    guard let cg = loadCG(path) else { FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!); continue }
    let W = Double(cg.width), H = Double(cg.height)
    let seg = VNGeneratePersonSegmentationRequest()
    seg.qualityLevel = .accurate
    seg.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let face = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([seg, face])
    let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    if let m = seg.results?.first {
        try writeGrayPNG(m.pixelBuffer, to: outDir.appendingPathComponent("\(stem)_matte.png"))
    }
    var faceBox: [Int] = []
    var lipBox: [Int] = []
    if let f = face.results?.first {
        let bb = f.boundingBox  // normalized, origin bottom-left
        faceBox = [Int(bb.minX * W), Int((1 - bb.maxY) * H), Int(bb.maxX * W), Int((1 - bb.minY) * H)]
        if let lips = f.landmarks?.outerLips {
            let pts = lips.pointsInImage(imageSize: CGSize(width: W, height: H))
            let xs = pts.map { Double($0.x) }, ys = pts.map { H - Double($0.y) }
            lipBox = [Int(xs.min()!), Int(ys.min()!), Int(xs.max()!), Int(ys.max()!)]
        }
    }
    print("{\"frame\": \"\(stem)\", \"face\": \(faceBox), \"lips\": \(lipBox)}")
}
