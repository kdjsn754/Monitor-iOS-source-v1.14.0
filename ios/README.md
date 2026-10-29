# OpenWrt Monitor — iOS

Android 版的 iOS 原生 SwiftUI 移植。

## v1.14.0 — 大幅降低连接时对路由器的 CPU 占用

现象：App 一打开、连上路由器，路由器 CPU 就冲高，OpenClash 场景下更明显。

定位到的开销（旧版 `poll`，每 2 秒一轮）：

| 位置 | 问题 |
| --- | --- |
| `pollCommand` | 一整段脚本里 **54 次进程创建**；端口那段对每个网口各起 `cat`×3、`ip`、`awk`、`ls\|wc`，网口越多越重 |
| `ocMetricsCommand` | 每 2 秒再起 10 个进程，`uci` 重复读取端口/密钥，`/connections` 每 2 秒让 clash 把整张连接表序列化一遍 |
| OpenClash 状态 | 用 `/etc/init.d/openclash status` 判断，部分固件会 source 整套 shell 函数甚至列防火墙规则 |
| 优先级 | 所有诊断命令都跑在默认优先级，和转发、NAT、clash 抢 CPU |
| 后台 | 退到后台仍继续轮询 |

这一版的做法：

1. **分档轮询**：快档（CPU/内存/网速/负载/WAN 口，3 秒）、慢档（闪存/温度/风扇/租约/端口，12 秒）、
   状态档（OpenClash 开关与配置，20 秒）、指标档（`/traffic` 6 秒、`/connections` 30 秒）。
   一眼能变的指标才值得勤刷，其余全部摊开。
2. **一条命令读完 /proc**：快档改成单个 `awk`，按文件名自动打段标记，不再 5 个 `cat`。
3. **sysfs 用内建 `read` 读**：温度、风扇、operstate/speed/duplex 全部零进程创建；
   端口表先在 awk 里建索引，再用 `set --` 查表，彻底去掉“每口 8 个进程”。
4. **`df` 只跑一次**（`/rom /overlay /` 一次给出三份数据），一块 awk 分发。
5. **`pidof` 代替 `init.d status`** 判断 OpenClash 是否在跑（覆盖 clash / clash_meta / clash_tun / clash_lite / mihomo）。
6. **复用状态查询的结果**：端口和密钥不再每次 `uci get`。
7. **全部脚本 `nice -n 19`**，监控永远不会抢路由工作和 clash 的 CPU。
8. **后台暂停轮询**，回前台自动恢复。
9. 顺手修掉 SSH 读取循环里 `EAGAIN` 的忙等（会占满手机 CPU、拖住路由器 shell），加 30 秒硬超时。

实测（同一台假路由器、4 个网口，统计每轮外部进程创建次数）：

| | 旧版 | 新版 |
| --- | --- | --- |
| 每轮进程数 | 54 + 10 | 快档 2 / 慢档 7 / 指标 2~5 |
| 折算每秒 | ≈ 32 次/秒 | ≈ 1.8 次/秒 |

约 **18 倍**下降，且都在最低优先级上执行。设置里新增「低功耗模式」，可再拉长一档。

## 功能

- SSH 直连 OpenWrt，密码登录
- Keychain 自动登录
- 多路由器连接配置：切换、新建、删除
- 概览：
  - CPU、内存、实时上下行、会话流量
  - 温度和风扇转速
  - DHCP 租约设备及详情
  - 仅 LAN 端口 / LAN 桥接
  - 系统信息（主机名、型号、架构、固件、内核、运行时间、负载）
  - 速度曲线和 CPU/内存趋势
- 概览模块：
  - 显示/隐藏
  - 拖动排序
  - 恢复默认
- 网络代理：
  - OpenClash 状态
  - 规则 / 全局 / 直连
  - 启动 / 关闭 / 重启（已运行时只提示，不重复发命令）
  - 运行数据：上传、下行、总量、连接数、内存、CPU、负载
  - 配置文件选择 + 独立“切换配置”按钮
  - 控制面板：App 内 WKWebView 打开
  - 访问检查：百度、网易云音乐、GitHub、YouTube，带延迟、状态、趋势
- 设置：
  - 跟随系统 / 浅色 / 深色
  - 概览模块管理
  - 路由器切换
  - 自动登录
  - 断开并清除密码
- 不显示订阅用量和 IP 地址卡片

## 构建

IPA 需要 macOS + Xcode + Apple 签名。当前仓库提供 GitHub Actions 的未签名 IPA 流程。

### GitHub Actions

1. 把整个仓库（包含 `ios/` 和 `.github/workflows/ios-unsigned.yml`）推到 GitHub。
2. Actions → **Build unsigned iOS IPA** → Run workflow。
3. 下载 artifact `OpenWrtMonitor-unsigned-ipa`。
4. 用 Sideloadly / AltStore 配合自己的 Apple ID 签名安装。

### Mac 本地

```bash
brew install xcodegen
cd ios
xcodegen generate
open OpenWrtMonitor.xcodeproj
```

或在 `ios/` 下运行：

```bash
chmod +x build-unsigned-ipa.sh
./build-unsigned-ipa.sh
```

生成 `build/OpenWrtMonitor-unsigned.ipa`。

## 依赖

- iOS 17+
- Xcode 15+
- [libssh2-apple](https://github.com/mfcollins3/libssh2-apple)：libssh2 1.10+，兼容 OpenWrt Dropbear
- XcodeGen

## 说明

- 应用只在本机和路由器之间传输数据，不经过云端。
- 接受路由器 SSH 主机密钥，适合可信局域网。
- 本地 HTTP 控制面板需要 ATS 例外，Info.plist 已配置。
- 这是原生重写，不是 Android APK 的包装。
