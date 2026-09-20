import SwiftUI

struct AmbientLibraryPage: View {
    @ObservedObject var model: PulseModel
    let onBack: () -> Void
    @State private var category = "all"
    @State private var query = ""
    @State private var previewSource = "design"
    @State private var pagination = PresetPagination(itemCount: 0, pageSize: 3)
    @State private var locateAfterFiltering = false
    private let catalog = AmbientCatalog.shared
    private let groups = [("all", "全部"), ("gkeys", "G1–G5 联动"), ("static", "静态"), ("loop", "循环"), ("zones", "分区"), ("reactive", "交互")]
    private var current: AmbientPreset? { catalog.presets.first { $0.id == model.preferences.ambientPreset } }
    private var filtered: [AmbientPreset] { catalog.filtered(category: category, query: query) }
    private var visiblePresets: [AmbientPreset] {
        let items = filtered
        return pagination.visibleRange.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }
    private func select(_ preset: AmbientPreset) {
        model.setPreference(\.ambientPreset, preset.id)
        model.setPreference(\.ambientPalette, preset.palette)
        model.setPreference(\.ambientProfile, preset.profile)
        model.setPreference(\.ambientPeriod, preset.period)
        model.setPreference(\.ambientZones, [:])
    }
    private func color(_ hex: String) -> Color {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var body: some View {
        GeometryReader { geometry in
            let browserWidth = min(310, max(280, geometry.size.width * 0.29))
            let editorWidth = max(300, geometry.size.width - 48 - browserWidth - 20)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) { Label("联动规则", systemImage: "chevron.left") }.buttonStyle(.plain)
                    Spacer()
                    Text(model.deviceReady && model.lighting && model.preferences.ambientEnabled ? "更改自动保存 · 等待设备应用" : "离线设计 · 保存到当前配置")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("灯效工作室").font(.title.bold())
                        Text("\(catalog.presets.count) 个预设 · \(catalog.palettes.count) 组色板 · \(catalog.zones.count) 个分区")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("应用非功能区灯效", isOn: Binding(get: { model.preferences.ambientEnabled }, set: { model.setPreference(\.ambientEnabled, $0) }))
                        .toggleStyle(.switch).fixedSize()
                }
                HStack(alignment: .top, spacing: 20) {
                    presetBrowser.frame(width: browserWidth)
                    editor(previewWidth: max(250, editorWidth - 32)).frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }.frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var presetBrowser: some View {
        GeometryReader { geometry in
            let pageSize = PresetPagination.pageSize(availableHeight: geometry.size.height - 180)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("预设").font(.headline)
                    Text("\(filtered.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button { locateCurrent() } label: { Label("定位当前", systemImage: "scope") }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(pulseMint).disabled(current == nil)
                        .help(current.map { "定位当前预设：\($0.name)" } ?? "当前预设不可用")
                }.frame(height: 20)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("查找名称、颜色或效果", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("清除预设搜索").foregroundStyle(.secondary)
                    }
                }.font(.callout).padding(.horizontal, 9).frame(height: 32)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                Picker("分类", selection: $category) {
                    ForEach(groups, id: \.0) { id, title in Text(title).tag(id) }
                }.pickerStyle(.menu).frame(height: 24)
                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                        Text("没有匹配的预设").font(.callout)
                        Button("清除筛选") { query = ""; category = "all" }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        ForEach(visiblePresets) { preset in presetRow(preset) }
                    }
                    Spacer(minLength: 0)
                }
                pager.frame(height: 30)
            }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .onAppear {
                    pagination.update(itemCount: filtered.count, pageSize: pageSize)
                    revealCurrentIndex()
                }
                .onChange(of: pageSize) { _, size in pagination.update(itemCount: filtered.count, pageSize: size) }
                .onChange(of: [category, query]) { _, _ in
                    pagination.update(itemCount: filtered.count, pageSize: pageSize, resetPage: true)
                    if locateAfterFiltering { revealCurrentIndex(); locateAfterFiltering = false }
                }
        }
    }

    private var pager: some View {
        HStack(spacing: 8) {
            Button { pagination.previous() } label: { Image(systemName: "chevron.left").frame(width: 22) }
                .disabled(pagination.page == 0).accessibilityLabel("上一页预设")
            Spacer(minLength: 0)
            if pagination.pageCount > 0 {
                Menu {
                    ForEach(0..<pagination.pageCount, id: \.self) { page in
                        Button("第 \(page + 1) 页") { pagination.move(to: page) }
                    }
                } label: {
                    Text("第 \(pagination.page + 1) / \(pagination.pageCount) 页").monospacedDigit()
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("预设页码，点击跳转")
            } else { Text("0 个结果").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Button { pagination.next() } label: { Image(systemName: "chevron.right").frame(width: 22) }
                .disabled(pagination.pageCount == 0 || pagination.page >= pagination.pageCount - 1).accessibilityLabel("下一页预设")
        }.controlSize(.small)
    }
    private func locateCurrent() {
        if category != "all" || !query.isEmpty {
            locateAfterFiltering = true
            category = "all"
            query = ""
        } else { revealCurrentIndex() }
    }
    private func revealCurrentIndex() {
        if let index = filtered.firstIndex(where: { $0.id == model.preferences.ambientPreset }) { pagination.reveal(index: index) }
    }
    private func presetRow(_ preset: AmbientPreset) -> some View {
        let selected = model.preferences.ambientPreset == preset.id
        return Button { select(preset) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(preset.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(pulseMint) }
                }
                Text(preset.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(Array((catalog.palettes[preset.palette]?.colors ?? []).enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 2).fill(color(hex)).frame(width: 17, height: 4)
                    }
                    Spacer(minLength: 0)
                    Text(preset.gkeyFocus ? "G1–G5" : groups.first { $0.0 == preset.category }?.1 ?? "")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 62)
                .background(selected ? pulseMint.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? pulseMint.opacity(0.65) : Color.primary.opacity(0.07), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(preset.name + "，" + preset.description)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func editor(previewWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(current?.name ?? "当前灯效").font(.title3.weight(.semibold))
                            Text(current?.description ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("恢复此预设") { if let current { select(current) } }.controlSize(.small).disabled(current == nil)
                    }
                    Picker("预览来源", selection: $previewSource) {
                        Text("设计预览").tag("design")
                        Text("实机发送帧").tag("live")
                    }.pickerStyle(.segmented)
                    if previewSource == "design" {
                        AmbientDesignPreview(model: model, previewWidth: previewWidth)
                    } else {
                        AmbientKeyboardView(enabled: model.preferences.ambientEnabled && model.lightingActive, expectedDeviceKey: model.selectedDeviceKey, previewWidth: previewWidth)
                    }
                    if !model.lighting { Button("开启键盘联动") { model.saveLighting(true) }.disabled(!model.deviceReady) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 17) {
                    Text("自由组合").font(.headline)
                    AmbientSettingsView(model: model, compactControls: true)
                    Divider()
                    HStack {
                        Text("非功能区总亮度")
                        Spacer()
                        Text("\(model.preferences.otherBrightness * 100, specifier: "%.0f")%").monospacedDigit()
                    }
                    Slider(value: Binding(get: { model.preferences.otherBrightness }, set: { model.setPreference(\.otherBrightness, $0) }), in: 0...1, step: 0.01)
                        .accessibilityLabel("非功能区总亮度")
                    Text("分区与总亮度相乘；功能区沿用自己的状态灯效。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
