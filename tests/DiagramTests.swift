import Foundation
import SwiftUI

@main struct DiagramTests {
    @MainActor static func main() throws {
        let data=Data(#"{"active":true,"startedAt":100,"mode":"running","style":"wave","taskCount":3,"frameSeconds":0.2,"keys":["93","logo"],"frames":[[16711680,255],[255,65280]]}"#.utf8)
        let plan=try JSONDecoder().decode(LightingPreviewData.self,from:data)
        let red=plan.rgb("93",at:100),blend=plan.rgb("93",at:100.1),blue=plan.rgb("93",at:100.2),wrapped=plan.rgb("93",at:100.4)
        precondition(red.0==1 && red.2==0)
        precondition(abs(blend.0-0.5)<1e-8 && abs(blend.2-0.5)<1e-8)
        precondition(blue.2>0.999 && blue.0<0.001)
        precondition(wrapped.0>0.999)
        let missing=plan.rgb("not-a-key",at:100);precondition(missing.0+missing.1+missing.2==0)
        let inactive=try JSONDecoder().decode(LightingPreviewData.self,from:Data(#"{"active":false,"startedAt":102}"#.utf8))
        let off=inactive.rgb("93",at:103);precondition(off.0+off.1+off.2==0)
        precondition(RunningStyle.allCases.count==5)
        for count in 1...4 { precondition(Set(RunningStyle.allCases.map{$0.title(count)}).count==5) }
        precondition(PreviewAnimationPolicy.shouldAnimate(visible:true,healthy:true,frameCount:2))
        precondition(!PreviewAnimationPolicy.shouldAnimate(visible:false,healthy:true,frameCount:2))
        precondition(!PreviewAnimationPolicy.shouldAnimate(visible:true,healthy:true,frameCount:1))
        precondition(!PreviewAnimationPolicy.shouldAnimate(visible:true,healthy:false,frameCount:64))
        precondition(!plan.isCurrent(for:"ghub:B"),"legacy preview must not be labelled as a selected device")
        let identified=try JSONDecoder().decode(LightingPreviewData.self,from:Data(#"{"active":true,"startedAt":100,"deviceKey":"ghub:A"}"#.utf8))
        precondition(identified.isCurrent(for:"ghub:A"))
        precondition(!identified.isCurrent(for:"ghub:B"))
        precondition(!identified.isCurrent(for:nil))
        print("PASS: shared-frame decoding, interpolation, clock wrap, missing/off states and style labels")
    }
}
