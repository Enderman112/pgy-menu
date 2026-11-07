# macOS 原生版（SwiftUI，legacy）

这是最初的 macOS 原生实现（SwiftUI `MenuBarExtra` + 设置窗口），功能齐全，仍在本地使用。
后来项目主实现切换为 Tauri（`apps/desktop`），这里保留作为参考。

```bash
cd apps/macos-swift
./build.sh                # 生成 dist/PGYMenu.app
open dist/PGYMenu.app
./dist/PGYMenu.app/Contents/MacOS/PGYMenu --selftest   # 设备连通性自检
```

要求：macOS 14+、Xcode 命令行工具（Swift 5.9+）。
