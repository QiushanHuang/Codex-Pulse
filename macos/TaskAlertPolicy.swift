import Foundation

enum NotificationDelivery:String,CaseIterable,Identifiable {
    case cards,system,both,off
    var id:String {rawValue}
    var label:String {
        switch self {
        case .cards:return "Pulse 卡片"
        case .system:return "macOS 通知"
        case .both:return "同时显示"
        case .off:return "关闭"
        }
    }
    var detail:String {
        switch self {
        case .cards:return "Pulse 卡片会从屏幕侧边滑入，点击可打开对应任务。"
        case .system:return "macOS 显示系统横幅，并将提醒保存在通知中心。"
        case .both:return "同时显示 macOS 系统通知和 Pulse 侧边卡片。"
        case .off:return "关闭弹出提醒和提示音，任务状态仍会显示在任务列表中。"
        }
    }
}

enum ReminderSound:String,CaseIterable,Identifiable,Codable {
    case silent, glass="Glass", hero="Hero", ping="Ping", morse="Morse", basso="Basso", sosumi="Sosumi"
    case tink="Tink", pop="Pop", purr="Purr", submarine="Submarine", bottle="Bottle", blow="Blow", frog="Frog", funk="Funk"
    var id:String {rawValue}
    var label:String {
        switch self {
        case .silent:return "静音"
        case .glass:return "清脆 · Glass"
        case .hero:return "凯旋 · Hero"
        case .ping:return "叮咚 · Ping"
        case .morse:return "电报码 · Morse"
        case .basso:return "低鸣 · Basso"
        case .sosumi:return "警示 · Sosumi"
        case .tink:return "轻铃 · Tink"
        case .pop:return "气泡 · Pop"
        case .purr:return "轻颤 · Purr"
        case .submarine:return "声呐 · Submarine"
        case .bottle:return "瓶音 · Bottle"
        case .blow:return "吹奏 · Blow"
        case .frog:return "蛙鸣 · Frog"
        case .funk:return "节拍 · Funk"
        }
    }
    var path:String? {self == .silent ? nil:"/System/Library/Sounds/\(rawValue).aiff"}
}

enum ReminderEvent:String,CaseIterable,Identifiable {
    case completed, waitingInput="waiting_input", waitingApproval="waiting_approval", failed, interrupted, reset
    var id:String {rawValue}
    var label:String {
        switch self {
        case .completed:return "轮次完成"
        case .waitingInput:return "需要回答"
        case .waitingApproval:return "等待审批"
        case .failed:return "任务失败"
        case .interrupted:return "任务中断"
        case .reset:return "额度重置"
        }
    }
    var defaultSound:ReminderSound {
        switch self {
        case .completed:return .glass
        case .waitingInput:return .ping
        case .waitingApproval:return .morse
        case .failed:return .basso
        case .interrupted:return .sosumi
        case .reset:return .hero
        }
    }
    var priority:Int {
        switch self {
        case .failed:return 6
        case .waitingApproval:return 5
        case .waitingInput:return 4
        case .interrupted:return 3
        case .reset:return 2
        case .completed:return 1
        }
    }
}

struct NotificationPreferences:Codable,Equatable {
    var systemEnabled=true
    var cardsEnabled=true
    var soundEnabled=false
    var soundSelections:[String:String]=[:]
    init(_ values:[String:Any]=[:]) {
        systemEnabled=values["systemEnabled"] as? Bool ?? true
        cardsEnabled=values["cardsEnabled"] as? Bool ?? true
        soundEnabled=values["soundEnabled"] as? Bool ?? false
        let selections=values["soundSelections"] as? [String:String] ?? [:]
        for event in ReminderEvent.allCases {
            soundSelections[event.rawValue]=(selections[event.rawValue].flatMap(ReminderSound.init(rawValue:)) ?? event.defaultSound).rawValue
        }
    }
    init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        self.init(["systemEnabled":try values.decodeIfPresent(Bool.self,forKey:.systemEnabled) ?? true,
                   "cardsEnabled":try values.decodeIfPresent(Bool.self,forKey:.cardsEnabled) ?? true,
                   "soundEnabled":try values.decodeIfPresent(Bool.self,forKey:.soundEnabled) ?? false,
                   "soundSelections":try values.decodeIfPresent([String:String].self,forKey:.soundSelections) ?? [:]])
    }
    func sound(for event:ReminderEvent)->ReminderSound {
        soundSelections[event.rawValue].flatMap(ReminderSound.init(rawValue:)) ?? event.defaultSound
    }
    func soundCandidate(in alerts:[TaskAlert])->ReminderSound? {
        guard soundForReminders else{return nil}
        return alerts.compactMap {alert -> ReminderEvent? in
            guard let event=ReminderEvent(rawValue:alert.kind),sound(for:event) != .silent else{return nil}
            return event
        }.max(by:{$0.priority<$1.priority}).map {sound(for:$0)}
    }
    var delivery:NotificationDelivery {
        get {systemEnabled ? (cardsEnabled ? .both:.system):(cardsEnabled ? .cards:.off)}
        set {systemEnabled=newValue == .system || newValue == .both;cardsEnabled=newValue == .cards || newValue == .both}
    }
    var soundForReminders:Bool {soundEnabled && delivery != .off}
    var dictionary:[String:Any] {["systemEnabled":systemEnabled,"cardsEnabled":cardsEnabled,"soundEnabled":soundEnabled,"soundSelections":soundSelections]}
}
struct TaskAlert:Equatable,Identifiable {
    let id:String
    let taskID:String
    let kind:String
    let at:Double
    let title:String
    var heading:String {
        ["completed":"轮次已完成","waiting_approval":"需要你授权","waiting_input":"需要你回答",
         "failed":"任务失败","interrupted":"任务已中断","reset":"额度已重置"][kind] ?? "任务状态更新"
    }
    var detail:String {kind=="reset" ? "服务端已确认额度重置":kind=="completed" ? "点击查看结果 · 轮次结束不代表目标已验收":"点击打开任务并处理"}
    var symbol:String {
        kind=="reset" ? "arrow.clockwise.circle.fill":kind=="completed" ? "checkmark.circle.fill":kind=="waiting_approval" ? "lock.shield.fill":
        kind=="waiting_input" ? "bubble.left.and.bubble.right.fill":"exclamationmark.circle.fill"
    }
    func resolved(taskStatus:String?)->Bool {!taskID.isEmpty && kind.hasPrefix("waiting_") && taskStatus != kind}
}
struct TaskAlertPolicy {
    private var initialized=false
    private var seen:[String]=[]
    mutating func consume(_ alerts:[TaskAlert],now:Double)->[TaskAlert] {
        let prior=Set(seen)
        let fresh=alerts.filter {
            let waiting=$0.kind.hasPrefix("waiting_")
            return (initialized || waiting) && !prior.contains($0.id) && $0.at.isFinite && 0<=now-$0.at && now-$0.at<(waiting ? 86400:120)
        }
        initialized=true
        seen=Array((seen+alerts.map(\.id).filter{!prior.contains($0)}).suffix(256))
        return fresh
    }
}

struct TaskSoundPolicy {
    private var lastPlayed:TimeInterval?
    mutating func consume(enabled:Bool,at:TimeInterval)->Bool {
        guard enabled,at.isFinite,lastPlayed.map({at-$0>=0.8}) ?? true else{return false}
        lastPlayed=at;return true
    }
}
