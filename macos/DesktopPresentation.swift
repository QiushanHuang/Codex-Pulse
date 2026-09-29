import Foundation
import CoreGraphics

enum RingCenterContent:String,CaseIterable,Identifiable {
    case credit,percentage,resetCredits
    var id:String {rawValue}
    var title:String {self == .credit ? "Credit 余额":self == .percentage ? "剩余百分比":"可用重置次数"}
}

enum GlassMaterial:String,CaseIterable,Identifiable {
    case clear,regular
    var id:String {rawValue}
    var title:String {self == .clear ? "清澈折射":"柔和磨砂"}
}
enum GlassPreset:String,CaseIterable,Identifiable {
    case crystal,soft,contrast,custom
    var id:String {rawValue}
    var title:String {
        switch self {case .crystal:return "清透";case .soft:return "柔雾";case .contrast:return "高对比";case .custom:return "自定义"}
    }
    var configuration:[String:Any] {
        switch self {
        case .crystal:return ["glassPreset":rawValue,"glassTransparency":0.98,"glassMaterial":"clear"]
        case .soft:return ["glassPreset":rawValue,"glassTransparency":0.75,"glassMaterial":"regular"]
        case .contrast:return ["glassPreset":rawValue,"glassTransparency":0.35,"glassMaterial":"regular"]
        case .custom:return ["glassPreset":rawValue]
        }
    }
}
enum DesktopPositionPreset:String,CaseIterable,Identifiable {
    case leftTop,leftCenter,leftBottom,rightTop,rightCenter,rightBottom,floatingCenter,custom
    var id:String {rawValue}
    var title:String {
        switch self {
        case .leftTop:return "左侧 · 靠上";case .leftCenter:return "左侧 · 居中";case .leftBottom:return "左侧 · 靠下"
        case .rightTop:return "右侧 · 靠上";case .rightCenter:return "右侧 · 居中";case .rightBottom:return "右侧 · 靠下"
        case .floatingCenter:return "便签 · 屏幕中央";case .custom:return "自定义位置"
        }
    }
    var side:SidebarSide? {
        switch self {case .leftTop,.leftCenter,.leftBottom:return .left;case .rightTop,.rightCenter,.rightBottom:return .right;default:return nil}
    }
    var position:Double {switch self {case .leftTop,.rightTop:return 0.85;case .leftBottom,.rightBottom:return 0.15;default:return 0.5}}
}
enum DesktopPlacement {
    static func point(x:Double,y:Double,in frame:CGRect)->CGPoint {
        CGPoint(x:frame.minX+8+max(0,frame.width-16)*max(0,min(1,x)),y:frame.minY+8+max(0,frame.height-16)*max(0,min(1,y)))
    }
    static func fractions(_ point:CGPoint,in frame:CGRect)->CGPoint {
        CGPoint(x:max(0,min(1,(point.x-frame.minX-8)/max(1,frame.width-16))),y:max(0,min(1,(point.y-frame.minY-8)/max(1,frame.height-16))))
    }
}

enum MiniRingSizing {
    static let range:ClosedRange<Double>=40...160
    static let defaultDiameter=96.0
    static func normalized(_ value:Double)->Double {
        value.isFinite ? max(range.lowerBound,min(range.upperBound,value.rounded())):defaultDiameter
    }
}

enum StickySize:String,CaseIterable,Identifiable {
    case mini,compact,standard
    var id:String {rawValue}
    var title:String {self == .mini ? "迷你":self == .compact ? "紧凑":"标准"}
    var contentSize:CGSize {
        switch self {
        case .mini:return CGSize(width:96,height:96)
        case .compact:return CGSize(width:220,height:180)
        case .standard:return CGSize(width:344,height:384)
        }
    }
    var detail:String {self == .mini ? "圆环与剩余数字 · 右键打开菜单":self == .compact ? "额度与重置时间":"趋势与最近任务"}
}

enum MiniRingClickAction:String,CaseIterable,Identifiable {
    case none,compact,standard
    var id:String {rawValue}
    var title:String {self == .none ? "不展开":self == .compact ? "紧凑浮层":"标准浮层"}
    var target:StickySize? {self == .none ? nil:self == .compact ? .compact:.standard}
    var hint:String? {target.map{"单击临时展开\($0.title)信息"}}
}

enum StickyExpansionGeometry {
    static func frame(anchor:CGRect,in screen:CGRect,size:CGSize)->CGRect {
        let width=min(size.width,screen.width-16),height=min(size.height,screen.height-16)
        let right=anchor.maxX+10
        let x=right+width<=screen.maxX-8 ? right:anchor.minX-width-10
        return CGRect(x:max(screen.minX+8,min(x,screen.maxX-width-8)),
                      y:max(screen.minY+8,min(anchor.midY-height/2,screen.maxY-height-8)),width:width,height:height)
    }
}

enum SidebarBadge:String,CaseIterable,Identifiable {
    case waveform,remaining
    var id:String {rawValue}
    var title:String {self == .waveform ? "波形图标":"剩余数字"}
}

enum SidebarSection:String,CaseIterable,Identifiable {
    case quota,reset,consumption,summary,tasks,trend
    var id:String {rawValue}
    var key:String {"sidebarShow"+rawValue.prefix(1).uppercased()+rawValue.dropFirst()}
    var title:String {
        switch self {
        case .quota:return "剩余额度"
        case .reset:return "重置时间"
        case .consumption:return "消耗速度与预计可用时间"
        case .summary:return "运行中与今日结束统计"
        case .tasks:return "最近任务"
        case .trend:return "额度趋势"
        }
    }
    var requiresQuota:Bool {self == .reset || self == .consumption}
}

struct SidebarContent:Equatable {
    var sections:Set<SidebarSection>=[.quota,.reset,.tasks]
    var taskLimit=3
    init(_ values:[String:Any]=[:]) {
        for section in SidebarSection.allCases {
            if let enabled=values[section.key] as? Bool {
                if enabled {sections.insert(section)} else {sections.remove(section)}
            }
        }
        if let count=values["sidebarTaskLimit"] as? Int {taskLimit=max(1,min(8,count))}
    }
    func shows(_ section:SidebarSection)->Bool {
        sections.contains(section) && (!section.requiresQuota || sections.contains(.quota))
    }
    var hasQuotaPage:Bool {shows(.quota) || shows(.trend)}
    var showsTabs:Bool {hasQuotaPage && shows(.tasks)}
    var hasBody:Bool {hasQuotaPage || shows(.tasks)}
    func preferredHeight(quotaCount:Int,taskCount:Int)->CGFloat {
        var height=132
        if shows(.summary) {height += 82}
        if showsTabs {height += 38}
        if shows(.quota) {height += 126+max(1,min(3,quotaCount))*(50+(shows(.reset) ? 22:0)+(shows(.consumption) ? 36:0))}
        if shows(.tasks) {height += 28+max(1,min(taskLimit,taskCount))*68}
        if shows(.trend) {height += 90}
        return CGFloat(max(200,min(570,height)))
    }
}

struct DesktopQuotaValue {
    let remaining:Double?
    init(remaining:Double?,fresh:Bool) {
        if fresh,let remaining,remaining.isFinite {self.remaining=max(0,min(100,remaining))}
        else {self.remaining=nil}
    }
    var number:String {remaining.map{String(format:"%.0f",$0)} ?? "—"}
    var fraction:Double {(remaining ?? 0)/100}
    var summary:String {remaining.map{String(format:"剩余 %.0f%%",$0)} ?? "额度待更新"}
}

struct DesktopDisplay:Identifiable,Equatable {
    let id:String
    let name:String
    let frame:CGRect
}
struct DesktopDockTarget:Equatable {
    let screenID:String
    let side:SidebarSide
    let position:Double
}
enum DesktopDocking {
    static let edgeBand:CGFloat=32
    static func target(at point:CGPoint,displays:[DesktopDisplay])->DesktopDockTarget? {
        guard let display=displays.first(where:{$0.frame.contains(point)}) else{return nil}
        let left=point.x-display.frame.minX,right=display.frame.maxX-point.x
        guard min(left,right)<=edgeBand else{return nil}
        return DesktopDockTarget(screenID:display.id,side:left<=right ? .left:.right,position:SidebarGeometry.position(centerY:point.y,in:display.frame))
    }
    static func target(for frame:CGRect,displays:[DesktopDisplay])->DesktopDockTarget? {
        let center=CGPoint(x:frame.midX,y:frame.midY)
        guard let display=displays.first(where:{$0.frame.contains(center)}) else{return nil}
        let nearLeft=frame.minX<=display.frame.minX+edgeBand,nearRight=frame.maxX>=display.frame.maxX-edgeBand
        guard nearLeft || nearRight else{return nil}
        let side:SidebarSide=nearLeft && (!nearRight || center.x-display.frame.minX<=display.frame.maxX-center.x) ? .left:.right
        return DesktopDockTarget(screenID:display.id,side:side,position:SidebarGeometry.position(centerY:center.y,in:display.frame))
    }
}

enum SidebarSide:String,CaseIterable,Identifiable {
    case left,right
    var id:String {rawValue}
    var title:String {self == .left ? "屏幕左侧":"屏幕右侧"}
}

enum SidebarStyle:String,CaseIterable,Identifiable {
    case glass,solid
    var id:String {rawValue}
    var title:String {self == .glass ? "液态玻璃":"实色"}
}

enum DesktopPalette {
    static func normalized(_ value:Any?)->String? {
        guard let raw=value as? String else {return nil}
        let text=raw.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        guard text.count==7,text.first=="#",text.dropFirst().allSatisfy({$0.isHexDigit}) else {return nil}
        return text
    }
}

enum SidebarDetailSizing {
    static let widthRange:ClosedRange<Double>=300...960
    static let heightRange:ClosedRange<Double>=200...1200
    static func normalized(_ value:Double?,in range:ClosedRange<Double>)->Double? {
        guard let value,value.isFinite else{return nil}
        return max(range.lowerBound,min(range.upperBound,value.rounded()))
    }
}

struct SidebarResizeSession {
    let original:CGRect
    let anchor:CGPoint
    let horizontal:Int
    let vertical:Int
    init?(frame:CGRect,point:CGPoint) {
        let local=CGPoint(x:point.x-frame.minX,y:point.y-frame.minY)
        guard CGRect(origin:.zero,size:frame.size).contains(local) else{return nil}
        horizontal=local.x<8 ? -1:local.x>frame.width-8 ? 1:0
        vertical=local.y<8 ? -1:local.y>frame.height-8 ? 1:0
        guard horizontal != 0 || vertical != 0 else{return nil}
        original=frame;anchor=point
    }
    func frame(at point:CGPoint,in display:CGRect)->CGRect {
        let bounds=display.insetBy(dx:8,dy:8)
        var result=original
        if horizontal != 0 {
            let available=horizontal<0 ? original.maxX-bounds.minX:bounds.maxX-original.minX
            let maximum=max(1,min(CGFloat(SidebarDetailSizing.widthRange.upperBound),available))
            result.size.width=max(min(300,maximum),min(maximum,original.width+CGFloat(horizontal)*(point.x-anchor.x)))
            if horizontal<0 {result.origin.x=original.maxX-result.width}
        }
        if vertical != 0 {
            let available=vertical<0 ? original.maxY-bounds.minY:bounds.maxY-original.minY
            let maximum=max(1,min(CGFloat(SidebarDetailSizing.heightRange.upperBound),available))
            result.size.height=max(min(200,maximum),min(maximum,original.height+CGFloat(vertical)*(point.y-anchor.y)))
            if vertical<0 {result.origin.y=original.maxY-result.height}
        }
        return result
    }
}

struct DesktopPreferences:Equatable {
    var glassTransparency=0.98
    var glassPreset:GlassPreset = .crystal
    var glassMaterial:GlassMaterial = .clear
    var positionPreset:DesktopPositionPreset = .custom
    var placementScreenID=""
    var stickyPositionX=0.5
    var stickyPositionY=0.5
    var outerRingColor:String?=nil
    var innerRingColor:String?=nil
    var ringCenter:RingCenterContent = .credit
    var stickySize:StickySize = .standard
    var miniDiameter=MiniRingSizing.defaultDiameter
    var miniClickAction:MiniRingClickAction = .none
    var stickyContentSize:CGSize {stickySize == .mini ? CGSize(width:miniDiameter,height:miniDiameter):stickySize.contentSize}
    var sidebarDetailWidth:Double?=nil
    var sidebarDetailHeight:Double?=nil
    var sidebarEnabled=false
    var sidebarSide:SidebarSide = .right
    var sidebarAutoHide=true
    var sidebarPosition=0.5
    var sidebarScreenID=""
    var sidebarStyle:SidebarStyle = .glass
    var sidebarBadge:SidebarBadge = .waveform
    var sidebarContent=SidebarContent()
    init(_ values:[String:Any]=[:]) {
        let hasCustom=values["glassTransparency"] != nil || values["outerRingColor"] != nil || values["innerRingColor"] != nil
        glassPreset=GlassPreset(rawValue:values["glassPreset"] as? String ?? "") ?? (hasCustom ? .custom:.crystal)
        let presetDefaults=glassPreset.configuration
        glassTransparency=presetDefaults["glassTransparency"] as? Double ?? 0.98
        glassMaterial=GlassMaterial(rawValue:values["glassMaterial"] as? String ?? presetDefaults["glassMaterial"] as? String ?? "clear") ?? .clear
        positionPreset=DesktopPositionPreset(rawValue:values["positionPreset"] as? String ?? "") ?? .custom
        placementScreenID=values["placementScreenID"] as? String ?? ""
        if let x=values["stickyPositionX"] as? Double,x.isFinite {stickyPositionX=max(0,min(1,x))}
        if let y=values["stickyPositionY"] as? Double,y.isFinite {stickyPositionY=max(0,min(1,y))}
        if let value=values["glassTransparency"] as? Double,value.isFinite {glassTransparency=max(0,min(1,value))}
        outerRingColor=DesktopPalette.normalized(values["outerRingColor"])
        innerRingColor=DesktopPalette.normalized(values["innerRingColor"])
        ringCenter=RingCenterContent(rawValue:values["ringCenter"] as? String ?? "") ?? .credit
        stickySize=StickySize(rawValue:values["stickySize"] as? String ?? "") ?? .standard
        if let value=values["miniDiameter"] as? Double {miniDiameter=MiniRingSizing.normalized(value)}
        miniClickAction=MiniRingClickAction(rawValue:values["miniClickAction"] as? String ?? "") ?? .none
        sidebarDetailWidth=SidebarDetailSizing.normalized(values["sidebarDetailWidth"] as? Double,in:SidebarDetailSizing.widthRange)
        sidebarDetailHeight=SidebarDetailSizing.normalized(values["sidebarDetailHeight"] as? Double,in:SidebarDetailSizing.heightRange)
        sidebarEnabled=values["sidebarEnabled"] as? Bool ?? false
        sidebarSide=SidebarSide(rawValue:values["sidebarSide"] as? String ?? "") ?? .right
        sidebarAutoHide=values["sidebarAutoHide"] as? Bool ?? true
        if let position=values["sidebarPosition"] as? Double,position.isFinite {sidebarPosition=max(0,min(1,position))}
        sidebarScreenID=values["sidebarScreenID"] as? String ?? ""
        sidebarStyle=SidebarStyle(rawValue:values["sidebarStyle"] as? String ?? "") ?? .glass
        sidebarBadge=SidebarBadge(rawValue:values["sidebarBadge"] as? String ?? "") ?? .waveform
        sidebarContent=SidebarContent(values)
    }
}

enum SidebarGeometry {
    static func handle(in screen:CGRect,side:SidebarSide,position:Double,tucked:Bool)->CGRect {
        let height=min(48,screen.height),width=min(tucked ? 12:48,screen.width)
        let inset:CGFloat=tucked ? 0:6
        let fraction=position.isFinite ? max(0,min(1,position)):0.5
        let y=screen.minY+CGFloat(fraction)*max(0,screen.height-height)
        let x=side == .left ? screen.minX+inset:screen.maxX-width-inset
        return CGRect(x:max(screen.minX,min(x,screen.maxX-width)),y:y,width:width,height:height)
    }
    static func detail(in screen:CGRect,handle:CGRect,side:SidebarSide,preferredHeight:CGFloat=570,preferredWidth:CGFloat=376)->CGRect {
        let width=min(max(300,preferredWidth),max(1,screen.width-16)),height=min(max(200,preferredHeight),max(1,screen.height-16))
        let proposedX=side == .left ? handle.maxX+10:handle.minX-width-10
        return CGRect(x:max(screen.minX+8,min(proposedX,screen.maxX-width-8)),
                      y:max(screen.minY+8,min(handle.midY-height/2,screen.maxY-height-8)),width:width,height:height)
    }
    static func position(centerY:CGFloat,in screen:CGRect)->Double {
        let travel=max(1,screen.height-min(48,screen.height))
        return max(0,min(1,Double((centerY-screen.minY-24)/travel)))
    }
}

struct SidebarInteraction:Equatable {
    private(set) var autoHide=true
    private(set) var pointerInside=false
    private(set) var expanded=false
    private(set) var tucked=false
    mutating func hover(_ inside:Bool) {pointerInside=inside;if inside {tucked=false}}
    mutating func toggleDetails() {expanded.toggle();tucked=false}
    mutating func dismiss() {expanded=false}
    mutating func setAutoHide(_ value:Bool) {autoHide=value;if !value {tucked=false}}
    mutating func hideIfIdle() {if autoHide && !pointerInside && !expanded {tucked=true}}
    mutating func reset() {pointerInside=false;expanded=false;tucked=false}
}
