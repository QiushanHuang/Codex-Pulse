# v2.1.2 validation

Checked on 2026-09-20, Apple Silicon, macOS 27.0. The declared deployment target is
macOS 14.0; that is not a claim of testing on macOS 14.

| Scope | Result |
| --- | --- |
| Python regression suite | 34 tests passed, including discovery of Codex.app without shell PATH |
| JavaScript regression suite | 85 tests passed; no hardware scripts executed |
| Native Swift | 14 suites passed: runtime paths, catalog, JavaScriptCore, configuration, diagram, input status, signatures, menu bar, pagination, sticky metrics/windows, trend rendering, window coordination and workbench state |
| App | Optimized arm64 build with CLT / MacOSX26.5.sdk; strict deep code-signature verification passed |
| Widget | Fresh Xcode extension build; app/extension versions both 2.1.2 |
| Packaged backend | Bundled Python imports and backend imports, 48-preset JavaScript engine and Node WebSocket passed |
| Relocation | Extracted app in a path containing spaces and Chinese characters; both runtimes launched using the app's resolver with PATH restricted to `/usr/bin:/bin` |
| Dynamic libraries | 11 runtime Mach-O files inspected; library dependencies are system or bundle-relative (self install IDs are not dependencies) |
| Packaging | ZIP extraction/seal and DMG integrity checked; hashes and runtime manifest included |
| Documentation | Same-page language anchors, staged local links and synthetic preview images checked |
| Attribution | Qiushan / QiushanHuang; GitHub-linked noreply author identity; original artwork MIT licensed |

The runtime-path regression was observed failing before the resolver change; the
Codex.app discovery regression was also observed failing before its fix. The new
Swift runner initially omitted dependencies and one output-directory argument; those
runner issues were corrected without weakening the underlying assertions.

Upstream license files are retained verbatim. reStructuredText heading underlines
can resemble conflict markers to `git diff --check`; these are upstream formatting,
not merge conflicts. Project-source whitespace checks exclude third-party notices.

The host's installed app, real account data, keyboard state and privacy settings were
not changed for release validation. The relocated backend probes do not query the
account service or take keyboard control. UI previews use synthetic fixture data.
No claim is made of clean-machine first launch, notarization, macOS 14/Intel runtime
acceptance, new physical keyboard tests, or long-term power measurements.

## 中文

在 Apple Silicon / macOS 27.0 上检查：34 项 Python、85 项 Node、14 组原生 Swift 通过；
优化构建、全新小组件、严格签名、解压后中文/空格路径、无 Homebrew 的内置运行时、
动态库依赖和 DMG 完整性均已检查。运行时路径及 Codex.app 发现回归先观察失败再修复。

未改变已安装应用、真实账户数据、键盘状态或系统权限；展示图使用模拟数据。
macOS 14 是部署目标，不代表已在该系统实测；未做全新机器首次打开、公证、Intel、
新一轮实体键盘或长期耗电验证。签名为 ad-hoc。
