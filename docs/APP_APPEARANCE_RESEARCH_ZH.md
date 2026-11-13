# LilaShift 2.0 — 应用桌面图标与名称研究 / App Appearance Research

状态：**研究原型**（2026-11-14）。维护者：@steam8871；基于 GestaltX by huamidev（GPL-3.0）。
**严禁将预览称为真正修改已安装微信。** 本分支不修改微信 Bundle、签名、聊天数据、SpringBoard、LaunchServices 或系统图标缓存。

## 已实现
- 在现有「启动图」详情页增加隔离的「App Icon & Name · Preview Only」分区（`AppAppearancePreviewView`，独立文件 `GestaltX/AppAppearanceViews.swift`；启动图编辑器本身不再承载预览状态）。
- 从相册导入图片并预览自定义图标，输入并预览自定义桌面名称；预览不持久化到目标 App，也不执行系统写入。
- 图片校验（`AppAppearanceValidatedImage`）：按 magic bytes 识别 PNG / JPEG / HEIC，拒绝空文件、超过 5 MB 的文件、不支持的格式、无法解码的文件、任一边超过 4096 px 的图片；每次失败都给出具体原因，不静默丢弃。
- 预览图用 ImageIO 下采样后裁剪（最长边不超过 512 px），不把原图全分辨率解码进内存；HEIC 按原始字节导入，不经过 `.compatible` 转码。
- 自定义裁剪（`AppAppearanceCrop`）：全图 / 居中正方形 / 自定义边距（0–40%），裁剪矩形按真实像素尺寸计算并钳制；圆角预览滑块 0–27。
- 撤销（`AppAppearancePreviewHistory`）：每次离散修改入栈，连续输入（打字、拖滑块）不淹没历史；拖动滑块松手后才作为一次可撤销操作提交。
- 本地草稿（`AppAppearanceDraft`）：只保存在紫序自己的 Application Support 目录（`GestaltX/AppAppearance/Drafts/<bundleID>.plist`），PropertyList 原子写 + 回读校验；文件内含图片 SHA-256，篡改、改名冒用、损坏文件均被拒绝。
- `AppAppearanceProposal` 严格验证 Bundle ID 与名称（空白、超长、控制字符），`canApplyNatively` 固定为 false，新增 `capability` 固定为 `.unknown`（默认未知，永不默认可写）。
- 新增 XCTest：格式识别、校验五种失败、裁剪矩形、裁剪缩略图尺寸、撤销历史、草稿保存/读取/篡改拒绝、名称边界、能力默认未知；并修复了原测试中 `"WX\\nBad"` 的错误断言（字面反斜杠不是控制字符，应为真实换行）。
- 所有新增界面文案均走 `L()` 本地化（10 语种同步）。以上均须由真实 CI 编译、测试、真机 UI 检查后才能宣称通过。

## 已验证的不同技术路径
1. **启动快照**：已有 `LaunchArtworkFiles.swift` 访问 app 数据容器的 `Library/SplashBoard/Snapshots/<bundle> - {DEFAULT GROUP}`。这是启动过程中短暂出现的图片，不是主屏幕图标。
2. **主屏幕图标**：由 SpringBoard / IconServices 等管理，可能引用应用图标资源和系统缓存。缓存地址、权限、重建和系统版本均须真实验证；不要从 SplashBoard 可写推论其他缓存可写。
3. **名称**：可能来自 Bundle 的 `CFBundleDisplayName`、本地化资源以及 LaunchServices 的显示名数据库。已有 `GXLaunchServicesDatabase.m` 实现只读发现；不可把读取能力当成修改权限。
4. **越狱 Hook**：能够在具有代码注入权的越狱环境改变 SpringBoard 的图标渲染/名称返回值，但普通 iOS 27 不能自动获得该权限。
5. **官方 Alternate Icons**：应用自身才能调用 `setAlternateIconName`，不是对第三方 App 的通用修改 API。
6. **快捷方式**：可替代桌面入口的视觉效果，但不等同原生图标，不保证原生角标；只能明确标成替代方案。
7. **重签 IPA**：修改应用自身签名资源意味着身份/数据/权限变化。禁止以微信主号或已有用户数据作为实验对象。

## 开源项目研究矩阵（版本和许可按引入时重新核验）
| 项目 | 地址 | 当前仓库许可（核验时间 2026-11-14） | 研究用途 | 代码策略 |
| --- | --- | --- | --- | --- |
| GestaltX | https://github.com/huamidev/GestaltX | GPL-3.0 | 项目上游、MobileGestalt、备份 | 遵守版权与 GPL |
| Erosion-CN | https://github.com/Kianuni/Erosion-CN | GPL-3.0 | 安全写入、动态布局、诊断 | 审阅后独立合入 |
| MGKeys | https://github.com/PoomSmart/MGKeys | MIT | MobileGestalt 键名解码和映射 | 保留 MIT notices |
| WQFiles | https://github.com/kolbicz/WQFiles | GPL-3.0 | 系统文件发现/路径权限的研究 | 仅在证据确凿时使用 |
| LumenBoard | https://github.com/xsxs18-dev/LumenBoard | MIT | 越狱环境图标渲染思路 | 不承诺非越狱可用 |
| Rune | https://github.com/KrisButIAmAnOSDev/rune | MIT | SpringBoard Hook 对照 | 仅用于隔离实验环境 |
| WorkPlot | https://github.com/gievano/WorkPlot | GPL-3.0 | 预设与操作会话交互 | 以真实版本适配为限 |
| Gester | https://github.com/sasobhabha/Gester | MIT | 诊断与设备访问设计 | 隔离权限行为 |
| idevice | https://github.com/jkcoxson/idevice | MIT | 桌面端设备通信 | 后续独立模块 |
| pymobiledevice3 | https://github.com/doronz88/pymobiledevice3 | GPL-3.0 | 辅助诊断与测试工具 | 外部测试工具优先 |
| Nugget | https://github.com/leminlimez/Nugget | AGPL-3.0 | 只做设计/历史研究 | 不复制代码 |
| swift-snapshot-testing | https://github.com/pointfreeco/swift-snapshot-testing | MIT | SwiftUI 页面截图回归 | 可引入测试目标 |
| SwiftLint | https://github.com/realm/SwiftLint | MIT | 静态质量和复杂度 | 可引入 CI |

**许可证警示**：每个仓库须检查具体 commit、子目录和 vendored 代码的许可证，AGPL 不应未经合规审查混入 GPL 分发。图标/品牌资源另行核查商标和版权。

## 后续阶段与验收
- **Gate 0**：首先把原有 PR #2 的 ModifiedValues CI 修绿；比较修复提交与完整错误日志，严禁删测、静默跳过。
- **Gate 1**：保留本分支仅预览，不向用户显示假状态。新增静态架构报告：所有推断标明“推断”，缓存偏移未知写“未知”。完成 XCTest + IPA build + UI 真实验收。
- **Gate 2**：开发注入式 `AppAppearanceBackend` 协议：`inspect(bundleID)` 返回 `unavailable/unknown/readOnly/verifiedWritable` 与证据元数据，默认 unknown。具体系统路径只能由真实设备只读检测得出，硬编码与猜测一律禁止。
- **Gate 3**：研究读取（不写入）图标缓存及名称来源，设备、系统 build、inode、路径、权限和摘要必须可复核；任何读取失败不回退猜测。
- **Gate 4**：仅在合法、经用户许可的隔离测试设备上试验受控写入。强制来源可信的完整备份，原文件哈希/布局匹配，失败恢复和重启后重新读取；不可碰微信账号数据或系统关键路径，异常停机。
- **Gate 5**：在不同 iOS 27 build、国行和非国行、重启、应用更新及设备数据迁移下验证。无充分真实证据时不可称支持「原生微信图标/名称替换」。
- **Gate 6**：整合智能兼容性、设备识别、原生 AI 过滤、SafePatch diff、可信恢复时间线、预设数据库、故障诊断，并保持各模块隔离与 fail-closed。
- **Gate 7**：若上游 GestaltX 新版本有可核实提交，独立分支逐步迁移，确保 Bundle ID 和 App Group 一致，扫描器保持动态解析；铃声和配对分别做真机验收。

### UI 原则
- 与现有启动图编辑器明确隔离，不把启动快照当应用图标。
- 真值状态分为：未读取、不可访问、仅预览、已验证写入、重启后验证、未知。
- 所有高风险项有中文用途、风险、设备要求、前后值、备份证据和恢复方式。
- 支持系统深/浅色、VoiceOver、动态字体、加载、空状态、失败重试、搜索和无障碍标注。

### 交付与禁止事项
- 每个模块独立分支、Draft PR；`main`、旧正式版 Release、正式签名均保持不变。
- 不自动创建系统路径的写入 exploit，不注入未越狱系统，不绕过系统权限。
- 未通过真实 CI、模拟器测试、IPA 元数据核验及真机验收的功能不得宣传已完成。
- 必须注明代码版本、commit SHA、CI 运行 URL、通过/失败/跳过计数、已知风险、是否可恢复、许可证归属和回滚流程。
