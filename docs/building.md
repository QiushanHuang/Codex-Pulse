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
lighting catalog/icon and signs the result with the fixed local certificate when available. It does not install, launch,
register login startup or change keyboard lighting unless an explicit optional action
is selected. Quit an app running from `build/` before overwriting that build.

| Option | Action |
| --- | --- |
| `--sdk /path/to/MacOSX.sdk` | Select the app compiler SDK |
| `--identity 'Developer ID Application: …'` | Choose an existing signer once; successful certificate builds pin its identity locally |
| `--allow-signing-change` | Explicit signer migration; may require privacy authorization again |
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

### Preserve input permission across updates

Local builds use `~/Library/Application Support/CodexPulse/build-signing.json` to
keep the same certificate identity. With no saved profile, a single available Apple
Development or Developer ID identity is selected and pinned after signature verification.
The profile contains public signer metadata, never a private key, and is not packaged
or committed. Missing/expired pinned identities stop the build; they never silently
fall back to ad-hoc signing. Build, installer and packager reject incompatible updates
unless an identity migration is explicitly requested.

The one-time switch from the old ad-hoc app to the certificate-backed app may require
Input Monitoring authorization again. Subsequent compatible signatures preserve code
identity even when the binary hash changes. Actual permission still comes from macOS;
matching signatures are not proof that a live input listener is authorized. Never reset
or edit TCC as part of routine updates. Fresh CI/development hosts without a certificate
can still produce ad-hoc builds; those cannot retain privacy identity across changes.
Apple Development is suitable for this local workflow; it is not Developer ID
notarization or a promise of public distribution trust. See [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).


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

The release packager needs **Python 3.12+**, a matching **2.2.0** app and extension,
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
  --output build/release/v2.2.0
```

Downloads are pinned by URL and SHA-256. Extraction uses Python's `data` filter.
The packager stages a separate app, embeds runtimes, copies license notices and offline
documentation, removes machine-specific input-authorization history, uses paths relative
to bundle resources, signs nested Mach-O files and verifies the bundle. It runs import
and WebSocket smoke checks, then creates DMG, ZIP, manifest and checksums.

Output defaults to `build/release/v2.2.0/`. `stage/` and `unpack/` are local staging
folders, not separate release uploads. Publish only the named DMG, ZIP,
`release-manifest.json` and `SHA256SUMS.txt`, alongside the tagged source archive.

The public 2.2.0 package uses ad-hoc signing. To reproduce it on a Mac whose local
build uses a pinned certificate, package a separate staged copy with
`--identity - --allow-signing-change`. This does not replace the installed app or
change the pinned local certificate. Installing that public package over a
certificate-signed app changes its identity and may require Input Monitoring
authorization again.

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

The recipe preserves the selected local signing identity and produces **unnotarized** packages. On a host with no certificate or profile, it uses ad-hoc signing. The public 2.2.0 packages are ad-hoc signed; the local installation can use its pinned development certificate. It is not a
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
本机已有固定签名配置时沿用该证书；首次发现唯一可用的 Apple 证书会在验证后固定。
配置保存于应用数据目录的 `build-signing.json`，仅含公开身份信息，不含私钥、不上传 GitHub。
固定证书不可用时停止构建，不自动改回临时签名。构建、安装和打包均检查更新身份兼容性。
从旧 ad-hoc 版切换到固定证书版可能需要最后确认一次输入监控；之后正常更新沿用同一身份。
如果正在运行 build 中的版本，先退出再重建。

`--sdk`指定 SDK；`--identity`首次选择现有证书，但不自动公证；`--allow-signing-change`仅用于明确迁移身份，可能再次要求授权；`--reuse-widget`仅适合兼容且
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

发行打包需要 **Python 3.12+**、匹配的 2.2.0 主应用与扩展，以及 macOS 打包工具和网络。
运行`python3 scripts/package_release.py`；也可用`--widget`指定新扩展，`--output`指定新目录。
公开的 2.2.0 包采用 ad-hoc 签名；在固定证书的机器上复现时，可对独立的打包副本指定
`--identity - --allow-signing-change`。这不会替换安装版或修改本机固定证书；如果用公开包
覆盖证书签名的安装版，身份会变化，可能需要重新授权输入监控。
脚本拒绝覆盖已有输出，下载来源和 SHA-256 已固定，使用安全解包过滤器。

流程在独立目录内嵌入 Python/Node、许可与离线文档，移除本机授权历史，使用相对路径、
签名并校验，再生成 DMG、ZIP、清单和校验和。只发布这四类产物，不上传 stage/unpack。
解压后再次检查中文/空格路径中的运行时、动态库依赖、签名及 DMG。
不要打包真实任务、配置、日志、恢复记录或开发 SDK。

### 签名边界

打包流程保留选定的本机签名身份，仍然 **未公证**；没有证书／固定配置的全新构建机使用 ad-hoc。
已发布的 2.2.0 包为 ad-hoc 签名；本机安装可沿用固定的开发证书。Apple Development 签名不等于 Developer ID 公证发布。正式 Developer ID 公证发布另需证书、适当的
嵌套签名/权限、Apple notarization 和 stapling；2.1.3 没有执行这些步骤。
因此不能声称首次打开无提示或更新后永远无需重新授权。未提供自动更新或遥测服务。
