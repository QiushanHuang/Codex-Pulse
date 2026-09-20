import Foundation

@main struct ConfigurationTests {
 static func expect(_ value:Bool,_ message:String){precondition(value,message)}
 static func main() throws {
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:directory)}
  let file=directory.appendingPathComponent("config.json")
  let legacy:Data=Data(##"{"lighting":true,"lightSettings":{"globalBrightness":0.4,"otherColor":"#AACCFF","ambientPreset":"splash"},"menuBarSettings":{"style":"waveformQuota"},"customFutureField":42}"##.utf8)
  try legacy.write(to:file)
  let store=PulseConfigurationStore(directory:directory)
  let migrated=try store.migrate(legacySignature:"KEYBOARD.g915.serial")
  expect(migrated["schemaVersion"] as? Int == 2,"version migration")
  expect(migrated["selectedDeviceKey"] as? String == "ghub:KEYBOARD.g915.serial","only known recovery identity migrated")
  expect(migrated["lighting"] as? Bool == true,"toggle preserved")
  let profiles=migrated["deviceProfiles"] as! [String:[String:Any]]
  expect((profiles["ghub:KEYBOARD.g915.serial"]?["lightSettings"] as? [String:Any])?["otherColor"] as? String == "#AACCFF","legacy settings preserved")
  let backups=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("config-before-v2-")}
  expect(backups.count==1,"single original backup")
  expect(try Data(contentsOf:backups[0]) == legacy,"backup preserves original bytes")
  _=try store.migrate(legacySignature:"other")
  expect(try store.read()["selectedDeviceKey"] as? String == "ghub:KEYBOARD.g915.serial","migration idempotent")
  _=try store.selectDevice("ghub:second",defaults:["otherColor":"#112233"])
  _=try store.saveLightSettings(["otherColor":"#445566"])
  _=try store.selectDevice("ghub:KEYBOARD.g915.serial",defaults:[:])
  let restored=try store.read()
  expect((restored["lightSettings"] as? [String:Any])?["otherColor"] as? String == "#AACCFF","per-device settings round trip")
  expect(restored["customFutureField"] as? Int == 42,"unknown fields retained")
  let current=try Data(contentsOf:file)
  try Data("{broken".utf8).write(to:file)
  do {_=try store.update{$0["lighting"]=false};preconditionFailure("invalid JSON must reject writes")} catch {}
  expect(try Data(contentsOf:file) == Data("{broken".utf8),"invalid file left intact")
  try Data(#"{"schemaVersion":99,"lighting":true}"#.utf8).write(to:file)
  do {_=try store.update{$0["lighting"]=false};preconditionFailure("future schema must reject writes")} catch {}
  let damagedProfile=Data(#"{"schemaVersion":2,"selectedDeviceKey":"ghub:a","deviceProfiles":{"ghub:a":"damaged"}}"#.utf8)
  try damagedProfile.write(to:file)
  var rejected=false
  do {_=try store.saveLightSettings(["globalBrightness":1])} catch {rejected=true}
  expect(rejected,"damaged device profile must reject write")
  expect(try Data(contentsOf:file)==damagedProfile,"damaged profile original preserved")
  try current.write(to:file)
  _=try store.update{$0["appearance"]="light"}
  expect(try store.read()["appearance"] as? String == "light","appearance persists")
  print("PASS: config migration/backup, idempotence, profile roundtrip, unknown fields, corruption/future-schema safety, appearance")
 }
}
