import Foundation

@main struct UsageTimelineTests {
    static func main() throws {
        let now=Date(timeIntervalSince1970:100_000)
        let window=UsageTimeWindow.recent(3600,now:now)
        precondition(window.valid && window.duration==3600)
        let zoom=window.zoom(0.5,ceiling:now)
        precondition(zoom.duration==1800 && zoom.start>window.start && zoom.end<window.end)
        precondition(zoom.zoom(2,ceiling:now)==window)
        precondition(window.shifted(-0.5,ceiling:now).end==now.addingTimeInterval(-1800))
        precondition(window.shifted(1,ceiling:now)==window,"cannot pan beyond current time")
        precondition(window.zoom(.nan,ceiling:now)==window)
        let selected=window.selection(now.addingTimeInterval(-900),now.addingTimeInterval(-1800))!
        precondition(selected.duration==900)
        precondition(window.selection(now,now.addingTimeInterval(-1))==nil,"ignore accidental tiny drags")
        let invalid=UsageTimeWindow(start:now,end:now.addingTimeInterval(-1))
        precondition(!invalid.valid && invalid.zoom(2,ceiling:now)==invalid)
        let raw=Data(#"{"start":100,"end":1000,"generatedAt":1000,"creditPoints":[{"at":100,"value":0,"segment":0}],"creditChanges":[],"quotas":[],"tokenPoints":[{"at":160,"value":120,"perMinute":60,"segment":0}],"tasks":[{"id":"t","title":"Test","tokens":120,"perMinute":120,"firstAt":100,"lastAt":160,"samples":2,"adjustments":0}],"credit":{"decreased":0,"increased":null,"perHour":null,"gaps":0},"tokens":120,"tokenPerMinute":120,"tokenAdjustments":0,"bucketSeconds":120,"recordedFrom":100,"accountRecordedFrom":100,"taskRecordedFrom":100}"#.utf8)
        let report=try JSONDecoder().decode(UsageHistoryReply.self,from:raw)
        precondition(report.creditPoints.first?.value==0)
        precondition(report.credit.increased==nil)
        precondition(UsageTimelineMetric.creditBalance.points(report,quotaID:"").first?.value==0)
        precondition(UsageTimelineMetric.tokenRate.points(report,quotaID:"").first?.value==60)
        precondition(UsageTimelineMetric.quota.points(report,quotaID:"").isEmpty)
        precondition(UsageTimelineMetric.tokens.points(nil,quotaID:"").isEmpty)
        precondition(report.tasks.first?.perMinute==120)
        print("PASS: temporal zoom, pan, custom range, invalid selection, history decoding and units")
    }
}
