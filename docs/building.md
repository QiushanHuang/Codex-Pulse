<a id="english"></a>

# Build, verify and package

[English](#english) · [简体中文](#中文) · [README](../README.md)

## Source build

Use macOS 14+, full Xcode with its license accepted, Python 3.9+ (with sqlite3/ssl)
and Node.js 22+. No pip/npm install is required for the application. Build scripts
prefer a working non-system Python rather than relying on the Xcode-dependent shim.

```sh
python3 scripts/build_macos.py
open "build/Codex Pulse.app"
```

The script compiles the SwiftUI app and a real WidgetKit extension, generates the
lighting catalog/icon and ad-hoc signs the result. It does not install, launch,
register login startup or change keyboard lighting unless an explicit optional action
is selected. Quit an app running from `build/` before overwriting that build.

| Option | Action |
| --- | --- |
| `--sdk /path/to/MacOSX.sdk` | Select the app compiler SDK |
| `--identity 'Developer ID Application: …'` | Use an existing signing identity; this alone is not notarization |
| `--reuse-widget` | Reuse a previously built, verified extension; only for a compatible unchanged widget |
| `--register` | Register the app/extension locally for discovery |
| `--install` | Run the backup/install/launch verification flow; refuses a running installed app |

Some combinations of a newly installed Xcode and Command Line Tools SDK can produce
missing Swift macro-plugin errors. Use a matching installed compiler/SDK pair. The
public 2.1.3 app was compiled with CLT and MacOSX26.5.sdk; its extension was freshly built
using Xcode. For that specific setup, first build the extension normally, copy it to
`build/Codex Pulse.app/Contents/PlugIns/CodexPulseWidget.appex`, then use:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
python3 scripts/build_macos.py --reuse-widget \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

Only use paths actually installed on your Mac. Intel source compilation is not verified.

## Offline checks

```sh
python3 -m unittest discover -s tests -v
node --test tests/*.test.mjs
python3 scripts/test_swift.py
codesign --verify --deep --strict "build/Codex Pulse.app"
```

The Swift runner supports `PULSE_MACOS_SDK` and `DEVELOPER_DIR`. It tests native model,
rendering, signature and window helpers without launching the app's monitor. Live
keyboard scripts (`live-*.mjs`, `probe-*.mjs`) are excluded; run those only when an
operator intends to change a connected keyboard. Unit tests do not establish device
compatibility, long-term power consumption or permission behavior on a different Mac.

For sticky/sidebar changes, also run `python3 scripts/preview_desktop.py`. It compiles
the real app model and views with a synthetic entry point, checks native resizing,
panel isolation, auto-hide and cleanup, and writes light/dark previews under
`build/desktop-preview/images`. `--interactive` opens an independent preview app with
temporary settings and synthetic data; quit that preview before rebuilding it. Neither
mode starts the monitor or controls a keyboard. Use the same SDK environment as the
Swift runner. The preview does not replace the installed application.
On macOS 15+, this also checks a cold SwiftUI launch with the sidebar already enabled,
using Launch Services and a completion receipt. macOS 14 runs the native surface
checks but reports the separate cold-launch scene check as unavailable.

## Reproduce the arm64 package

The release packager needs **Python 3.12+**, a matching **2.1.3** app and extension,
`codesign`, `ditto`, `hdiutil` and network access for pinned upstream runtimes.
It rejects an existing output directory to preserve previous artifacts.

```sh
python3 scripts/package_release.py
```

To supply a freshly built extension independently:

```sh
python3 scripts/generate_xcode_project.py
xcodebuild -project macos/CodexPulse.xcodeproj -target CodexPulseWidget \
  -configuration Release "CONFIGURATION_BUILD_DIR=$PWD/build/release/widget" \
  CODE_SIGN_IDENTITY=-
python3 scripts/package_release.py \
  --widget build/release/widget/CodexPulseWidget.appex \
  --output build/release/v2.1.3
```

Downloads are pinned by URL and SHA-256. Extraction uses Python's `data` filter.
The packager stages a separate app, embeds runtimes, copies license notices and offline
documentation, removes machine-specific input-authorization history, uses paths relative
to bundle resources, signs nested Mach-O files and verifies the bundle. It runs import
and WebSocket smoke checks, then creates DMG, ZIP, manifest and checksums.

Output defaults to `build/release/v2.1.3/`. `stage/` and `unpack/` are local staging
folders, not separate release uploads. Publish only the named DMG, ZIP,
`release-manifest.json` and `SHA256SUMS.txt`, alongside the tagged source archive.

Check the app again after extracting the ZIP into a path containing spaces/Unicode:

```sh
xcrun swiftc -parse-as-library macos/RuntimePaths.swift tests/BundledRuntimeTests.swift \
  -o build/bundled-runtime-tests
build/bundled-runtime-tests "/path/to/extracted/Codex Pulse.app/Contents/Resources"
```

This uses the same runtime resolver as the app and launches its bundled backends.
Run its bundled Python imports and Node checks with no Homebrew in PATH, inspect
runtime dynamic-library paths, and verify the DMG. Do not include local snapshots,
configurations, logs, recovery records, task screenshots or downloaded development SDKs.

## Signing and distribution limits

The included recipe produces **ad-hoc signed, unnotarized** packages. It is not a
Developer ID release pipeline. A notarized distribution additionally needs authorized
Developer ID credentials, appropriate nested signing/entitlements, Apple notarization
and stapling; those steps were not performed for 2.1.3. Check Gatekeeper behavior and
Input Monitoring on a clean Mac before claiming a seamless first-launch experience.
No updater or automatic telemetry service is included.

---

<a id="中文"></a>

## 中文

[English](#english) · [简体中文](#中文)

### 构建与验证

源码需要 macOS 14+、已接受许可的完整 Xcode、Python 3.9+（含 sqlite3/ssl）、Node.js 22+。
应用无需 pip/npm 安装。运行`python3 scripts/build_macos.py`，产物为`build/Codex Pulse.app`。
构建包括真正的 WidgetKit 扩展、目录数据、图标和签名；默认不安装、不启动、不更改灯光。
如果正在运行 build 中的版本，先退出再重建。

`--sdk`指定 SDK；`--identity`使用现有证书，但不自动公证；`--reuse-widget`仅适合兼容且
未变更的已有扩展；`--register`进行本机注册；`--install`执行备份、安装和启动验证。

完整离线检查：

```sh
python3 -m unittest discover -s tests -v
node --test tests/*.test.mjs
python3 scripts/test_swift.py
codesign --verify --deep --strict "build/Codex Pulse.app"
```

Swift 检查接受`PULSE_MACOS_SDK`和`DEVELOPER_DIR`，不启动真实监控或键盘控制。
硬件脚本不纳入 CI；只有操作者明确希望改变键盘时才运行。

便签与侧边栏修改还应运行 `python3 scripts/preview_desktop.py`，使用与 Swift 检查相同的 SDK 环境。
它使用模拟数据检查窗口尺寸、圆环临时展开、侧边栏隔离、自动隐藏及清理，并生成浅色／深色预览。
`--interactive` 打开独立测试应用，`--build-only` 只编译；不会启动监控、控制键盘或替换已安装应用。
macOS 15+ 额外检查已启用侧边栏时的冷启动，macOS 14 仅运行原生展示检查。

若出现 Swift 宏插件不匹配，使用匹配的编译器/SDK。本次主应用使用 CLT 的 MacOSX26.5.sdk，
扩展由 Xcode 重新编译；对应命令与扩展位置见上方英文段。不要照抄本机不存在的 SDK 路径。
Intel 源码编译尚未验证。

### 打包

发行打包需要 **Python 3.12+**、匹配的 2.1.3 主应用与扩展，以及 macOS 打包工具和网络。
运行`python3 scripts/package_release.py`；也可用`--widget`指定新扩展，`--output`指定新目录。
脚本拒绝覆盖已有输出，下载来源和 SHA-256 已固定，使用安全解包过滤器。

流程在独立目录内嵌入 Python/Node、许可与离线文档，移除本机授权历史，使用相对路径、
签名并校验，再生成 DMG、ZIP、清单和校验和。只发布这四类产物，不上传 stage/unpack。
解压后再次检查中文/空格路径中的运行时、动态库依赖、签名及 DMG。
不要打包真实任务、配置、日志、恢复记录或开发 SDK。

### 签名边界

当前流程生成 **ad-hoc 签名、未公证**包。正式 Developer ID 公证发布另需证书、适当的
嵌套签名/权限、Apple notarization 和 stapling；2.1.3 没有执行这些步骤。
因此不能声称首次打开无提示或更新后永远无需重新授权。未提供自动更新或遥测服务。
