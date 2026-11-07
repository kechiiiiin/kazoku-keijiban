// アプリアイコン（1024px）を描く: `swift scripts/gen-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(red: 0.95, green: 0.58, blue: 0.31, alpha: 1), ending: NSColor(red: 0.85, green: 0.45, blue: 0.17, alpha: 1))!
    .draw(in: rect, angle: -90)
// 掲示板の紙
let paper = NSBezierPath(roundedRect: NSRect(x: 212, y: 190, width: 600, height: 650), xRadius: 60, yRadius: 60)
NSColor(white: 1, alpha: 0.96).setFill()
paper.fill()
// ○ と ✓ の行
let green = NSColor(red: 0.18, green: 0.62, blue: 0.42, alpha: 1)
let gray = NSColor(white: 0.78, alpha: 1)
for (i, done) in [true, false, true].enumerated() {
    let y = CGFloat(650 - i * 170)
    let circle = NSBezierPath(ovalIn: NSRect(x: 290, y: y - 45, width: 90, height: 90))
    if done { green.setFill(); circle.fill() } else { gray.setStroke(); circle.lineWidth = 16; circle.stroke() }
    if done {
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 312, y: y)); check.line(to: NSPoint(x: 330, y: y - 20)); check.line(to: NSPoint(x: 360, y: y + 22))
        check.lineWidth = 14; check.lineCapStyle = .round; check.lineJoinStyle = .round
        NSColor.white.setStroke(); check.stroke()
    }
    let bar = NSBezierPath(roundedRect: NSRect(x: 420, y: y - 18, width: 320, height: 36), xRadius: 18, yRadius: 18)
    (done ? gray : NSColor(white: 0.35, alpha: 1)).setFill(); bar.fill()
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
