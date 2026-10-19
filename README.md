# IP, PLEASE — iOS 版

把 [ip-please/ip-please.github.io](https://github.com/ip-please/ip-please.github.io) 的纯静态网页游戏
包成一个原生 iOS App，并加上了**存档导入 / 导出**。

| | |
| --- | --- |
| 安装包 | `dist/IP-PLEASE.ipa`（或在 Releases 里下载） |
| Bundle ID | `com.ipplease.game` |
| 最低系统 | iOS 14.0，arm64 |
| 版本 | 1.1 |

## 结构

| 路径 | 内容 |
| --- | --- |
| `src/main.m` | App 壳：UIWindow + WKWebView，横屏、隐藏状态栏、关滚动/长按菜单，注入「存档」按钮 |
| `src/saves.m` | 存档导入导出：JS 桥 + 系统分享面板 + 文件选择器 |
| `src/httpserver.c` | 极简回环 HTTP 服务器（只监听 127.0.0.1），把 `www/` 当静态站点提供 |
| `www/` | 游戏本体（原仓库的 html/js，未改动） |
| `res/icons/` | 用像素字形生成的图标 |
| `gen_icon.py` | 图标生成脚本 |
| `Info.plist` | 横屏、全屏、最低 iOS 14 |
| `build.sh` | 一条命令出 ipa |

## 存档导入 / 导出

游戏把进度存在 `localStorage['ip-please-save-v1']`，卸载 App 或换签名重装会一起清掉
（免费 Apple ID 的证书 7 天一换，这个很要命）。所以右上角加了个「存档」按钮：

- **导出存档到文件** → 把进度包成 JSON（带 `format / version / exportedAt` 头），
  唤起系统分享面板，可存到「文件」、发给自己、扔 iCloud Drive
- **从文件导入存档** → 从「文件」里选一份 JSON，校验 `day` 字段后写回 `localStorage`，
  刷新页面即恢复到对应天数

导出格式：

```json
{
  "format": "ip-please-save",
  "version": 1,
  "game": "IP, PLEASE",
  "exportedAt": "2026-10-20T01:40:00Z",
  "save": { "day": 3, "savings": 42, "family": {}, "stats": {}, "flags": {}, "tut": {} }
}
```

导入时也接受不带外壳的裸存档（就是 `save` 里那一坨），手改过的 JSON 直接塞回去也行。

## 为什么内置 HTTP 服务器

WKWebView 以 `file://` 打开页面时来源是 `null`，`localStorage` 直接抛异常（存档静默失效）。
所以 App 启动时在 `http://127.0.0.1:48123` 起一个只服务 Bundle 内文件的小服务器，
WebView 用这个地址加载：存档、WebAudio 音效、字体渲染都和浏览器里一致。
端口固定，重启 App 后仍然认作同一个来源。

## 重新构建

```bash
./build.sh                       # 产物：dist/IP-PLEASE.ipa
SDK=/path/to/iPhoneOS16.5.sdk ./build.sh
```

交叉编译用 `clang -target arm64-apple-ios14.0` + `ld64.lld` + iPhoneOS SDK，
再用 `ldid -S` 做 ad-hoc 签名，所以不需要 macOS / Xcode。

## 安装

ipa 是 ad-hoc 签名，直接装不上，需要用签名工具重签一次：

- Windows / macOS：[Sideloadly](https://sideloadly.io)、[AltStore](https://altstore.io)
  （免费 Apple ID 即可，证书 7 天有效）
- 装了 TrollStore 或越狱的设备：直接安装

重签前先导出一次存档，换证书重装后再导入，进度就不会丢。

## 许可

游戏代码 MIT（原作者 [ip-please](https://github.com/ip-please/ip-please.github.io)），
本壳代码同样 MIT。像素字体见 `www/OFL-fusion-pixel.txt`（SIL OFL 1.1）。
