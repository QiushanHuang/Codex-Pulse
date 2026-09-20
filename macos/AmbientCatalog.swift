import Foundation

struct AmbientPreset: Decodable, Identifiable { let id,name,category,effect,palette,profile,description:String;let period:Double;let gkeyFocus:Bool }
struct AmbientPalette: Decodable { let name:String;let colors:[String] }
struct AmbientProfile: Decodable { let name:String;let values:[String:Double] }
struct AmbientZone: Decodable,Identifiable { let id,name:String }
struct AmbientKey: Decodable,Identifiable {let id,label,zone:String;let x,y,w,h:Double;let `protected`:Bool}
struct AmbientCatalog: Decodable {
    let presets:[AmbientPreset],palettes:[String:AmbientPalette],profiles:[String:AmbientProfile],zones:[AmbientZone],keys:[AmbientKey]
    static let shared:AmbientCatalog = {
        guard let url=Bundle.main.url(forResource:"ambient-catalog",withExtension:"json"),let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(AmbientCatalog.self,from:data) else {
            return AmbientCatalog(presets:[],palettes:[:],profiles:[:],zones:[],keys:[])
        };return value
    }()
}


extension AmbientCatalog {
    func filtered(category:String,query:String)->[AmbientPreset] {
        let term=query.trimmingCharacters(in:.whitespacesAndNewlines)
        return presets.filter { p in
            let inCategory=category == "all" || (category == "gkeys" ? p.gkeyFocus:p.category == category)
            let text=[p.name,p.id,p.description,p.palette,palettes[p.palette]?.name ?? ""].joined(separator:" ")
            return inCategory && (term.isEmpty || text.localizedCaseInsensitiveContains(term))
        }
    }
}
