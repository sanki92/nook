import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

let art = pixelContext(width: 32, height: 32)!
let pen = Pen(g: art, width: 32, height: 32)
pen.mascot(6, MascotPose(eyes: .happy, ground: 26))
pen.px(hex("#FFD166"), 26, 6); pen.px(hex("#FFD166"), 25, 7, 3, 1); pen.px(hex("#FFD166"), 26, 8)
pen.px(hex("#FFF4CF"), 4, 9)
let sprite = art.makeImage()!

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let side = points * scale
    let g = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(side)
    let tile = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    g.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil))
    g.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [hex("#46377A"), hex("#1B1730")] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    g.interpolationQuality = .none
    let inset = tile.insetBy(dx: s * 0.06, dy: s * 0.06)
    g.draw(sprite, in: inset)
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let rep = NSBitmapImageRep(cgImage: g.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
