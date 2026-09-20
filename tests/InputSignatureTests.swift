import Foundation
@main struct InputSignatureTests {
    static func main() {
        guard let current=InputSignature.current() else { fatalError("Running signature must be readable") }
        precondition(!current.cdhash.isEmpty && !current.requirement.isEmpty)
        precondition(InputSignature.continuity(with:current) == "matches")
        let different=InputSignature(identifier:current.identifier,cdhash:"0000000000000000000000000000000000000000",requirement:"cdhash H\"0000000000000000000000000000000000000000\"",team:current.team)
        precondition(InputSignature.continuity(with:different) == "changed")
        precondition(InputSignature.continuity(with:nil) == "unknown")
        let malformed=InputSignature(identifier:"x",cdhash:"x",requirement:"not a requirement",team:"x")
        precondition(InputSignature.continuity(with:malformed) == "unknown")
        print("PASS: running signature, matching DR, changed DR, absent and malformed baseline")
    }
}
