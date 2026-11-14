from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]
TRANSLATIONS = '''
Save Current Launch Image	保存当前启动图
Allow LilaShift to add photos in Settings, then try again.	请在“设置”中允许 紫序 添加照片，然后重试。
The launch image was saved to Photos.	启动图已保存到相册。
App Launch Images	应用启动图
No Launch Images	暂无启动图
Only apps with readable launch images are listed. iOS may refresh these images.	仅显示能读取启动图的 App。iOS 可能会重新生成这些图片。
Choose Photo	选择照片
Shown briefly while the app opens. Close the selected app before applying.	仅在 App 启动时短暂显示。应用前请先关闭目标 App。
The original launch images will be backed up before applying.	应用前会备份原始启动图。
Only launch images changed by LilaShift will be restored.	仅还原由 紫序 修改的启动图。
Launch image saved. Close and reopen the app to see it.	启动图已保存，请关闭并重新打开该 App 查看。
Restored. Launch images refreshed by iOS were left unchanged.	已还原；iOS 重新生成的启动图保持不变。
No launch images found. Open the app once, close it, then read again.	未找到启动图。请先打开该 App 一次，关闭后重新读取。
The app was reinstalled. Its saved launch images cannot be restored.	该 App 已重新安装，无法还原之前保存的启动图。
This image could not be used. Choose another image.	无法使用这张图片，请选择其他图片。
Importing…	正在导入…
Share one file at a time.	一次仅分享一个文件。
Choose a MobileGestalt plist or a wallpaper pack.	请选择 MobileGestalt plist 或壁纸包。
Open LilaShift to confirm importing the wallpaper pack.	打开 紫序 以确认导入壁纸包。
Import this wallpaper pack? It will be added to Wallpaper Settings.	导入这个壁纸包？导入后将添加到“壁纸设置”。
A shared file is waiting. Save or discard your current changes, then import it.	有分享的文件等待导入，请先保存或放弃当前更改。
Import a .tendies or .zip wallpaper pack. You can also share it to LilaShift.	导入 .tendies 或 .zip 壁纸包，也可通过分享发送到 紫序。
Applied	已应用
Customization	个性化
Import Wallpaper	导入壁纸
No Wallpapers	暂无壁纸
This only deletes the imported pack from LilaShift. Applied wallpapers will be kept.	只从 紫序 删除导入包，已应用的壁纸会保留。
Open Wallpaper Gallery	打开壁纸图库
Delete the imported wallpaper pack?	删除导入的壁纸包？
Some files could not be restored. The backup has been kept.	部分文件未能恢复，备份已保留。
System Settings	系统设置
The app could not be opened. Open it manually.	未能打开应用，请手动打开。
The archive contains unsafe paths or links.	压缩包包含不安全的路径或链接。
The archive is invalid or exceeds the size limit.	压缩包无效或超过大小限制。
The device container could not be located. Read again.	未能定位设备容器，请重新读取。
The files changed. Read again before applying.	文件已变化，请重新读取后再应用。
The original files could not be backed up.	未能备份原始文件。
This adds new wallpapers without replacing your existing ones.	将添加新壁纸，保留现有壁纸。
This pack contains no compatible wallpapers.	此包中没有兼容的壁纸。
This wallpaper was changed outside LilaShift. It was not removed.	壁纸已被其他方式修改，未执行移除。
Wallpaper added. Open the wallpaper gallery to select it. If it does not appear, restart PosterBoard or respring.	壁纸已添加，请打开图库选择。若未出现，可重新启动 PosterBoard 或执行注销。
Wallpaper Settings	壁纸设置
WAPI	WAPI
Disable WAPI	关闭 WAPI
Disabling may show Wi-Fi and change some network options. Restart to apply.	关闭后可显示为 Wi-Fi，部分联网选项可能随之变化。重启后生效。
Restore Original	恢复原值
Special Thanks	特别鸣谢
Supported	支持
Unsupported	不支持
Welcome	欢迎
Welcome to LilaShift	欢迎使用 紫序
MobileGestalt Editor	MobileGestalt 编辑工具
Disclaimer	免责说明
I Understand, Continue	我已了解，继续
System access and available features vary by OS version, device and signing.	系统文件访问和功能可用性因系统版本、设备与签名而异。
Changing MobileGestalt may cause system instability, missing features or a boot loop. Recovering the device may require a restore.	修改 MobileGestalt 可能导致系统不稳定、功能异常或无法开机，严重时可能需要恢复设备。
Back up your device before making changes, and export a copy of the original plist.	修改前请备份设备，并导出一份原始 plist，请谨慎操作。
Capability flags cannot add missing hardware. Some changes require a device restart.	功能标记无法增加设备缺少的硬件，部分更改需要重新启动设备才能生效。
Use only devices you own or are authorized to manage. You are responsible for the changes you choose to apply.	仅在你拥有或获授权管理的设备上使用，并自行承担所选修改带来的风险。
This software is provided without warranty. Read the included license before use.	本软件不提供任何担保，使用前请阅读随附的开源许可证。
GitHub Repository	GitHub 仓库
Credits & Licenses	鸣谢与许可
License	许可证
Respring Technique	注销方法
Read Again	重新读取
A device restart may be required.	可能需要重新启动设备才能生效。
Restart the device after changing the region.	更改地区后需要重新启动设备。
Some changes require a device restart.	部分更改需要重新启动设备。
Restart required. Apple Intelligence also depends on device and region.	需要重新启动设备。Apple 智能还取决于机型与地区。
Restart the device, then reopen Settings. Pencil hardware support is still required.	重新启动设备后再打开“设置”，仍需要 Apple Pencil 硬件支持。
Respring first. Restart the device if the change does not appear.	先执行注销，若未生效则重新启动设备。
Write verified. Some features require a device restart.	写入已验证。部分功能需要重新启动设备才能生效。
Model	机型
Status	状态
Connected	已连接
Local File	本地文件
Not Loaded	未读取
Reading…	正在读取…
Read MobileGestalt	读取 MobileGestalt
Import Plist	导入 plist
Actions	操作
Apply Changes	应用更改
Respring Required	需要注销
Log	日志
Experimental settings. Back up before applying.	实验性设置，请在应用前备份。
No Backups	暂无备份
A backup is created before each write.	每次写入前会自动备份。
This will attempt to restart SpringBoard using NeoSpring.	将通过 NeoSpring 尝试重新启动 SpringBoard。
GitHub Projects	GitHub 项目
GNU GPL v3	GNU GPL v3
Date	日期
Enter an ISO 8601 date, such as 2026-11-09T12:00:00Z.	请输入 ISO 8601 日期，例如 2026-11-09T12:00:00Z。
Tools	工具
Backups	备份
About	关于
LilaShift	紫序
OK	好
Cancel	取消
Apply	应用
Done	完成
Close	关闭
More	更多
Ready	就绪
Enable	启用
Disable	停用
Disable (Restore Original)	停用（恢复原值）
Remove Added Fields	移除新增字段
Disabling restores the recorded original values. Use Remove Added Fields only for fields you know were originally absent.	停用会恢复已记录的原值。确认原本不存在的字段，才使用“移除新增字段”。
Original values could not be read. No system changes were made.	无法读取原值记录，未修改系统文件。
The original-value record belongs to a different device.	原值记录属于其他设备。
Original values could not be saved and verified. No system write was started.	无法保存并验证原值记录，未开始写入系统文件。
The selected added fields must be removed before applying.	请先移除选中的新增字段，再应用更改。
Device identity fields cannot be changed in the system plist. Open a local file to edit these fields.	不能更改系统 plist 中的设备身份字段。如需编辑这些字段，请打开本地文件。
Keep Current	保持当前值
Display	显示
Device	设备
iPad	iPad
Intelligence	Apple 智能与地区
Advanced	高级
String	字符串
Integer	整数
Real	浮点数
Boolean	布尔值
Data	数据
Array	数组
Dictionary	字典
Make your device your own.	让设备更合你意。
Capabilities	功能设置
Choose what to change.	选择你想调整的功能。
Connect or open a plist to start editing.	连接设备或打开 plist，开始编辑。
Quick Actions	快捷操作
Keep a copy. Refresh when ready.	先留一份备份，准备好后再刷新。
Back Up	备份
Export Plist	导出 plist
Respring	注销
Changes are verified. Respring when you are ready.	更改已验证，准备好后可执行注销。
Session Log	操作日志
Open Plist…	打开 plist…
Connect to Device	连接设备
Pending Changes	待应用更改
%lld fields changed	已更改 %lld 个字段
Review	查看更改
On Device	本机模式
Local Document	本地文稿
Your Device	你的设备
Not Connected	未连接
%lld fields	%lld 个字段
Live snapshot	当前快照
Open the system cache, or work with a plist from Files.	读取系统缓存，或编辑“文件”中的 plist。
Connecting…	正在连接…
Connect	连接
Open File	打开文件
Refresh	刷新
System-cache access depends on OS and signing. Upstream lists SystemGroup access for iOS 27; iOS 26 can use local files.	系统缓存的访问取决于系统版本与签名。上游仅列明 iOS 27 可访问 SystemGroup；iOS 26 可编辑本地文件。
Dynamic Island Layout	灵动岛布局
A different layout can affect the status bar and keyboard. Keep a backup.	更改布局可能影响状态栏与键盘，请保留备份。
Device Identity	设备标识
Change Model Name	更改机型名称
Model Name	机型名称
Sales Region	销售地区
Region Code	地区代码
Usually, changing the region code is enough. There is no need to change Sales Region.	通常只需修改地区代码，无需更改销售地区。
* If you previously changed Sales Region, restore your device's original sales region and apply it first.	* 之前修改过销售地区的用户，请先改回设备原本的销售地区并应用。
Changing the sales-region suffix may cause verification tools to report a mismatch with factory information.	更改销售地区后缀可能导致验机工具提示与出厂信息不匹配。
Changing a region flag does not guarantee Apple Intelligence or region-restricted services.	更改地区标记并不保证可用 Apple 智能或受地区限制的服务。
Experimental	实验性
Presets	预设
Selections are staged until you review and apply them. Capability flags do not add missing hardware.	所选更改会先暂存，查看后再统一应用。功能标记无法增加设备缺少的硬件。
iPadOS CacheData conversion is not enabled for these OS builds.	这些系统版本尚未开放 iPadOS CacheData 转换。
Unverified byte-offset patches are excluded. Use supported presets or inspect individual fields.	未接入未经验证的偏移补丁。你可以使用已有预设或查看具体字段。
Review Changes	查看更改
No Document Open	尚未打开文稿
Connect or open a plist in Tools to browse its fields.	在“工具”中连接设备或打开 plist，即可查看字段。
%lld bytes	%lld 字节
Raw system fields. Review the key and type before saving.	这里是原始系统字段，保存前请核对键名与类型。
Search keys and values	搜索键名与值
Add Field	添加字段
Delete	删除
Delete this field?	删除这个字段？
The deletion is staged. The device file changes only after you apply.	删除操作会先暂存，应用后才会修改设备文件。
Key	键名
Field Key	字段键名
Value	值
Type	类型
Use an XML plist fragment, including the array or dict tags. Nested data and numeric types are preserved.	请输入包含 array 或 dict 标签的 XML plist 片段。嵌套的数据与数字类型会被保留。
Data values use Base64 encoding.	数据值使用 Base64 编码。
Edit Field	编辑字段
Stage	暂存
Write to this device	写入本机
Save local document	保存本地文稿
A backup is created before writing. The result is read back and compared.	写入前会创建备份，写入后会回读并比较内容。
This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed.	仅编辑 紫序 中打开的文件。请导出以保存副本，系统文件不会被修改。
Apply to Device	应用到设备
Save Local Changes	保存本地更改
Discard Changes	放弃更改
Apply these changes?	应用这些更改？
Incorrect system values can affect device behavior. A verified backup will be kept. No respring is triggered automatically.	错误的系统值可能影响设备运行。应用会保留经过验证的备份，且不会自动执行注销。
The current local document will be backed up before saving your edits.	保存更改前会先备份当前本地文稿。
Before	更改前
After	更改后
Not present	不存在
Create Backup	创建备份
Device backups stay linked to this installation. Imported files are kept separate.	本机备份与本次安装关联，导入文件的备份会单独保存。
Your Safety Net	多一份保障
Backups appear here before each write. You can also make one anytime.	每次写入前会自动备份，你也可以随时手动备份。
Device Backup	本机备份
Local File Backup	本地文件备份
Open	打开
Export	导出
Restore	恢复
Initial backup	首次备份
Original values snapshot	修改前原值快照
Revert	还原
Original values restored.	已还原原值。
Restore this backup?	恢复这个备份？
The current document is backed up first. Device restores are verified after writing.	会先备份当前文稿。本机恢复会在写入后进行验证。
Delete this backup?	删除这个备份？
This removes the local backup permanently. It does not change the device file.	本地备份将被永久删除，设备文件不会被修改。
No activity yet.	暂无操作记录。
Clear	清空
Respring now?	立即注销？
NeoSpring will attempt to restart SpringBoard. Save your work first. It may not work on every OS build.	NeoSpring 将尝试重新启动 SpringBoard，请先保存其他应用中的工作。部分系统版本可能不适用。
Dynamic Island, Always-On and Liquid Glass	灵动岛、全天候显示与液态玻璃
Charging, buttons and device identity	充电、按键与设备标识
Stage Manager and app compatibility	台前调度与应用兼容性
Region and generative model capabilities	地区与生成式模型功能
Internal features and research settings	内部功能与研究设置
Dynamic Island	灵动岛
Enable the alternate Dynamic Island capability.	启用备用灵动岛功能标记。
Always-On Display	全天候显示
AOD Vibrancy	全天候显示色彩
Adjust Always-On rendering capabilities.	调整全天候显示的渲染功能标记。
Liquid Glass Low-Power Rendering	液态玻璃低性能渲染
Boot & Shutdown Chime	开关机提示音
Expose the startup and shutdown sound capability.	显示开关机提示音功能。
Charge Limit	充电上限
Tap to Wake	轻点唤醒
Camera Control	相机控制
Action Button	操作按钮
Show the Action Button settings page.	显示操作按钮设置页面。
Apple Pencil	Apple Pencil
Stage Manager	台前调度
iPad App Compatibility	iPad 应用兼容性
Allow iPad app compatibility types on iPhone.	允许 iPhone 使用 iPad 应用兼容类型。
Apple Intelligence Capability	Apple 智能
Apple Internal Features	Apple 内部功能
Internal Storage View	内部存储视图
Show internal storage categories. Experimental on iPad.	显示内部存储分类，在 iPad 上属于实验性功能。
Security Research Device	安全研究设备
United States	美国
Hong Kong	中国香港
Japan	日本
China (Mainland)	中国大陆
Taiwan	中国台湾
United Kingdom	英国
Connect to your device or open a plist.	连接设备或打开 plist。
Checking device access…	正在检查设备访问权限…
Device connected	设备已连接
Device access unavailable	无法访问设备
Local file opened	已打开本地文件
Changes verified on device	本机更改已验证
Local changes saved	本地更改已保存
Changes verified on device. Respring to refresh supported features.	本机更改已验证，可执行注销以刷新受支持的功能。
Local changes saved. Export the plist to keep a copy.	本地更改已保存，请导出 plist 以保留副本。
Backup saved	备份已保存
Backup restored and verified.	备份已恢复并通过验证。
This backup already matches the device. No changes were made.	此备份已与设备一致，未作任何更改。
Backup opened as a local document.	已将备份打开为本地文稿。
Manual backup	手动备份
Before editing	编辑前备份
Before applying	应用前备份
Before restoring	恢复前备份
Enter a valid whole number.	请输入有效的整数。
Enter a finite decimal number.	请输入有限的十进制数。
Use true or false for a Boolean value.	布尔值请输入 true 或 false。
Enter valid Base64 data.	请输入有效的 Base64 数据。
Enter an XML plist array or dictionary fragment.	请输入有效的 XML plist 数组或字典片段。
Choose a MobileGestalt plist with a CacheExtra dictionary.	请选择包含 CacheExtra 字典的 MobileGestalt plist。
The edited document is not a valid property list.	编辑后的文稿不是有效的属性列表。
MobileGestalt access was denied. Check the OS version and App Group signing.	MobileGestalt 访问被拒绝，请检查系统版本与 App Group 签名。
The backup could not be verified. No system write was started.	备份验证失败，未开始写入系统文件。
This backup does not belong to this device. Open it as a local file instead.	此备份不属于当前设备，请将其作为本地文件打开。
MobileGestalt changed since it was loaded. Refresh before applying your edits.	MobileGestalt 已在加载后发生变化，请刷新后再应用更改。
The write did not match the readback.	写入内容与回读结果不一致。
The original file could not be restored.	无法恢复原始文件。
Write verification and recovery failed. Keep the backup and recover the device file before trying again.	写入验证与恢复均失败。请保留备份，恢复设备文件后再尝试。
The write failed. The previous file was restored and verified.	写入失败，之前的文件已恢复并通过验证。
Device access is unavailable in the Simulator. Open a plist to explore LilaShift.	模拟器无法访问设备文件，你可以打开 plist 体验 紫序。
The signed app has no usable App Group. Enable its App Group capability and sign it again.	当前签名没有可用的 App Group，请启用对应能力后重新签名。
Choose a plist smaller than 16 MB.	请选择小于 16 MB 的 plist。
Enter a field key.	请输入字段键名。
Load a document first.	请先加载文稿。
That key already exists. Edit the existing field instead.	此键名已存在，请直接编辑已有字段。
Enter a model name before applying.	请先输入机型名称再应用。
A little more possibility.	多一点可能。
More Projects by huamidev	huamidev 的更多项目
Supported OS	支持系统
Languages	语言
Compatibility	兼容性
Credits	鸣谢
worse_query sandbox escape	worse_query 沙盒逃逸原语
Original WebKit respring technique	原始 WebKit 注销方法
Swift implementation of the respring technique	注销方法的 Swift 实现
NeoSpring project and respring research	NeoSpring 项目与注销研究
GPL-licensed respring adaptation	采用 GPL 许可的注销适配实现
MobileGestalt key research	MobileGestalt 键名研究
MobileGestalt preset research	MobileGestalt 预设研究
MobileGestalt workflow reference	MobileGestalt 工作流参考
Open Source	开源许可
Third-Party Notices	第三方声明
LilaShift is independent software. It is not affiliated with Apple or the credited projects.	紫序 是独立软件，与 Apple 及鸣谢项目没有隶属关系。
worse_query	worse_query
Available paths and MobileGestalt presets vary by device and OS build.	可访问的路径及 MobileGestalt 预设因设备与系统版本而异。
Read Upstream Compatibility	查看上游兼容性说明
MobileGestalt Access	MobileGestalt 访问
iOS 27: access is checked on the device.	iOS 27：通过本机实际探测访问权限。
iOS 26: SystemGroup access is not claimed by upstream. Local plist editing is available.	iOS 26：上游未声明支持 SystemGroup 访问，可编辑本地 plist。
A correctly provisioned App Group is required. Export and backup are available for any document you can open.	需要正确配置并签名 App Group。能够打开的文稿均可导出与备份。
NeoSpring	NeoSpring
NeoSpring attempts a SpringBoard refresh using WebKit. Its effectiveness varies by OS build. Some MobileGestalt changes may still need a manual device restart.	NeoSpring 使用 WebKit 尝试刷新 SpringBoard，效果因系统版本而异。部分 MobileGestalt 更改仍可能需要手动重新启动设备。
License text could not be loaded.	无法加载许可文本。
Respring did not finish.	注销未完成。
Refreshing SpringBoard…	正在刷新 SpringBoard…
This OS build may not support the technique. You can close this screen and try a manual restart later.	当前系统版本可能不支持此方法。你可以关闭此页面，稍后手动重新启动设备。
Your device may briefly return to the Lock Screen.	设备可能会短暂返回锁定屏幕。
The cache layout or values do not match this preset.	缓存布局或数值与此预设不符。
The original value belongs to a different cache layout. A matching backup is needed to restore it.	原值属于不同的缓存布局，需要匹配的备份才能恢复。
This preset changes unrelated cache bytes.	此预设更改了无关的缓存字节。
Unable to resolve this device's MobileGestalt cache layout.	无法解析此设备的 MobileGestalt 缓存布局。
Importing Plist…	正在导入 plist…
Share one MobileGestalt plist at a time.	请每次分享一个 MobileGestalt plist 文件。
Sign LilaShift and its share extension with the same App Group, then try again.	请为 紫序 和分享扩展签入同一个 App Group 后重试。
The shared plist could not be read. Share it again.	无法读取分享的 plist，请重新分享。
A shared plist is waiting. Save or discard your current changes, then import it.	有分享的 plist 等待导入，请先保存或放弃当前更改。
Save or discard your current changes before opening another plist.	请先保存或放弃当前更改，再打开另一个 plist。
Import	导入
Open LilaShift to confirm importing the plist.	请打开 紫序 确认导入 plist。
This device's identity could not be verified. Read MobileGestalt on this device and try sharing again.	无法核验本机身份，请先读取本机 MobileGestalt 后重新分享。
This plist belongs to another device and cannot be imported.	此 plist 的设备标识与本机不符，无法导入。
This plist does not contain enough device identifiers to verify ownership.	此 plist 缺少足够的设备标识，无法确认属于本机。
Additional Options	附加选项
MG Control	MG 控制
Read MobileGestalt in Tools, or share this device's plist to LilaShift.	在工具中读取 MobileGestalt，或将本机 plist 分享到 紫序。
This plist has been verified for this device. Import it?	已核验此 plist 属于本机，是否导入？
This plist's device proof could not be verified on this device.	无法在本机验证此 plist 的设备凭证。
The device proof is temporarily unavailable. Unlock this device and try again.	设备凭证暂时不可用。请解锁此设备后重试。
This plist uses a different system cache layout and cannot be restored.	此 plist 的系统缓存布局与本机不符，无法恢复。
Restore Imported Plist	恢复导入的 plist
The current device file will be backed up before restoring. Restart the device afterward.	恢复前会备份当前设备文件，完成后请重启设备。
Share this device's plist to LilaShift to edit its keys and values or restore a verified backup. Export a copy from LilaShift first to keep a device-bound proof.	现在可将本机 plist 分享到 紫序，核验后导入、增删改键值并恢复。建议先从 紫序 导出一份带本机校验凭证的备份。
Canada	加拿大
Model Number	型号号码
A device restart may be required after changing the model number.	修改型号号码后可能需要重启设备。
Listed values apply to iPhone Air, iPhone 18 Pro and iPhone 18 Pro Max only. Choosing a model number that does not match your hardware can make verification tools report a mismatch.	以下号码仅适用于 iPhone Air、iPhone 18 Pro 和 iPhone 18 Pro Max。选择与硬件不符的号码，可能导致验机工具报告不匹配。
A3260 — Air · United States / Canada	A3260 — Air · 美国／加拿大
A3516 — Air · Japan	A3516 — Air · 日本
A3517 — Air · Other regions	A3517 — Air · 其他地区
A3518 — Air · China mainland	A3518 — Air · 中国大陆
A3472 — 18 Pro · United States	A3472 — 18 Pro · 美国
A3713 — 18 Pro · Canada / Japan	A3713 — 18 Pro · 加拿大／日本
A3714 — 18 Pro · Other regions	A3714 — 18 Pro · 其他地区
A3715 — 18 Pro · China mainland	A3715 — 18 Pro · 中国大陆
A3473 — 18 Pro Max · United States	A3473 — 18 Pro Max · 美国
A3716 — 18 Pro Max · Canada / Japan	A3716 — 18 Pro Max · 加拿大／日本
A3717 — 18 Pro Max · Other regions	A3717 — 18 Pro Max · 其他地区
A3718 — 18 Pro Max · China mainland	A3718 — 18 Pro Max · 中国大陆
The artwork field is not a dictionary. Edit it in MG Control before using these presets.	artwork 字段不是字典，请先在 MG 控制中编辑此字段，再使用这些预设。
High-Luminance Always-On Display	高亮度始终显示
Allow Always-On Display to reach a higher brightness level.	允许“始终显示”达到更高亮度。
Always-On Display Flipbook	始终显示翻页组件
Enable AOD flipbook widgets on the Lock Screen.	在锁屏上启用 AOD 翻页小组件。
AOD Flipbook Count	AOD 翻页数量
Disable Wallpaper Parallax	关闭壁纸视差
Stop the wallpaper from moving with device motion.	停止壁纸随设备移动产生位移。
HDR Photo Display	HDR 照片显示
Enable true HDR rendering for photos.	为照片启用真正的 HDR 渲染。
Pulse Width Modulation	脉宽调制 (PWM)
DisplayPort Output	DisplayPort 输出
Collision SOS	车祸检测 SOS
Audio Mix	音频混音
Enable the audio mix capability for supported media.	为支持的媒体启用音频混音能力。
Spatial FaceTime Audio	FaceTime 空间音频
Enable spatial audio playback for FaceTime.	为 FaceTime 启用空间音频播放。
Internal Settings Bundle	内部设置包
On-Device Siri	端侧 Siri
Audio Intelligence	音频智能
Advertise the iOS 27 audio intelligence capability.	启用音频智能功能。
Personal Translator	个人翻译
Advertise the personal translator capability.	用于支持的翻译场景，让系统识别设备具备个人翻译能力。
Photos Clean Up	照片消除
Advertise the photos inpainting (Clean Up) capability.	用于在“照片”里移除画面中的干扰物。
Handwriting Synthesis	手写合成
Advertise the handwriting synthesis model capability.	用于生成手写笔迹。
Always-Listening Hey Siri	常听 Hey Siri
Advertise always-listening Hey Siri support.	让支持的设备监听“嘿 Siri”唤醒语。
Internal Build	内部构建
Enable Internal Build?	启用内部构建？
This stages the system-wide InternalBuild flag. It can affect system services beyond the storage screen. You can review the change before applying it.	这会暂存系统全局的 InternalBuild 标记变更。它可能影响存储页面以外的系统服务。你可以在应用前检查这项变更。
Lock Screen Text	锁屏底部文字
Add your own text at the bottom of the Lock Screen.	在锁屏底部显示自定义文字。
System Default	系统默认
Empty	空
Current Value	当前值
Unavailable	无法访问
Your lock screen text	输入锁屏文字
Original values are saved before writing. Revert removes keys that were originally absent.	写入前会保存原值，原本不存在的键会在还原时移除。
The affected settings files will be backed up before writing. You can restore each option afterward.	写入前会备份相关设置文件，之后可逐项还原。
The system settings file is not a valid dictionary.	系统设置文件不是有效的字典，已停止操作。
System settings changed. Read them again before applying.	系统设置已发生变化，请重新读取后再应用。
Use a single line of up to 256 characters.	请输入单行文字，最多 256 个字符。
The settings backup could not be verified. No changes were applied.	无法验证设置备份，未应用任何更改。
System settings could not be verified after writing.	写入后无法验证系统设置。
Some settings could not be restored automatically. Read them again and use Revert.	部分设置未能自动恢复，请重新读取并使用“还原”。
These system settings are not accessible on this device.	当前设备无法访问这些系统设置。
Lock screen text updated.	锁屏文字已更新。
China Unlock	国行一键解锁
One-Tap Restore	一键还原
One-Tap Unlock	一键解锁
China AI	国行 AI
Enable the six Apple Intelligence features on a China-model iPhone.	在国行 iPhone 上启用 6 项 Apple 智能功能。
Enable China AI	启用国行 AI
Restore AI	还原 AI
eSIM & Region	eSIM 与地区
Enable eSIM and set the region code to US (LL).	启用 eSIM，并将地区代码设为美国 (LL)。
Enable eSIM & Region	启用 eSIM 与地区
Restore eSIM & Region	还原 eSIM 与地区
Modified Values	已修改的值
Fields whose current value differs from the recorded original.	当前值与已记录原始值不同的字段。
Read the device first to see modified values.	请先读取本机数据，再查看已修改的值。
No recorded originals. Whether anything was modified cannot be determined.	没有已记录的原始值，无法判断是否修改过。
Only changes with a recorded original are listed.	仅列出有已记录原始值的改动。
No modifications found	未发现修改
Modified %d fields	已修改 %d 项
Not set	未设定
Regulatory Model	监管型号
Product Type	产品类型
eSIM (green-tea)	eSIM（green-tea）
eSIM (not-green-tea)	eSIM（not-green-tea）
Device Information	设备信息
Included AI Features	查看包含的 AI 功能
Review the changes, apply them, then restart the device.	先查看并应用更改，然后重启设备。
Read Device	读取本机
Read the device before choosing a preset.	读取本机后即可选择预设。
Configured	已配置
Not Configured	未配置
eSIM settings are unavailable. You can still configure region and AI under Intelligence.	无法读取 eSIM 配置。仍可在“Apple 智能与地区”中单独设置地区代码和 AI。
Import and apply wallpaper packs.	导入并应用壁纸包。
Change the image shown when an app opens.	更换 App 打开时短暂显示的图片。
Technical Details	技术详情
Other Fields	其他字段
Advanced & Diagnostics	高级与诊断
After applying, restart, then check the related entries in system Settings.	应用后请重启设备，再到系统“设置”查看相关入口。
Apple Intelligence	Apple 智能
Apple Intelligence & Region	Apple 智能与地区
Back to adjust	返回调整
Charge limit, tap to wake	充电上限、轻点唤醒
Charging & Buttons	充电与按键
Charging limits, buttons and alerts.	充电上限、按键与提醒。
Check which settings this will update.	检查这次操作会更新哪些设置。
Configure 6 items	将配置 6 项
Confirm Changes	确认更改
Device identity, internal features and diagnostics.	设备标识、内部功能与诊断。
Diagnostics	诊断
Digital SIM	数字 SIM
Digital SIM, Wi-Fi options	数字 SIM、Wi-Fi 选项
Display Effects	画面效果
Dynamic Island, Always-On Display	灵动岛、全天候显示
Feature Categories	功能分类
Internal Features	内部功能
Lock Screen Display	锁屏显示
Lock screen display, screen brightness and display effects.	锁屏显示、屏幕亮度与画面效果。
Model, sales region, run log	型号、销售地区、运行日志
More options	更多选项
Multitasking	多任务
Network & eSIM	网络与 eSIM
Not read yet	尚未读取
Pending	待应用
Personalization	个性化
Read MobileGestalt first.	请先读取 MobileGestalt。
Region	地区
Region code and Apple Intelligence features.	地区代码与 Apple 智能功能。
Region code, translation and Clean Up	地区代码、翻译与消除
Screen & Lock Screen	屏幕与锁屏
Set up eSIM, region code and Apple Intelligence in one tap.	一次配置 eSIM、地区代码和 Apple 智能。
Share Log	分享日志
Stage Manager, Apple Pencil	台前调度、Apple Pencil
View %lld pending changes	查看 %lld 项待应用更改
Wallpapers, Lock Screen text and app launch images.	壁纸、锁屏文字与应用启动图。
Wallpapers, Lock Screen text, launch images	壁纸、锁屏文字、启动图
Wi-Fi & Calls	Wi-Fi 与通话
Will configure	将配置
eSIM options, WAPI and call audio.	eSIM 选项、WAPI 与通话音频。
iPad & Multitasking	iPad 与多任务
iPad features on iPhone.	在 iPhone 上使用 iPad 功能。
Restore pre-unlock state	还原解锁前状态
Latest backup	最新备份
A backup is created before writing.	写入前会创建备份。
Tools LilaShift	工具 紫序
Author @steam8871	作者 @steam8871
Data read from this device	已读取本机数据
Open Source & Acknowledgements	开源与鸣谢
Original Project	原项目
Original Author	原项目作者
Enhanced Version Maintainer	国行增强版维护
Open Source License	开源许可证
Original Project URL	原项目地址
Enhanced Source URL	增强版源码地址
Source Code	源代码
The enhanced version is distributed under the GNU GPL v3.0. Its complete source is distributed with the release as the pristine v1.0.7 source plus the modification patch.	增强版遵循 GNU GPL v3.0 发布。完整源代码随发布一同提供，即官方 v1.0.7 原始源码加修改补丁。
Reading device data…	读取本机数据...
Reading related settings…	正在读取相关配置...
Write	写入
Verify	校验
Apply Progress (Writing %lld/4)	应用进度（正在写入中 %lld/4）
Apply Progress (Done %lld/4)	应用进度（已完成 %lld/4）
Keep the Lock Screen visible while the display is off.	屏幕关闭后仍显示锁屏内容。
Set how many AOD flipbook entries are allowed.	设置允许的 AOD 翻页条目数量。
Advertise PWM display support.	声明支持 PWM 调光。
Advertise DisplayPort output support.	声明支持 DisplayPort 输出。
Use low-power Liquid Glass rendering.	使用低功耗液态玻璃渲染。
Show charging limit settings.	显示充电上限设置。
Expose tap-to-wake.	显示轻点唤醒选项。
Show Camera Control settings.	显示相机控制设置。
Show collision detection in Emergency SOS settings.	在“紧急 SOS”设置中显示车祸检测。
Expose Apple Pencil settings.	显示 Apple Pencil 设置。
Expose Stage Manager support.	显示台前调度功能。
Enable Apple Intelligence generative models.	启用 Apple 智能生成式模型。
Run Siri processing on the device.	在设备端处理 Siri 请求。
Expose internal menus.	显示内部菜单。
Mark the device as an internal build.	将设备标记为内部版本。
Change the Security Research Device capability flag.	更改安全研究设备功能标记。
Expose Apple's internal settings bundle.	显示 Apple 内部设置包。
Respring first. Restart the device if the change does not appear. Display behavior depends on the panel and may increase power use and burn-in risk.	先执行注销，若未生效则重新启动设备。显示效果取决于屏幕面板，可能增加耗电与烧屏风险。
A device restart may be required. Experimental; the accepted range varies by iOS build.	可能需要重新启动设备才能生效。实验性功能，可用范围因系统版本而异。
A device restart may be required. Actual dimming behavior depends on the panel.	可能需要重新启动设备才能生效。实际调光行为取决于屏幕面板。
A device restart may be required. Compatible hardware is still required.	可能需要重新启动设备才能生效。仍需要兼容硬件。
Respring first. Restart the device if the change does not appear. Requires iOS 26 or later.	先执行注销，若未生效则重新启动设备。需要 iOS 26 或更高版本。
A device restart may be required. Actual charging control depends on hardware.	可能需要重新启动设备才能生效。实际充电控制仍取决于硬件。
A device restart may be required. Only shown on devices where tap-to-wake is hidden.	可能需要重新启动设备才能生效。仅在隐藏轻点唤醒的设备上显示。
A device restart may be required. This does not add a physical button.	可能需要重新启动设备才能生效。此操作不会为设备增加实体按钮。
A device restart may be required. Hardware support is still required.	可能需要重新启动设备才能生效。仍需要硬件支持。
A device restart may be required. Layout behavior varies by device.	可能需要重新启动设备才能生效。布局效果因设备而异。
Restart required. Siri uses a device-specific capability type; changing it may affect the Apple Intelligence Siri interface. Keep the current value or restore the recorded original.	需要重新启动设备。Siri 使用机型相关的能力类型，修改此类型可能影响 Apple 智能 Siri 界面，请保持当前值或还原已记录的原始值。
Restart required. Apple Intelligence also depends on device and region. Results depend on the app and system support.	需要重新启动设备。Apple 智能还取决于机型与地区。效果取决于 App 和系统支持。
A device restart may be required. Some system services may behave differently.	可能需要重新启动设备才能生效。部分系统服务的行为可能发生变化。
A device restart may be required. This changes the system-wide InternalBuild flag, not just storage information. System services may behave differently. Revert restores the recorded original value.	可能需要重新启动设备才能生效。此操作修改系统全局的 InternalBuild 标记，并非仅调整存储信息。系统服务的行为可能发生变化。“还原”会恢复已记录的原始值。
A device restart may be required. This does not turn the device into an Apple SRD.	可能需要重新启动设备才能生效。此操作不会将设备变成 Apple 官方安全研究设备。
Choose the Dynamic Island layout size.	选择灵动岛布局尺寸。
Set the device region code for region-locked features.	设置设备地区代码，用于解锁地区限定功能。
Set the sales-region suffix of the device model.	设置机型型号的销售地区后缀。
Change the reported device model number.	更改设备上报的机型号。
Change the device model name shown by the system.	更改系统显示的设备机型名称。
Enable or disable the eSIM-related system options.	启用或停用与 eSIM 相关的系统选项。
Use the WAPI wireless security standard.	使用 WAPI 无线安全标准。
Add a digital SIM in Settings.	在“设置”中添加数字 SIM。
eSIM requires eSIM hardware.	需要设备具备 eSIM 硬件。
Enable six Apple Intelligence features, including translation, Clean Up and always-listening Hey Siri.	启用 6 项 Apple 智能功能，包括翻译、照片消除和常听 Hey Siri。
CacheData[0x%X] · slot %d	CacheData[0x%X] · 槽位 %d
Other CacheData bytes changed	其他 CacheData 字节已更改
Unrelated cache bytes changed — apply will be refused.	存在无关缓存字节更改，将拒绝应用。
No US regulatory model known for this device — region code only.	未知此设备的美国监管型号，仅使用地区代码。
Apple Intelligence readiness	Apple 智能就绪检查
Ready %d/4	就绪 %d/4
Live status unknown	本机状态未知
Fix	修复
Regulatory model (factory model kept)	监管型号（保留出厂型号）
eSIM gate and conflicts	eSIM 门控与冲突
On-device AI eligibility	本机 AI 资格
Native Apple Intelligence hardware	原生 Apple 智能硬件
Personal Translator slot is off on a native-AI iPhone — Photos Clean Up and Camera Siri may fail.	个人翻译槽位在原生 Apple 智能 iPhone 上处于关闭状态，照片消除与相机 Siri 可能失效。
Audio Intelligence slot is on — Photos high-quality Clean Up may fail.	音频智能槽位处于开启状态，照片高质量消除可能失败。
Personal Translator CacheData slot #%d reads 0 on a native-AI iPhone — its native baseline is 1. Photos Clean Up and Camera Siri may fail.	原生 AI iPhone 上个人翻译 CacheData 槽位 #%d 读数为 0，原生基线为 1。照片消除与相机 Siri 可能失败。
Audio Intelligence CacheData slot #%d reads 1 — its native baseline is 0. Photos high-quality Clean Up may fail.	音频智能 CacheData 槽位 #%d 读数为 1，原生基线为 0。照片高质量消除可能失败。
Audio Intelligence CacheData slot reads 1 — its native baseline is 0. Photos high-quality Clean Up may fail.	音频智能 CacheData 槽位读数为 1，原生基线为 0。照片高质量消除可能失败。
Audio Intelligence CacheData slot #%d reads 1, but its native baseline is 0. Repair the slot to 0 before staging Audio Intelligence.	音频智能 CacheData 槽位 #%d 读数为 1，但其原生基线为 0。请先将槽位修复为 0，再暂存音频智能。
Audio Intelligence CacheData slot reads 1, but its native baseline is 0. Repair the slot to 0 before staging Audio Intelligence.	音频智能 CacheData 槽位读数为 1，但其原生基线为 0。请先将槽位修复为 0，再暂存音频智能。
Personal Translator CacheData slot #%d reads 0, but its native baseline on a native-AI iPhone is 1. Repair the slot to 1 before staging.	个人翻译 CacheData 槽位 #%d 读数为 0，但其在原生 AI iPhone 上的原生基线为 1。请先将槽位修复为 1，再暂存。
Personal Translator CacheData slot reads 0, but its native baseline on a native-AI iPhone is 1. Repair the slot to 1 before staging.	个人翻译 CacheData 槽位读数为 0，但其在原生 AI iPhone 上的原生基线为 1。请先将槽位修复为 1，再暂存。
Personal Translator CacheExtra key is explicitly 0 on a native-AI iPhone, but its native CacheData slot baseline is 1. Restore the CacheExtra key before staging.	原生 AI iPhone 上个人翻译 CacheExtra 键明确为 0，但其原生 CacheData 槽位基线为 1。请先恢复 CacheExtra 键，再暂存。
Audio Intelligence CacheData slot did not resolve, so its native baseline cannot be verified. Auto-staging is refused until the slot is verified on-device.	音频智能 CacheData 槽位未能解析，无法验证其原生基线。在真机上验证槽位之前，拒绝自动暂存。
Personal Translator CacheData slot did not resolve, so its native baseline cannot be verified. Auto-staging is refused until the slot is verified on-device.	个人翻译 CacheData 槽位未能解析，无法验证其原生基线。在真机上验证槽位之前，拒绝自动暂存。
CacheExtra audioIntelligence is staged as 1 while CacheData slot #%d reads its native 0. Whether the CacheExtra key alone is safe on native-AI hardware is unverified — confirm explicitly before staging.	CacheExtra audioIntelligence 已暂存为 1，而 CacheData 槽位 #%d 读数为原生 0。仅 CacheExtra 键在原生 AI 硬件上是否安全尚未验证——暂存前请明确确认。
CacheExtra audioIntelligence is staged as 1 while its CacheData slot reads its native 0. Whether the CacheExtra key alone is safe on native-AI hardware is unverified — confirm explicitly before staging.	CacheExtra audioIntelligence 已暂存为 1，而其 CacheData 槽位读数为原生 0。仅 CacheExtra 键在原生 AI 硬件上是否安全尚未验证——暂存前请明确确认。
The live probe reports Apple Intelligence off on this native-AI iPhone, which conflicts with staging AI capabilities. Confirm explicitly before staging.	实时检测报告此原生 AI iPhone 的 Apple 智能为关闭，与暂存 AI 能力冲突。暂存前请明确确认。
Audio Intelligence CacheData slot #%d reads 1, but the recorded iPhone/iPad baseline is 0. This hardware has no native-AI baseline — confirm explicitly before staging.	音频智能 CacheData 槽位 #%d 读数为 1，但记录的 iPhone/iPad 基线为 0。此硬件没有原生 AI 基线——暂存前请明确确认。
Audio Intelligence CacheData slot reads 1, but the recorded iPhone/iPad baseline is 0. This hardware has no native-AI baseline — confirm explicitly before staging.	音频智能 CacheData 槽位读数为 1，但记录的 iPhone/iPad 基线为 0。此硬件没有原生 AI 基线——暂存前请明确确认。
CacheData slots match their native baselines; staging is verified-safe.	CacheData 槽位与原生基线一致，暂存已验证安全。
No native-AI baseline applies to this hardware; the unlock enables AI capabilities.	此硬件不适用原生 AI 基线；一键解锁将启用 AI 能力。
Unverified combination explicitly confirmed by the user; staging proceeds.	用户已明确确认该未验证组合，继续暂存。
Verified factory backup	已验证的出厂备份
First-read device state	首次读取的设备状态
State before change	修改前的状态
Imported backup	导入的备份
Unknown source	来源未知
Personal Translator CacheExtra key is explicitly 0 on a native-AI iPhone — its native CacheData slot baseline is 1. Photos Clean Up and Camera Siri may fail.	个人翻译 CacheExtra 键在原生 AI iPhone 上明确为 0——其原生 CacheData 槽位基线为 1。照片消除与相机 Siri 可能失效。
Personal Translator is off on a native-AI iPhone — its CacheData slot reads 0. Photos Clean Up and Camera Siri may fail.	个人翻译在原生 AI iPhone 上处于关闭状态——其 CacheData 槽位读数为 0。照片消除与相机 Siri 可能失效。
Restart required. Apple Intelligence also depends on device and region. This stages the CacheExtra key; the CacheData slot is a separate value.	需要重启。Apple 智能还取决于设备与地区。此操作暂存 CacheExtra 键；CacheData 槽位是另一个独立值。
Restart required. Apple Intelligence also depends on device and region. The exact entry point depends on the device and OS version. This stages the CacheExtra key; the CacheData slot is a separate value.	需要重启。Apple 智能还取决于设备与地区。具体入口取决于设备与系统版本。此操作暂存 CacheExtra 键；CacheData 槽位是另一个独立值。
Live probe: on	实时探针：开启
Live probe: off — restart to apply	实时探针：关闭 — 重启后生效
%d steps, %d blockers	共 %d 步，%d 个阻止项
A precise restore cannot be guaranteed without a trusted backup. Use read-only diagnostics or import a backup instead.	没有可信备份，无法保证精确恢复。请改用只读诊断或导入备份。
A simulation passing does not mean the system will take effect. Real-device verification after a restart is still required.	模拟通过并不代表系统一定会生效。仍需在重启后于真机上验证。
A trusted backup exists for restore.	已有可信备份可用于恢复。
A trusted original is available for this change.	此更改有可信的原值可用。
AI Only	仅 AI
All preset dependencies are satisfied.	所有预设依赖均已满足。
Backup Verification	备份验证
Backup and restore prerequisites	备份与恢复的前提条件
Backup file not found.	未找到备份文件。
Blocked	已阻止
Blocked by a pre-check.	被前置检查阻止。
Cache layout is resolved from the device's own library, never selected by model or OS.	缓存布局取自设备自身的系统库，从不按机型或系统版本推测。
CacheData slot #%d reads back at its native baseline — this verifies the slot value, not the feature itself.	CacheData 槽位 #%d 回读值为原生基线——这仅验证槽位值，不验证功能本身。
CacheData slots #%d/#%d read back as staged — this verifies the flags, not eSIM hardware.	CacheData 槽位 #%d/#%d 回读值与暂存一致——这仅验证标志位，不验证 eSIM 硬件。
CacheExtra key %@ reads back as staged — this verifies the staged flag, not the underlying hardware or service.	CacheExtra 键 %@ 回读值与暂存一致——这仅验证暂存的标志位，不验证底层硬件或服务。
Cannot restore automatically	无法自动恢复
Changed	已更改
China Unlock is not ready	一键解锁尚未就绪
China Unlock is ready to stage	一键解锁已就绪，可以暂存
Conflict	冲突
Current	当前
Detected	已检测到
Device identity is unavailable.	无法获取设备身份。
Effect States	生效状态
Eligible	符合条件
File write success is never presented as the feature definitely working.	文件写入成功绝不代表功能一定生效。
File write verified	文件写入已验证
File write verified: the written file read back as staged.	文件写入已验证：写入的文件回读值与暂存一致。
First-recorded value	首次记录值
Hardware-identity check	硬件身份检查
Hide Details	隐藏详情
Hide Pre-Checks	隐藏前置检查
High risk	高风险
History is unavailable: no installation ID has been recorded yet.	历史记录不可用：尚未记录安装 ID。
In effect	生效中
Lila Intelligence	紫序智能引擎
Low risk	低风险
Medium risk	中风险
Modification Timeline	修改时间线
Modification timeline and precise restore, from trusted records only.	修改时间线与精确恢复，仅依据可信记录。
Native	原生
Native support and conflicts	原生支持与冲突
No backups stored yet.	尚未存储任何备份。
No device document is available, so this feature cannot be judged.	没有可用的设备文档，无法判断此功能。
No document has been read.	尚未读取任何文档。
No eligibility result was provided for this feature, so it cannot be staged.	未提供此功能的资格评估结果，因此无法暂存。
No fresh re-read was supplied, so the snapshot could not be re-verified.	未提供新的重新读取数据，因此无法再次验证快照。
No hardware-identity field is touched.	未触及任何硬件身份字段。
No modifications recorded and no differences detected.	未记录任何修改，也未检测到差异。
No native support or conflict blocks this proposal.	没有原生支持或冲突会阻止此方案。
No recorded original exists, so a precise restore cannot be guaranteed.	不存在已记录的原值，因此无法保证精确恢复。
No restore path is connected for this CacheData slot yet.	此 CacheData 槽位尚未连接恢复路径。
No restore path is connected for this artwork key yet.	此 artwork 键尚未连接恢复路径。
No restore path is connected for this key yet.	此键尚未连接恢复路径。
No trusted backup exists yet. A pre-change restore point will be created before applying; a precise restore is only guaranteed for changes with a trusted original.	尚无可信备份。应用前会创建修改前还原点；仅对有可信原值的更改保证精确恢复。
No verified OS-build compatibility table exists for this model, so OS-build compatibility is unknown.	此机型没有已验证的系统版本兼容表，因此系统版本兼容性未知。
No verified per-model eSIM-hardware table exists, so eSIM hardware presence is unknown.	没有已验证的按机型 eSIM 硬件表，因此无法确认是否存在 eSIM 硬件。
Not a China-market device.	不是中国市场机型。
Not yet	尚未
Offline serialization	离线序列化
Original	原值
Original → target diff	原值 → 目标值差异
Original: first-recorded value	原值：首次记录值
Original: key was absent	原值：键原本不存在
Original: recorded original	原值：已记录的原值
Personalized recommendations for this device, generated locally from real readings.	针对本机的个性化建议，根据真实读取数据在本地生成。
Pre-Restore Diff	恢复前差异
Preset dependencies	预设依赖
Proposal	方案
Re-read consistent after restart	重启后重读一致
Re-read consistent after restart: the value survived a device restart.	重启后重读一致：该值在设备重启后仍保持。
Read the device first to see personalized recommendations.	请先读取设备，再查看个性化建议。
Read the device first to see the modification timeline.	请先读取设备，再查看修改时间线。
Read the device first to simulate a change.	请先读取设备，再模拟更改。
Recommendations are generated on this device from its own readings. Nothing is sent anywhere.	建议根据本机自身的读取数据在设备上生成，不会向任何地方发送数据。
Region code is unknown, so this device cannot be confirmed as a China-market device.	地区代码未知，因此无法确认此设备为中国市场机型。
Region code is unknown.	地区代码未知。
Region code reads back as %@ — this verifies the staged code, not region-restricted services.	地区代码回读值为 %@——这仅验证暂存的代码，不验证受地区限制的服务。
Requires a device restart to take effect.	需要重启设备才能生效。
Restart verified	已验证重启
Restore Backup	恢复备份
Restore Intelligence	智能恢复引擎
Restore Preview	恢复预览
Restore log: %d entries	恢复日志：%d 条
Restore path not yet connected for this item.	此项目尚未连接恢复路径。
Restore staged through the existing path. Apply and restart to verify.	已通过现有路径暂存恢复。请应用并重启以验证。
Restore staged. Apply it, then restart and re-read to verify.	恢复已暂存。请应用，然后重启并重新读取以验证。
Restore to	恢复为
Restored	已恢复
Restores the whole device file from this backup (%@).	将从此备份（%@）恢复整个设备文件。
Restoring only one of the eSIM pair leaves the flags inconsistent. Restore both together.	仅恢复 eSIM 两个标志中的一个会导致标志不一致。请一起恢复。
Restoring only the region code leaves the sales-region suffix inconsistent. Restore both together.	仅恢复地区代码会导致销售地区后缀不一致。请一起恢复。
Review required	需要复核
SafePatch Simulator	SafePatch 模拟器
Sales region	销售地区
See what a change would do before you enable it. Simulation only — nothing is written.	在启用更改前，先查看它会产生什么影响。仅为模拟——不会写入任何内容。
Show All	显示全部
Show Details	显示详情
Show Less	收起
Show Pre-Checks	显示前置检查
Signing state could not be read.	无法读取签名状态。
Simulation blocked	模拟已阻止
Simulation passed	模拟已通过
Some features are already natively supported or configured and need no change.	部分功能已获得原生支持或已配置，无需更改。
Staged	已暂存
Staged: the change is prepared for review, not yet written.	已暂存：更改已准备好供审核，尚未写入。
Staging flips the eSIM cache flags only. It does not prove eSIM hardware is present.	暂存仅翻转 eSIM 缓存标志，不能证明存在 eSIM 硬件。
System function actually verified	系统功能已实际验证
System function actually verified: the feature works on the device.	系统功能已实际验证：该功能在设备上可用。
The CacheData slot cannot be repaired to a known baseline on this device, so staging is refused until the recorded original value is available.	此设备上的 CacheData 槽位无法修复到已知的基线，因此在获得已记录的原值之前拒绝暂存。
The backup could not be verified. No system changes were made.	无法验证备份，未做任何系统更改。
The change history could not be read. No system changes were made.	无法读取更改历史，未做任何系统更改。
The change history could not be saved and verified. No system changes were made.	无法保存并验证更改历史，未做任何系统更改。
The device data changed since the snapshot. Read again before simulating.	自快照以来设备数据已更改。请重新读取后再模拟。
The device data matches the snapshot.	设备数据与快照一致。
The first-read value is the first-recorded value, never a factory original. Fields with no trusted original never offer a precise restore.	首次读取值即首次记录值，绝非出厂原值。没有可信原值的字段绝不提供精确恢复。
The region code restores with the eSIM & Region group, not per item.	地区代码随 eSIM 与地区组合一起恢复，不支持单项恢复。
The restore could not be staged.	无法暂存恢复。
The restore could not be staged. No system changes were made.	无法暂存恢复，未做任何系统更改。
The restore log could not be read. No system changes were made.	无法读取恢复日志，未做任何系统更改。
The simulated document could not be serialized and verified.	无法序列化并验证模拟文档。
The simulated document serializes and reads back correctly.	模拟文档序列化并回读正确。
The stored artwork value is malformed, so it cannot be restored.	存储的 artwork 值格式错误，因此无法恢复。
The system cache layout could not be resolved, so CacheData checks are unavailable.	无法解析系统缓存布局，因此 CacheData 检查不可用。
This backup's origin is not trusted, so it cannot be restored automatically. It can be reviewed manually instead.	此备份来源不可信，因此无法自动恢复。可改为手动复核。
This change touches a CacheData slot that cannot be located on this device.	此更改涉及此设备上无法定位的 CacheData 槽位。
This device already has Dynamic Island natively.	此设备原生已有灵动岛。
This device natively supports Apple Intelligence.	此设备原生支持 Apple 智能。
This feature is not in the capability catalog, so it cannot be staged.	此功能不在能力目录中，因此无法暂存。
This history belongs to a different device.	此历史记录属于另一台设备。
This history uses a newer format this version cannot read.	此历史记录使用了当前版本无法读取的新格式。
This proposal changes a device-identity field. Staging it is refused.	此方案会更改设备身份字段，已拒绝暂存。
This proposal touches a hardware-identity field. Staging it is refused.	此方案触及硬件身份字段，已拒绝暂存。
This proposal would change nothing on this device.	此方案不会更改此设备上的任何内容。
This proposal would change nothing.	此方案不会产生任何更改。
This restores all %d keys of %@.	这将恢复 %d 个键（%@）。
This restores both eSIM flags together.	这将同时恢复两个 eSIM 标志。
This restores every field in the backup, not just one change.	这将恢复备份中的所有字段，而不仅是一项更改。
Trusted original snapshot	可信原值快照
Unchanged since snapshot	自快照以来未更改
Unknown	未知
Unknown OS	未知系统
Unknown build	未知版本
Unknown device	未知设备
Unknown feature — eligibility cannot be determined.	未知功能——无法确定资格。
Verified	已验证
Verified, but the cache layout differs from this device.	已验证，但缓存布局与此设备不同。
Verified.	已验证。
Verified. Cache layout matches this device.	已验证。缓存布局与此设备一致。
WAPI flag reads back as disabled — this verifies the staged flag, not network hardware.	WAPI 标志回读值为关闭——这仅验证暂存的标志位，不验证网络硬件。
Would change %d fields	将更改 %d 个字段
%@ conflicts with %@	%@ 与 %@ 冲突
%@ is changed to the same value by %@	%@ 被 %@ 改为相同的值
%@ is set to different values by %@	%@ 被 %@ 设为不同的值
%d accepted	已接受 %d 个
%d conflicts block staging.	%d 个冲突阻止暂存。
%d fields changed since the fingerprint was recorded.	自记录指纹以来，有 %d 个字段发生了变化。
%d fields were modified outside this app's records.	有 %d 个字段是在本 App 记录之外被修改的。
%d not re-read	%d 个未重新读取
%d of %d fields accepted after restart.	重启后 %d / %d 个字段已接受。
%d of %d fields accepted after restart; %d reverted.	重启后 %d / %d 个字段已接受；%d 个已还原。
%d of %d fields hold the staged value, but the device was not confirmed restarted.	%d / %d 个字段保留了暂存值，但未确认设备已重启。
%d prerequisites are missing.	缺少 %d 个前置条件。
%d recorded modifications have not been verified as restored.	有 %d 项已记录的修改尚未验证是否已还原。
%d reverted	已还原 %d 个
A trusted, verified backup exists for restore.	存在受信任且已验证的备份，可用于还原。
Accepted	已接受
Accepted changes marked restart-verified in history.	已接受的更改已在历史记录中标记为重启后已验证。
Across the selected set	所选组合整体
Analysis only — nothing is staged or written here.	仅供分析——此处不暂存、不写入任何内容。
App Group	App 群组
Audio Intelligence slot	音频智能插槽
Backup	备份
Backups have not been verified yet.	备份尚未验证。
Build	构建号
Cache bytes	缓存字节数
Cache integrity	缓存完整性
Cache layout	缓存布局
Cache layout resolved, CacheUUID present, originals recorded, document verified.	缓存布局已解析，CacheUUID 存在，原始值已记录，文档已验证。
Cache slots	缓存插槽数
Cache, compatibility, backup and modification risk, from real readings only.	缓存、兼容性、备份与修改风险，均来自真实读取。
Dependencies, conflicts and duplicates for a proposal, before you stage it.	在暂存之前，先查看该方案的依赖、冲突与重复修改。
Dependency	依赖
Dependency Analyzer	依赖分析器
Device Capability Fingerprint	设备能力指纹
Duplicate	重复
Fair	一般
Fingerprint saved.	指纹已保存。
Fingerprint unchanged since it was recorded.	指纹自记录以来未发生变化。
Has conflicts	存在冲突
Health could not be scored: no evidence was available.	无法评分健康状况：没有任何证据。
Health score %d of 100. %@	健康评分 %d / 100。%@
Healthy	健康
I restarted the device after applying	应用后我已重启设备
Live probe agrees with the staged value.	实时检测与暂存值一致。
Live probe disagrees with the staged value.	实时检测与暂存值不一致。
Mark accepted as restart-verified	将已接受项标记为重启后已验证
Missing prerequisites	缺少前置条件
Model number	型号
Model, OS build and support scope are recorded for this device.	该设备的型号、系统构建号与支持范围均已记录。
Modification risk	修改风险
Native Apple Intelligence	原生 Apple Intelligence
Needs attention	需要注意
No backups exist yet.	尚无备份。
No fingerprint has been recorded for this device yet.	尚未为该设备记录指纹。
No modifications have been recorded yet.	尚未记录任何修改。
No modifications recorded.	未记录任何修改。
No post-restart document has been read. Nothing is claimed accepted.	尚未读取重启后的文档。没有任何内容被声称为已接受。
No trusted backup exists yet.	尚无受信任的备份。
Not re-read	未重新读取
Off	关
On	开
Only fields that were re-read after a restart are claimed accepted. A value in the file does not prove the system uses it.	只有在重启后重新读取过的字段才会被声称为已接受。文件中的值并不能证明系统实际在使用它。
Personal Translator slot	个人翻译插槽
Post-Modification Acceptance	修改后验收
Product type	产品类型
Re-read the device after a restart and check what actually stuck.	重启后重新读取设备，检查实际生效了什么。
Read the device first to analyze a proposal.	请先读取设备，再分析方案。
Read the device first to capture its fingerprint.	请先读取设备，再记录其指纹。
Read the device first to score its health.	请先读取设备，再评估其健康状况。
Recorded %@ · Digest %@	已记录 %@ · 摘要 %@
Region code	地区码
Reverted	已还原
Reverted: %@	已还原：%@
Safe to stage	可以暂存
Safe to stage: %d features, %d warnings.	可以暂存：%d 个功能，%d 个警告。
Safe to stage: %d features, no findings.	可以暂存：%d 个功能，无发现。
Save current fingerprint	保存当前指纹
System Health Score	系统健康评分
Target %@ · Now %@	目标 %@ · 当前 %@
The change history could not be saved. No system changes were made.	无法保存更改历史。未做任何系统更改。
The device fingerprint could not be read. No system changes were made.	无法读取设备指纹。未做任何系统更改。
The device fingerprint could not be saved. No system changes were made.	无法保存设备指纹。未做任何系统更改。
The document could not be serialized and verified.	文档无法序列化与验证。
The fingerprint is stored only on this device, in the app's own history. It is never sent anywhere.	指纹仅保存在本设备上，位于 App 自身的历史记录中，绝不会发送到任何地方。
The recorded support scope may no longer apply. Re-verification is needed before staging.	已记录的支持范围可能不再适用。暂存前需要重新验证。
The stored fingerprint belongs to a different device. It was not used.	存储的指纹属于另一台设备，未被使用。
This device's real capabilities and build, recorded locally with a SHA-256 digest.	该设备的真实能力与构建信息，本地记录并附 SHA-256 摘要。
This score is a diagnostic summary only. It does not guarantee safety or that any feature will work.	此评分仅为诊断性汇总，不保证安全，也不保证任何功能一定可用。
Trusted backup	受信任的备份
Unreadable	无法读取
eSIM	eSIM
eSIM green-tea	eSIM 绿茶
eSIM not-green-tea	eSIM 非绿茶
iOS version	iOS 版本
The device could not be identified, so its fingerprint was not saved.	无法识别设备，因此未保存其指纹。
%d errors, %d warnings, %d notes	%d 个错误，%d 个警告，%d 条提示
%d fields could not be re-read.	有 %d 个字段无法重新读取。
A backup file is missing from disk.	磁盘上缺少一个备份文件。
A read attempt failed.	一次读取尝试失败了。
A restore attempt failed.	一次恢复尝试失败了。
A suggested fix is a suggestion, not a guarantee. It may not work on this device.	建议的修复方法只是建议，不是保证，在这台设备上可能无效。
A verified backup is from a different cache generation than the current document.	一个已验证的备份来自与当前文稿不同的缓存世代。
A write attempt did not verify.	一次写入尝试未能通过验证。
Apple Intelligence slot could not be resolved	无法定位 Apple 智能插槽
Backup could not be verified	备份无法通过验证
Backup file is missing	备份文件缺失
Backup is from a different cache generation	备份来自不同的缓存世代
Backup “%@” — cache layout does not match the current document.	备份“%@”——缓存布局与当前文稿不匹配。
Backup “%@” — file not found.	备份“%@”——找不到文件。
Backup “%@” — verification failed.	备份“%@”——验证失败。
Backups exist, but none has been verified in this session.	已有备份，但本次会话中尚未验证任何一个。
Backups have not been verified	备份尚未验证
Cache integrity needs attention	缓存完整性需要注意
Cause not yet determined.	原因尚未确定。
Check whether this model is in the supported list, and re-read the device.	请确认该机型是否在支持列表中，并重新读取设备。
Compatibility could not be determined for this device.	无法确定此设备的兼容性。
Compatibility is unknown	兼容性未知
Confirm the device was restarted after applying, then re-read and check the acceptance report. If the region keeps reverting, restore from a verified backup.	请确认应用后设备已重新启动，然后重新读取并查看验收报告。如果地区仍在还原，请从已验证的备份恢复。
Create a backup before changing anything.	在更改任何内容之前，请先创建备份。
Create a fresh backup before changing anything. This record cannot be used to restore.	在更改任何内容之前，请先创建一个新的备份。此记录无法用于恢复。
Create a fresh backup on this build. Treat a restore from this backup as review-required.	请在此构建上创建一个新的备份。从此备份恢复时需要复核。
Device changed — support scope needs re-verification	设备已更改——支持范围需要重新验证
Device identity or build changed since the last fingerprint.	自上次记录指纹以来，设备标识或构建已更改。
Device not read yet	尚未读取设备
Device state changed since the last fingerprint	自上次记录指纹以来设备状态已更改
Device values changed between the stored fingerprint and the current read.	在已存储的指纹与当前读取之间，设备值发生了变化。
Do not restore from this backup. Create a fresh backup, and keep the failed file for inspection.	请勿从此备份恢复。请创建一个新的备份，并保留失败的文件以供检查。
Do not retry the write blindly. Re-read the device to see its current state first.	请勿盲目重试写入。请先重新读取设备，查看其当前状态。
Error	错误
Evidence	证据
Hardware-identity change refused	已拒绝更改硬件标识
Live system disagrees with the file	实时系统与文件值不一致
Modification risk needs attention	修改风险需要注意
No action is needed unless the change was unexpected — then review the change history.	除非该更改出乎意料，否则无需采取行动——如有意外，请查看更改历史。
No backup has been created yet.	尚未创建任何备份。
No backups yet	暂无备份
No issues were found in the available data.	在现有数据中未发现问题。
No read has happened yet, so there is nothing to diagnose.	尚未进行任何读取，因此无可诊断。
Note	提示
On native Apple Intelligence hardware, skip this item: the native slot stays off. Otherwise use the repair path, then re-read after a restart.	在原生支持 Apple 智能的硬件上，请跳过此项：原生插槽保持关闭。否则请使用修复路径，然后在重新启动后重新读取。
Re-read after a restart and check the live probe again.	请在重新启动后重新读取，并再次检查实时检测。
Re-read the device and check the restore log. If the device is in an unwanted state, restore from a verified backup.	请重新读取设备并查看恢复日志。如果设备处于不希望的状态，请从已验证的备份恢复。
Re-read the device and check whether the fields can be read then.	请重新读取设备，查看届时是否可以读取这些字段。
Re-read the device and check whether the integrity checks pass then.	请重新读取设备，查看届时完整性检查是否通过。
Re-read the device. If it keeps failing, note the model and iOS minor version — the layout may not be resolvable on this build.	请重新读取设备。如果仍然失败，请记下机型和 iOS 小版本号——此构建上的布局可能无法解析。
Re-verify support on this build before staging anything.	在暂存任何内容之前，请在此构建上重新验证支持情况。
Read failed	读取失败
Read the device first to diagnose faults.	请先读取设备以诊断故障。
Read the device to see its current state.	请读取设备以查看其当前状态。
Region reverted after restart	重新启动后地区已还原
Remove hardware-identity fields from the proposal.	请从方案中移除硬件标识字段。
Restore failed	恢复失败
Review the change history and the Modified Values report. If a change was unwanted, restore from a trusted backup.	请查看更改历史和“已修改的值”报告。如果某项更改并非所需，请从受信任的备份恢复。
Run backup verification before relying on a backup.	在依赖备份之前，请先运行备份验证。
Smart Fault Diagnosis	智能故障诊断
Some device values changed since the fingerprint was captured.	自记录指纹以来，一些设备值已更改。
Some fields could not be re-read	部分字段无法重新读取
Suggested fix	建议的修复方法
The CacheData slot for this key cannot be located on this device's layout. On native Apple Intelligence hardware the slot is natively off, while the CacheExtra key can be staged on — the two are separate values.	在此设备的布局上无法定位此键对应的 CacheData 插槽。在原生支持 Apple 智能的硬件上，该插槽原生为关闭，而 CacheExtra 键可以暂存为开启——两者是相互独立的值。
The CacheData slot for this key could not be located.	无法定位此键对应的 CacheData 插槽。
The backup file is no longer on disk.	备份文件已不在磁盘上。
The backup was written from a different cache generation.	该备份写入自不同的缓存世代。
The cache integrity checks did not all pass.	缓存完整性检查并未全部通过。
The cache layout could not be resolved on this model and OS build, so eSIM staging was refused by the guard.	在此机型和系统构建上无法解析缓存布局，因此防护机制拒绝了 eSIM 暂存。
The eSIM cache layout could not be resolved on this device.	无法解析此设备上的 eSIM 缓存布局。
The file failed its byte-count, digest or plist check.	该文件未通过字节数、摘要或 plist 检查。
The file holds the staged value, but the live system returns a different answer. A value in the file does not prove the system uses it.	文件保存的是暂存值，但实时系统返回了不同的答案。文件中有某个值，并不能证明系统正在使用它。
The live probe did not answer for these keys: acceptance is based on the file value only.	实时检测未回答这些键：验收仅基于文件值。
The live system answer disagrees with the file value.	实时系统的答案与文件值不一致。
The modification-risk checks did not all pass.	修改风险检查并未全部通过。
The product type, OS build, cache layout or slot count changed since the fingerprint was captured, so the previously recorded support scope may no longer apply.	自记录指纹以来，产品类型、系统构建、缓存布局或插槽数量已更改，因此此前记录的支持范围可能不再适用。
The proposal touched a hardware-identity field. Staging it is refused by design: changing such a field can break Face ID or make the system discard the whole cache at boot.	该方案触及了硬件标识字段。按设计会拒绝暂存：更改此类字段可能破坏面容 ID，或导致系统在启动时丢弃整个缓存。
The region code is back to its original value in the re-read document.	在重新读取的文稿中，地区代码已恢复为原值。
The system rebuilt the cached region value on restart instead of keeping the staged value. This has been observed on iPhone 17 Pro Max (A3527): the region returned to CH after a restart.	系统在重新启动时重建了缓存的地区值，而没有保留暂存值。这一情况已在 iPhone 17 Pro Max（A3527）上观察到：重新启动后地区恢复为 CH。
Try reading again. If it keeps failing, check the App Group and signing state.	请重试读取。如果仍然失败，请检查 App Group 和签名状态。
Warning	警告
What went wrong, why, and what to try — from real readings only.	出了什么问题、为什么、以及可以尝试什么——仅基于真实读取。
Write did not verify	写入未能通过验证
Write, restore and guard events are not recorded yet.	写入、恢复和防护事件尚未记录。
eSIM layout could not be resolved	无法解析 eSIM 布局
%d members	%d 个成员
%d members are no longer in the catalog.	有 %d 个成员已不在预设库中。
%d verified models	%d 个已验证机型
A combination cannot contain the same preset twice.	一个组合不能两次包含同一个预设。
All	全部
Applies to	适用范围
Category	分类
Check Result	检查结果
China-market devices	中国大陆市场设备
Choose at least one preset.	请至少选择一个预设。
Choose members	选择成员
Combination name	组合名称
Conflicts	冲突
Custom Combinations	自定义组合
Dependencies	依赖
Eligibility	适用情况
Favorites first	收藏优先
Give the combination a name.	请给组合起个名字。
Group	组
High	高
Hypothesis	假设
Low	低
Medium	中
Members	成员
Minimum system	最低系统
New Combination	新建组合
No combinations yet.	暂无自定义组合。
No presets match this search.	没有符合搜索条件的预设。
Not verified	未验证
Observed	实测
Preset Catalog	智能预设库
Read the device first to see eligibility on this device.	请先读取设备，以查看本机上的适用情况。
Restore method	恢复方式
Risk	风险
Risk level	风险等级
Save Combination	保存组合
Search presets…	搜索预设…
Search, filter and save presets — from the catalog only.	搜索、筛选并收藏预设——仅基于预设库。
Simulation can proceed	模拟可继续
Source code	源码
The combinations could not be read. No system changes were made.	无法读取组合。未做任何系统更改。
The combinations could not be saved and verified. No system changes were made.	无法保存并验证组合。未做任何系统更改。
The favorites could not be read. No system changes were made.	无法读取收藏。未做任何系统更改。
The favorites could not be saved and verified. No system changes were made.	无法保存并验证收藏。未做任何系统更改。
These combinations belong to a different device.	这些组合属于另一台设备。
These combinations use a newer format this version cannot read.	这些组合使用了此版本无法读取的新格式。
These favorites belong to a different device.	这些收藏属于另一台设备。
These favorites use a newer format this version cannot read.	这些收藏使用了此版本无法读取的新格式。
This combination is a plan only. It is not connected to staging or applying.	此组合仅为计划，未连接暂存或套用。
Unknown preset: %@	未知预设：%@
Upstream	上游
iPad hardware	iPad 硬件
%d of 32 characters	%d / 32 个字符
%lld files	%lld 个文件
A custom preset cannot contain the same preset twice.	自定义预设不能两次包含同一预设。
A preset name is 1–32 characters.	预设名称为 1–32 个字符。
All Tools cards are hidden. Re-enable them in the Personalization Center.	工具页卡片已全部隐藏，请在个性化中心重新开启。
App Cache	应用缓存
App cache cleared.	应用缓存已清理。
Application Support	应用支持文件
Available	可用
Battery	电池
Battery health, cycle count and capacity are not available through public iOS APIs.	电池健康、循环次数与容量无法通过 iOS 公开 API 获取。
Battery level	电量
Battery state	电池状态
Battery, app cache, connection status and the operation log — read-only.	电池、应用缓存、连接状态与操作日志——仅读取。
Cache Read	缓存读取
Caches	缓存
Catalog Sort	目录排序
Charging	充电中
Clear App Cache	清理应用缓存
Connection Status	连接状态
Custom Presets	自定义预设
Custom presets are plans only. They are not connected to staging or applying.	自定义预设仅为计划，未连接暂存或套用。
Custom presets, catalog sort and Tools page cards — saved on this device only.	自定义预设、目录排序与工具页卡片——仅保存在本机。
Delete this custom preset?	删除此自定义预设？
Describe what this preset does.	请描述此预设的作用。
Description	描述
Diagnostics Expansion	诊断扩展
Edit	编辑
Explain the risk of this preset.	请说明此预设的风险。
Full	已充满
Give the custom preset a name.	请给自定义预设起个名字。
Last Read	上次读取
New Custom Preset	新建自定义预设
No custom presets yet.	暂无自定义预设。
No operation events recorded yet.	尚未记录任何操作事件。
OS Build	系统构建
Operation Log	操作日志
Personalization Center	个性化中心
Personalization Settings	个性化设置
Preset Name	预设名称
Read %lld bytes from the device.	从设备读取了 %lld 字节。
Read succeeded	读取成功
Read the device first to check this preset.	请先读取设备以检查此预设。
Read: %lld bytes	已读取：%lld 字节
Refusing to clear a directory that is not the app's Caches directory.	拒绝清理非本应用 Caches 的目录。
Restore succeeded	还原成功
Risk Reason	风险原因
Save Changes	保存更改
Save Custom Preset	保存自定义预设
Show or hide each card on the Tools page. The Personalization Center card itself always stays on this page.	选择在工具页显示哪些卡片。个性化中心卡片始终保留在本页。
Sort by Category	按分类排序
Sort by Name	按名称排序
Sort by Risk	按风险排序
Temporary	临时文件
The app cache could not be cleared.	应用缓存无法清理。
The custom presets could not be read. No system changes were made.	自定义预设无法读取，未做任何系统更改。
The custom presets could not be saved and verified. No system changes were made.	自定义预设无法保存并验证，未做任何系统更改。
The settings could not be read. Defaults are used.	设置无法读取，已使用默认值。
The settings could not be saved and verified. No system changes were made.	设置无法保存并验证，未做任何系统更改。
These custom presets belong to a different device.	这些自定义预设属于另一台设备。
These custom presets use a newer format this version cannot read.	这些自定义预设使用了本版本无法读取的新格式。
These settings belong to a different device.	这些设置属于另一台设备。
These settings use a newer format this version cannot read.	这些设置使用了本版本无法读取的新格式。
This clears only this app's own Caches directory. It never touches system caches.	仅清理本应用自己的 Caches 目录，绝不触碰系统缓存。
Tools Page Cards	工具页卡片
Total	合计
Unplugged	未充电
Wallpaper and Launch Images	壁纸与启动图
Write, restore and guard events are not recorded yet: the only hook points are inside the write path, which this version must not touch.	写入、还原与守卫事件尚未记录：唯一的接入点在写入路径内部，本版本不得触碰。
iOS offers no public API for an app to change the system wallpaper or another app's launch image. Save an image to Photos and set it manually.	iOS 未提供公开 API 供 App 更改系统壁纸或他 App 的启动图。请把图片保存到相册后手动设置。
Custom Home Screen Name	自定义桌面名称
Choose Preview Icon	选择预览图标
App Icon & Name · Preview Only	应用图标与名称 · 仅预览
Preview only. This does not change the installed app, its Home Screen icon, SpringBoard, or LaunchServices.	仅预览，不会修改已安装的 App、其桌面图标、SpringBoard 或 LaunchServices。
Use 1–32 characters without control characters.	请使用 1–32 个字符，且不含控制字符。
Native write capability: Unknown — not verified	原生写入能力：未知 — 未验证
This image is empty.	这张图片是空的。
This image is too large. Choose an image under %d MB.	这张图片太大了，请选择小于 %d MB 的图片。
This image format is not supported. Use PNG, JPEG, or HEIC.	不支持这种图片格式，请使用 PNG、JPEG 或 HEIC。
This image is too large in pixels. Choose an image up to %d pixels on its longest side.	这张图片像素太大了，请选择最长边不超过 %d 像素的图片。
Image: %@ · %d × %d · %d KB	图片：%@ · %d × %d · %d KB
Crop	裁剪
Square	正方形
Custom	自定义
Crop inset	裁剪边距
Corner radius	圆角半径
Undo	撤销
Save Draft	保存草稿
Load Draft	读取草稿
Reset	重置
Draft saved.	草稿已保存。
Draft loaded.	草稿已读取。
No draft found.	未找到草稿。
Full Image	完整
'''
entries = {}
for line in TRANSLATIONS.strip().splitlines():
    if not line.strip():
        continue
    key, value = line.split('\t', 1)
    entries[key] = {'localizations': {lang: {'stringUnit': {'state': 'translated', 'value': text}} for lang, text in [('en', key), ('zh-Hans', value)]}}
for translation_file in sorted((ROOT / 'localization').glob('*.json')):
    locale = translation_file.stem
    translations = json.loads(translation_file.read_text())
    missing = set(entries) - set(translations)
    if missing:
        raise ValueError(f'{locale}: missing {len(missing)} translations')
    for key in entries:
        entries[key]['localizations'][locale] = {'stringUnit': {'state': 'translated', 'value': translations[key]}}
(ROOT / 'GestaltX/Localizable.xcstrings').write_text(json.dumps({'sourceLanguage': 'en', 'strings': entries, 'version': '1.0'}, ensure_ascii=False, indent=2) + '\n')
print(f'Generated {len(entries)} strings in {len(next(iter(entries.values()))["localizations"])} locales.')
