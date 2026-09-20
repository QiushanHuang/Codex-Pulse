# Third-party notices

Codex Pulse source and original logo artwork are MIT-licensed by Qiushan
(QiushanHuang). The release also distributes these unmodified upstream runtimes
(apart from local code signing):

| Component | Version / source | License files |
| --- | --- | --- |
| CPython | 3.13.15, python-build-standalone 20260901, aarch64-apple-darwin install_only | [Python and dependency notices](docs/third-party/python/) and runtime `lib/python3.13/LICENSE.txt` |
| Node.js | 22.23.2, official darwin-arm64 distribution | [Node and bundled dependency notices](docs/third-party/NODE-LICENSE.txt) |

Python source: https://github.com/astral-sh/python-build-standalone/releases/tag/20260901

Node source: https://nodejs.org/dist/v22.23.2/

The package retains the Python installation's own license metadata, including pip
and vendored packages, and includes the upstream standalone builder's license set.
Not every license in that set applies to every platform. Node's LICENSE includes
notices for its bundled dependencies. Artifact hashes and download URLs are pinned
in `scripts/package_release.py` and recorded in the release manifest.

OpenAI Codex, Logitech G HUB, Apple SDKs and proprietary device firmware are **not**
bundled. Install the relevant products separately. Their names and trademarks belong
to their respective owners. Codex Pulse does not claim affiliation or endorsement.

## 中文

源码和原创 Logo 使用项目 MIT 许可。发行包另含 Python 3.13.15 与 Node.js 22.23.2，
保留各自及所含依赖的许可文本；Python standalone 的完整许可集合中可能包含其他平台组件。
下载来源与 SHA-256 固定在打包脚本并写入发行清单。
发行包不包含 Codex、G HUB、Apple SDK 或设备固件；这些产品需另行安装。
