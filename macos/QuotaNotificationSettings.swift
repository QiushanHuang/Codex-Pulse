import SwiftUI
import Security
import Combine

struct QuotaNotificationPreferences:Codable,Equatable {
    var enabled=false, fiveHour=true, weekly=true, manual=true
    var channel="push", smtpHost="", smtpPort="465", smtpTLS="ssl", smtpUser="", sender="", recipient=""
    init(_ values:[String:Any]=[:]) {
        enabled=values["enabled"] as? Bool ?? false
        fiveHour=values["fiveHour"] as? Bool ?? true
        weekly=values["weekly"] as? Bool ?? true
        manual=values["manual"] as? Bool ?? true
        channel=values["channel"] as? String == "email" ? "email":"push"
        smtpHost=values["smtpHost"] as? String ?? ""
        smtpPort=values["smtpPort"] as? String ?? "465"
        smtpTLS=values["smtpTLS"] as? String == "starttls" ? "starttls":"ssl"
        smtpUser=values["smtpUser"] as? String ?? ""
        sender=values["sender"] as? String ?? ""
        recipient=values["recipient"] as? String ?? ""
    }
    var dictionary:[String:Any] {(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]}
    func validate(_ secret:[String:String]) throws {
        if channel == "push" {
            guard let value=secret["pushURL"],let url=URLComponents(string:value),url.scheme=="https",
                  let host=url.host,!host.isEmpty,url.user==nil,url.password==nil,url.query==nil,url.fragment==nil,
                  !url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")).isEmpty else {
                throw QuotaCredentialStore.Failure.message("请填写完整 HTTPS Bark 推送地址（含设备密钥）。")
            }
        } else {
            guard !smtpHost.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  let port=Int(smtpPort),(1...65535).contains(port),sender.contains("@"),recipient.contains("@"),
                  !sender.contains("\n"),!recipient.contains("\n"),!sender.contains("\r"),!recipient.contains("\r"),
                  !(secret["smtpPassword"] ?? "").isEmpty else {
                throw QuotaCredentialStore.Failure.message("请填写 SMTP 主机、有效端口、发件和收件邮箱及授权码。")
            }
        }
    }
}

enum QuotaCredentialStore {
    static let service="com.qiushan.codexpulse.remote-notifications"
    enum Failure:LocalizedError {
        case keychain(OSStatus), message(String)
        var errorDescription:String? {
            switch self {
            case .keychain(let code):return "无法访问通知钥匙串（\(code)），请检查权限后重试。"
            case .message(let value):return value
            }
        }
    }
    static var query:[String:Any] {[
        kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:service,kSecAttrAccount as String:"quota"
    ]}
    static func read() throws -> [String:String] {
        var request=query
        request[kSecReturnData as String]=true
        request[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        let code=SecItemCopyMatching(request as CFDictionary,&result)
        if code==errSecItemNotFound {return [:]}
        guard code==errSecSuccess else {throw Failure.keychain(code)}
        guard let data=result as? Data,let values=try JSONSerialization.jsonObject(with:data) as? [String:String] else {
            throw Failure.message("通知钥匙串数据无法读取。")
        }
        return values
    }
    static func write(_ values:[String:String]) throws {
        let data=try JSONSerialization.data(withJSONObject:values)
        let code=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if code==errSecItemNotFound {
            var request=query
            request[kSecValueData as String]=data
            request[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added=SecItemAdd(request as CFDictionary,nil)
            guard added==errSecSuccess else {throw Failure.keychain(added)}
        } else if code != errSecSuccess {throw Failure.keychain(code)}
    }
}

struct QuotaNotificationSettings:View {
    @ObservedObject var model:PulseModel
    @State private var preferences=QuotaNotificationPreferences()
    @State private var pushURL=""
    @State private var password=""
    @State private var notice:String?
    @State private var deliveryStatus=""
    @State private var busy=false
    @State private var testChild:Process?
    private let statusTimer=Timer.publish(every:5,on:.main,in:.common).autoconnect()
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("额度重置通知").font(.headline)
            Toggle("额度重置后通知手机",isOn:$preferences.enabled)
            Picker("接收方式",selection:$preferences.channel) {
                Text("手机推送 · Bark").tag("push")
                Text("邮件 · SMTP").tag("email")
            }.pickerStyle(.segmented)
            HStack {
                Toggle("5 小时自然重置",isOn:$preferences.fiveHour)
                Toggle("每周自然重置",isOn:$preferences.weekly)
            }
            Toggle("使用重置券后通知（含 Tibo 等外部入口）",isOn:$preferences.manual)
            Text("外部重置根据未到期券减少及额度提前恢复识别；仅额度回升不会通知。")
                .font(.caption).foregroundStyle(.secondary)
            if preferences.channel == "push" {
                SecureField("完整 HTTPS Bark 地址（含设备密钥）",text:$pushURL)
                Text("从 iPhone Bark App 复制完整推送地址，也可填自建服务地址。留空保留已保存地址。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("SMTP 主机",text:$preferences.smtpHost)
                HStack {
                    TextField("端口",text:$preferences.smtpPort).frame(width:100)
                    Picker("加密",selection:$preferences.smtpTLS) {
                        Text("SSL / TLS").tag("ssl");Text("STARTTLS").tag("starttls")
                    }.onChange(of:preferences.smtpTLS) {_,value in preferences.smtpPort=value=="ssl" ? "465":"587"}
                }
                TextField("登录用户名（留空使用发件邮箱）",text:$preferences.smtpUser)
                TextField("发件邮箱",text:$preferences.sender)
                TextField("收件邮箱",text:$preferences.recipient)
                SecureField("邮箱授权码 / 应用专用密码",text:$password)
                Text("授权码留空保留已保存值。请在手机邮件 App 中开启新邮件通知。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("保存设置") {save()}
                Button("保存并测试发送") {if save(testing:true) {test()}}
                if busy {ProgressView().controlSize(.small)}
            }.disabled(busy)
            if let notice {Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
            if !deliveryStatus.isEmpty {Text(deliveryStatus).font(.caption).foregroundStyle(.secondary)}
            Text("地址密钥和邮箱授权码存入 macOS 钥匙串。Mac 联网且 Pulse 监控运行时发送；首次开启不补发旧事件。测试会实际发送一条消息。")
                .font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder)
        .onAppear {preferences=model.quotaNotificationPreferences;refreshStatus()}
        .onReceive(statusTimer) {_ in refreshStatus()}
    }
    @discardableResult private func save(testing:Bool=false)->Bool {
        do {
            // Disabling must remain possible when credentials are inaccessible.
            if preferences.enabled || testing || !pushURL.isEmpty || !password.isEmpty {
                var secret=try QuotaCredentialStore.read()
                let url=pushURL.trimmingCharacters(in:.whitespacesAndNewlines)
                if !url.isEmpty {secret["pushURL"]=url}
                if !password.isEmpty {secret["smtpPassword"]=password}
                if preferences.enabled || testing {try preferences.validate(secret)}
                if !url.isEmpty || !password.isEmpty {try QuotaCredentialStore.write(secret)}
            }
            var values=preferences.dictionary
            values["revision"]=UUID().uuidString
            guard model.saveQuotaNotificationSettings(values) else {notice=model.configurationNotice;return false}
            pushURL="";password=""
            notice=preferences.enabled ? "已保存，等待下一次服务确认的额度重置。":"已保存，自动通知已关闭。"
            return true
        } catch {notice=error.localizedDescription;return false}
    }
    private func refreshStatus() {
        let file=PulsePaths.data.appendingPathComponent("remote-notification-status.json")
        guard let data=try? Data(contentsOf:file),let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              let message=value["message"] as? String else{return}
        let at=value["at"] as? Double ?? 0
        deliveryStatus="最近发送（\(Date(timeIntervalSince1970:at).formatted(date:.abbreviated,time:.shortened))）：\(message)"
    }
    private func test() {
        guard !busy,let resources=Bundle.main.resourceURL,
              let python=Bundle.main.infoDictionary?["PulsePython"] as? String else {notice="无法找到通知测试运行环境。";return}
        busy=true;notice="正在测试发送…首次访问通知钥匙串时，macOS 可能请求授权。"
        let child=Process(),output=Pipe()
        child.executableURL=PulseRuntimePaths.resolve(python,resources:resources)
        child.currentDirectoryURL=resources.appendingPathComponent("backend")
        child.arguments=["-B","-m","codex_pulse.remote_notifications","--data-dir",PulsePaths.data.path,"--test"]
        child.standardOutput=output;child.standardError=FileHandle.nullDevice
        child.terminationHandler={_ in
            let data=output.fileHandleForReading.readDataToEndOfFile()
            let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            let message=result?["message"] as? String ?? "测试未取得结果，请检查钥匙串权限和网络。"
            Task {@MainActor in busy=false;notice=message;testChild=nil}
        }
        testChild=child
        do {try child.run()} catch {busy=false;testChild=nil;notice="无法启动通知测试。"}
    }
}
