import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size*scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        let transform = NSAffineTransform(); transform.scale(by:CGFloat(pixels)/512); transform.concat()
        NSColor(srgbRed:16/255,green:19/255,blue:21/255,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:20,y:20,width:472,height:472),xRadius:108,yRadius:108).fill()
        NSColor(srgbRed:232/255,green:232/255,blue:232/255,alpha:1).setStroke()
        let p = NSBezierPath(); p.lineWidth = 42; p.lineCapStyle = .round
        p.appendArc(withCenter:NSPoint(x:256,y:256),radius:132,startAngle:38,endAngle:323,clockwise:false); p.stroke()
        let bar = NSBezierPath(); bar.lineWidth = 42; bar.lineCapStyle = .round; bar.move(to:NSPoint(x:265,y:256)); bar.line(to:NSPoint(x:388,y:256)); bar.line(to:NSPoint(x:388,y:202)); bar.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    }
}
