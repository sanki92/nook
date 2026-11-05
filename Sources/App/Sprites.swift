import CoreGraphics
import Foundation

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
private var colorCache: [String: CGColor] = [:]

func hex(_ s: String) -> CGColor {
    if let c = colorCache[s] { return c }
    let v = UInt32(s.dropFirst(), radix: 16) ?? 0
    let c = CGColor(colorSpace: sRGB, components: [CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255, 1])!
    colorCache[s] = c
    return c
}

func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, CGFloat(max(0, min(1, a)))])!
}

private enum Palette {
    static let body = hex("#D97757"), dark = hex("#B4583A"), lite = hex("#EE9B7B"), eye = hex("#1B1210")
    static let white = hex("#F4F1EA"), shade = hex("#D6D0C3"), shadow = rgba(0, 0, 0, 0.3)
    static let wood = hex("#7A5439"), iron = hex("#A8ADB6"), gold = hex("#FFD166"), blush = hex("#F2A08A")
    static let confetti = ["#FFD166", "#EF476F", "#46D39A", "#6EC6FF", "#FFFFFF", "#C792EA"].map(hex)
}

enum Eyes { case open, blink, closed, happy, x }
enum Arm { case standard, at(Int, Int), hidden }

struct MascotPose {
    var w = 20, h = 13, legH = 3, lift = 0
    var shadow = true
    var step: [Bool]? = nil
    var left = Arm.standard, right = Arm.standard
    var eyes = Eyes.open, look = 0, eyeY = 4, eyeH = 4
    var ground = 46
}

struct Pen {
    let g: CGContext
    var extraX = 0, extraY = 0
    var width = 86, height = 50

    func px(_ c: CGColor, _ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) {
        g.setFillColor(c)
        g.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func pxf(_ c: CGColor, _ x: Double, _ y: Double, _ w: Int = 1, _ h: Int = 1) {
        px(c, Int((x + 0.5).rounded(.down)), Int((y + 0.5).rounded(.down)), w, h)
    }

    @discardableResult
    func mascot(_ x: Int, _ p: MascotPose = MascotPose()) -> Int {
        let top = p.ground - p.legH - p.h - p.lift
        if p.shadow {
            let s = max(8, p.w - 4 - p.lift)
            pxf(Palette.shadow, Double(x) + Double(p.w - s) / 2, Double(p.ground), s, 1)
        }
        if p.legH > 0 {
            for (i, l) in [2, 6, 12, 16].enumerated() {
                px(Palette.dark, x + l, top + p.h, 2, p.legH - ((p.step?[i] ?? false) ? 1 : 0))
            }
        }
        px(Palette.body, x, top, p.w, p.h)
        px(Palette.lite, x, top, p.w, 1)
        px(Palette.dark, x, top + p.h - 1, p.w, 1)

        func arm(_ a: Arm, _ dx: Int) {
            switch a {
            case .standard: px(Palette.body, x + dx, top + 5, 3, 3)
            case .at(let ax, let ay): px(Palette.body, x + ax, top + ay, 3, 3)
            case .hidden: break
            }
        }
        arm(p.left, -3)
        arm(p.right, p.w)

        let ey = top + p.eyeY, l = x + 5 + p.look, r = x + p.w - 7 + p.look
        switch p.eyes {
        case .open:
            px(Palette.eye, l, ey, 2, p.eyeH); px(Palette.eye, r, ey, 2, p.eyeH)
        case .blink:
            px(Palette.eye, l, ey + 2, 2, 1); px(Palette.eye, r, ey + 2, 2, 1)
        case .closed:
            px(Palette.eye, l - 1, ey, 4, 1); px(Palette.eye, r - 1, ey, 4, 1)
        case .happy:
            for a in [l, r] {
                px(Palette.eye, a - 1, ey + 1); px(Palette.eye, a, ey, 2, 1); px(Palette.eye, a + 2, ey + 1)
            }
            px(Palette.blush, l - 2, ey + 3, 3, 1); px(Palette.blush, r + 1, ey + 3, 3, 1)
            px(Palette.eye, x + 8, ey + 4, 1, 1); px(Palette.eye, x + 9, ey + 5, 2, 1); px(Palette.eye, x + 11, ey + 4, 1, 1)
        case .x:
            for a in [l, r] {
                px(Palette.eye, a - 1, ey); px(Palette.eye, a + 1, ey); px(Palette.eye, a, ey + 1); px(Palette.eye, a - 1, ey + 2); px(Palette.eye, a + 1, ey + 2)
            }
        }
        return top
    }

    func chefHat(_ x: Int, _ top: Int) {
        px(Palette.shade, x + 4, top - 3, 12, 3)
        px(Palette.white, x + 3, top - 9, 14, 6)
        px(Palette.white, x + 5, top - 10, 10, 1)
        px(Palette.shade, x + 3, top - 4, 14, 1)
    }

    func hardHat(_ x: Int, _ top: Int) {
        px(hex("#E9B44C"), x + 2, top - 5, 16, 5)
        px(hex("#E9B44C"), x + 4, top - 6, 12, 1)
        px(hex("#F3CC79"), x + 8, top - 6, 4, 6)
        px(hex("#C48F2C"), x - 1, top - 1, 22, 2)
    }

    func disc(_ cx: Int, _ cy: Int, rx: Int, ry: Int, _ c: CGColor) {
        guard rx > 0, ry > 0 else { return }
        for dy in -ry...ry {
            let t = Double(dy) / Double(ry)
            let half = Int((Double(rx) * (1 - t * t).squareRoot()).rounded())
            px(c, cx - half, cy + dy, half * 2 + 1, 1)
        }
    }

    func bang(_ x: Int, _ y: Int) {
        px(Palette.gold, x, y, 2, 6)
        px(Palette.gold, x, y + 7, 2, 2)
    }

    func zee(_ x: Int, _ y: Int, _ s: Int, _ c: CGColor) {
        px(c, x, y, s, 1)
        if s > 2 { for i in 1..<(s - 1) { px(c, x + s - 1 - i, y + i) } }
        px(c, x, y + s - 1, s, 1)
    }

    func trophy(_ cx: Int, _ y: Int) {
        let gold = hex("#FFC94A"), deep = hex("#C9901F"), lite = hex("#FFE9A8")
        px(gold, cx - 4, y, 9, 5); px(gold, cx - 3, y + 5, 7, 1); px(gold, cx - 1, y + 6, 3, 1)
        px(lite, cx - 3, y + 1, 2, 3)
        px(gold, cx - 6, y + 1, 2, 1); px(gold, cx - 6, y + 2, 1, 2); px(gold, cx - 5, y + 3, 1, 1)
        px(gold, cx + 5, y + 1, 2, 1); px(gold, cx + 6, y + 2, 1, 2); px(gold, cx + 5, y + 3, 1, 1)
        px(deep, cx - 1, y + 7, 3, 1); px(deep, cx - 3, y + 8, 7, 1)
    }
}

private func blink(_ f: Int) -> Bool { f % 41 < 2 }

extension Pen {
    func draw(_ state: AgentState, frame f: Int) {
        switch state {
        case .thinking: thinking(f)
        case .cooking: cooking(f)
        case .building: building(f)
        case .reading: reading(f)
        case .gate: gate(f)
        case .done: done(f)
        case .sleeping: sleeping(f)
        case .error: error(f)
        }
    }

    private func thinking(_ f: Int) {
        let x = 26 + (f % 16 < 8 ? 0 : 1)
        mascot(x, MascotPose(right: .at(20, f % 16 < 8 ? 4 : 5), eyes: blink(f) ? .blink : .open, look: 1, eyeY: 3))
        px(Palette.white, 46, 27, 2, 2); px(Palette.white, 50, 23, 3, 3)
        px(Palette.white, 54, 5, 26, 16); px(Palette.white, 52, 7, 30, 12); px(Palette.white, 56, 3, 22, 20)
        for i in 0..<3 {
            let on = (f / 4) % 4 == i
            px(on ? hex("#5866D6") : hex("#C9CCE0"), 59 + i * 6, on ? 10 : 11, 4, 4)
        }
    }

    private func cooking(_ f: Int) {
        let x = 11, t = f % 14, off = [0, -1, -2, -2, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0][t], py = 30 + off
        px(hex("#3F4249"), 50, 38, 28, 8); px(hex("#6C7079"), 50, 38, 28, 1)
        px(hex("#26282D"), 61, 40, 13, 5); px(hex("#E5533D"), 53, 41, 2, 2); px(hex("#E5533D"), 57, 41, 2, 2)
        px(Palette.shadow, 50, 46, 28, 1)
        for i in 0..<6 {
            let h = 2 + (f * 3 + i * 5) % 4
            px(hex("#F07F2E"), 54 + i * 3, 38 - h, 2, h)
            px(Palette.gold, 54 + i * 3, 38 - max(1, h - 2), 2, max(1, h - 2))
        }
        px(hex("#23252B"), 53, py, 21, 3); px(hex("#5C606A"), 53, py, 21, 1)
        px(Palette.wood, 34, py + 1, 19, 1)
        let armY = py - 30 < -1 ? -1 : py - 29
        let top = mascot(x, MascotPose(step: t < 2 ? [false, true, false, true] : nil, right: .at(20, armY), eyes: blink(f) ? .blink : .open, look: 1))
        chefHat(x, top)
        for (c, fx, k) in [(Palette.gold, 57, 1.0), (hex("#7AC74F"), 63, 1.25), (hex("#E5533D"), 69, 0.95)] {
            let a = Double(t * (10 - t)) * k * 0.42
            pxf(c, Double(fx), Double(py - 2) - (t < 10 ? a : 0), 3, 2)
        }
        for i in 0..<3 {
            let p = (f + i * 7) % 18
            px(rgba(255, 255, 255, 0.4 - Double(p) * 0.02), 58 + i * 6 + (p % 6 < 3 ? 0 : 1), py - 7 - p, 2, 2)
        }
    }

    private func building(_ f: Int) {
        let x = 11, t = f % 10, hit = t == 4 || t == 5
        let top = mascot(x, MascotPose(h: hit ? 12 : 13, right: .hidden, eyes: blink(f) ? .blink : .open, look: 1, eyeY: 5, eyeH: 3))
        hardHat(x, top)
        let hx = 31, hy = top + 6
        if t < 3 || t > 7 {
            px(Palette.wood, hx + 1, hy - 11, 2, 12); px(Palette.iron, hx - 2, hy - 15, 8, 4)
        } else if t == 3 || t == 6 || t == 7 {
            for i in 0..<8 { px(Palette.wood, hx + 1 + i, hy - i, 2, 2) }
            px(Palette.iron, hx + 8, hy - 12, 5, 6)
        } else {
            px(Palette.wood, hx, hy, 11, 2); px(Palette.iron, hx + 10, hy - 2, 4, 8)
        }
        px(Palette.body, hx - 1, hy - 1, 3, 3)
        px(hex("#5D616A"), 37, 41, 13, 5); px(hex("#7D828C"), 37, 41, 13, 1); px(Palette.shadow, 37, 46, 13, 1)
        if hit { for (a, b) in [(39, 35), (46, 33), (50, 37), (36, 37)] { px(Palette.gold, a, b, 2, 2) } }
        let total = 18, n = (f / 10) % (total + 6)
        for i in 0..<min(n, total) {
            let row = i / 3, col = i % 3
            let bx = 56 + col * 8 + (row % 2 == 1 ? 4 : 0), by = 41 - row * 5
            px(i == n - 1 && hit ? hex("#E58B5F") : hex("#B5613F"), bx, by, 7, 4)
            px(hex("#CF7C58"), bx, by, 7, 1)
        }
    }

    private func reading(_ f: Int) {
        let x = 28, flip = f % 28 < 3, look = [-2, 0, 2, 0][(f / 5) % 4]
        let top = mascot(x, MascotPose(left: .at(-2, 8), right: .at(19, 8), eyes: .open, look: look, eyeY: 2, eyeH: 3))
        px(hex("#7E4B9E"), x - 1, top + 7, 22, 10); px(Palette.white, x, top + 8, 20, 8)
        px(Palette.shade, x + 9, top + 8, 2, 8)
        for l in [1, 3, 5] {
            px(hex("#9A958A"), x + 2, top + 8 + l, 6, 1)
            if !flip { px(hex("#9A958A"), x + 12, top + 8 + l, 6, 1) }
        }
        if flip { px(hex("#FFFFFF"), x + 11, top + 3, 8, 12) }
        for (i, (c, a, w)) in [("#4F8FBF", 62, 16), ("#E0A23A", 60, 19), ("#5FA777", 63, 15)].enumerated() {
            px(hex(c), a, 42 - i * 4, w, 4)
            px(rgba(255, 255, 255, 0.3), a, 42 - i * 4, w, 1)
        }
        px(Palette.shadow, 60, 46, 19, 1)
        let b = (f / 2) % 26
        px(rgba(255, 255, 255, 0.55), 12, 34 - b, 7, 9)
        px(rgba(0, 0, 0, 0.25), 13, 36 - b, 5, 1); px(rgba(0, 0, 0, 0.25), 13, 38 - b, 5, 1)
    }

    private func gate(_ f: Int) {
        let t = f % 36, walk = t < 6 ? [0, 1, 2, 3, 3, 1][t] : 0, x = 11 + walk
        let top = mascot(x, MascotPose(
            step: t < 6 && t % 2 == 1 ? [true, false, true, false] : nil,
            right: t > 2 && t < 6 ? .at(20, 3) : .at(20, 6),
            eyes: blink(f) ? .blink : .open, look: t < 6 ? 1 : 0))
        bang(x + 9, top - 12 - ((f / 4) % 2))
        for a in [42, 74] {
            px(hex("#5A5048"), a, 28, 4, 18)
            px(hex("#3F3833"), a - 2, 45, 8, 1)
        }
        for rowY in [24, 34] {
            for i in 0..<40 {
                let stripe = ((i + (rowY == 34 ? 3 : 0)) / 5) % 2 == 1
                px(stripe ? Palette.white : hex("#E5533D"), 39 + i, rowY, 1, 6)
            }
            px(rgba(0, 0, 0, 0.22), 39, rowY + 5, 40, 1)
        }
        let lit = (f / 3) % 2 == 0
        for (i, a) in [44, 76].enumerated() {
            let on = i == 1 ? !lit : lit
            if on { px(rgba(255, 209, 102, 0.3), a - 4, 16, 8, 9) }
            px(on ? Palette.gold : hex("#8A6A2A"), a - 2, 18, 4, 5)
            px(hex("#3F3833"), a - 2, 23, 4, 1)
        }
        px(Palette.shadow, 40, 46, 38, 1)
    }

    private func done(_ f: Int) {
        let t = f % 14
        let jump = t < 9 ? Int((Double(t * (9 - t)) * 0.62).rounded()) : 0
        let squash = t == 9 || t == 10
        let x = 33
        let up = jump > 0
        let top = mascot(x, MascotPose(
            h: squash ? 11 : 13, lift: jump,
            step: up ? [true, true, true, true] : nil,
            left: up ? .at(1, -2) : .at(-3, 2),
            right: up ? .at(16, -2) : .at(20, 2),
            eyes: .happy, eyeY: squash ? 3 : 4))
        if up {
            trophy(x + 9, top - 11)
        } else {
            trophy(x + 9, top - 10)
            px(Palette.body, x + 1, top - 2, 3, 2); px(Palette.body, x + 16, top - 2, 3, 2)
        }

        for (i, (dx, dy)) in [(-11, -14), (29, -12), (-7, -4), (26, -3), (9, -20)].enumerated() {
            let phase = (f + i * 5) % 16
            guard phase < 6 else { continue }
            let sx = x + dx, sy = top + dy + jump
            px(hex("#FFF4CF"), sx, sy)
            if phase > 0 && phase < 5 { px(hex("#FFE08C"), sx - 1, sy); px(hex("#FFE08C"), sx + 1, sy); px(hex("#FFE08C"), sx, sy - 1); px(hex("#FFE08C"), sx, sy + 1) }
            if phase == 2 || phase == 3 { px(rgba(255, 224, 140, 0.6), sx - 2, sy); px(rgba(255, 224, 140, 0.6), sx + 2, sy); px(rgba(255, 224, 140, 0.6), sx, sy - 2); px(rgba(255, 224, 140, 0.6), sx, sy + 2) }
        }

        let left = -extraX + 3, right = 86 + extraX - 4
        let lift = (Double(46 + extraY) / 46).squareRoot()
        for burst in 0..<3 {
            let life = (f + burst * 20) % 60
            let seed = (f + burst * 20) / 60 + burst * 7
            for i in 0..<22 {
                let fromLeft = i % 2 == 0
                let spreadX = 0.55 + Double((i * 7 + seed * 3) % 10) * 0.16
                let spreadY = (1.5 + Double((i * 11 + seed * 5) % 10) * 0.19) * lift
                let time = Double(life)
                let px0 = Double(fromLeft ? left : right)
                let dx = spreadX * time * (fromLeft ? 1 : -1)
                let y = 44.0 - spreadY * time + 0.09 * time * time
                guard y < 47 else { continue }
                let color = Palette.confetti[(i + seed) % Palette.confetti.count]
                let tumble = (f / 2 + i) % 3
                pxf(color, px0 + dx, y, tumble == 0 ? 2 : 1, tumble == 2 ? 2 : 1)
            }
        }
    }

    private func sleeping(_ f: Int) {
        let br = (f / 14) % 2, x = 31
        mascot(x, MascotPose(w: 24, h: 8 + br, legH: 0, left: .at(-2, 4 + br), right: .at(23, 4 + br), eyes: .closed))
        for i in 0..<3 {
            let p = (f + i * 15) % 45, s = 3 + p / 15
            zee(57 + p / 5 + i, 32 - Int(Double(p) * 0.55), s, rgba(190, 205, 240, p > 34 ? 0.3 : 0.85))
        }
        for (a, b, w) in [(12, 4, 4), (10, 5, 4), (9, 6, 3), (9, 7, 3), (9, 8, 3), (9, 9, 4), (10, 10, 5), (12, 11, 4)] {
            px(hex("#EBDDB0"), a, b, w, 1)
        }
        for (i, (a, b)) in [(28, 5), (42, 12), (70, 4), (79, 16), (24, 18), (60, 8)].enumerated() where (f / 8 + i) % 3 != 0 {
            px(hex("#C8D2EE"), a, b)
        }
    }

    private func error(_ f: Int) {
        let x = 33, shake = f % 6 < 3 ? 0 : 1
        let top = mascot(x + shake, MascotPose(h: 12, left: .at(-3, 8), right: .at(20, 8), eyes: .x))
        for i in 0..<3 {
            let a = Double(f) / 3 + Double(i) * 2.09
            let sx = Double(x + 10) + cos(a) * 15, sy = Double(top - 6) + sin(a) * 3
            pxf(Palette.gold, sx - 1, sy, 3, 1); pxf(Palette.gold, sx, sy - 1, 1, 3)
        }
        for i in 0..<4 {
            let p = (f + i * 9) % 30, s = 2 + p / 8
            px(rgba(170, 170, 180, 0.65 - Double(p) * 0.02), x + 22 + (p % 8 < 4 ? 0 : 1) + i, top + 2 - p, s, s)
        }
    }
}

extension Pen {
    func drawIcon(_ state: AgentState, frame f: Int) {
        let eyes: Eyes = blink(f) ? .blink : .open
        switch state {
        case .thinking:
            let t = mascot(6, MascotPose(eyes: eyes, look: 1, eyeY: 3))
            for i in 0..<3 { px((f / 4) % 3 == i ? hex("#FFFFFF") : rgba(255, 255, 255, 0.35), 11 + i * 4, t - 5, 2, 2) }
        case .cooking:
            let t = mascot(6, MascotPose(eyes: eyes, look: 1))
            chefHat(6, t)
            for i in 0..<2 {
                let p = (f + i * 7) % 12
                px(rgba(255, 255, 255, 0.5 - Double(p) * 0.035), 27 + i, t + 4 - p, 2, 2)
            }
        case .building:
            let up = f % 8 < 4
            let t = mascot(6, MascotPose(right: .at(20, up ? 3 : 6), eyes: eyes, look: 1, eyeY: 5, eyeH: 3))
            hardHat(6, t)
            px(Palette.wood, 28, t + (up ? -3 : 0), 1, 7)
            px(Palette.iron, 26, t + (up ? -6 : -3), 5, 3)
        case .reading:
            let t = mascot(6, MascotPose(left: .at(-2, 8), right: .at(19, 8), eyes: .open, look: [-2, 0, 2, 0][(f / 5) % 4], eyeY: 2, eyeH: 3))
            px(hex("#7E4B9E"), 5, t + 7, 22, 8); px(Palette.white, 6, t + 8, 20, 6); px(Palette.shade, 15, t + 8, 2, 6)
        case .gate:
            let t = mascot(6, MascotPose(eyes: eyes))
            bang(15, t - 11 - ((f / 4) % 2))
            for i in 0..<30 { px((i / 4) % 2 == 1 ? Palette.white : hex("#E5533D"), 1 + i, 42, 1, 4) }
        case .done:
            let t = f % 12, jump = t < 8 ? Int((Double(t * (8 - t)) * 0.17).rounded()) : 0
            mascot(6, MascotPose(lift: jump, left: jump > 0 ? .at(-3, -1) : .at(-3, 5), right: jump > 0 ? .at(20, -1) : .at(20, 5), eyes: .happy))
            for (i, (a, c)) in [(1, 20), (28, 16), (4, 28), (29, 26)].enumerated() where (f / 4 + i) % 2 == 1 {
                px(Palette.confetti[i], a, c + 18, 2, 2)
            }
        case .sleeping:
            let br = (f / 14) % 2
            mascot(4, MascotPose(w: 24, h: 8 + br, legH: 0, left: .at(-2, 4 + br), right: .at(23, 4 + br), eyes: .closed))
            let p = f % 30
            zee(21 + p / 8, 34 - p / 3, 3 + p / 15, rgba(190, 205, 240, 0.85))
        case .error:
            let t = mascot(6, MascotPose(h: 12, left: .at(-3, 8), right: .at(20, 8), eyes: .x))
            let a = Double(f) / 3
            pxf(Palette.gold, 15 + cos(a) * 9, Double(t - 3) + sin(a) * 2, 2, 2)
        }
    }
}

extension Pen {
    func campfire(frame f: Int) {
        let w = width, h = height
        let groundY = h - 15

        for i in 0..<46 {
            let sx = (i * 53 + 17) % w, sy = (i * 29 + 5) % (groundY - 18)
            let twinkle = (f / 7 + i * 3) % 9
            if twinkle == 0 { continue }
            px(i % 5 == 0 ? hex("#FFF4CF") : rgba(200, 212, 245, twinkle < 3 ? 0.4 : 0.8), sx, sy)
            if i % 11 == 0 && twinkle > 6 { px(rgba(255, 244, 207, 0.5), sx - 1, sy); px(rgba(255, 244, 207, 0.5), sx + 1, sy); px(rgba(255, 244, 207, 0.5), sx, sy - 1); px(rgba(255, 244, 207, 0.5), sx, sy + 1) }
        }

        let mx = w - 34, my = 7
        disc(mx + 6, my + 6, rx: 15, ry: 15, rgba(235, 221, 176, 0.035))
        disc(mx + 6, my + 6, rx: 11, ry: 11, rgba(235, 221, 176, 0.05))
        for (dx, row, len) in [(4, 0, 6), (2, 1, 7), (1, 2, 6), (0, 3, 5), (0, 4, 4), (0, 5, 4), (0, 6, 4), (0, 7, 4), (0, 8, 5), (1, 9, 6), (2, 10, 8), (4, 11, 8), (6, 12, 5)] {
            px(hex("#EBDDB0"), mx + dx, my + row, len, 1)
        }
        px(hex("#D4C48F"), mx + 2, my + 5, 1, 1); px(hex("#D4C48F"), mx + 4, my + 10, 2, 1)

        let streak = f % 170
        if streak < 9 {
            let sx = 12 + streak * 5, sy = 5 + streak * 2
            for i in 0..<6 { px(rgba(255, 255, 255, 0.85 - Double(i) * 0.14), sx - i * 2, sy - i, 2, 1) }
        }

        for x in 0..<w {
            let far = abs(((x + 6) % 52) - 26) * 7 / 13 + abs((x % 23) - 11) / 4
            px(hex("#1F2748"), x, groundY - 27 + far, 1, 30 - far)
            let near = abs(((x + 30) % 38) - 19) * 3 / 4 + abs(((x + 4) % 15) - 7) / 3
            px(hex("#171D38"), x, groundY - 16 + near, 1, 20 - near)
        }

        for (tx, s) in [(6, 5), (15, 7), (w - 14, 6), (w - 24, 8), (w - 6, 4)] {
            for level in 0..<3 {
                let top = groundY - s * 3 + level * s
                for row in 0..<(s + 2) {
                    px(hex("#101731"), tx - row * 3 / 4, top + row, row * 3 / 2 + 2, 1)
                }
            }
            px(hex("#0C1126"), tx, groundY - 3, 2, 3)
        }

        let fireX = w / 2 + 24
        let breathe = (f / 4) % 3
        for (r, alpha) in [(26, 0.018), (19, 0.024), (12, 0.035)] {
            disc(fireX + 1, groundY - 9, rx: r + breathe, ry: r + breathe, rgba(255, 150, 70, alpha))
        }
        px(hex("#121830"), 0, groundY, w, h - groundY)
        px(hex("#1A2140"), 0, groundY, w, 1)
        for (rx, ry, alpha) in [(40, 7, 0.06), (28, 5, 0.09), (17, 3, 0.13)] {
            disc(fireX + 1, groundY + 2, rx: rx + breathe, ry: ry, rgba(255, 150, 70, alpha))
        }
        px(hex("#121830"), 0, groundY + 10, w, max(0, h - groundY - 10))

        let tentX = w / 2 - 62, tentW = 36, tentH = 24
        for row in 0..<tentH {
            let half = row * tentW / (2 * tentH)
            let cx = tentX + tentW / 2
            px(hex("#A65E3F"), cx - half, groundY - tentH + row, half, 1)
            px(hex("#D08A5F"), cx, groundY - tentH + row, half + 1, 1)
            if row > 7 {
                let door = (row - 7) * 7 / (tentH - 7)
                px(hex("#2A1A18"), cx - door, groundY - tentH + row, door * 2 + 1, 1)
            }
        }
        let flagWave = (f / 5) % 2
        px(hex("#5A3F2F"), tentX + tentW / 2, groundY - tentH - 5, 1, 6)
        px(hex("#FFD166"), tentX + tentW / 2 + 1, groundY - tentH - 5 + flagWave, 4, 2)

        let seatX = fireX - 42
        px(hex("#5B3A26"), seatX - 2, groundY - 3, 26, 4)
        px(hex("#73503A"), seatX - 2, groundY - 3, 26, 1)
        px(hex("#8E6A4F"), seatX + 23, groundY - 3, 1, 4)
        let cycle = f % 200
        let lookingUp = cycle > 120 && cycle < 165
        let eyes: Eyes = blink(f) ? .blink : .open
        let stickDip = (f / 12) % 2
        let top = mascot(seatX, MascotPose(
            shadow: false, right: .at(20, 5 + stickDip),
            eyes: eyes, look: lookingUp ? 0 : 1, eyeY: lookingUp ? 2 : 4, ground: groundY - 1))

        let handX = seatX + 23, handY = top + 6 + stickDip
        let tipX = fireX - 5
        for i in 0..<(tipX - handX) { px(hex("#8A6241"), handX + i, handY - i / 5, 1, 1) }
        let tipY = handY - (tipX - handX) / 5
        let toast = (f / 40) % 4
        px([hex("#F7F3EA"), hex("#F2DFB8"), hex("#E0B878"), hex("#B87F45")][toast], tipX - 1, tipY - 2, 5, 4)
        px(rgba(255, 255, 255, 0.6), tipX - 1, tipY - 2, 5, 1)

        px(hex("#5B3A26"), fireX - 10, groundY - 2, 22, 3)
        px(hex("#73503A"), fireX - 10, groundY - 2, 22, 1)
        px(hex("#4A2F1F"), fireX - 7, groundY - 4, 16, 2)
        for i in 0..<9 {
            let center = abs(i - 4)
            let base = 13 - center * 3
            let flick = (f * 3 + i * 7) % 3
            let flameH = max(2, base + flick)
            px(hex("#E5533D"), fireX - 8 + i * 2, groundY - 3 - flameH, 2, flameH)
            let mid = max(1, flameH * 2 / 3)
            px(hex("#F58F2E"), fireX - 8 + i * 2, groundY - 3 - mid, 2, mid)
            let core = max(1, flameH / 3)
            if center < 4 { px(Palette.gold, fireX - 8 + i * 2, groundY - 3 - core, 2, core) }
        }

        for i in 0..<7 {
            let p = (f + i * 11) % 36
            let sx = fireX + (i * 5) % 11 - 5 + (p / 6 + i) % 3 - 1
            px(i % 2 == 0 ? rgba(255, 209, 102, 1 - Double(p) / 36) : rgba(255, 130, 60, 1 - Double(p) / 36), sx, groundY - 16 - p, 1, 1)
        }

        for i in 0..<5 where (f / 6 + i * 2) % 5 != 0 {
            let a = Double(f) / 18 + Double(i) * 1.7
            pxf(hex("#E9F58A"), 28 + Double(i * 37 % (w - 40)) + cos(a) * 7, Double(groundY - 8 - i * 4) + sin(a * 1.4) * 4)
        }
    }
}
