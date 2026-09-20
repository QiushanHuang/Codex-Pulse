import Foundation
import Security

struct InputSignature: Codable {
    let identifier: String
    let cdhash: String
    let requirement: String
    let team: String

    static func current() -> InputSignature? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue:kSecCSSigningInformation | kSecCSRequirementInformation), &info) == errSecSuccess,
              let values=info as? [String:Any],
              let hash=values[kSecCodeInfoUnique as String] as? Data,
              let identifier=values[kSecCodeInfoIdentifier as String] as? String,
              let requirement=values[kSecCodeInfoDesignatedRequirement as String] else { return nil }
        var description: CFString?
        guard SecRequirementCopyString(requirement as! SecRequirement, [], &description) == errSecSuccess,
              let description else { return nil }
        return InputSignature(identifier:identifier,cdhash:hash.map{String(format:"%02x",$0)}.joined(),requirement:description as String,team:values[kSecCodeInfoTeamIdentifier as String] as? String ?? "ad-hoc / 无 Team ID")
    }
    // Test the running code against the old DR. CDHash changes alone do not imply identity changes.
    static func continuity(with previous:InputSignature?) -> String {
        guard let previous, !previous.requirement.isEmpty else { return "unknown" }
        var requirement: SecRequirement?
        var code: SecCode?
        guard SecRequirementCreateWithString(previous.requirement as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unknown" }
        let result=SecCodeCheckValidity(code, [], requirement)
        if result == errSecSuccess { return "matches" }
        return result == errSecCSReqFailed ? "changed" : "unknown"
    }
}

struct InputAuthorizationBaseline: Codable {
    let signature: InputSignature
    let source: String
    let at: Double
    static func read(_ url:URL) -> InputAuthorizationBaseline? {
        guard let data=try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(Self.self,from:data)
    }
}
