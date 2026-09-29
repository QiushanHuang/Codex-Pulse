import Foundation
import SwiftUI

struct UsageDay:Codable {let date:String;let tokens:Int}
struct AccountUsage:Codable {let days:[UsageDay];let lifetimeTokens:Int?}
struct UsagePeriodRow:Identifiable {
    let id:String
    let label:String
    let tokens:Int?
    let reportedDays:Int
    let expectedDays:Int
    var formattedTokens:String {tokens.map{PulseUsageFormat.compact(Double($0))} ?? "—"}
}
enum UsagePeriod:String,CaseIterable,Identifiable {
    case daily,weekly
    var id:String {rawValue}
    var title:String {self == .daily ? "每天":"每周"}
    func rows(usage:AccountUsage?,now:Date=Date(),calendar input:Calendar = .current)->[UsagePeriodRow] {
        var calendar=Calendar(identifier:.iso8601)
        calendar.timeZone=input.timeZone;calendar.firstWeekday=2;calendar.minimumDaysInFirstWeek=4
        let format=DateFormatter();format.calendar=calendar;format.locale=Locale(identifier:"en_US_POSIX")
        format.timeZone=calendar.timeZone;format.dateFormat="yyyy-MM-dd";format.isLenient=false
        let today=calendar.startOfDay(for:now)
        let parsed=(usage?.days ?? []).compactMap {day -> (Date,Int)? in
            guard day.tokens>=0,let date=format.date(from:day.date),format.string(from:date)==day.date else {return nil}
            return (date,day.tokens)
        }
        let start=self == .daily ? today:calendar.dateInterval(of:.weekOfYear,for:today)!.start
        return (0..<(self == .daily ? 14:8)).map {offset in
            let lower=calendar.date(byAdding:.day,value:-(self == .daily ? offset:offset*7),to:start)!
            let upper=min(today,calendar.date(byAdding:.day,value:self == .daily ? 0:6,to:lower)!)
            let entries=parsed.filter{$0.0>=lower && $0.0<=upper}
            var total=0,overflow=false
            var seen=Set<Date>()
            for (date,tokens) in entries {
                if !seen.insert(date).inserted {overflow=true;continue}
                let sum=total.addingReportingOverflow(tokens);overflow = overflow || sum.overflow;total=sum.partialValue
            }
            let key=format.string(from:lower)
            let label=self == .daily ? String(key.suffix(5)) : "\(key.suffix(5))–\(format.string(from:upper).suffix(5))"
            return UsagePeriodRow(id:key,label:label,tokens:entries.isEmpty || overflow ? nil:total,
                                  reportedDays:seen.count,expectedDays:calendar.dateComponents([.day],from:lower,to:upper).day!+1)
        }
    }
}

struct AccountUsageSummary:View {
    let snapshot:PulseSnapshot
    var compact=false
    private var today:UsagePeriodRow {UsagePeriod.daily.rows(usage:snapshot.usage)[0]}
    private var week:UsagePeriodRow {UsagePeriod.weekly.rows(usage:snapshot.usage)[0]}
    var body:some View {
        HStack(spacing:compact ? 12:24) {
            metric("今日 Token",row:today)
            Divider()
            metric("本周 Token",row:week)
        }.fixedSize(horizontal:false,vertical:true)
            .opacity(snapshot.usageStale ? 0.65:1)
            .help("账号用量来自服务每日记录，本周从周一开始；未返回日期不填零。\(snapshot.usageStale ? "当前为历史采样。":"")")
    }
    private func metric(_ title:String,row:UsagePeriodRow)->some View {
        VStack(alignment:.leading,spacing:compact ? 3:6) {
            Text(title).font(.system(size:compact ? 10:12)).foregroundStyle(.secondary)
            Text(row.formattedTokens).font(.system(size:compact ? 17:28,weight:.semibold,design:.rounded)).monospacedDigit()
            if !compact {Text("已报告 \(row.reportedDays)/\(row.expectedDays) 天").font(.caption).foregroundStyle(.secondary)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct AccountUsageHistory:View {
    let snapshot:PulseSnapshot
    @State private var period:UsagePeriod = .daily
    private var rows:[UsagePeriodRow] {period.rows(usage:snapshot.usage)}
    private var maximum:Double {max(1,Double(rows.compactMap(\.tokens).max() ?? 0))}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Label("用量统计",systemImage:"chart.bar.xaxis").font(.headline)
                Spacer()
                Picker("统计周期",selection:$period) {
                    ForEach(UsagePeriod.allCases) {Text($0.title).tag($0)}
                }.pickerStyle(.segmented).frame(width:180)
            }
            AccountUsageSummary(snapshot:snapshot)
            if let error=snapshot.usageError {Text(error).font(.caption).foregroundStyle(.orange)}
            else if snapshot.usageStale {Text("用量待更新 · 下方为最近采样").font(.caption).foregroundStyle(.orange)}
            ForEach(rows) {row in
                HStack(spacing:14) {
                    Text(row.label).font(.system(size:12)).monospacedDigit().frame(width:period == .daily ? 46:100,alignment:.leading)
                    GeometryReader {proxy in
                        Capsule().fill(Color.primary.opacity(0.06))
                        if let tokens=row.tokens {
                            Capsule().fill(pulseMint.opacity(snapshot.usageStale ? 0.4:0.85))
                                .frame(width:proxy.size.width*Double(tokens)/maximum)
                        }
                    }.frame(height:7).accessibilityHidden(true)
                    VStack(alignment:.trailing,spacing:2) {
                        Text(row.formattedTokens).font(.system(size:12,weight:.medium)).monospacedDigit()
                        if period == .weekly && row.reportedDays<row.expectedDays {
                            Text("\(row.reportedDays)/\(row.expectedDays) 天").font(.system(size:9)).foregroundStyle(.secondary)
                        }
                    }.frame(width:78,alignment:.trailing)
                }.frame(minHeight:24)
                    .help(row.tokens.map{"\(row.id) · \($0.formatted()) tokens"} ?? "该日期暂无服务记录")
            }
            HStack {
                Text("账号级 Token · 服务每日记录 · 每 5 分钟刷新")
                Spacer()
                if let at=snapshot.usageAt,at>0 {Text(Date(timeIntervalSince1970:at),style:.time)}
            }.font(.caption).foregroundStyle(.secondary)
            Text("日期保留服务口径；周一至周日汇总，当前周截至今天。未报告日期显示 —，周合计只包含已报告天数。Token 不是 Credit，也不是套餐剩余额度。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(20).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:16))
    }
}
