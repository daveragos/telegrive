// Draws the window a Mac shows when Telegrive's disk image opens: the app on
// the left, an arrow to Applications on the right, and a line on opening it
// the first time, which macOS asks about since the app isn't notarized.
// tool/build_dmg.sh runs it, and tool/dmg_settings.py puts the two icons
// where the picture leaves room for them.
//
//   swift tool/dmg_background.swift <folder>
//
// writes background.png and background@2x.png into <folder>.
import AppKit

/// The window shows 660 by about 400 points, the title bar aside; the
/// picture runs on below that, so however tall a Mac draws the title bar,
/// the window never shows past its foot.
let width: CGFloat = 660
let height: CGFloat = 440

/// Where the icons' centres go, as tool/dmg_settings.py places them.
let appCentre = CGPoint(x: 170, y: 190)
let applicationsCentre = CGPoint(x: 490, y: 190)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

let ink = color(0x15171B)
let text2 = color(0x5B6170)
let text3 = color(0x6B7280)
let accent = color(0x2356E0)
let line = color(0xE3E7EF)

func centred(_ text: NSAttributedString, in rect: CGRect) {
  let style = NSMutableParagraphStyle()
  style.alignment = .center
  style.lineSpacing = 3
  let copy = NSMutableAttributedString(attributedString: text)
  copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
  copy.draw(with: rect, options: [.usesLineFragmentOrigin])
}

func plain(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSAttributedString {
  NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: size, weight: weight),
    .foregroundColor: color,
  ])
}

func drawWindow(_ cg: CGContext) {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!

  // A light ground, a shade cooler towards the foot.
  let ground = CGGradient(
    colorsSpace: space,
    colors: [color(0xFFFFFF).cgColor, color(0xEEF2FA).cgColor] as CFArray,
    locations: [0, 1]
  )!
  cg.drawLinearGradient(ground, start: .zero, end: CGPoint(x: 0, y: height), options: [])

  // A faint glow of the accent behind the arrow, which ties the two icons.
  let glow = CGGradient(
    colorsSpace: space,
    colors: [accent.withAlphaComponent(0.09).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray,
    locations: [0, 1]
  )!
  let middle = CGPoint(x: width / 2, y: appCentre.y)
  cg.drawRadialGradient(glow, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: 250, options: [])

  // The arrow: a row of dots, then a chevron.
  let from = appCentre.x + 92
  let to = applicationsCentre.x - 92
  cg.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
  cg.setLineCap(.round)
  cg.setLineWidth(5)
  cg.setLineDash(phase: 0, lengths: [0, 13])
  cg.move(to: CGPoint(x: from, y: appCentre.y))
  cg.addLine(to: CGPoint(x: to - 16, y: appCentre.y))
  cg.strokePath()
  cg.setLineDash(phase: 0, lengths: [])
  cg.setStrokeColor(accent.cgColor)
  cg.setLineWidth(5)
  cg.setLineJoin(.round)
  cg.move(to: CGPoint(x: to - 13, y: appCentre.y - 13))
  cg.addLine(to: CGPoint(x: to, y: appCentre.y))
  cg.addLine(to: CGPoint(x: to - 13, y: appCentre.y + 13))
  cg.strokePath()

  centred(
    plain("Drag Telegrive to Applications", size: 22, weight: .semibold, color: ink),
    in: CGRect(x: 40, y: 34, width: width - 80, height: 30)
  )
  centred(
    plain("Then open it from your Applications folder.", size: 13, color: text2),
    in: CGRect(x: 40, y: 68, width: width - 80, height: 20)
  )

  // The first launch, at the foot.
  cg.setStrokeColor(line.cgColor)
  cg.setLineWidth(1)
  cg.move(to: CGPoint(x: 56, y: 318.5))
  cg.addLine(to: CGPoint(x: width - 56, y: 318.5))
  cg.strokePath()
  let note = NSMutableAttributedString()
  note.append(plain("The first time, if macOS says it can't check Telegrive,\nopen ", size: 12, color: text3))
  note.append(plain("System Settings › Privacy & Security", size: 12, weight: .semibold, color: text2))
  note.append(plain(" and click ", size: 12, color: text3))
  note.append(plain("Open Anyway", size: 12, weight: .semibold, color: text2))
  note.append(plain(".", size: 12, color: text3))
  centred(note, in: CGRect(x: 70, y: 334, width: width - 140, height: 40))
}

func write(scale: CGFloat, to url: URL) throws {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale),
    pixelsHigh: Int(height * scale),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  let context = NSGraphicsContext(bitmapImageRep: rep)!
  let cg = context.cgContext
  // Points from the top left, as Finder places icons.
  cg.translateBy(x: 0, y: height * scale)
  cg.scaleBy(x: scale, y: -scale)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
  drawWindow(cg)
  NSGraphicsContext.restoreGraphicsState()
  // The size in points, so the larger picture reads as the Retina one.
  rep.size = NSSize(width: width, height: height)
  try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try write(scale: 1, to: folder.appendingPathComponent("background.png"))
try write(scale: 2, to: folder.appendingPathComponent("background@2x.png"))
