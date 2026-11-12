![LilaShift](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

## LilaShift 2.0 (紫序) — LilaShift 1.0.7

[![Version](https://img.shields.io/badge/version-1.0.7-blue)](https://github.com/fafa920q-hue/LilaShift-2.0)

[![Platform](https://img.shields.io/badge/iOS-27.x-black?logo=apple)](#compatibility)

[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)](https://github.com/fafa920q-hue/LilaShift-2.0)

[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

[English](README.md) · [简体中文](README_ZH-CN.md)

One-tap eSIM, region code and Apple Intelligence setup for China-model iPhones — the full-source LilaShift 2.0 project, based on upstream GestaltX v1.0.7.

## What this repository is

This is the **full-source project** for LilaShift 2.0 (紫序), the China Unlock enhanced version of GestaltX. The complete modified source lives in this repository — no patch step, CI builds the IPA straight from this source. It is based on upstream [huamidev/GestaltX](https://github.com/huamidev/GestaltX) `v1.0.7` (commit `dfd4a7e`, build `11130112`) plus the upstream wallpaper-delete fix in PR #126 (commit `c60519c`). The previous patch-based build repository ([fafa920q-hue/LilaShift](https://github.com/fafa920q-hue/LilaShift)) stays as it is.

## What's new in this build

- **One-tap China Unlock (9 items).** eSIM switches (green-tea off, not-green-tea on), region code set to US (`LL`, sales region untouched), and six Apple Intelligence capabilities enabled — all staged in one tap, then reviewed and applied.
  - The eSIM cache layout is verified before staging. If it cannot be verified, the whole eSIM group stops and shows the reason; region and AI can still be set individually.
  - Every apply is automatically backed up and read-back verified. One-tap restore reverts all 9 items from the recorded originals.
- **Light-lavender Liquid Glass redesign.** Page background `#F6F3FF`, primary purple `#8652DC`. No large dark backgrounds.
- **One-line purpose description under every feature.** All 33 presets show a Simplified Chinese purpose line under the feature name; device requirements and how the change takes effect live in the details.
- **Author badge and progress cards.** Maintainer `@steam8871` is credited in the header and the About page. Reading and applying show real progress (backup / write / verify / done) driven by the actual operation — never faked.
- **Open-source compliance.** The About page carries an "Open Source & Acknowledgements" section, the full GPL v3.0 text is bundled in the app, and the enhanced source repository (this repo) is linked in the app.
- **Hardened writes, learned from Erosion-CN.** In-place writes (never pre-truncate, `F_FULLFSYNC`, full read-back, in-place rollback on failure), runtime dynamic resolution of the eSIM cache layout, a diff preview before applying, a dual-vault backup (a factory vault that survives uninstall/reinstall), a region-mode choice (region code only, or full US `LL` + `LL/A`), and a 4-factor Apple Intelligence checkup with conflict guards — all without copying Erosion-CN code.
- **LilaShift identity.** The app is named **LilaShift** (中文：紫序), with a cat photo as the app icon and the author `@steam8871` credited in the header and the About page.

## Features

| Category | Presets and tools |
| --- | --- |
| China Unlock | One-tap staging of 9 items: eSIM switches, region code US (`LL`), and six Apple Intelligence capabilities — reviewed before applying, with eSIM cache-layout verification, automatic backup, read-back verification, and one-tap restore |
| Display | Dynamic Island capability and layout, Always-On Display, AOD Vibrancy, high-luminance AOD, AOD flipbook, HDR photo display, wallpaper parallax, Liquid Glass low-power rendering, experimental PWM and DisplayPort flags |
| Device | Model name, boot/shutdown chime, charge limit, tap to wake, Camera Control settings, Action Button settings, Collision SOS, Audio Mix, Spatial FaceTime audio |
| iPad | Apple Pencil settings, Stage Manager capability, iPad app compatibility |
| Intelligence | Independent region-code options, Apple Intelligence capability flag, on-device Siri, Audio Intelligence, Personal Translator, Photos Clean Up, Handwriting Synthesis, always-listening Hey Siri, and sales-region options for activation attempts on China-mainland devices |
| Advanced | Apple internal feature flags, the system-wide InternalBuild flag with explicit enable confirmation, internal settings bundle, Security Research Device flag |
| Field editor | Read, search, add, edit, and remove `CacheExtra` fields; local plist import/export; String, Integer, Real, Boolean, Data, Date, Array, and Dictionary values |
| Changes | Automatic reading and manual re-read, staged before/after review, verified writes, per-preset restore |
| Backups | Automatic initial backup before device editing, backup before every write, original-value records; open, export, restore, and delete |
| Logs & respring | Actual exploit-stage logs and manual NeoSpring respring |

Usually, changing the region code is enough to try enabling AI; there is no need to change Sales Region. Selecting United States for Region Code sets `RegionCode` to `LL` and keeps the sales-region suffix. You can also choose China (Mainland), Hong Kong, Taiwan, Japan or the United Kingdom. Sales Region and Region Code can be applied together: the sales suffix follows Sales Region, while the code follows Region Code.

*If you previously changed Sales Region, restore your device’s original sales region and apply it first.*

Disabling a preset or using its Revert button restores the recorded original values and types. Keys that were originally absent are removed. If an older change has no original record, use Remove Added Fields only when you know those fields were added.

Presets modify capability flags; actual effects depend on the device and OS. China-mainland devices can use the Apple Intelligence and region options to attempt activation; availability also depends on the model, OS version, and Apple services.

## Compatibility

Supports **iOS / iPadOS 27.x**. **iOS / iPadOS 26.x is not supported for on-device MobileGestalt access.** Powered by [worse_query](https://github.com/forcequitOS/worse_query). SystemGroup access requires iOS 27; available features depend on the device and OS. Local plist editing is also supported.

Signing requires a certificate and provisioning profile with at least one usable App Group. Sign the app and its embedded share extension with at least one **common App Group**, and keep the extension when re-signing. Both processes detect their actual signed App Groups at runtime. Distributed IPAs carry ad-hoc signatures with these entitlements embedded so SideStore and AltStore can detect them when re-signing; they are not signed with a developer certificate.

The easiest install needs no signing at all: [LiveContainer](https://github.com/khanhduytran0/LiveContainer) runs the original IPA without re-signing, so the App Group requirement is met without a paid developer account.

## Download

Download the IPA from [Releases](https://github.com/fafa920q-hue/LilaShift-2.0/releases/latest) — `LilaShift_1.0.7.ipa` (bundle `com.huami.gestultx`, version `1.0.7`, build `11130112`, minimum iOS `26.0`, ~5.9 MB). The first release is published after the first verified build.

Some users report incomplete downloads with Safari on iOS 27. If the file is reported as damaged or cannot be extracted, download it again; several attempts may be needed. Try another browser if it persists. The cause has not been confirmed.

## Install

1. Install the IPA with [LiveContainer](https://github.com/khanhduytran0/LiveContainer).
2. Open LilaShift and tap **Read Device** first.
3. Open **China Unlock**, review the 9 staged items, then apply.
4. **Restart the device** after applying, then check eSIM and Apple Intelligence in system Settings.
5. To undo everything, use the one-tap restore — it reverts all 9 items from the backup.

## Requirements and caveats

- **eSIM hardware is required.** The unlock only flips the capability flags; it does not add eSIM hardware to a device that has none.
- **Apple Intelligence depends on hardware and Apple's servers.** Turning the flags on does not guarantee the features appear or work.
- **Carrier and location rules still apply.** A foreign eSIM cannot be installed while inside mainland China (Apple rule); installing one abroad generally needs Location Services on. A Chinese carrier eSIM must be activated at a carrier store in China.
- **System updates may revert the changes.** Re-apply after updating iOS if needed.
- **Do not update iOS blindly.** GestaltX relies on an unpatched iOS sandbox-escape vulnerability (`worse_query`). Apple may close it in a future update; confirm compatibility before updating if you rely on this tool.
- **Back up before applying.** The app backs up automatically, but a separate device backup is still good practice.

## Frequently asked questions

### eSIM still doesn't work after unlocking, or "Add eSIM" disappeared

- **iPhone 18 Pro / Pro Max with two physical SIMs in the tray.** These models share one baseband channel between the dual physical slots and the eSIM. If both physical slots are occupied, the baseband can hide "Add eSIM". Fix: remove the SIM tray (empty), apply the unlock, cold restart, add the eSIMs, then reinsert the physical SIM(s).
- **A respring is not enough for eSIM.** The baseband daemons (`CommCenter`, `ctkd`) do not reload the cache on a respring. After applying, power the device fully off and back on (cold restart).
- **Both switches must be on.** The region change and the eSIM change must both be applied; changing only the region code leaves the eSIM hardware lock in place.
- **Never change the model identifier (`ProductType`).** Forcing a China board (e.g. `iPhone19,7`) to a US model breaks baseband checks and hides the eSIM menu entirely.
- **Adding a foreign eSIM inside mainland China is blocked by Apple.** Scan the code with airplane mode on and Wi-Fi connected through an overseas proxy.
- **Hardware limits.** Only models with a physical eUICC chip (iPhone Air, iPhone 18 series, etc.) can add eSIMs. Older dual-nano-SIM-only models have no eUICC chip, so the switch only unlocks FaceTime audio and AI region access.

### The preset page and MG Control don't agree

MG Control shows the live CacheExtra values; the preset page shows the last read. Tap **Re-read** on the home page first. If they still disagree, the values were written directly (bypassing the preset) — apply the one-tap unlock once to normalize them.

### AI shows 1/6 (or fewer than 6)

Only that many of the 6 AI capability flags are currently on. Open the Apple Intelligence page to see which ones. A change made by an older version persists in the cache until reverted; if it was made before this app's first backup, the backup already contains it.

### I want to restore the original state, but there is no backup

Restore can only return values the app recorded. Check the Backups page for any earlier backup first. If there is none:
- Keys that were **added** (did not exist before) → use **Remove Added Fields**, only for keys you are sure were added.
- Keys that were **modified** → set them back in MG Control. `RegionCode` and the AI flags are CacheExtra keys and searchable there. `green-tea` / `not-green-tea` are CacheData slots (#383 / #506) and are **not** searchable — set them via the eSIM preset instead (`green-tea` → `true`, `not-green-tea` → `false`).
- Restart the device after restoring.

### The AI menu doesn't appear, or Siri says "something went wrong"

Check that the region code is `LL`, the 6 AI flags are on, and the device has finished downloading the AI models (Wi-Fi + charging, idle for a while). Proxy rules matter: Siri domains (`guzzoni.apple.com`, `*.siri.apple.com`, `dejavu.apple.com`, `sequoia.apple.com`) must go **DIRECT** with a real IP, not through a proxy; AI / Private Cloud Compute domains go through a clean US node. Do not set the system region to United States if you want to keep China Mandarin call screening — set it to Taiwan instead.

### Photos Clean Up works, but high-quality cleanup / extend / reimagine fails

On native-AI iPhones the factory baseline needs `Personal Translator` slot #266 = `true` and `Audio Intelligence` slot #178 = `false`. Forcing the experimental Audio Intelligence slot can break ModelCatalog asset checks and make high-quality cleanup fail. Turn it off / restore the baseline and try again.

### Reinstalling the app, or the certificate expires

Our build keeps backups inside the app container — uninstalling the app deletes them. Export your backup before reinstalling or letting the certificate expire.

## Import a plist

In Files or another app, select a MobileGestalt plist, tap **Share**, and choose **LilaShift**. The share extension reads the supplied file and hands it to the app through the shared App Group. Return to LilaShift if it does not open automatically. The app checks a device-bound proof from a GestaltX export, or at least two unique identifiers obtained from this device, then asks you to confirm the import. Files that cannot be verified are rejected. Previously imported files are never used as the reference for device identity.

Some original plists contain no unique device identifiers. Export a copy from LilaShift on this device first: its verification key stays in the device-only Keychain and is never included in the file.

Shared files are checked at launch and on return to the foreground. Pending edits are preserved until you save or discard them. Confirmed imports open as local documents. **MG Control** supports adding, editing, renaming and deleting typed keys and values. Use **Restore Imported Plist** to restore a verified file to this device; restoration requires a matching system cache layout and an additional confirmation, backs up the current file, and verifies the write. Restart the device afterward.

## Build it yourself

**Build LilaShift IPA** (`.github/workflows/build.yml`) builds the IPA straight from this source — on every push to `main`, pull request, version tag, release, and manual dispatch. The IPA is uploaded as a workflow artifact named `LilaShift-<version>`; tag and release runs also attach it to the matching GitHub release.

The screenshots in the previous build repository come from a simulator with no real device document, so they show the "Not read yet" state and a 1-item review — not the 9-item China Unlock summary, which needs a real device.

## Language support

GestaltX follows your iOS language settings, with English as the default and fallback. Persian includes right-to-left layout support.

| Language | Locale |
| --- | --- |
| English | `en` |
| 简体中文 — Simplified Chinese | `zh-Hans` |
| 繁體中文（台灣）— Traditional Chinese (Taiwan) | `zh-Hant-TW` |
| 繁體中文（香港）— Traditional Chinese (Hong Kong) | `zh-Hant-HK` |
| Tiếng Việt — Vietnamese | `vi` |
| Русский — Russian | `ru` |
| فارسی — Persian | `fa` |
| 한국어 — Korean | `ko` |
| Español — Spanish | `es` |
| 日本語 — Japanese | `ja` |

## Open source and license

This project is distributed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) (byte-identical to upstream v1.0.7).

- Upstream project: [huamidev/GestaltX](https://github.com/huamidev/GestaltX) (`v1.0.7`, commit `dfd4a7e`, plus PR #126, commit `c60519c`)
- Enhanced version maintainer: `@steam8871`
- Modifications in this build: the 9-item China Unlock preset and its safety checks, the light-lavender Liquid Glass redesign, one-line purpose descriptions, the author badge and progress cards, the in-app source-repository link, the open-source compliance section, the Erosion-CN-inspired hardening (write path, dynamic layout resolution, diff preview, dual-vault backup, region mode, AI checkup), the LilaShift rebrand, and the cat app icon.
- The complete corresponding source is in this repository (full source, no patch step).

## Credits

- **huamidev** — GestaltX.
- [forcequitOS / Taj C — worse_query](https://github.com/forcequitOS/worse_query)
- [neonmodder123](https://github.com/neonmodder123)
- [skadz108](https://github.com/skadz108)
- [rooootdev — NeoSpring](https://github.com/rooootdev/neospring)
- [Nouvborne — Ketamine](https://github.com/Nouvborne/Ketamine)
- [PoomSmart — MGKeys](https://github.com/PoomSmart/MGKeys)
- [leminlimez — Nugget](https://github.com/leminlimez/Nugget)
- [rooootdev — mond](https://github.com/rooootdev/mond)
- [frs0n — GestaltEdit](https://github.com/frs0n/GestaltEdit)

## Disclaimer

This is an unofficial modified build, not affiliated with Apple or endorsed by the upstream author. For security research and educational purposes only. Use only on devices you own or are authorized to manage.

Back up your data before making changes. Modifying MobileGestalt may cause system instability or require a device restore. Capability flags do not guarantee features. You are responsible for the changes you apply and the resulting risks.

## License

[GNU GPL v3](LICENSE) · Copyright © 2026 huamidev. China Unlock enhancements maintained by `@steam8871`.
