![LilaShift](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

## LilaShift 2.0（紫序）— LilaShift 1.0.7

[![Version](https://img.shields.io/badge/version-1.0.7-blue)](https://github.com/fafa920q-hue/LilaShift-2.0)

[![Platform](https://img.shields.io/badge/iOS-27.x-black?logo=apple)](#兼容性)

[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)](https://github.com/fafa920q-hue/LilaShift-2.0)

[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

[English](README.md) · [简体中文](README_ZH-CN.md)

国行 iPhone 一键解锁：eSIM、地区码、Apple Intelligence，一次点按完成。这是完整源码的 LilaShift 2.0 项目，基于官方 GestaltX v1.0.7。

## 这是什么仓库

这是 LilaShift 2.0（紫序）的**完整源码项目**，即 GestaltX 国行增强版。完整修改源码都在这个仓库里，没有补丁步骤，CI 直接从这份源码构建 IPA。基于上游 [huamidev/GestaltX](https://github.com/huamidev/GestaltX) `v1.0.7`（提交 `dfd4a7e`，build `11130112`）加上上游壁纸删除修复 PR #126（提交 `c60519c`）。之前的补丁式构建仓库（[fafa920q-hue/LilaShift](https://github.com/fafa920q-hue/LilaShift)）保持原样不动。

## 本版新增内容

- **一键解锁（9 项）。** eSIM 两项开关（green-tea 关、not-green-tea 开）、地区码改美国（`LL`，销售地区不变）、6 项 Apple Intelligence 能力——一次点按全部暂存，确认后应用。
  - 暂存前会先校验 eSIM 缓存布局；验不过整组停住并显示原因，地区码和 AI 仍可单独设置。
  - 每次应用都会自动备份并写回校验；一键还原可从记录的原始值恢复全部 9 项。
- **浅紫 Liquid Glass 全新视觉。** 页面背景 `#F6F3FF`，主紫 `#8652DC`，无大面积深色背景。
- **每个功能名下都有一句简体中文用途说明。** 33 个预设全覆盖；设备要求与生效方式放在详情里。
- **作者徽章与进度卡。** 维护者 `@steam8871` 显示在首页与关于页；读取与应用进度（备份 / 写入 / 校验 / 完成）由真实操作驱动，绝不伪造。
- **开源合规。** 关于页有「开源与鸣谢」，App 内置 GPL v3.0 全文，并链接了本增强版源码仓库。
- **写入加固，借鉴 Erosion-CN。** 原地写入（不预先截断、`F_FULLFSYNC`、完整写回校验、失败原地回滚）、运行时动态解析 eSIM 缓存布局、应用前 Diff 预览、双金库备份（卸载重装后还在的出厂金库）、地区二选一（只改地区码，或完整美国 `LL` + `LL/A`）、四要素 Apple 智能体检与冲突防呆——均未照抄 Erosion-CN 代码。
- **LilaShift 身份。** 应用名为 **LilaShift**（中文：紫序），猫照片做应用图标，作者 `@steam8871` 显示在首页与关于页。

## 功能

| 分类 | 预设与工具 |
| --- | --- |
| 国行一键解锁 | 一次暂存 9 项：eSIM 两项开关、地区码美国（`LL`）、6 项 Apple Intelligence 能力——应用前先确认，带 eSIM 缓存布局校验、自动备份、写回校验和一键还原 |
| 显示 | 灵动岛功能标记与布局、全天候显示、AOD 色彩、高亮度 AOD、AOD 翻页组件、HDR 照片显示、壁纸视差、液态玻璃低性能渲染，以及实验性的 PWM 与 DisplayPort 标记 |
| 设备 | 机型名称、开关机提示音、充电上限、轻点唤醒、相机控制设置、操作按钮设置、车祸检测 SOS、音频混音、FaceTime 空间音频 |
| iPad | Apple Pencil 设置、台前调度功能标记、iPad 应用兼容性 |
| 智能 | 独立的地区代码选项、Apple 智能功能标记、端侧 Siri、音频智能、个人翻译、照片消除、手写合成、常听 Hey Siri 及销售地区选项；国行设备可尝试开启 AI |
| 高级 | Apple 内部功能标记、需单独确认启用的系统全局 InternalBuild 标记、内部设置包、安全研究设备标记 |
| 字段编辑 | 读取、搜索、添加、编辑与删除 `CacheExtra` 字段；本地 plist 导入导出；支持字符串、整数、浮点数、布尔值、数据、日期、数组和字典 |
| 更改管理 | 启动自动读取、手动重新读取、暂存更改前后对比、写入验证、逐项还原 |
| 备份 | 首次读取自动备份、每次写入前备份、原值记录；打开、导出、恢复和删除 |
| 日志与注销 | 实际漏洞利用过程日志、手动 NeoSpring 注销 |

通常只需修改地区代码即可尝试启用 AI，无需更改销售地区。“地区代码”选择“美国”时仅将 `RegionCode` 设为 `LL`，保留销售地区后缀，也可选择中国大陆、香港、台湾、日本或英国。销售地区与地区代码可以一起应用：后缀按销售地区设置，代码按地区代码设置。

*之前修改过销售地区的用户，请先改回设备原本的销售地区并应用。*

停用预设或点击该项“还原”，会恢复已记录的原值及类型；原本不存在的字段会被删除。旧版修改若缺少原值记录，请仅对确认是后来添加的字段使用“移除新增字段”。

预设修改的是功能标记，实际效果取决于设备与系统。国行设备可通过 Apple 智能与地区选项尝试启用 AI，实际可用性还取决于机型、系统版本及 Apple 服务。

## 兼容性

支持 **iOS / iPadOS 27.x**。**iOS / iPadOS 26.x 不支持本机 MobileGestalt 访问。** 基于 [worse_query](https://github.com/forcequitOS/worse_query)。SystemGroup 访问需要 iOS 27，功能可用性因设备与系统而异，同时支持本地 plist 编辑。

签名所用的证书及描述文件必须提供至少一个可用的 App Group。主应用和内置分享扩展必须签入至少一个**相同的 App Group**，重签时请保留分享扩展。两者均会在运行时读取实际签名中的 App Group。发布的 IPA 使用 ad-hoc 签名嵌入这些 entitlements，便于 SideStore、AltStore 在重签时识别，不使用开发者证书。

最简单的安装不需要签名：用 [LiveContainer](https://github.com/khanhduytran0/LiveContainer) 直接运行原始 IPA，无需重签，即可满足 App Group 要求，不需要付费开发者账号。

## 下载

请在 [Releases](https://github.com/fafa920q-hue/LilaShift-2.0/releases/latest) 下载 IPA：`LilaShift_1.0.7.ipa`（包名 `com.huami.gestultx`，版本 `1.0.7`，build `11130112`，最低 iOS `26.0`，约 5.9 MB）。第一个 Release 会在首次编包验证通过后发布。

部分用户反馈，iOS 27 上使用 Safari 下载的文件可能不完整。如果提示文件损坏或无法解压，可重新下载几次；仍有问题时换用其他浏览器。目前尚未确认具体原因。

## 安装

1. 用 [LiveContainer](https://github.com/khanhduytran0/LiveContainer) 安装 IPA。
2. 打开 LilaShift，先点 **Read Device** 读取本机数据。
3. 打开 **China Unlock**，确认 9 项内容后应用。
4. 应用后**重新启动设备**，再去系统「设置」里检查 eSIM 与 Apple Intelligence。
5. 想全部撤销时用一键还原，会从备份恢复全部 9 项。

## 要求与注意事项

- **需要 eSIM 硬件。** 解锁只改能力开关，不能给没有 eSIM 硬件的设备加上 eSIM。
- **Apple Intelligence 取决于硬件与苹果服务器。** 打开开关不保证功能一定出现或可用。
- **运营商与位置规则仍然适用。** 在中国大陆境内无法安装境外 eSIM（苹果规则）；在境外安装通常需要打开定位服务；中国运营商 eSIM 须在中国营业厅激活。
- **系统更新可能还原改动。** 升级 iOS 后如有需要请重新应用。
- **不要盲目升级 iOS。** GestaltX 依赖一个未修复的 iOS 沙盒逃逸漏洞（`worse_query`）。苹果可能在未来版本中修掉它；如果你依赖这个工具，升级前请先确认兼容性。
- **应用前请备份。** App 会自动备份，但另外做一份设备备份仍是好习惯。

## 常见问题

### 解锁后 eSIM 还是不能用，或者「添加 eSIM」消失了

- **iPhone 18 Pro / Pro Max 插着双实体卡。** 这两款是双实体卡槽 + 内置 eSIM 三通道复用硬件，两个实体卡槽都占着时基带可能隐藏「添加 eSIM」。解决：先拔出卡托（空卡状态），应用解锁后冷重启，加上 eSIM，再插回实体卡。
- **注销（Respring）不够。** 基带守护进程（`CommCenter`、`ctkd`）注销时不会重载缓存，应用后必须手动滑动关机、黑屏后再开机（冷重启）才生效。
- **两个开关都要开。** 地区码和 eSIM 两项必须同时应用，只改地区码不解 green-tea 硬件锁，eSIM 菜单一样会被屏蔽。
- **不要改机型标识（`ProductType`）。** 把国行主板（如 `iPhone19,7`）强改成美版会让基带校验失配，整个 eSIM 菜单消失。
- **在中国大陆境内扫码添加境外 eSIM 会被拦截。** 扫码时开飞行模式 + 连 Wi-Fi（挂海外代理）。
- **硬件限制。** 只有带物理 eUICC 芯片的机型（iPhone Air、iPhone 18 系列等）能加 eSIM；早期纯双实体卡槽、主板空焊 eUICC 的机型没有这个硬件，开关只能解锁 FaceTime 音频和 AI 地区准入。

### 预设页和 MG 控制对不上

MG 控制显示的是 CacheExtra 的实时值，预设页是上次读取的快照。先点首页的「重新读取」刷新。如果还对不上，说明之前是直接改字段改的、没走预设，点一次一键解锁重新写一遍就一致了。

### AI 显示 1/6（或不到 6）

说明 6 项 AI 能力里只有这么多项是开着的。点进 Apple 智能那页看是哪几项。旧版本改过的值会一直留在缓存里，直到还原；如果那次改动是在这个 App 第一次备份之前做的，备份里已经带了改动后的值。

### 想恢复原状，但没有备份

还原只能恢复 App 记录过的原始值。先去备份页看有没有更早的备份。没有的话：
- **新增的键**（原来没有的）→ 用「移除新增字段」，只删确定是后来加的。
- **改了值的键** → 在 MG 控制里手动改回去。`RegionCode` 和 AI 那几项是 CacheExtra 的键，能搜到；`green-tea` / `not-green-tea` 是 CacheData 槽位（#383 / #506），**搜不到**，得去 eSIM 预设里改（`green-tea` → `true`，`not-green-tea` → `false`）。
- 恢复后重启设备。

### AI 菜单不出现，或 Siri 说“碰到了一点问题”

检查：地区码是 `LL`、6 项 AI 都开了、设备已经下完 AI 模型（连 Wi-Fi 充电静置一会儿）。代理规则很关键：Siri 域名（`guzzoni.apple.com`、`*.siri.apple.com`、`dejavu.apple.com`、`sequoia.apple.com`）必须 **DIRECT 直连 + 真实 IP**，不能走代理；AI / PCC 域名走干净的美区节点。想保留国行普通话「询问来电原因」就别把系统地区设成美国，设成台湾。

### 照片「快速消除」正常，但「高质量消除 / 扩图延伸 / 重构」报错

原生 AI 机型的出厂基线要求 `Personal Translator` 槽位 #266 = `true`、`Audio Intelligence` 槽位 #178 = `false`。强开实验性的 Audio Intelligence 槽位会让 ModelCatalog 资产校验断路，导致高质量消除报错。关掉它、恢复基线再试。

### 重装 App，或证书过期

本版备份存在 App 容器里，卸载 App 会一起删掉。重装或证书过期前先导出备份。

## 导入 plist

在“文件”或其他 App 中选中 MobileGestalt plist，点击**分享**，再选择 **LilaShift**。分享扩展会直接读取收到的文件，并通过共同的 App Group 交给主应用。如未自动打开，请返回 LilaShift。应用会验证 GestaltX 导出文件的本机凭证，或将文件中的至少两个唯一设备标识与本机信息比对，通过后弹窗确认导入。无法核验的文件均拒绝导入，不会把之前导入的文件当成本机身份依据。

部分原始 plist 不含唯一设备标识，请先在本机通过 LilaShift 导出一份副本。校验密钥只保存在本机钥匙串，不随文件导出。

应用会在启动和回到前台时检查分享文件。当前有未保存更改时，会等待你保存或放弃后再导入。确认导入的文件作为本地文档打开。“**MG 控制**”支持新增、修改、重命名和删除不同类型的键值。点击“**恢复导入的 plist**”可将已核验的文件恢复到本机；恢复时会核对系统缓存布局，经过二次确认后先备份当前文件，再写入并验证。完成后请重启设备。

## 自己构建

**Build LilaShift IPA**（`.github/workflows/build.yml`）直接从这份源码构建 IPA——每次推送到 `main`、拉取请求、版本标签、Release 与手动触发都会运行。IPA 作为产物上传，名为 `LilaShift-<版本>`；打标签与发布 Release 时也会挂到对应的 Release 上。

之前构建仓库里的截图来自没有真实设备文件的模拟器，因此显示「Not read yet」状态，确认页为 1 项预览——不是 9 项解锁摘要，9 项摘要需要真机读取。

## 语言支持

GestaltX 跟随 iOS 的语言设置，默认及回退语言为英语。波斯语已适配从右向左布局。

| 语言 | 语言代码 |
| --- | --- |
| English（英语） | `en` |
| 简体中文 | `zh-Hans` |
| 繁體中文（台灣） | `zh-Hant-TW` |
| 繁體中文（香港） | `zh-Hant-HK` |
| Tiếng Việt（越南语） | `vi` |
| Русский（俄语） | `ru` |
| فارسی（波斯语） | `fa` |
| 한국어（韩语） | `ko` |
| Español（西班牙语） | `es` |
| 日本語（日语） | `ja` |

## 开源与许可证

本项目遵循 **GNU 通用公共许可证 v3.0** 发布，见 [LICENSE](LICENSE)（与官方 v1.0.7 逐字节相同）。

- 上游项目：[huamidev/GestaltX](https://github.com/huamidev/GestaltX)（`v1.0.7`，提交 `dfd4a7e`，另加 PR #126，提交 `c60519c`）
- 国行增强版维护者：`@steam8871`
- 本版修改内容：9 项一键解锁预设及安全检查、浅紫 Liquid Glass 界面、每项功能一句话用途说明、作者徽章与进度卡、App 内源码仓库链接、开源合规栏目、借鉴 Erosion-CN 的加固（写入路径、动态布局解析、Diff 预览、双金库备份、地区二选一、AI 体检）、LilaShift 更名、猫图标。
- 完整对应源码就在本仓库（完整源码，无补丁步骤）。

## 鸣谢

- **huamidev**——GestaltX。
- [forcequitOS / Taj C — worse_query](https://github.com/forcequitOS/worse_query)
- [neonmodder123](https://github.com/neonmodder123)
- [skadz108](https://github.com/skadz108)
- [rooootdev — NeoSpring](https://github.com/rooootdev/neospring)
- [Nouvborne — Ketamine](https://github.com/Nouvborne/Ketamine)
- [PoomSmart — MGKeys](https://github.com/PoomSmart/MGKeys)
- [leminlimez — Nugget](https://github.com/leminlimez/Nugget)
- [rooootdev — mond](https://github.com/rooootdev/mond)
- [frs0n — GestaltEdit](https://github.com/frs0n/GestaltEdit)

## 免责声明

这是非官方修改版，与苹果公司及上游作者无关，也不代表其立场。本项目仅供安全研究与学习交流，请仅在本人持有或已获授权的设备上使用。

修改前请备份数据。修改 MobileGestalt 可能导致系统不稳定，严重时需要恢复设备。能力开关不保证功能可用，使用者须自行承担所选修改及其带来的风险。

## 许可证

[GNU GPL v3](LICENSE) · Copyright © 2026 huamidev。国行增强版由 `@steam8871` 维护。
