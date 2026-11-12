LilaShift — Third-Party Notices
Based on GestaltX by huamidev
Copyright (C) 2026 huamidev
https://github.com/huamidev

LilaShift is the enhanced version of GestaltX, maintained by @steam8871
(https://github.com/fafa920q-hue/LilaShift). The maintainer role covers
the LilaShift enhancements only: all upstream GestaltX work remains
attributed to its author, huamidev, below.

LilaShift is licensed under the GNU General Public License version 3.
The complete GPL v3 text is included with the app
(GestaltX/Licenses/GestaltX-GPL-3.0.txt) and in LICENSE at the repository
root. No warranty is provided.

How to read this file: each entry states how the material is used —
bundled code (shipped verbatim), adapted code (reworked from upstream),
reused data (values transcribed, code reimplemented), design reference
(ideas reimplemented, no code copied), or research reference (key names
and workflows cross-checked, no code or data copied). Only bundled and
adapted entries ship third-party code in the app.

1. GestaltX — upstream application baseline (bundled code, GPL-3.0)
Author: huamidev — https://github.com/huamidev/GestaltX
License: GNU GPL v3; full text: GestaltX-GPL-3.0.txt (identical to LICENSE).
The whole LilaShift application is built on the GestaltX 1.0.7 baseline
(upstream main c60519c): the MobileGestalt editor, presets, backups,
transactions, staging model and interface. LilaShift adds the China
Unlock enhancements, wallpaper tools, AI readiness checkup and the
LilaShift branding on top of that baseline. The provisioned App Group
identifier remains group.com.huami.gestultx.

2. worse_query (bundled code, GPL-3.0-or-later)
Author: Taj C (forcequit / forcequitOS)
Copyright (C) 2026 Taj C (forcequit)
Source: https://github.com/forcequitOS/worse_query
License: GPL-3.0-or-later, as stated in the source-file notices.
Included verbatim: GestaltX/worse_query.m and GestaltX/worse_query.h.
The original sandbox-escape implementation and its notices are
preserved. forcequitOS's fsgetpath research is also followed for
container identity discovery (GestaltX/GXCustomizationAccess.m).
GestaltX supplies its own application, document transactions and UI.

3. Ketamine / NeoSpring respring (adapted code, GPL-3.0)
GPL-licensed adaptation used as reference and incorporated here:
Nouvborne/Ketamine — https://github.com/Nouvborne/Ketamine
Original WebKit technique: neonmodder123 — https://github.com/neonmodder123
Swift implementation: skadz108 — https://github.com/skadz108
NeoSpring project: rooootdev — https://github.com/rooootdev/neospring
License: GNU GPL v3 (copy included in the app: GestaltX-GPL-3.0.txt).
Adapted: the respring HTML/logic in GestaltX/NeoSpringView.swift and the
earlier GestaltX respring implementation.
GestaltX changes dated 2026-11-09: fixed raw-string closing-tag escaping
and Web Crypto request length; added timeout, cancellation, nonpersistent
WebKit data store and Simulator exclusion. NeoSpring itself is credited
as a project/technique reference, not assigned a license it does not
declare.

4. LCSign (design reference)
Author: huamidev — https://sign.lc
The runtime entitlement-reading approach in
GestaltX/GXEntitlementsReader.m is adapted from LCSign's
LCEntitlementsReader and reimplemented for GestaltX with strict Mach-O
bounds checks and effective SecTask lookup. No LCSign code is bundled.
No public license statement for LCSign was found, so none is asserted
here; it is listed as a design reference from the same author.

5. Erosion-CN (design reference and reused data, GPL-3.0)
Author: Kianuni — https://github.com/Kianuni/Erosion-CN
License: GNU GPL v3; full text: Erosion-GPL-3.0.txt (standard GPL v3 text,
identical to LICENSE). Erosion-CN is a Simplified-Chinese fork of Erosion.
No Erosion-CN code is copied verbatim. Its ideas were reimplemented for
GestaltX, and two data tables were transcribed value-for-value:
- Design reference, reimplemented: the Apple Intelligence readiness
  checkup idea (GestaltX/AIReadinessCheckup.swift, adapted from
  Erosion-CN's AppleIntelligenceCheckupCard); the in-place device-plist
  writer idea (GestaltX/DevicePlistWriter.swift, adapted from Erosion-CN's
  `writeFileAtomically` — the name only; our writer is an in-place pwrite
  writer with no atomicity claim, see its header); the `__cfstring` walk for CacheUUID discovery
  (GestaltX/GXMobileGestaltImage.m, adapted from Erosion-CN's MGImageReader).
- Reused data, transcribed: the US regulatory-model A-number pairs in
  GestaltX/USRegulatoryModelMapping.swift (from Erosion-CN's
  `usRegulatoryModelNumber`); the native Apple Intelligence device list in
  GestaltX/DeviceAIEligibility.swift (from Erosion-CN's `isAppleIntellHD`);
  the native Audio Intelligence / Personal Translator slot baselines in
  GestaltX/DeviceAIEligibility.swift, taken from Erosion-CN's live device
  probes (iPhone 18 Pro Max iPhone19,7 and iPhone 15 Pro Max iPhone16,2,
  iOS 27). Erosion-CN's own note warning that a full-US mapping can
  conflict on CN dual-physical-SIM + eSIM hardware is followed in
  GestaltX/Capabilities.swift (Full US stays an explicit opt-in).
Because LilaShift is itself GPL-3.0, this reuse stays under the same
license; the attribution above records where the data came from.

6. Erosion (design reference, GPL-3.0)
Author: lunginspector / jailbreak.party and contributors
Source: https://github.com/jailbreakdotparty/Erosion
License: GNU GPL v3; full text: Erosion-GPL-3.0.txt.
Reference for .tendies descriptor layouts and PosterBoard targets
(GestaltX/CustomizationThemes.swift, GestaltX/GXCustomizationAccess.m).
No Erosion code is copied. GestaltX adds its own native interface,
bounded archive validation, runtime container identity checks, isolated
wallpaper ownership records, verified writes and original-file recovery.

7. Gester (design reference, MIT)
Author: sasobhabha; copyright (c) 2026 KAMUI contributors
Source: https://github.com/sasobhabha/Gester
License: MIT License; full text: Gester-MIT.txt.
Reference for PosterBoard descriptor providers, identifier regeneration
and the PosterBoard refresh flag (`PBF_RESET_FILE_PROTECTIONS`,
GestaltX/CustomizationStore.swift). No Gester code is copied; only key
names and descriptor conventions are followed.

8. ZIPFoundation 0.9.20 (bundled library, MIT)
Author: Thomas Zoechling
Source: https://github.com/weichsel/ZIPFoundation
License: MIT License; full text: ZIPFoundation-MIT.txt.
Linked as a Swift Package (exact version 0.9.20) and used for ZIP archive
reading and decompression (GestaltX/CustomizationFiles.swift). No
wallpaper theme assets are bundled.

9. Primer Octicons (bundled asset, MIT)
Author: GitHub Inc.
Source: https://raw.githubusercontent.com/primer/octicons/main/icons/mark-github-16.svg
License: MIT License; full text: Primer-Octicons-MIT.txt.
The GitHub mark SVG is bundled as
GestaltX/Assets.xcassets/GitHubMark.imageset/GitHubMark.svg and used as
the GitHub icon on the About page. GitHub names and marks remain GitHub
trademarks.

10. Research and workflow references (not bundled code or data)
These projects informed key names and workflow design. GestaltX
implements its own preset catalog, plist model, backups, transactions
and interface; their application code, assets and noncommercial-licensed
components are not included. Each upstream retains its own license and
copyright. No code from the AGPL-licensed projects below has been
ported: porting it would impose AGPL terms on this app.
- PoomSmart/MGKeys (MIT): https://github.com/PoomSmart/MGKeys
  Public MobileGestalt key mappings cross-checked
  (GestaltX/Capabilities.swift).
- leminlimez/Nugget (AGPL-3.0): https://github.com/leminlimez/Nugget
  Key mappings cross-checked; no code ported.
- rooootdev/mond (AGPL-3.0): https://github.com/rooootdev/mond
  Key mappings cross-checked; no code ported.
- frs0n/GestaltEdit (PolyForm Noncommercial License 1.0.0):
  https://github.com/frs0n/GestaltEdit
  Workflow reference only; no code included, in keeping with its
  noncommercial terms.

Not used here: Leaflet, gcoord, libimobiledevice, zsign, Feather,
SideStore, AltStore and LiveContainer do not appear in this tree; they
belong to other projects (WLOC web tooling and the LilaShift 2.0
signing/install research) and are deliberately not claimed above. The
app icon is a user-supplied photograph, and the AppMark is the app's own
mark; neither is third-party material.

LilaShift is not affiliated with Apple or any credited project. Upstream
sandbox-escape OS support is not a guarantee that the MobileGestalt
system cache is writable, or that capability flags produce working
hardware features. A verified file write does not prove a feature works
or that a respring succeeded.
