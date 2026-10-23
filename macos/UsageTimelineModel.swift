import Foundation

struct UsageTimelinePoint:Codable,Identifiable {
    let at:Double
    let value:Double
    var segment:Int=0
    var refill:Double?=nil
    var perMinute:Double?=nil
    var id:String {"\(at):\(segment)"}
    var date:Date {Date(timeIntervalSince1970:at)}
}
struct UsageQuotaSeries:Codable,Identifiable {
    let id:String
    let label:String
    let points:[UsageTimelinePoint]
}
struct UsageCreditSummary:Codable {
    let decreased:Double?
    let increased:Double?
    let perHour:Double?
    let gaps:Int
}
struct UsageTaskSummary:Codable,Identifiable {
    let id:String
    let title:String
    let tokens:Double?
    let perMinute:Double?
    let firstAt:Double
    let lastAt:Double
    let samples:Int
    let adjustments:Int
}
struct UsageHistoryReply:Codable {
    let start:Double
    let end:Double
    let generatedAt:Double
    let creditPoints:[UsageTimelinePoint]
    let creditChanges:[UsageTimelinePoint]
    let quotas:[UsageQuotaSeries]
    let tokenPoints:[UsageTimelinePoint]
    let tasks:[UsageTaskSummary]
    let credit:UsageCreditSummary
    let tokens:Double?
    let tokenPerMinute:Double?
    let tokenAdjustments:Int
    let bucketSeconds:Double
    let recordedFrom:Double?
    let accountRecordedFrom:Double?
    let taskRecordedFrom:Double?
}

struct UsageTimeWindow:Equatable {
    var start:Date
    var end:Date
    var duration:TimeInterval {end.timeIntervalSince(start)}
    var valid:Bool {start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && start.timeIntervalSince1970>=0 && duration>0}
    static func recent(_ seconds:Double,now:Date=Date())->Self {.init(start:now.addingTimeInterval(-seconds),end:now)}
    func zoom(_ factor:Double,ceiling:Date=Date())->Self {
        guard valid,factor.isFinite,factor>0 else{return self}
        let span=max(60,min(5*365*86400,duration*factor))
        let center=start.addingTimeInterval(duration/2)
        let upper=min(ceiling,center.addingTimeInterval(span/2))
        return .init(start:max(Date(timeIntervalSince1970:0),upper.addingTimeInterval(-span)),end:upper)
    }
    func shifted(_ fraction:Double,ceiling:Date=Date())->Self {
        guard valid,fraction.isFinite else{return self}
        let upper=min(ceiling,end.addingTimeInterval(duration*fraction))
        return .init(start:max(Date(timeIntervalSince1970:0),upper.addingTimeInterval(-duration)),end:upper)
    }
    func selection(_ a:Date,_ b:Date)->Self? {
        let lower=max(start,min(a,b)),upper=min(end,max(a,b))
        guard upper.timeIntervalSince(lower)>=10 else{return nil}
        return .init(start:lower,end:upper)
    }
}

enum UsageTimelineMetric:String,CaseIterable,Identifiable {
    case creditBalance,creditDrop,quota,tokens,tokenRate
    var id:String {rawValue}
    var title:String {
        switch self {
        case .creditBalance:return "Credit 余额"
        case .creditDrop:return "Credit 消耗"
        case .quota:return "套餐额度"
        case .tokens:return "Token 用量"
        case .tokenRate:return "Token 速度"
        }
    }
    var unit:String {
        switch self {
        case .creditBalance,.creditDrop:return "cr"
        case .quota:return "% 剩余"
        case .tokens:return "tokens"
        case .tokenRate:return "tokens/min"
        }
    }
    var bars:Bool {self == .creditDrop || self == .tokens || self == .tokenRate}
    func points(_ report:UsageHistoryReply?,quotaID:String)->[UsageTimelinePoint] {
        guard let report else{return []}
        switch self {
        case .creditBalance:return report.creditPoints
        case .creditDrop:return report.creditChanges.filter{$0.value>0}
        case .quota:return (report.quotas.first{$0.id==quotaID} ?? report.quotas.first)?.points ?? []
        case .tokens:return report.tokenPoints
        case .tokenRate:return report.tokenPoints.map{UsageTimelinePoint(at:$0.at,value:$0.perMinute ?? 0)}
        }
    }
}
