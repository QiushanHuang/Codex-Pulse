import Foundation
import Darwin
import CoreFoundation

struct PulseConfigurationStore {
    let directory:URL
    var file:URL {directory.appendingPathComponent("config.json")}
    enum Failure:LocalizedError {
        case invalid, newerVersion, lock
        var errorDescription:String? {
            switch self {
            case .invalid:return "设置文件无法读取，已保留原文件。请在诊断中检查后重试。"
            case .newerVersion:return "设置来自更新版本，当前版本不会覆盖它。"
            case .lock:return "暂时无法保存设置，请稍后重试。"
            }
        }
    }
    func read() throws -> [String:Any] {
        guard FileManager.default.fileExists(atPath:file.path) else {return [:]}
        guard let data=try? Data(contentsOf:file),let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {throw Failure.invalid}
        if let raw=value["schemaVersion"] {
            guard let number=raw as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue==Double(number.intValue),number.intValue>=1 else {throw Failure.invalid}
            if number.intValue>2 {throw Failure.newerVersion}
        }
        if let raw=value["windowSettings"] {
            guard let settings=raw as? [String:Any] else {throw Failure.invalid}
            if let pin=settings["stickyPinned"] {
                guard let number=pin as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID() else {throw Failure.invalid}
            }
        }
        if let profiles=value["deviceProfiles"],!(profiles is [String:Any]) {throw Failure.invalid}
        if let profiles=value["deviceProfiles"] as? [String:Any] {
            for (_,raw) in profiles {
                guard let profile=raw as? [String:Any] else {throw Failure.invalid}
                if let settings=profile["lightSettings"],!(settings is [String:Any]) {throw Failure.invalid}
            }
        }
        if let settings=value["lightSettings"],!(settings is [String:Any]) {throw Failure.invalid}
        if let selected=value["selectedDeviceKey"],!(selected is NSNull),!(selected is String) {throw Failure.invalid}
        return value
    }
    private func locked<T>(_ action:() throws -> T) throws ->T {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let fd=Darwin.open(directory.appendingPathComponent("config.lock").path,O_CREAT|O_RDWR,0o600)
        guard fd>=0 else {throw Failure.lock}
        defer {Darwin.close(fd)}
        guard flock(fd,LOCK_EX)==0 else {throw Failure.lock}
        defer {_=flock(fd,LOCK_UN)}
        return try action()
    }
    private func write(_ config:[String:Any]) throws {
        let data=try JSONSerialization.data(withJSONObject:config,options:[.sortedKeys])
        try data.write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    @discardableResult func update(_ change:(inout [String:Any])->Void) throws ->[String:Any] {
        try locked {
            var config=try read();change(&config);try write(config);return config
        }
    }
    @discardableResult func migrate(legacySignature:String?) throws ->[String:Any] {
        try locked {
            var config=try read()
            if config["schemaVersion"] as? Int == 2 {return config}
            if FileManager.default.fileExists(atPath:file.path) {
                let backup=directory.appendingPathComponent("config-before-v2-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at:file,to:backup)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:backup.path)
            }
            config["schemaVersion"]=2
            config["appearance"]=config["appearance"] as? String ?? "system"
            var profiles=config["deviceProfiles"] as? [String:Any] ?? [:]
            if let signature=legacySignature,!signature.isEmpty {
                let key="ghub:"+signature
                config["selectedDeviceKey"]=key
                profiles[key]=["lightSettings":config["lightSettings"] as? [String:Any] ?? [:]]
            }
            config["deviceProfiles"]=profiles
            try write(config);return config
        }
    }
    @discardableResult func saveStickyPinned(_ pinned:Bool) throws ->[String:Any] {
        try update {config in
            var preferences=config["windowSettings"] as? [String:Any] ?? [:]
            preferences["stickyPinned"]=pinned
            config["windowSettings"]=preferences
        }
    }
    @discardableResult func saveLightSettings(_ settings:[String:Any]) throws ->[String:Any] {
        try update {config in
            config["lightSettings"]=settings
            if let key=config["selectedDeviceKey"] as? String,!key.isEmpty {
                var profiles=config["deviceProfiles"] as? [String:Any] ?? [:]
                var profile=profiles[key] as? [String:Any] ?? [:]
                profile["lightSettings"]=settings;profiles[key]=profile;config["deviceProfiles"]=profiles
            }
        }
    }
    @discardableResult func selectDevice(_ key:String,defaults:[String:Any]) throws ->[String:Any] {
        try update {config in
            var profiles=config["deviceProfiles"] as? [String:Any] ?? [:]
            let previous=config["selectedDeviceKey"] as? String
            if let previous,!previous.isEmpty {
                var profile=profiles[previous] as? [String:Any] ?? [:]
                profile["lightSettings"]=config["lightSettings"] as? [String:Any] ?? [:];profiles[previous]=profile
            }
            var profile=profiles[key] as? [String:Any] ?? [:]
            let settings=profile["lightSettings"] as? [String:Any] ?? (previous == nil ? config["lightSettings"] as? [String:Any] ?? defaults:defaults)
            profile["lightSettings"]=settings;profiles[key]=profile
            config["deviceProfiles"]=profiles;config["selectedDeviceKey"]=key;config["lightSettings"]=settings
            config.removeValue(forKey:"preview")
        }
    }
}
