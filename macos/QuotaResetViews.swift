import SwiftUI

struct QuotaResetCard:View {
    @ObservedObject var model:PulseModel
    @State private var confirming=false
    @State private var confirmedAccount=""
    @State private var requestID=""
    @State private var retrying=false
    @State private var confirmationSummary=""
    private var snapshot:PulseSnapshot {model.snapshot}
    private var quotaSummary:String {
        guard !snapshot.stale,!snapshot.mainWindows.isEmpty else{return "等待最新额度"}
        return snapshot.mainWindows.map{"\($0.label)剩余 \(String(format:"%.0f%%",$0.remaining))"}.joined(separator:" · ")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("余额与重置券").font(.headline)
                Spacer()
                Button {model.requestQuotaRefresh()} label: {Label("立即刷新",systemImage:"arrow.clockwise")}
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(!model.running || model.resetBusy || Date().timeIntervalSince1970-model.quotaRefreshRequestedAt<5)
            }
            HStack(alignment:.top,spacing:24) {
                VStack(alignment:.leading,spacing:7) {
                    Label("Credit 余额",systemImage:"circle.grid.2x2").font(.callout).foregroundStyle(.secondary)
                    Text(snapshot.credits?.display(fresh:!snapshot.stale) ?? "—")
                        .font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(pulseCredit)
                    Text("套餐外用量点数，按实际使用扣减").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Divider()
                VStack(alignment:.leading,spacing:7) {
                    Label("可用重置次数",systemImage:"arrow.counterclockwise").font(.callout).foregroundStyle(.secondary)
                    Text(snapshot.stale ? "—":snapshot.resetCredits.map{"\($0) 次"} ?? "—")
                        .font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(pulseMint)
                    Text("使用重置券，恢复符合条件的套餐窗口").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.fixedSize(horizontal:false,vertical:true)
            if let vouchers=snapshot.resetVouchers,!vouchers.isEmpty {
                VStack(alignment:.leading,spacing:7) {
                    Text("重置券有效期").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(vouchers.sorted{($0.expiresAt ?? .infinity)<($1.expiresAt ?? .infinity)}.prefix(5).enumerated()),id:\.element.id) {index,voucher in
                        HStack {
                            Text("重置券 \(index+1)")
                            Spacer()
                            if let expiry=voucher.expiresAt {
                                if expiry>Date().timeIntervalSince1970 {
                                    Text(Date(timeIntervalSince1970:expiry),format:.dateTime.month().day().hour().minute())
                                    Text("到期")
                                } else {Text("已到期 · 等待服务刷新").foregroundStyle(.orange)}
                            } else {Text("服务未提供有效期").foregroundStyle(.secondary)}
                        }.font(.caption)
                    }
                }
            } else if (snapshot.resetCredits ?? 0)>0 {
                Text("已取得可用次数，服务暂未提供重置券有效期。").font(.caption).foregroundStyle(.secondary)
            }
            Text("当前套餐："+quotaSummary).font(.callout).foregroundStyle(.secondary)
            HStack(spacing:12) {
                Button {
                    guard let key=snapshot.accountKey else{return}
                    confirmedAccount=key
                    confirmationSummary=quotaSummary
                    retrying=model.pendingResetID != nil
                    requestID=model.pendingResetID ?? UUID().uuidString.lowercased()
                    confirming=true
                } label: {
                    Label(model.resetBusy ? "正在处理…":model.pendingResetID != nil ? "重试同次操作":"使用 1 次重置机会",systemImage:"arrow.counterclockwise")
                }.buttonStyle(.borderedProminent).tint(pulseMint).disabled(!model.resetReady)
                if model.resetBusy {ProgressView().controlSize(.small)}
                Text("不会增加 Credit 余额").font(.caption).foregroundStyle(.secondary)
            }
            if let result=model.resetResult,result.accountKey==snapshot.accountKey {
                Text(result.message).font(.callout).foregroundStyle(result.succeeded ? pulseMint:result.uncertain ? Color.orange:.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            Text("重置以服务返回结果为准。超时后保留同一请求编号供确认，不会自动发起新的重置。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:16))
        .environment(\.locale,Locale(identifier:"zh_CN"))
        .alert(retrying ? "确认上一次重置结果？":"使用 1 次重置机会？",isPresented:$confirming) {
            Button("取消",role:.cancel) {}
            Button(retrying ? "确认同次重试":"确认重置",role:.destructive) {
                model.useQuotaReset(accountKey:confirmedAccount,requestID:requestID)
            }
        } message: {
            Text(retrying ? "上一次结果未确认。本次沿用相同请求编号，不会重复兑换已成功使用的重置券。":"\(confirmationSummary)。将使用当前账号的 1 次重置机会，由服务选择可用重置券并重置符合条件的套餐窗口。此操作不会增加 Credit 余额。")
        }
    }
}
