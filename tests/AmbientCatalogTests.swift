import Foundation
@main struct AmbientCatalogTests {
 static func main() throws {
 let c=try JSONDecoder().decode(AmbientCatalog.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
 precondition(c.filtered(category:"all",query:"").count==48)
 precondition(c.filtered(category:"gkeys",query:"").count==16,"G-key filter must exclude unrelated presets")
 precondition(c.filtered(category:"loop",query:"").count==16)
 precondition(c.filtered(category:"all",query:"  五阶流光  ").map(\.id)==["g-ladder"])
 precondition(c.filtered(category:"all",query:"GLACIER").count>0,"palette search is case-insensitive")
 precondition(c.filtered(category:"static",query:"五阶流光").isEmpty,"search and category intersect")
 precondition(c.filtered(category:"all",query:"not-a-preset").isEmpty)
 print("PASS: preset counts, G-key category, trimmed and case-insensitive search, category intersection and empty results")
 }
}
