// 마인크래프트풍 겨울밤 움짤 생성기
// 창밖: 눈 덮인 산과 가문비나무, 내리는 눈 / 안: 촛불, 노트북, 김이 나는 코코아가 있는 따뜻한 방
// 정적인 장면은 복셀 레이트레이싱으로 한 번만 렌더링하고(조명 레이어 분리),
// 매 프레임 촛불 일렁임 · 불꽃 · 눈송이를 합성합니다. 12초 끊김 없는 반복.
//
// 빌드: swiftc -Ounchecked -o mcwinter MinecraftWinter.swift
// 영상: ./mcwinter 마크겨울.mp4
// 미리보기: ./mcwinter - preview.png 0.25   (해상도 배율, 영상은 만들지 않음)
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import simd

typealias V3 = SIMD3<Float>

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "마크겨울.mp4"
let previewPath: String? = args.count > 2 ? args[2] : nil
let previewOnly = args.count > 3
let scale: Float = args.count > 3 ? Float(args[3]) ?? 1 : 1
let W = Int(3440 * scale) / 2 * 2
let H = Int(1440 * scale) / 2 * 2
let fps: Int32 = 30
let T = 12.0
let frameCount = Int(T) * Int(fps)
let tau = 2 * Double.pi

// MARK: - 해시 · 노이즈 · 색

@inline(__always) func hash(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Float {
    var x = UInt32(truncatingIfNeeded: a) &* 0x9E37_79B1
    x = (x ^ UInt32(truncatingIfNeeded: b)) &* 0x85EB_CA77
    x = (x ^ (x >> 13) ^ UInt32(truncatingIfNeeded: c)) &* 0xC2B2_AE3D
    x = (x ^ (x >> 16) ^ UInt32(truncatingIfNeeded: d)) &* 0x27D4_EB2F
    x ^= x >> 15; x = x &* 0x2C1B_3C6D; x ^= x >> 12; x = x &* 0x297A_2D39; x ^= x >> 15
    return Float(x) * (1.0 / 4_294_967_296.0)
}

func vnoise(_ x: Float, _ z: Float, _ s: Int) -> Float {
    let xi = Int(floor(x)), zi = Int(floor(z))
    let fx = x - floor(x), fz = z - floor(z)
    let ux = fx * fx * (3 - 2 * fx), uz = fz * fz * (3 - 2 * fz)
    let a = hash(xi, zi, s, 0), b = hash(xi + 1, zi, s, 0)
    let c = hash(xi, zi + 1, s, 0), d = hash(xi + 1, zi + 1, s, 0)
    let ab = a + (b - a) * ux, cd = c + (d - c) * ux
    return ab + (cd - ab) * uz
}

func fbm(_ x: Float, _ z: Float, _ s: Int) -> Float {
    var sum: Float = 0, amp: Float = 0.5, f: Float = 1
    for o in 0..<4 { sum += amp * vnoise(x * f, z * f, s + o * 31); amp *= 0.5; f *= 2 }
    return sum / 0.9375
}

func lin(_ hex: UInt32) -> V3 {
    V3(powf(Float((hex >> 16) & 255) / 255, 2.2), powf(Float((hex >> 8) & 255) / 255, 2.2), powf(Float(hex & 255) / 255, 2.2))
}

@inline(__always) func mix(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }

// MARK: - 재질

let AIR: UInt8 = 0, SNOW: UInt8 = 1, DIRT: UInt8 = 2, STONE: UInt8 = 3, SLOG: UInt8 = 4, LEAVES: UInt8 = 5
let SPLANK: UInt8 = 6, DOAK: UInt8 = 7, GLASS: UInt8 = 8, OPLANK: UInt8 = 9, WAX: UInt8 = 10, WICK: UInt8 = 11
let IRON: UInt8 = 12, LAPTOP: UInt8 = 13, MSNOW: UInt8 = 14, WOOL: UInt8 = 15
let SCREEN: UInt8 = 16, MUG: UInt8 = 17

let cSnow = lin(0xF2F5FA), cSnow2 = lin(0xE0E6F0), cSnow3 = lin(0xCDD5E3)
let cDirt = lin(0x7A5536), cStone = lin(0x7D7D80), cStone2 = lin(0x66666A)
let cBark = lin(0x3B2A17), cBark2 = lin(0x4C3720), cBark3 = lin(0x2C1F10), cRing = lin(0x6B4D2C), cRing2 = lin(0x56401F)
let cLeaf = lin(0x2B4A35), cSPlank = lin(0x6E5034), cSSeam = lin(0x4A3420)
let cOPlank = lin(0xB08655), cOSeam = lin(0x7A5A34), cDOak = lin(0x3A2614), cDOak2 = lin(0x2A1B0D), cDOakTop = lin(0x4E3820)
let cWax = lin(0xEDE4CC), cWaxTop = lin(0xDCD0B0), cWick = lin(0x2A201A), cIron = lin(0x2E3138), cIron2 = lin(0x41454F)
let cAlu = lin(0xB4B9C2), cAluDark = lin(0x8E939C), cKey = lin(0x2A2C32), cBezel = lin(0x16171B)
let cMug = lin(0xEDE3D2), cMugBand = lin(0xC0392F), cMugRim = lin(0xF6F0E6), cCocoa = lin(0x5A3421), cMallow = lin(0xF7F1E8)
let codeColors = [V3(1.0, 0.45, 0.72), V3(0.42, 0.82, 1.0), V3(1.0, 0.84, 0.4), V3(0.65, 0.89, 0.18), V3(0.8, 0.82, 0.9)]
let cWool = lin(0x9C3328), cWool2 = lin(0x86281F), cGlass = lin(0xDCE8F0)

// MARK: - 월드 격자

let X0 = -220, Y0 = -4, Z0 = -10
let NX = 440, NY = 108, NZ = 280
let grid = UnsafeMutablePointer<UInt8>.allocate(capacity: NX * NY * NZ)
grid.initialize(repeating: 0, count: NX * NY * NZ)

@inline(__always) func cell(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
    let ix = x - X0, iy = y - Y0, iz = z - Z0
    if ix < 0 || iy < 0 || iz < 0 || ix >= NX || iy >= NY || iz >= NZ { return AIR }
    return grid[(iz * NY + iy) * NX + ix]
}

@inline(__always) func put(_ x: Int, _ y: Int, _ z: Int, _ m: UInt8, onlyAir: Bool = false) {
    let ix = x - X0, iy = y - Y0, iz = z - Z0
    if ix < 0 || iy < 0 || iz < 0 || ix >= NX || iy >= NY || iz >= NZ { return }
    let i = (iz * NY + iy) * NX + ix
    if onlyAir && grid[i] != AIR { return }
    grid[i] = m
}

// 바깥 지형
struct Peak { let x, z, h, r: Float }
let peaks = [
    Peak(x: -75, z: 180, h: 66, r: 90), Peak(x: -20, z: 220, h: 56, r: 70), Peak(x: 48, z: 170, h: 26, r: 45),
    Peak(x: -160, z: 150, h: 48, r: 70), Peak(x: 150, z: 215, h: 40, r: 75), Peak(x: 5, z: 135, h: 20, r: 40),
    Peak(x: -110, z: 110, h: 22, r: 45),
]
var heights = [Float](repeating: -10, count: NX * NZ)
@inline(__always) func heightAt(_ x: Int, _ z: Int) -> Float {
    let ix = x - X0, iz = z - Z0
    if ix < 0 || iz < 0 || ix >= NX || iz >= NZ { return -10 }
    return heights[iz * NX + ix]
}

for iz in 0..<NZ {
    let z = iz + Z0
    if z < 7 { continue }
    for ix in 0..<NX {
        let fx = Float(ix + X0), fz = Float(z)
        var h = (fbm(fx * 0.06, fz * 0.06, 1) - 0.5) * 3 * min(1, (fz - 7) / 12)
        var m: Float = 0
        for p in peaks {
            let d = ((fx - p.x) * (fx - p.x) + (fz - p.z) * (fz - p.z)).squareRoot() / p.r
            if d < 1 {
                let v = p.h * powf(1 - d, 1.4)
                m = max(m, v) + min(m, v) * 0.25
            }
        }
        if m > 0 { m += (fbm(fx * 0.05, fz * 0.05, 9) - 0.5) * 16 * min(1, m / 12) }
        h += max(m, 0)
        heights[iz * NX + ix] = max(h, -1)
    }
}
for iz in 0..<NZ {
    let z = iz + Z0
    if z < 7 { continue }
    for ix in 0..<NX {
        let x = ix + X0
        let h = heightAt(x, z)
        let top = Int(ceil(h)) - 1
        var slope: Float = 0
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let hn = heightAt(x + dx, z + dz)
            if hn > -5 { slope = max(slope, abs(h - hn)) }
        }
        let topMat: UInt8 = (slope > 2.4 && h > 8) ? STONE : (h > 5 ? MSNOW : SNOW)
        if top < Y0 { continue }
        for y in Y0...min(top, Y0 + NY - 1) {
            put(x, y, z, y == top ? topMat : (h > 5 ? STONE : DIRT))
        }
    }
}

// 가문비나무
func spruce(_ x: Int, _ z: Int, _ hgt: Int) {
    let by = Int(ceil(heightAt(x, z)))
    let top = by + hgt
    for y in by..<top { put(x, y, z, SLOG) }
    put(x, top, z, LEAVES); put(x, top + 1, z, LEAVES)
    for y in (by + 2)...top {
        let ry = top - y
        let base = min(3, (ry + 2) / 3)
        let r = (ry % 2 == 0) ? max(base - 1, 0) : base
        if r == 0 { put(x, y, z, LEAVES, onlyAir: true); continue }
        for dx in -r...r {
            for dz in -r...r {
                if abs(dx) == r && abs(dz) == r { continue }
                put(x + dx, y, z + dz, LEAVES, onlyAir: true)
            }
        }
    }
}
var treeSeed = 0
func rnd() -> Float { treeSeed += 1; return hash(treeSeed, 77, 3, 1) }
// 창가 근처 큰 나무 몇 그루
for (x, z, h) in [(-22, 13, 11), (-15, 18, 9), (-31, 15, 12), (30, 13, 11), (36, 19, 12)] {
    spruce(x, z, h)
}
for _ in 0..<900 {
    let x = Int(rnd() * 320) - 160
    let z = Int(20 + rnd() * 120)
    if z < 70 && x > -26 && x < 34 && hash(x, z, 5, 5) < 0.85 { continue }
    let h = heightAt(x, z)
    if h > 16 || h < -2 { continue }
    if abs(heightAt(x + 1, z) - h) > 1.5 || abs(heightAt(x, z + 1) - h) > 1.5 { continue }
    spruce(x, z, 6 + Int(rnd() * 7))
}

// 방 (바닥 y=0, 창문 벽 z=6)
for x in -16...16 {
    for z in -8...6 {
        for y in Y0..<0 { put(x, y, z, y == -1 ? OPLANK : DIRT) }
        put(x, 8, z, SPLANK)
    }
    for y in 0...8 { put(x, y, -8, SPLANK) }
}
for z in -8...6 { for y in 0...8 { put(-16, y, z, SPLANK); put(16, y, z, SPLANK) } }
let posts: Set<Int> = [-12, -7, -2, 3, 8, 13]
for x in -15...15 {
    for y in 0...7 {
        let m: UInt8
        if y == 0 { m = SPLANK } else if posts.contains(x) || y == 7 { m = DOAK } else { m = GLASS }
        put(x, y, 6, m)
    }
    put(x, 0, 4, OPLANK); put(x, 0, 5, OPLANK)    // 창가 선반
}
for x in -15...15 { for z in -2...1 { put(x, -1, z, WOOL) } }   // 러그

// MARK: - 소품 (블록보다 작은 상자들)

struct Box { var lo: V3; var hi: V3; var mat: UInt8; var group: Int }
struct Light { var p: V3; var col: V3; var r: Float; var ignore: Int }
var boxes: [Box] = []
var candleLights: [Light] = []
var steadyLights: [Light] = []
struct Flame { var p: V3; var seed: Int }
var flames: [Flame] = []

let candleCol = V3(1.0, 0.48, 0.15) * 0.55
let candles: [(x: Float, z: Float, w: Float, h: Float)] = [
    (-0.95, 4.70, 0.375, 0.8125), (-0.40, 4.45, 0.375, 0.5625), (-0.60, 5.30, 0.375, 1.0),
    (0.00, 5.05, 0.3125, 0.4375),
]
for (i, c) in candles.enumerated() {
    let top: Float = 1 + c.h
    boxes.append(Box(lo: V3(c.x - c.w / 2, 1, c.z - c.w / 2), hi: V3(c.x + c.w / 2, top, c.z + c.w / 2), mat: WAX, group: -1))
    boxes.append(Box(lo: V3(c.x - 1 / 32, top, c.z - 1 / 32), hi: V3(c.x + 1 / 32, top + 2 / 16, c.z + 1 / 32), mat: WICK, group: i))
    let fp = V3(c.x, top + 4 / 16, c.z)
    candleLights.append(Light(p: fp, col: candleCol, r: 0.06, ignore: i))
    flames.append(Flame(p: V3(c.x, top + 1.5 / 16, c.z), seed: i * 13 + 5))
}
// 노트북 (키보드 쪽이 방을 향함, 화면은 코드 에디터)
let lapX: Float = 2.2, lapZ: Float = 4.3
let lapLo = V3(lapX - 9 / 16, 1, lapZ)
boxes.append(Box(lo: lapLo, hi: lapLo + V3(18 / 16, 1 / 16, 11 / 16), mat: LAPTOP, group: 200))
let screenLo = lapLo + V3(0, 1 / 16, 10 / 16)
boxes.append(Box(lo: screenLo, hi: screenLo + V3(18 / 16, 11 / 16, 1 / 16), mat: SCREEN, group: 200))
steadyLights.append(Light(p: V3(lapX, 1.42, lapZ + 0.45), col: V3(0.75, 0.5, 1.0) * 0.12, r: 0.25, ignore: 200))
// 머그 쪽을 비추는 은은한 실내등
steadyLights.append(Light(p: V3(2.9, 2.2, 3.2), col: V3(1.0, 0.6, 0.3) * 0.18, r: 0.3, ignore: -2))

// 코코아 머그컵 (손잡이는 왼쪽)
let mugX: Float = 3.55, mugZ: Float = 4.45
boxes.append(Box(lo: V3(mugX - 4 / 16, 1, mugZ - 4 / 16), hi: V3(mugX + 4 / 16, 1 + 7 / 16, mugZ + 4 / 16), mat: MUG, group: 300))
for (x0, y0, x1, y1) in [(-6, 2, -5, 6), (-6, 5, -4, 6), (-6, 2, -4, 3)] as [(Float, Float, Float, Float)] {
    boxes.append(Box(lo: V3(mugX + x0 / 16, 1 + y0 / 16, mugZ - 1 / 32), hi: V3(mugX + x1 / 16, 1 + y1 / 16, mugZ + 1 / 32), mat: MUG, group: 301))
}

// MARK: - 카메라 · 하늘

let camPos = V3(0.3, 2.45, -1.2)
let yaw: Float = 6 * .pi / 180, pitch: Float = 1.5 * .pi / 180
let fwd = V3(sinf(yaw) * cosf(pitch), sinf(pitch), cosf(yaw) * cosf(pitch))
let rgt = simd_normalize(V3(cosf(yaw), 0, -sinf(yaw)))
let upv = simd_cross(fwd, rgt)
let focal = Float(W) / 2 / tanf(42 * .pi / 180)

let moonDir = simd_normalize(V3(0.50, 0.22, 0.84))
let moonR = simd_normalize(simd_cross(V3(0, 1, 0), moonDir))
let moonU = simd_cross(moonDir, moonR)
let moonLight = V3(0.55, 0.55, 0.78) * 0.55
let skyZenith = lin(0x2E2763), skyHorizon = lin(0x7E6496), skyWarm = lin(0xA27E9C)
let fogCol = lin(0x76618F)
let skyAmb = V3(0.13, 0.115, 0.22)

func sky(_ d: V3) -> V3 {
    let e = max(d.y, -0.1)
    var c = mix(skyHorizon, skyZenith, powf(min(max(e * 1.8 + 0.05, 0), 1), 0.65))
    c = mix(c, skyWarm, max(0, 1 - e * 8) * 0.35)
    let cm = simd_dot(d, moonDir)
    if cm > 0.99 {
        let u = simd_dot(d, moonR) / cm, v = simd_dot(d, moonU) / cm
        let s: Float = 0.032
        if abs(u) < s && abs(v) < s {
            let tu = Int((u / s + 1) * 4), tv = Int((v / s + 1) * 4)
            let crater = hash(tu, tv, 9, 9) < 0.22
            return V3(1.0, 0.95, 0.84) * (crater ? 1.8 : 2.6)
        }
    }
    let g = max(cm, 0)
    c += V3(0.55, 0.48, 0.6) * (powf(g, 900) * 0.8 + powf(g, 60) * 0.12)
    if d.y > 0.06 {
        let q = d * 260
        if hash(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)), 4) < 0.0025 { c += V3(0.5, 0.5, 0.62) }
    }
    return c
}

// MARK: - 텍스처

@inline(__always) func faceUV(_ p: V3, _ axis: Int) -> (Float, Float) {
    switch axis {
    case 0: return (p.z, p.y)
    case 1: return (p.x, p.z)
    default: return (p.x, p.y)
    }
}

func albedo(_ m: UInt8, _ tu: Int, _ tv: Int, _ bx: Int, _ by: Int, _ bz: Int, _ axis: Int, _ ny: Float) -> V3 {
    let r = hash(bx * 16 + tu, by * 16 + tv, bz, Int(m) &* 977 &+ axis)
    switch m {
    case SNOW:
        return r < 0.07 ? cSnow3 : (r < 0.28 ? cSnow2 : cSnow)
    case MSNOW:
        if axis != 1 && tv < 11 { return cStone * (0.82 + 0.3 * r) }
        return r < 0.07 ? cSnow3 : (r < 0.28 ? cSnow2 : cSnow)
    case DIRT: return cDirt * (0.8 + 0.4 * r)
    case STONE:
        let patch = hash(bx * 4 + tu / 4, by * 4 + tv / 4, bz, 31) < 0.3
        return (patch ? cStone2 : cStone) * (0.85 + 0.3 * r)
    case SLOG:
        if axis == 1 {
            let d = max(abs(Float(tu) - 7.5), abs(Float(tv) - 7.5))
            return d > 6.5 ? cBark : (Int(d) % 2 == 0 ? cRing : cRing2)
        }
        let s = hash(bx, by, bz * 16 + tu, 5)
        return (s < 0.3 ? cBark3 : (s < 0.7 ? cBark : cBark2)) * (0.9 + 0.2 * r)
    case LEAVES:
        if ny > 0.5 { return (r < 0.3 ? cSnow2 : cSnow) * 0.97 }
        if r < 0.22 { return cSnow2 * 0.9 }
        return cLeaf * (0.7 + 0.6 * r)
    case SPLANK, OPLANK:
        let row = (tv + (axis == 1 ? 0 : 0)) / 4
        let seamU = (row * 7 + bx * 3 + bz * 5 + 3) & 15
        let isSeam = tv % 4 == 0 || tu == seamU
        let base = m == SPLANK ? cSPlank : cOPlank
        let seam = m == SPLANK ? cSSeam : cOSeam
        let grain = 0.88 + 0.22 * hash(bx, by * 4 + row, bz, tu / 3 + 50)
        return isSeam ? seam : base * grain * (0.95 + 0.1 * r)
    case DOAK:
        if axis == 1 {
            let d = max(abs(Float(tu) - 7.5), abs(Float(tv) - 7.5))
            return d > 6.5 ? cDOak2 : cDOakTop * (Int(d) % 2 == 0 ? 1 : 0.85)
        }
        let s = hash(bx, by, bz * 16 + (axis == 0 ? tv : tu), 6)
        return (s < 0.35 ? cDOak2 : cDOak) * (0.9 + 0.2 * r)
    case WOOL: return (r < 0.3 ? cWool2 : cWool) * (0.95 + 0.1 * r)
    case GLASS: return cGlass
    default: return V3(0.5, 0.5, 0.5)
    }
}

// MARK: - 노트북 음악 플레이어 화면 (안쪽 34x20 픽셀, v는 아래→위)

func playerPixel(_ u: Int, _ v: Int) -> V3 {
    // 가운데 앨범 커버 (보랏빛 밤하늘, 달, 눈밭)
    if u >= 11 && u <= 22 && v >= 6 && v <= 17 {
        let au = u - 11, av = v - 6
        if av <= 2 { return V3(0.62, 0.64, 0.80) * 0.45 }
        if (au == 8 || au == 9) && (av == 8 || av == 9) { return V3(1.0, 0.94, 0.8) * 0.6 }
        return mix(V3(0.42, 0.18, 0.42), V3(0.10, 0.06, 0.26), Float(av - 3) / 8) * 0.45
    }
    // 얇은 진행 막대
    if v == 3 && u >= 8 && u <= 25 {
        return u <= 14 ? V3(0.85, 0.82, 0.95) * 0.35 : V3(0.06, 0.055, 0.09)
    }
    return V3(0.006, 0.005, 0.014)
}

// MARK: - 광선 추적

struct VHit { var t: Float; var mat: UInt8; var axis: Int; var x, y, z: Int; var sgn: Int }

// mode 0: 첫 번째 블록(유리 포함) / mode 1: 그림자(유리는 통과하며 감쇠)
@inline(__always) func march(_ o: V3, _ d: V3, _ tLimit: Float, _ shadowMode: Bool, _ trans: inout Float, skipGlass: Bool = false) -> VHit? {
    var x = Int(floor(o.x)), y = Int(floor(o.y)), z = Int(floor(o.z))
    let sx = d.x > 0 ? 1 : -1, sy = d.y > 0 ? 1 : -1, sz = d.z > 0 ? 1 : -1
    let dx = d.x != 0 ? abs(1 / d.x) : Float.infinity
    let dy = d.y != 0 ? abs(1 / d.y) : Float.infinity
    let dz = d.z != 0 ? abs(1 / d.z) : Float.infinity
    var tx = d.x > 0 ? (Float(x + 1) - o.x) * dx : (d.x < 0 ? (o.x - Float(x)) * dx : .infinity)
    var ty = d.y > 0 ? (Float(y + 1) - o.y) * dy : (d.y < 0 ? (o.y - Float(y)) * dy : .infinity)
    var tz = d.z > 0 ? (Float(z + 1) - o.z) * dz : (d.z < 0 ? (o.z - Float(z)) * dz : .infinity)
    var t: Float = 0
    var axis = 0
    while true {
        if tx < ty && tx < tz { x += sx; t = tx; tx += dx; axis = 0 }
        else if ty < tz { y += sy; t = ty; ty += dy; axis = 1 }
        else { z += sz; t = tz; tz += dz; axis = 2 }
        if t > tLimit { return nil }
        if (y >= Y0 + NY && sy > 0) || (y < Y0 && sy < 0) || (x >= X0 + NX && sx > 0) || (x < X0 && sx < 0)
            || (z >= Z0 + NZ && sz > 0) || (z < Z0 && sz < 0) { return nil }
        let m = cell(x, y, z)
        if m == AIR || (skipGlass && m == GLASS) { continue }
        if m == LEAVES {
            let p = o + d * t
            let (u, v) = faceUV(p, axis)
            let tu = Int((u - floor(u)) * 16), tv = Int((v - floor(v)) * 16)
            if hash(x * 16 + tu, y * 16 + tv, z, 1234) < 0.2 { continue }
        }
        if shadowMode {
            if m == GLASS { trans *= 0.85; continue }
            trans = 0
            return nil
        }
        let sg = axis == 0 ? sx : (axis == 1 ? sy : sz)
        return VHit(t: t, mat: m, axis: axis, x: x, y: y, z: z, sgn: sg)
    }
}

@inline(__always) func hitBox(_ o: V3, _ inv: V3, _ b: Box, _ tMax: Float) -> (Float, Int)? {
    let t0 = (b.lo - o) * inv, t1 = (b.hi - o) * inv
    let mn = simd_min(t0, t1), mx = simd_max(t0, t1)
    let tn = max(mn.x, max(mn.y, mn.z)), tf = min(mx.x, min(mx.y, mx.z))
    if tn > tf || tn < 1e-4 || tn > tMax { return nil }
    let axis = tn == mn.x ? 0 : (tn == mn.y ? 1 : 2)
    return (tn, axis)
}

func shadow(_ o: V3, _ d: V3, _ maxT: Float, _ ignore: Int) -> Float {
    let inv = V3(1 / d.x, 1 / d.y, 1 / d.z)
    for b in boxes where b.group != ignore {
        if hitBox(o, inv, b, maxT) != nil { return 0 }
    }
    var tr: Float = 1
    _ = march(o, d, maxT, true, &tr)
    return tr
}

@inline(__always) func solidAO(_ x: Int, _ y: Int, _ z: Int) -> Float {
    let m = cell(x, y, z)
    return (m == AIR || m == GLASS) ? 0 : 1
}

func ambientOcclusion(_ h: VHit, _ p: V3) -> Float {
    let nx = h.axis == 0 ? -h.sgn : 0, ny = h.axis == 1 ? -h.sgn : 0, nz = h.axis == 2 ? -h.sgn : 0
    let cx = h.x + nx, cy = h.y + ny, cz = h.z + nz
    var ux = 0, uy = 0, uz = 0, vx = 0, vy = 0, vz = 0
    switch h.axis {
    case 0: uz = 1; vy = 1
    case 1: ux = 1; vz = 1
    default: ux = 1; vy = 1
    }
    let (fu0, fv0) = faceUV(p, h.axis)
    let fu = fu0 - floor(fu0), fv = fv0 - floor(fv0)
    func occ(_ a: Int, _ b: Int) -> Float { solidAO(cx + ux * a + vx * b, cy + uy * a + vy * b, cz + uz * a + vz * b) }
    func corner(_ a: Int, _ b: Int) -> Float {
        let s1 = occ(a, 0), s2 = occ(0, b), c = occ(a, b)
        return (s1 > 0 && s2 > 0) ? 0 : 3 - (s1 + s2 + c)
    }
    let c00 = corner(-1, -1), c10 = corner(1, -1), c01 = corner(-1, 1), c11 = corner(1, 1)
    let a = c00 + (c10 - c00) * fu, b = c01 + (c11 - c01) * fu
    return 0.3 + 0.7 * ((a + (b - a) * fv) / 3)
}

// 표면 조명: (일정한 빛, 촛불 빛)
func lightSurface(_ p: V3, _ n: V3, _ inside: Bool, _ ao: Float, _ seed: Int) -> (V3, V3) {
    var steady: V3
    if inside {
        steady = (V3(0.022, 0.019, 0.034) + V3(0.05, 0.044, 0.095) * expf(-(6 - p.z) / 2.2)) * ao
    } else {
        steady = skyAmb * ao * (0.6 + 0.4 * max(n.y, 0))
    }
    let o = p + n * 0.002
    let nl = simd_dot(n, moonDir)
    if nl > 0 { steady += moonLight * nl * shadow(o, moonDir, 400, -1) }
    var cand = V3(0, 0, 0)
    if p.z < 8.5 && abs(p.x) < 18 {
        for (li, l) in steadyLights.enumerated() {
            let j = V3(hash(seed, li, 1, 7), hash(seed, li, 2, 7), hash(seed, li, 3, 7)) * 2 - 1
            let lp = l.p + j * l.r
            var dv = lp - p
            let dist = simd_length(dv); dv /= dist
            let ndl = simd_dot(n, dv)
            if ndl <= 0 { continue }
            steady += l.col * ndl / (dist * dist + 0.25) * shadow(o, dv, dist - 0.02, l.ignore)
        }
        for (li, l) in candleLights.enumerated() {
            let j = V3(hash(seed, li, 4, 8), hash(seed, li, 5, 8), hash(seed, li, 6, 8)) * 2 - 1
            let lp = l.p + j * l.r
            var dv = lp - p
            let dist = simd_length(dv); dv /= dist
            let ndl = simd_dot(n, dv)
            if ndl <= 0 { continue }
            cand += l.col * ndl / (dist * dist + 0.15) * shadow(o, dv, dist - 0.02, l.ignore)
        }
    }
    return (steady, cand)
}

struct Sample { var a: V3; var c: V3; var mask: Float }

func traceSample(_ d: V3, _ seed: Int) -> Sample {
    var o = camPos
    var trans: Float = 1
    var A = V3(0, 0, 0), C = V3(0, 0, 0)
    var passedGlass = false
    var travelled: Float = 0
    for _ in 0..<6 {
        var vt: Float = 0
        let vh = march(o, d, 700, false, &vt, skipGlass: passedGlass)
        let vtHit = vh?.t ?? 700
        // 소품 상자
        let inv = V3(1 / d.x, 1 / d.y, 1 / d.z)
        var bestB = -1; var bestT = vtHit; var bestAxis = 0
        for (i, b) in boxes.enumerated() {
            if let (t, ax) = hitBox(o, inv, b, bestT) { bestB = i; bestT = t; bestAxis = ax }
        }
        if bestB >= 0 {
            let b = boxes[bestB]
            let p = o + d * bestT
            var n = V3(0, 0, 0); n[bestAxis] = d[bestAxis] > 0 ? -1 : 1
            let l = (p - b.lo) * 16
            let (u, v) = faceUV(l, bestAxis)
            let tu = Int(u), tv = Int(v)
            let r = hash(tu, tv, bestB, bestAxis)
            var alb: V3
            var emit = V3(0, 0, 0), emitC = V3(0, 0, 0)
            switch b.mat {
            case WAX:
                if bestAxis == 1 {
                    let size = Int((b.hi.x - b.lo.x) * 16)
                    let edge = tu == 0 || tv == 0 || tu == size - 1 || tv == size - 1
                    alb = edge ? cWax : cWaxTop
                } else {
                    alb = cWax * (0.94 + 0.1 * r)
                }
                // 불꽃 아래 밀랍이 은은하게 비침
                emitC = V3(1.0, 0.55, 0.22) * 0.5 * expf(-(b.hi.y - p.y) * 9)
            case WICK: alb = cWick
            case LAPTOP:
                if bestAxis == 1 && n.y > 0 {
                    let key = tv >= 4 && tv <= 8 && tu >= 2 && tu <= 15
                    let pad = tv >= 1 && tv <= 3 && tu >= 6 && tu <= 11
                    alb = key ? cKey * (0.85 + 0.3 * r) : (pad ? cAluDark : cAlu * (0.97 + 0.06 * r))
                } else { alb = cAluDark }
            case SCREEN:
                if bestAxis == 2 && n.z < 0 {
                    // 화면은 블록당 32픽셀로 더 촘촘하게
                    let su = Int((p.x - b.lo.x) * 32), sv = Int((p.y - b.lo.y) * 32)
                    if su <= 0 || su >= 35 || sv <= 0 || sv >= 21 { alb = cBezel } else {
                        alb = V3(0, 0, 0)
                        emit = playerPixel(su - 1, sv - 1)
                    }
                } else { alb = bestAxis == 2 ? cAlu : cAluDark }
            case MUG:
                if bestAxis == 1 && n.y > 0 && b.group == 300 {
                    let edge = tu == 0 || tv == 0 || tu == 7 || tv == 7
                    let mallow = (tu == 3 && tv == 4) || (tu == 4 && tv == 3) || (tu == 4 && tv == 4) || (tu == 2 && tv == 2)
                    alb = edge ? cMugRim : (mallow ? cMallow : cCocoa * (0.9 + 0.2 * r))
                } else {
                    alb = (b.group == 300 && (tv == 2 || tv == 3)) ? cMugBand : cMug * (0.93 + 0.1 * r)
                }
            default: alb = r < 0.5 ? cIron : cIron2
            }
            let (s, c) = lightSurface(p, n, true, 1, seed)
            A += trans * (alb * s + emit)
            C += trans * (alb * c + emitC)
            return Sample(a: A, c: C, mask: 0)
        }
        guard let h = vh else {
            A += trans * sky(d)
            return Sample(a: A, c: C, mask: passedGlass ? trans : 0)
        }
        let p = o + d * h.t
        var n = V3(0, 0, 0); n[h.axis] = Float(-h.sgn)
        let (u, v) = faceUV(p, h.axis)
        let tu = min(15, Int((u - floor(u)) * 16)), tv = min(15, Int((v - floor(v)) * 16))
        let inside = p.z < 6.5 && abs(p.x) < 16.5 && p.y < 8.2
        if h.mat == GLASS {
            // 은은한 줄무늬만 있는 맑은 유리
            let streak = (tu - tv == 4 || tu - tv == 5) && tu >= 6 && tu <= 11
            let edge = tu == 0 || tv == 0 || tu == 15 || tv == 15
            let alpha: Float = streak ? 0.05 : (edge ? 0.03 : 0.012)
            let (s, c) = lightSurface(p, n, true, 1, seed)
            A += trans * alpha * cGlass * s * 1.5
            C += trans * alpha * cGlass * c * 1.5
            trans *= (1 - alpha) * 0.93
            passedGlass = true
            travelled += h.t
            o = p + d * 0.001
            continue
        }
        let alb = albedo(h.mat, tu, tv, h.x, h.y, h.z, h.axis, n.y)
        let ao = ambientOcclusion(h, p)
        let (s, c) = lightSurface(p, n, inside, ao, seed)
        var col = alb * s
        let dist = travelled + h.t
        var fog: Float = 0
        if !inside {
            fog = 1 - expf(-max(0, dist - 5) * 0.0062)
            col = mix(col, fogCol, fog)
        }
        A += trans * col
        C += trans * alb * c
        return Sample(a: A, c: C, mask: passedGlass ? trans : 0)
    }
    return Sample(a: A, c: C, mask: 0)
}

// MARK: - 정적 장면 렌더링

let N = W * H
let layerA = UnsafeMutablePointer<Float>.allocate(capacity: N * 3)
let layerC = UnsafeMutablePointer<Float>.allocate(capacity: N * 3)
let layerM = UnsafeMutablePointer<UInt8>.allocate(capacity: N)
let vignette = UnsafeMutablePointer<Float>.allocate(capacity: N)

let started = Date()
var spp: [(Float, Float)] = []
for k in 0..<16 {
    let ox: Float = Float(k % 4) * 0.25 + 0.125
    let oy: Float = Float(k / 4) * 0.25 + 0.125
    spp.append((ox, oy))
}
func renderRegion(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ la: UnsafeMutablePointer<Float>, _ lc: UnsafeMutablePointer<Float>, _ full: Bool) {
DispatchQueue.concurrentPerform(iterations: y1 - y0) { row in
    let py = row + y0
    for px in x0..<x1 {
        var a = V3(0, 0, 0), c = V3(0, 0, 0), m: Float = 0
        for (si, (ox, oy)) in spp.enumerated() {
            let sx = Float(px) + ox - Float(W) / 2
            let sy = Float(H) / 2 - (Float(py) + oy)
            let d = simd_normalize(fwd * focal + rgt * sx + upv * sy)
            let s = traceSample(d, (py * W + px) * 16 + si)
            a += s.a; c += s.c; m += s.mask
        }
        let i = py * W + px
        let inv = 1 / Float(spp.count); a *= inv; c *= inv; m *= inv
        la[i * 3] = a.x; la[i * 3 + 1] = a.y; la[i * 3 + 2] = a.z
        lc[i * 3] = c.x; lc[i * 3 + 1] = c.y; lc[i * 3 + 2] = c.z
        if !full { continue }
        layerM[i] = UInt8(min(255, m * 255))
        let vx = (Float(px) / Float(W) - 0.5) * 2, vy = (Float(py) / Float(H) - 0.5) * 2
        let rr = (vx * vx * 0.6 + vy * vy).squareRoot()
        vignette[i] = 1 - 0.38 * min(1, max(0, (rr - 0.55) / 0.75))
    }
}
}
renderRegion(0, W, 0, H, layerA, layerC, true)

print(String(format: "장면 렌더링 %.1f초 (%dx%d)", Date().timeIntervalSince(started), W, H))

let maskImage: CGImage = {
    let ctx = CGContext(data: layerM, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    return ctx.makeImage()!
}()

// MARK: - 프레임 합성

let gammaLUT: [UInt8] = (0..<4096).map { UInt8(min(255, powf(Float($0) / 4095, 1 / 2.2) * 255 + 0.5)) }
let exposure: Float = 1.7

@inline(__always) func aces(_ x: Float) -> Int {
    let v = x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14)
    return Int(min(max(v, 0), 1) * 4095)
}

func flicker(_ u: Double) -> Float {
    Float(0.9 + 0.05 * sin(tau * 5 * u) + 0.035 * sin(tau * 11 * u + 1.3) + 0.02 * sin(tau * 23 * u + 0.4))
}

struct Flake { var x, y: CGFloat; var p: CGFloat; var shape: Int; var k: Double; var amp: CGFloat; var m: Double; var ph: Double; var a: CGFloat }
var flakes: [Flake] = []
var fs = 0
func frnd() -> Double { fs += 1; return Double(hash(fs, 4242, 1, 1)) }
let px1 = CGFloat(scale)
for (count, p, k, a) in [(420, 3.0, 1.0, 0.55), (220, 5.0, 2.0, 0.8), (70, 8.0, 3.0, 0.95)] as [(Int, Double, Double, Double)] {
    for _ in 0..<count {
        flakes.append(Flake(x: CGFloat(frnd()) * CGFloat(W), y: CGFloat(frnd()) * CGFloat(H), p: CGFloat(p) * px1,
                            shape: Int(frnd() * 4), k: k, amp: CGFloat(10 + frnd() * 25 * k) * px1,
                            m: Double(1 + Int(frnd() * 3)), ph: frnd() * tau, a: CGFloat(a * (0.75 + 0.25 * frnd()))))
    }
}
let shapes: [[(Int, Int)]] = [
    [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
    [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
    [(0, 0)],
    [(0, 0), (1, 0), (0, 1), (1, 1)],
]

func project(_ p: V3) -> (CGFloat, CGFloat, CGFloat) {
    let r = p - camPos
    let z = simd_dot(r, fwd)
    let sx = Float(W) / 2 + focal * simd_dot(r, rgt) / z
    let syDown = Float(H) / 2 - focal * simd_dot(r, upv) / z
    return (CGFloat(sx), CGFloat(Float(H) - syDown), CGFloat(focal / z))
}

let flamePatterns: [[String]] = [
    [".r.", "roo", "oyo", "ywy", "wwy"],
    ["r..", "or.", "oyo", "ywy", "yww"],
    ["..r", ".or", "oyo", "ywy", "wwy"],
    [".r.", "ror", "oyo", "ywy", "ywy"],
    ["...", ".r.", "oyo", "ywy", "wwy"],
]
let flameColors: [Character: CGColor] = [
    "w": CGColor(srgbRed: 1, green: 0.98, blue: 0.86, alpha: 1), "y": CGColor(srgbRed: 1, green: 0.84, blue: 0.36, alpha: 1),
    "o": CGColor(srgbRed: 1, green: 0.55, blue: 0.16, alpha: 1), "r": CGColor(srgbRed: 0.88, green: 0.27, blue: 0.1, alpha: 1),
]
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func radial(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ rgb: (CGFloat, CGFloat, CGFloat), _ a: CGFloat) {
    let g = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: a),
        CGColor(srgbRed: rgb.0, green: rgb.1 * 0.8, blue: rgb.2 * 0.6, alpha: a * 0.3),
        CGColor(srgbRed: rgb.0, green: rgb.1 * 0.7, blue: rgb.2 * 0.5, alpha: 0),
    ] as CFArray, locations: [0, 0.35, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}

func renderFrame(_ base: UnsafeMutableRawPointer, _ bpr: Int, _ i: Int) {
    let u = Double(i) / Double(frameCount)
    let f = flicker(u)
    let px = base.assumingMemoryBound(to: UInt8.self)
    DispatchQueue.concurrentPerform(iterations: H) { y in
        let row = px + y * bpr
        for x in 0..<W {
            let k = y * W + x
            let v = vignette[k] * exposure
            let r = (layerA[k * 3] + layerC[k * 3] * f) * v
            let g = (layerA[k * 3 + 1] + layerC[k * 3 + 1] * f) * v
            let b = (layerA[k * 3 + 2] + layerC[k * 3 + 2] * f) * v
            row[x * 4] = gammaLUT[aces(b)]
            row[x * 4 + 1] = gammaLUT[aces(g)]
            row[x * 4 + 2] = gammaLUT[aces(r)]
            row[x * 4 + 3] = 255
        }
    }
    let ctx = CGContext(data: base, width: W, height: H, bitsPerComponent: 8, bytesPerRow: bpr, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let full = CGRect(x: 0, y: 0, width: W, height: H)

    // 창밖 눈
    ctx.saveGState()
    ctx.clip(to: full, mask: maskImage)
    let span = CGFloat(H) + 60 * px1
    for fl in flakes {
        var y = fl.y - CGFloat(fl.k * u) * span
        y = y.truncatingRemainder(dividingBy: span); if y < 0 { y += span }
        y -= 30 * px1
        let x = fl.x + fl.amp * CGFloat(sin(tau * fl.m * u + fl.ph))
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.92, blue: 1.0, alpha: fl.a))
        for (dx, dy) in shapes[fl.shape] {
            ctx.fill(CGRect(x: (x + CGFloat(dx) * fl.p).rounded(), y: (y + CGFloat(dy) * fl.p).rounded(), width: fl.p.rounded(), height: fl.p.rounded()))
        }
    }
    ctx.restoreGState()

    // 촛불
    let step = Int(Double(i) / Double(fps) * 8) % (Int(T) * 8)
    for fl in flames {
        let (sx, sy, ppb) = project(fl.p)
        let s = ppb / 16
        let fi = CGFloat(0.85 + 0.3 * Double(hash(fl.seed, step, 2, 2)))
        ctx.setBlendMode(.plusLighter)
        radial(ctx, CGPoint(x: sx, y: sy + 3 * s), ppb * 2.4, (1, 0.6, 0.3), 0.07 * fi)
        radial(ctx, CGPoint(x: sx, y: sy + 3 * s), ppb * 0.65 * (0.9 + 0.15 * fi), (1, 0.72, 0.38), 0.32 * fi)
        ctx.setBlendMode(.normal)
        let pat = flamePatterns[Int(hash(fl.seed, step, 1, 1) * Float(flamePatterns.count)) % flamePatterns.count]
        for (ri, rowStr) in pat.enumerated() {
            for (ci, ch) in rowStr.enumerated() {
                guard let c = flameColors[ch] else { continue }
                ctx.setFillColor(c)
                let x0 = (sx + (CGFloat(ci) - 1.5) * s).rounded(), y0 = (sy + CGFloat(4 - ri) * s).rounded()
                let x1 = (sx + (CGFloat(ci) - 0.5) * s).rounded(), y1 = (sy + CGFloat(5 - ri) * s).rounded()
                ctx.fill(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
            }
        }
        ctx.setBlendMode(.plusLighter)
        radial(ctx, CGPoint(x: sx, y: sy + 2 * s), s * 3.2, (1, 0.85, 0.55), 0.35 * fi)
        ctx.setBlendMode(.normal)
    }
    // 노트북 화면 빛 번짐
    let (lx, ly, lppb) = project(V3(lapX, 1.4, lapZ + 0.66))
    ctx.setBlendMode(.plusLighter)
    radial(ctx, CGPoint(x: lx, y: ly), lppb * 0.9, (0.75, 0.5, 1.0), 0.035)
    ctx.setBlendMode(.normal)
    // 코코아 김 (3초 주기로 반복)
    let mugTop = V3(mugX, 1 + 7 / 16, mugZ)
    for k in 0..<16 {
        let p = (u * 4 + Double(k) / 16).truncatingRemainder(dividingBy: 1)
        let sway = 0.05 * sin(tau * p * 1.3 + Double(k) * 2.1) + 0.035 * sin(tau * 2 * u + Double(k))
        let pos = mugTop + V3(Float(sway) + (hash(k, 0, 3, 3) - 0.5) * 0.14, Float(p) * 0.75, (hash(k, 1, 3, 3) - 0.5) * 0.12)
        let (sx, sy, ppb) = project(pos)
        let sz = (ppb / 16 * CGFloat(1 + Int(p * 2.5))).rounded()
        let a = CGFloat(0.6 * (1 - p) * min(1, p * 6))
        ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.94, blue: 0.97, alpha: a))
        ctx.fill(CGRect(x: (sx - sz / 2).rounded(), y: sy.rounded(), width: sz, height: sz))
    }
}

func savePNG(_ ctx: CGContext, _ path: String) {
    let img = ctx.makeImage()!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

if previewOnly, let path = previewPath {
    let bpr = W * 4
    let buf = UnsafeMutableRawPointer.allocate(byteCount: bpr * H, alignment: 16)
    renderFrame(buf, bpr, 0)
    let ctx = CGContext(data: buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: bpr, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    savePNG(ctx, path)
    print("미리보기: \(path)")
    exit(0)
}

// MARK: - 영상 저장 (HEVC)

let out = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: out)
let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 32_000_000, AVVideoQualityKey: 0.9],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
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
    renderFrame(CVPixelBufferGetBaseAddress(buf)!, CVPixelBufferGetBytesPerRow(buf), i)
    if i == 0, let path = previewPath {
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        savePNG(ctx, path)
    }
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
    if i % 60 == 0 { print("프레임 \(i)/\(frameCount)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "완료: \(out.path)" : "실패: \(String(describing: writer.error))")
