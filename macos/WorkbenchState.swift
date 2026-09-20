import SwiftUI
import Foundation

enum WorkbenchRoute: String, CaseIterable, Identifiable {
    case overview, tasks, quota, devices, rules, studio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "总览"
        case .tasks: return "任务"
        case .quota: return "额度与趋势"
        case .devices: return "设备"
        case .rules: return "联动规则"
        case .studio: return "灯效工作室"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "house"
        case .tasks: return "list.bullet.rectangle"
        case .quota: return "chart.xyaxis.line"
        case .devices: return "keyboard"
        case .rules: return "link"
        case .studio: return "lightbulb"
        }
    }
}

enum PulseAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "跟随系统" : self == .light ? "浅色" : "深色" }
    var symbol: String { self == .system ? "desktopcomputer" : self == .light ? "sun.max" : "moon" }
    var preferredScheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

enum TaskStatusFilter: String, CaseIterable, Identifiable {
    case all, active, attention, completed
    var id: String { rawValue }
    var title: String { self == .all ? "全部" : self == .active ? "运行中" : self == .attention ? "需要关注" : "轮次结束" }
}

enum WorkbenchTasks {
    static func filtered(_ tasks: [PulseTask], query: String = "", filter: TaskStatusFilter = .all) -> [PulseTask] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func priority(_ task: PulseTask) -> Int { task.status == "active" ? 0 : task.status == "completed" ? 2 : 1 }
        return tasks.filter { task in
            let matchesQuery = needle.isEmpty || task.title.localizedCaseInsensitiveContains(needle) || task.id.localizedCaseInsensitiveContains(needle)
            let matchesStatus: Bool
            switch filter {
            case .all: matchesStatus = true
            case .active: matchesStatus = task.status == "active"
            case .attention: matchesStatus = task.status != "active" && task.status != "completed"
            case .completed: matchesStatus = task.status == "completed"
            }
            return matchesQuery && matchesStatus
        }.sorted { lhs, rhs in
            if priority(lhs) != priority(rhs) { return priority(lhs) < priority(rhs) }
            if lhs.at != rhs.at { return lhs.at > rhs.at }
            return lhs.id < rhs.id
        }
    }
    static func taskURL(for task: PulseTask) -> URL? {
        guard task.id.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil,
              UUID(uuidString: task.id) != nil else { return nil }
        return URL(string: "codex://threads/\(task.id)")
    }
}

struct KeyboardDevice: Codable, Identifiable, Equatable {
    let id: String
    let key: String
    let name: String
    let model: String
    let provider: String
    let connection: String
    let state: String
    let support: String
    let reason: String
    let selectable: Bool
    let layoutId: String?
    let capabilities: [String]
    var isVerified: Bool { support == "verified" }
    var supportLabel: String { isVerified ? "已验证支持" : support == "unverified" ? "尚未验证" : "不支持" }
}

struct DeviceInventory: Codable, Equatable {
    var at: Double
    var status: String
    var message: String
    var devices: [KeyboardDevice]
    var selectedKey: String?
    var activeKey: String?
    static let empty = DeviceInventory(at: 0, status: "unavailable", message: "尚未发现设备", devices: [], selectedKey: nil, activeKey: nil)
    func isStale(now: Double = Date().timeIntervalSince1970) -> Bool {
        !at.isFinite || at <= 0 || now < at || now - at > 30
    }
}
