import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "MacVigilIcon.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
let bounds = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
NSBezierPath(rect: bounds).fill()

let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 38, dy: 38), xRadius: 215, yRadius: 215)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.58, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.97, alpha: 1),
    NSColor(calibratedRed: 0.59, green: 0.27, blue: 0.96, alpha: 1)
])!
gradient.draw(in: outer, angle: -35)
NSColor.white.withAlphaComponent(0.28).setStroke()
outer.lineWidth = 12
outer.stroke()

let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 785))
shield.curve(to: NSPoint(x: 745, y: 680), controlPoint1: NSPoint(x: 605, y: 738), controlPoint2: NSPoint(x: 698, y: 704))
shield.line(to: NSPoint(x: 745, y: 470))
shield.curve(to: NSPoint(x: 512, y: 238), controlPoint1: NSPoint(x: 745, y: 355), controlPoint2: NSPoint(x: 645, y: 270))
shield.curve(to: NSPoint(x: 279, y: 470), controlPoint1: NSPoint(x: 379, y: 270), controlPoint2: NSPoint(x: 279, y: 355))
shield.line(to: NSPoint(x: 279, y: 680))
shield.curve(to: NSPoint(x: 512, y: 785), controlPoint1: NSPoint(x: 326, y: 704), controlPoint2: NSPoint(x: 419, y: 738))
shield.close()
NSColor.white.withAlphaComponent(0.92).setStroke()
shield.lineWidth = 34
shield.lineJoinStyle = .round
shield.stroke()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 255, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.95)
]
let mark = NSString(string: "M")
let markSize = mark.size(withAttributes: attrs)
mark.draw(at: NSPoint(x: 512 - markSize.width / 2, y: 435), withAttributes: attrs)

let pulse = NSBezierPath()
pulse.move(to: NSPoint(x: 350, y: 395))
pulse.line(to: NSPoint(x: 435, y: 395))
pulse.line(to: NSPoint(x: 480, y: 335))
pulse.line(to: NSPoint(x: 525, y: 455))
pulse.line(to: NSPoint(x: 570, y: 310))
pulse.line(to: NSPoint(x: 615, y: 395))
pulse.line(to: NSPoint(x: 690, y: 395))
NSColor(calibratedRed: 0.72, green: 0.98, blue: 1.0, alpha: 1).setStroke()
pulse.lineWidth = 18
pulse.lineCapStyle = .round
pulse.lineJoinStyle = .round
pulse.stroke()

let badge = NSBezierPath(ovalIn: NSRect(x: 650, y: 150, width: 235, height: 235))
NSGradient(colors: [NSColor.systemGreen, NSColor(calibratedRed: 0.05, green: 0.72, blue: 0.36, alpha: 1)])!.draw(in: badge, angle: -45)
NSColor.white.withAlphaComponent(0.65).setStroke()
badge.lineWidth = 11
badge.stroke()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 773, y: 335))
bolt.line(to: NSPoint(x: 710, y: 245))
bolt.line(to: NSPoint(x: 762, y: 245))
bolt.line(to: NSPoint(x: 736, y: 187))
bolt.line(to: NSPoint(x: 832, y: 278))
bolt.line(to: NSPoint(x: 778, y: 278))
bolt.close()
NSColor.white.setFill()
bolt.fill()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: output))
print("Generated MacVigil icon at \(output)")
