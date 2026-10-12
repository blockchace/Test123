import AppKit

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210)
NSGradient(starting: NSColor(calibratedRed: 0.33, green: 0.25, blue: 0.88, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.40, alpha: 1))!.draw(in: background, angle: -90)
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 402, y: 420, width: 220, height: 360), xRadius: 110, yRadius: 110).fill()
NSColor.white.setStroke()
let cradle = NSBezierPath()
cradle.move(to: NSPoint(x: 334, y: 552))
cradle.line(to: NSPoint(x: 334, y: 452))
cradle.curve(to: NSPoint(x: 690, y: 452), controlPoint1: NSPoint(x: 334, y: 218), controlPoint2: NSPoint(x: 690, y: 218))
cradle.line(to: NSPoint(x: 690, y: 552))
cradle.lineWidth = 42
cradle.lineCapStyle = .round
cradle.stroke()
let stand = NSBezierPath()
stand.move(to: NSPoint(x: 512, y: 278))
stand.line(to: NSPoint(x: 512, y: 210))
stand.move(to: NSPoint(x: 404, y: 210))
stand.line(to: NSPoint(x: 620, y: 210))
stand.lineWidth = 42
stand.lineCapStyle = .round
stand.stroke()
image.unlockFocus()
var rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
      let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
    fatalError("No se pudo generar el icono")
}
try data.write(to: URL(fileURLWithPath: output))
