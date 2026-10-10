// 따뜻한 겨울밤 움짤(MP4) 생성기 — 눈 내리는 밤, 불 켜진 오두막. 12초 끊김 없는 반복.
// 사용: swiftc -O -o winter WinterScene.swift && ./winter 출력.mp4
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

let W = 1920, H = 1080
let fps: Int32 = 30
let T = 12.0                      // 반복 주기(초)
let frameCount = Int(T * Double(fps))
let Wf = CGFloat(W), Hf = CGFloat(H)
let tau = 2 * Double.pi

func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

struct RNG {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double(s >> 11) / Double(1 << 53)
    }
    mutating func r(_ a: Double, _ b: Double) -> CGFloat { CGFloat(a + (b - a) * next()) }
}
var rng = RNG(s: 20261010)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func linear(_ ctx: CGContext, _ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func glow(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat, sy: CGFloat = 1) {
    let g = CGGradient(colorsSpace: space, colors: [col(hex, a), col(hex, a * 0.35), col(hex, 0)] as CFArray,
                       locations: [0, 0.4, 1])!
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.scaleBy(x: 1, y: sy)
    ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
    ctx.restoreGState()
}

func hill(_ ctx: CGContext, base: CGFloat, amps: [(CGFloat, CGFloat, CGFloat)], top: UInt32, bottom: UInt32) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    for x in stride(from: 0, through: W, by: 8) {
        let xf = CGFloat(x)
        var y = base
        for (a, f, ph) in amps { y += a * sin(xf * f + ph) }
        p.addLine(to: CGPoint(x: xf, y: y))
    }
    p.addLine(to: CGPoint(x: Wf, y: 0))
    p.closeSubpath()
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    linear(ctx, [col(top), col(bottom)], CGPoint(x: 0, y: base + 80), CGPoint(x: 0, y: 0))
    ctx.restoreGState()
}

func pine(_ ctx: CGContext, x: CGFloat, y: CGFloat, h: CGFloat, color: UInt32, snow: UInt32, snowA: CGFloat) {
    let tiers = 4
    let trunkH = h * 0.08
    ctx.setFillColor(col(0x1a120e))
    ctx.fill(CGRect(x: x - h * 0.03, y: y, width: h * 0.06, height: trunkH + 2))
    for i in 0..<tiers {
        let fi = CGFloat(i)
        let by = y + trunkH + fi * h * 0.2
        let hw = h * (0.34 - fi * 0.07)
        let ty = by + h * 0.36
        ctx.setFillColor(col(color))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x - hw, y: by))
        ctx.addLine(to: CGPoint(x: x, y: ty))
        ctx.addLine(to: CGPoint(x: x + hw, y: by))
        ctx.closePath(); ctx.fillPath()
        // 가지 위에 쌓인 눈
        ctx.setFillColor(col(snow, snowA))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x - hw * 0.55, y: by + h * 0.13))
        ctx.addLine(to: CGPoint(x: x, y: ty))
        ctx.addLine(to: CGPoint(x: x + hw * 0.35, y: by + h * 0.18))
        ctx.addLine(to: CGPoint(x: x, y: by + h * 0.22))
        ctx.closePath(); ctx.fillPath()
    }
}

// MARK: 오두막 위치
let groundY: CGFloat = 300
let cabin = CGRect(x: 760, y: groundY, width: 400, height: 210)
let win1 = CGRect(x: 805, y: 375, width: 90, height: 80)
let win2 = CGRect(x: 1025, y: 375, width: 90, height: 80)
let door = CGRect(x: 925, y: groundY, width: 70, height: 140)
let roofL = CGPoint(x: 720, y: 500), roofT = CGPoint(x: 960, y: 690), roofR = CGPoint(x: 1200, y: 500)
let chimney = CGRect(x: 1040, y: 590, width: 44, height: 120)
let smokeOrigin = CGPoint(x: 1062, y: 728)

// MARK: 정적 배경
func drawBackground(_ ctx: CGContext) {
    linear(ctx, [col(0x070d24), col(0x16204a), col(0x3b3466), col(0x6a4a6e)],
           CGPoint(x: 0, y: Hf), CGPoint(x: 0, y: 330))
    // 달
    glow(ctx, CGPoint(x: 1560, y: 860), 380, 0xffe6c4, 0.18)
    glow(ctx, CGPoint(x: 1560, y: 860), 120, 0xfff1d8, 0.45)
    ctx.setFillColor(col(0xfff6e6))
    ctx.fillEllipse(in: CGRect(x: 1560 - 46, y: 860 - 46, width: 92, height: 92))
    ctx.setFillColor(col(0xe9dcc6, 0.6))
    ctx.fillEllipse(in: CGRect(x: 1540, y: 868, width: 18, height: 14))
    ctx.fillEllipse(in: CGRect(x: 1572, y: 840, width: 12, height: 10))

    // 먼 산과 숲
    hill(ctx, base: 470, amps: [(40, 0.0031, 0.4), (18, 0.009, 1.7)], top: 0x8d97c2, bottom: 0x5e6694)
    var r = RNG(s: 7)
    for i in 0..<70 {
        let x = CGFloat(i) * 28 + r.r(-8, 8)
        let y = 470 + 40 * sin(x * 0.0031 + 0.4) + 18 * sin(x * 0.009 + 1.7) - 22
        pine(ctx, x: x, y: y, h: r.r(50, 85), color: 0x2a3160, snow: 0xb7c0e0, snowA: 0.55)
    }
    hill(ctx, base: 380, amps: [(30, 0.0024, 2.2), (12, 0.007, 0.3)], top: 0xb4bfe0, bottom: 0x8994c0)
    for i in 0..<34 {
        let x = CGFloat(i) * 58 + r.r(-15, 15)
        if x > 640 && x < 1280 { continue }
        let y = 380 + 30 * sin(x * 0.0024 + 2.2) + 12 * sin(x * 0.007 + 0.3) - 30
        pine(ctx, x: x, y: y, h: r.r(90, 140), color: 0x1f2650, snow: 0xcfd7f0, snowA: 0.7)
    }

    // 앞쪽 눈밭
    hill(ctx, base: groundY + 10, amps: [(16, 0.002, 0.9), (6, 0.011, 2.0)], top: 0xe4eaf7, bottom: 0xa9b4d6)

    // 오두막 벽(통나무)
    ctx.setFillColor(col(0x4a3226))
    ctx.fill(cabin)
    for i in 0..<9 {
        let y = cabin.minY + CGFloat(i) * 24
        ctx.setFillColor(col(i % 2 == 0 ? 0x5a3d2d : 0x3f2a20))
        ctx.fill(CGRect(x: cabin.minX, y: y, width: cabin.width, height: 22))
        ctx.setFillColor(col(0x2a1b14))
        ctx.fill(CGRect(x: cabin.minX, y: y + 22, width: cabin.width, height: 2))
    }
    // 굴뚝
    ctx.setFillColor(col(0x5b3a30)); ctx.fill(chimney)
    ctx.setFillColor(col(0x3c261f))
    for i in 0..<5 { ctx.fill(CGRect(x: chimney.minX, y: chimney.minY + CGFloat(i) * 24, width: chimney.width, height: 2)) }
    ctx.setFillColor(col(0xf2f5fc))
    ctx.addPath(CGPath(roundedRect: CGRect(x: chimney.minX - 6, y: chimney.maxY - 4, width: chimney.width + 12, height: 16),
                       cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.fillPath()
    // 지붕 + 눈
    ctx.setFillColor(col(0x2e1d17))
    ctx.beginPath(); ctx.move(to: roofL); ctx.addLine(to: roofT); ctx.addLine(to: roofR); ctx.closePath(); ctx.fillPath()
    ctx.setStrokeColor(col(0xf3f6fd)); ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: roofL.x - 4, y: roofL.y + 8)); ctx.addLine(to: CGPoint(x: roofT.x, y: roofT.y + 10))
    ctx.addLine(to: CGPoint(x: roofR.x + 4, y: roofR.y + 8)); ctx.strokePath()
    ctx.setStrokeColor(col(0xc9d3ee)); ctx.setLineWidth(6)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: roofL.x, y: roofL.y - 4)); ctx.addLine(to: CGPoint(x: roofT.x, y: roofT.y - 4))
    ctx.addLine(to: CGPoint(x: roofR.x, y: roofR.y - 4)); ctx.strokePath()
    // 고드름
    ctx.setFillColor(col(0xdfe8fb, 0.9))
    var ir = RNG(s: 3)
    for i in 0..<16 {
        let x = 740 + CGFloat(i) * 28 + ir.r(-6, 6)
        let len = ir.r(10, 34)
        ctx.beginPath(); ctx.move(to: CGPoint(x: x - 4, y: 498)); ctx.addLine(to: CGPoint(x: x, y: 498 - len))
        ctx.addLine(to: CGPoint(x: x + 4, y: 498)); ctx.closePath(); ctx.fillPath()
    }
    // 문
    ctx.setFillColor(col(0x2b1a12)); ctx.fill(door.insetBy(dx: -5, dy: 0))
    ctx.setFillColor(col(0x6b4128)); ctx.fill(door)
    ctx.setFillColor(col(0xffd27a)); ctx.fillEllipse(in: CGRect(x: door.maxX - 18, y: door.minY + 62, width: 8, height: 8))
    // 앞쪽 큰 나무
    pine(ctx, x: 120, y: 150, h: 620, color: 0x101833, snow: 0xdbe3f5, snowA: 0.85)
    pine(ctx, x: 330, y: 230, h: 380, color: 0x141c3b, snow: 0xdbe3f5, snowA: 0.8)
    pine(ctx, x: 1760, y: 170, h: 560, color: 0x101833, snow: 0xdbe3f5, snowA: 0.85)
    pine(ctx, x: 1560, y: 250, h: 320, color: 0x141c3b, snow: 0xdbe3f5, snowA: 0.8)
    pine(ctx, x: 640, y: 290, h: 240, color: 0x18213f, snow: 0xdbe3f5, snowA: 0.8)
    pine(ctx, x: 1290, y: 285, h: 260, color: 0x18213f, snow: 0xdbe3f5, snowA: 0.8)
    // 앞쪽 눈 둔덕
    hill(ctx, base: 150, amps: [(30, 0.003, 1.2), (14, 0.009, 0.2)], top: 0xeef2fb, bottom: 0xc4cde6)
}

// MARK: 움직이는 요소
struct Flake { var x: CGFloat; var y: CGFloat; var r: CGFloat; var k: Double; var amp: CGFloat; var m: Double; var ph: Double; var a: CGFloat }
var flakes: [Flake] = []
for (count, rMin, rMax, k, a) in [(260, 1.2, 2.4, 1.0, 0.55), (150, 2.4, 3.8, 2.0, 0.75), (55, 4.0, 6.5, 3.0, 0.9)] {
    for _ in 0..<count {
        flakes.append(Flake(x: rng.r(0, Double(W)), y: rng.r(0, Double(H)), r: rng.r(rMin, rMax), k: k,
                            amp: rng.r(8, 30) * CGFloat(k), m: Double(Int(rng.r(1, 4))), ph: Double(rng.r(0, tau)),
                            a: CGFloat(a) * rng.r(0.7, 1)))
    }
}
struct Star { var p: CGPoint; var r: CGFloat; var m: Double; var ph: Double }
var stars: [Star] = (0..<160).map { _ in
    Star(p: CGPoint(x: rng.r(0, Double(W)), y: rng.r(620, Double(H))), r: rng.r(0.6, 1.8),
         m: Double(Int(rng.r(1, 6))), ph: Double(rng.r(0, tau)))
}.filter { hypot($0.p.x - 1560, $0.p.y - 860) > 140 }
let bulbColors: [UInt32] = [0xffb347, 0xff6b5b, 0xffe08a, 0x9be59b, 0xffa0c8]

func drawFrame(_ ctx: CGContext, bg: CGImage, t: Double) {
    let u = t / T
    ctx.draw(bg, in: CGRect(x: 0, y: 0, width: W, height: H))

    // 별 반짝임
    for s in stars {
        let a = 0.35 + 0.45 * (0.5 + 0.5 * sin(tau * s.m * u + s.ph))
        ctx.setFillColor(col(0xfff6e0, CGFloat(a)))
        ctx.fillEllipse(in: CGRect(x: s.p.x - s.r, y: s.p.y - s.r, width: s.r * 2, height: s.r * 2))
    }

    // 창문 불빛(난로 불처럼 일렁임)
    let f = CGFloat(0.86 + 0.07 * sin(tau * 7 * u) + 0.04 * sin(tau * 13 * u + 1.1) + 0.03 * sin(tau * 31 * u + 2.3))
    glow(ctx, CGPoint(x: 960, y: groundY - 30), 520, 0xffa040, 0.32 * f, sy: 0.28)
    for w in [win1, win2] {
        glow(ctx, CGPoint(x: w.midX, y: w.midY), 170, 0xffb050, 0.38 * f)
        let g = CGGradient(colorsSpace: space, colors: [col(0xfff0b0), col(0xffb347), col(0xe0702a)] as CFArray,
                           locations: [0, 0.55, 1])!
        ctx.saveGState(); ctx.clip(to: w)
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w.midX, y: w.minY + 18), startRadius: 0,
                               endCenter: CGPoint(x: w.midX, y: w.minY + 18), endRadius: 95 * (0.9 + 0.1 * f), options: [.drawsAfterEndLocation])
        ctx.setFillColor(col(0xffe9a0, 0.25 * f)); ctx.fill(w)
        ctx.restoreGState()
        ctx.setStrokeColor(col(0x2a1a12)); ctx.setLineWidth(8); ctx.stroke(w.insetBy(dx: -4, dy: -4))
        ctx.setLineWidth(5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: w.midX, y: w.minY)); ctx.addLine(to: CGPoint(x: w.midX, y: w.maxY))
        ctx.move(to: CGPoint(x: w.minX, y: w.midY)); ctx.addLine(to: CGPoint(x: w.maxX, y: w.midY))
        ctx.strokePath()
        ctx.setFillColor(col(0xf3f6fd))
        ctx.addPath(CGPath(roundedRect: CGRect(x: w.minX - 12, y: w.minY - 14, width: w.width + 24, height: 12),
                           cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
    }
    // 문틈 불빛
    ctx.setFillColor(col(0xffc060, 0.8 * f)); ctx.fill(CGRect(x: door.minX + 18, y: door.minY + 92, width: 34, height: 30))

    // 처마 전구 장식
    for i in 0..<15 {
        let s = CGFloat(i) / 14
        let p = s < 0.5
            ? CGPoint(x: roofL.x + 20 + (roofT.x - roofL.x - 20) * s * 2, y: roofL.y - 10 + (roofT.y - roofL.y) * s * 2 - 14)
            : CGPoint(x: roofT.x + (roofR.x - 20 - roofT.x) * (s - 0.5) * 2, y: roofT.y - 14 - (roofT.y - roofR.y) * (s - 0.5) * 2 - 10)
        let c = bulbColors[i % bulbColors.count]
        let a = CGFloat(0.55 + 0.45 * (0.5 + 0.5 * sin(tau * Double(1 + i % 4) * u + Double(i) * 1.7)))
        glow(ctx, p, 26, c, 0.55 * a)
        ctx.setFillColor(col(c, 0.7 + 0.3 * a))
        ctx.fillEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
    }

    // 굴뚝 연기
    for i in 0..<7 {
        let p = (u * 3 + Double(i) / 7).truncatingRemainder(dividingBy: 1)
        let pc = CGFloat(p)
        let x = smokeOrigin.x + 60 * pc * pc + 14 * CGFloat(sin(tau * (p * 1.5) + Double(i)))
        let y = smokeOrigin.y + 280 * pc
        let r = 16 + 46 * pc
        let a = 0.28 * (1 - pc) * min(1, pc * 6)
        ctx.setFillColor(col(0xc8c4d8, a))
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 1.7))
    }

    // 내리는 눈 (k * 화면높이 / 주기 → 끊김 없이 반복)
    for fl in flakes {
        var y = fl.y - CGFloat(fl.k * u) * (Hf + 40)
        y = y.truncatingRemainder(dividingBy: Hf + 40); if y < -20 { y += Hf + 40 }
        let x = fl.x + fl.amp * CGFloat(sin(tau * fl.m * u + fl.ph))
        ctx.setFillColor(col(0xffffff, fl.a * 0.25))
        ctx.fillEllipse(in: CGRect(x: x - fl.r * 2, y: y - fl.r * 2, width: fl.r * 4, height: fl.r * 4))
        ctx.setFillColor(col(0xffffff, fl.a))
        ctx.fillEllipse(in: CGRect(x: x - fl.r, y: y - fl.r, width: fl.r * 2, height: fl.r * 2))
    }

    // 따뜻한 색감 + 비네트
    ctx.setFillColor(col(0xff9a50, 0.04)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let v = CGGradient(colorsSpace: space, colors: [col(0x000000, 0), col(0x05030f, 0.45)] as CFArray, locations: [0.55, 1])!
    ctx.saveGState()
    ctx.translateBy(x: Wf / 2, y: Hf / 2); ctx.scaleBy(x: 1, y: Hf / Wf)
    ctx.drawRadialGradient(v, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: Wf * 0.62, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: 출력
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "따뜻한겨울.mp4")
try? FileManager.default.removeItem(at: out)

let bgCtx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
drawBackground(bgCtx)
let bg = bgCtx.makeImage()!

let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W,
    kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for i in 0..<frameCount {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buf = pb else { fatalError("pixel buffer") }
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    drawFrame(ctx, bg: bg, t: Double(i) / Double(fps))
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
    if i % 60 == 0 { print("프레임 \(i)/\(frameCount)") }
    if i == 0, CommandLine.arguments.count > 2 {   // 미리보기 PNG
        let img = ctx.makeImage()!
        let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "완료: \(out.path)" : "실패: \(String(describing: writer.error))")
