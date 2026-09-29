import Foundation

@main struct PeriodUsageTests {
    static func main() throws {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=TimeZone(secondsFromGMT:8*3600)!
        let now=calendar.date(from:DateComponents(year:2026,month:9,day:29,hour:12))!
        let usage=AccountUsage(days:[UsageDay(date:"2026-09-27",tokens:500),UsageDay(date:"2026-09-28",tokens:100),UsageDay(date:"2026-09-29",tokens:0)],lifetimeTokens:nil)
        let days=UsagePeriod.daily.rows(usage:usage,now:now,calendar:calendar)
        precondition(days[0].tokens==0 && days[1].tokens==100 && days[3].tokens==nil)
        let weeks=UsagePeriod.weekly.rows(usage:usage,now:now,calendar:calendar)
        precondition(weeks[0].tokens==100 && weeks[0].reportedDays==2 && weeks[0].expectedDays==2)
        precondition(weeks[1].tokens==500 && weeks[1].reportedDays==1 && weeks[1].expectedDays==7)
        precondition(UsagePeriod.daily.rows(usage:nil,now:now,calendar:calendar)[0].tokens==nil)
        let newYear=calendar.date(from:DateComponents(year:2027,month:1,day:1,hour:12))!
        let crossing=AccountUsage(days:[UsageDay(date:"2026-12-28",tokens:20),UsageDay(date:"2027-01-01",tokens:30)],lifetimeTokens:nil)
        precondition(UsagePeriod.weekly.rows(usage:crossing,now:newYear,calendar:calendar)[0].tokens==50)
        let huge=AccountUsage(days:[UsageDay(date:"2026-09-28",tokens:Int.max),UsageDay(date:"2026-09-29",tokens:1)],lifetimeTokens:nil)
        precondition(UsagePeriod.weekly.rows(usage:huge,now:now,calendar:calendar)[0].tokens==nil)
        precondition(DesktopPreferences().ringCenter == .credit)
        precondition(DesktopPreferences(["ringCenter":"percentage"]).ringCenter == .percentage)
        precondition(DesktopPreferences(["ringCenter":"resetCredits"]).ringCenter == .resetCredits)
        precondition(DesktopPreferences(["ringCenter":"unknown"]).ringCenter == .credit)
        print("PASS: daily/week boundaries, zero vs missing, partial coverage, year boundary, overflow, ring preference")
    }
}
