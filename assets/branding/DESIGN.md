# Codex Pulse identity

The large white waveform represents activity. The smaller mint semicircle below it
represents remaining quota. The dark rounded tile mirrors the native menu-bar
waveform and quota arc without reproducing the OpenAI or Logitech logos.
The arc is a fixed 75% illustration in the app icon, not a live quota indicator.

`logo.svg` and `banner.svg` contain original editable vector paths. The matching
1024px app icon is `codex-pulse-logo-v3.png`; regenerate it on macOS with:

```sh
xcrun swift assets/branding/render-logo-v3.swift assets/branding/codex-pulse-logo-v3.png
```

The paths were drawn deterministically in SVG and AppKit; no image-generation
model was used. Keep the waveform dominant and the arc secondary. Use the supplied
transparent margin when creating `.icns` assets. Artwork is covered by the project
MIT license. Earlier local design candidates are not release assets.

中文：白色波形表示活动，下方较小的薄荷绿半环表示剩余额度，与菜单栏保持一致。
应用图标中的 75% 半环只是固定示意，并非实时额度。SVG 为可编辑原创路径，
PNG 由随附 Swift 脚本绘制；未使用图片生成模型。
