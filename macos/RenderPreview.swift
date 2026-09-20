import SwiftUI
import AppKit

@main
struct RenderPreview {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let snapshot = PulseSnapshot.read()
        for (name,width,height,compact,expanded) in [("small",164.0,164.0,true,false),("medium",344.0,164.0,false,false),("large",344.0,344.0,false,true)] {
            let view = PulseCard(snapshot:snapshot,compact:compact,expanded:expanded).padding(16)
                .frame(width:width,height:height)
                .background(LinearGradient(colors:[Color(red:0.055,green:0.11,blue:0.14),Color(red:0.04,green:0.065,blue:0.09)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius:24))
                .environment(\.colorScheme,.dark).environment(\.locale,Locale(identifier:"zh_CN"))
            let renderer=ImageRenderer(content:view);renderer.scale=2
            guard let cgImage=renderer.cgImage else { throw NSError(domain:"RenderPreview",code:1) }
            let rep=NSBitmapImageRep(cgImage:cgImage)
            try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(name+".png"))
        }
    }
}
