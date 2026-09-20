import Foundation
struct InputMonitorState {
    static func status(requested:Bool,preflight:Bool,tapActive:Bool)->String {
        if !requested{return "全局按键交互未开启"}
        if tapActive{return "普通按键交互已开启"}
        return preflight ? "输入监听创建失败":"系统未允许创建按键监听，请重新确认输入监控权限"
    }
}

struct InputAssessment {
    let code: String
    let title: String
    let guidance: String
    let needsPermission: Bool
}
extension InputMonitorState {
    static func assess(requested:Bool,preflight:Bool,tapActive:Bool,continuity:String)->InputAssessment {
        if !requested { return InputAssessment(code:"disabled",title:"按键交互未运行 · 授权未实测",guidance:"启用灯光、交互预设和响应普通键盘输入后验证。",needsPermission:false) }
        if tapActive { return InputAssessment(code:"verified",title:"输入监控可用 · 监听已验证",guidance:"按普通按键后确认接收计数增加；安全输入模式可能暂时阻止事件。",needsPermission:false) }
        if preflight { return InputAssessment(code:"listener_failed",title:"权限预检通过 · 监听创建失败",guidance:"先点重新检查；仍失败时退出并重新打开本 app。此状态不能确定为授权失效。",needsPermission:false) }
        return InputAssessment(code:continuity == "changed" ? "signature_changed_denied":"permission_required",
            title:continuity == "changed" ? "签名已变化 · 输入监控未生效":"输入监控未获准",
            guidance:"在系统设置 → 隐私与安全性 → 输入监控中开启 Codex Pulse，再退出并重新打开。若已开启仍失败，移除列表中的旧条目，用 ＋ 添加下方当前 app，开启后重新打开。",needsPermission:true)
    }
}
