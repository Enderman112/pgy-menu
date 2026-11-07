import AppKit
import Foundation

// 命令行入口：
//   PGYMenu                     正常启动菜单栏 App
//   PGYMenu --selftest          设备连通性/接口自检（不弹界面）

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

PGYMenuApp.main()
