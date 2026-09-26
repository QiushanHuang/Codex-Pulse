import Foundation
import CoreGraphics

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
        case .standard:return CGSize(width:344,height:344)
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
        if shows(.quota) {height += max(1,min(3,quotaCount))*(50+(shows(.reset) ? 22:0)+(shows(.consumption) ? 36:0))}
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

enum SidebarSide:String,CaseIterable,Identifiable {
    case left,right
    var id:String {rawValue}
    var title:String {self == .left ? "屏幕左侧":"屏幕右侧"}
}

enum SidebarStyle:String,CaseIterable,Identifiable {
    case glass,solid
    var id:String {rawValue}
    var title:String {self == .glass ? "毛玻璃":"实色"}
}

struct DesktopPreferences:Equatable {
    var stickySize:StickySize = .standard
    var miniDiameter=MiniRingSizing.defaultDiameter
    var miniClickAction:MiniRingClickAction = .none
    var stickyContentSize:CGSize {stickySize == .mini ? CGSize(width:miniDiameter,height:miniDiameter):stickySize.contentSize}
    var sidebarEnabled=false
    var sidebarSide:SidebarSide = .right
    var sidebarAutoHide=true
    var sidebarPosition=0.5
    var sidebarScreenID=""
    var sidebarStyle:SidebarStyle = .glass
    var sidebarBadge:SidebarBadge = .waveform
    var sidebarContent=SidebarContent()
    init(_ values:[String:Any]=[:]) {
        stickySize=StickySize(rawValue:values["stickySize"] as? String ?? "") ?? .standard
        if let value=values["miniDiameter"] as? Double {miniDiameter=MiniRingSizing.normalized(value)}
        miniClickAction=MiniRingClickAction(rawValue:values["miniClickAction"] as? String ?? "") ?? .none
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
    static func detail(in screen:CGRect,handle:CGRect,side:SidebarSide,preferredHeight:CGFloat=570)->CGRect {
        let width=min(376,max(1,screen.width-16)),height=min(max(200,preferredHeight),max(1,screen.height-16))
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
