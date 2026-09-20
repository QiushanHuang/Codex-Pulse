import AppKit

// Original path geometry; no font or system-symbol artwork is embedded.
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,
    bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
    colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let context = NSGraphicsContext(bitmapImageRep:rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
NSColor(srgbRed:0.055,green:0.075,blue:0.09,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:200,yRadius:200).fill()
let wave = NSBezierPath(); wave.lineWidth=44; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
let points:[NSPoint] = [.init(x:216,y:566),.init(x:324,y:566),.init(x:388,y:712),.init(x:490,y:444),.init(x:586,y:758),.init(x:656,y:566),.init(x:808,y:566)]
wave.move(to:points[0]);for point in points.dropFirst(){wave.line(to:point)}
NSColor.white.setStroke();wave.stroke()
func arc(_ fraction:Double)->NSBezierPath {
    let p=NSBezierPath();p.appendArc(withCenter:.init(x:512,y:443),radius:174,startAngle:180,endAngle:180+180*fraction)
    p.lineWidth=32;p.lineCapStyle = .round;return p
}
NSColor(srgbRed:0.17,green:0.24,blue:0.25,alpha:1).setStroke();arc(1).stroke()
NSColor(srgbRed:0.37,green:0.91,blue:0.73,alpha:1).setStroke();arc(0.75).stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
