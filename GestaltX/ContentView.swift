// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import SwiftUI

private enum IncomingShareOffer {
    case plist(PlistImportOffer)
    case wallpaper(SharedWallpaperOffer)
}

struct ContentView: View {
    @StateObject private var model = GestaltManager()
    @StateObject private var systemSettings = SystemSettingsModel()
    @StateObject private var customizations = CustomizationModel()
    @StateObject private var launchCatalog = LaunchArtworkCatalogModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importOffer: PlistImportOffer?
    @State private var showsImportConfirmation = false
    @State private var wallpaperOffer: SharedWallpaperOffer?
    @State private var showsWallpaperConfirmation = false
    @State private var showsSharedWallpapers = false
    @State private var isCheckingSharedImport = false
    @State private var pendingSharedImport = false
    @State private var capturingDirectImports = 0
    @State private var sharesFile: TemporaryExport?
    @State private var activeExport: TemporaryExport?
    @State private var showsChanges = false
    @State private var asksRespring = false
    @State private var asksImportedRestore = false
    @State private var showsShareNotice = false
    @AppStorage("GestaltX.sharedImportNotice.v1") private var sharedImportNoticeShown = false
    @State private var selectedTab = 0
    @State private var didStart = false
    @State private var didAutoRead = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if targetEnvironment(simulator)
    @State private var previewCategory: CapabilityCategory?
    #endif
    @AppStorage("GestaltX.acceptedWelcome.v1") private var acceptedWelcome = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { tools }
                .tabItem { Label(L("Tools"), systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { FieldsView() }
                .tabItem { Label(L("MG Control"), systemImage: "slider.horizontal.3") }.tag(1)
            NavigationStack { BackupsView(share: presentShare) }
                .tabItem { Label(L("Backups"), systemImage: "clock.arrow.circlepath") }.tag(2)
            NavigationStack { AboutView() }
                .tabItem { Label(L("About"), systemImage: "info.circle") }.tag(3)
        }
        .environmentObject(model)
        .tint(Color.gestaltAccent)
        #if targetEnvironment(simulator)
        .sheet(item: $previewCategory) { category in
            NavigationStack {
                ToolGroupView(group: ToolGroup(for: category), systemSettings: systemSettings, customizations: customizations, launchCatalog: launchCatalog)
            }.environmentObject(model)
        }
        #endif
        .sheet(isPresented: Binding(get: { !acceptedWelcome && !isPreviewSession }, set: { _ in })) {
            WelcomeView { acceptedWelcome = true }
        }
        .sheet(item: $sharesFile, onDismiss: {
            activeExport?.cleanUp()
            activeExport = nil
        }) { ShareSheet(export: $0) }
        .sheet(isPresented: $showsChanges) { ChangeReviewView().environmentObject(model) }
        .sheet(isPresented: $showsSharedWallpapers) {
            NavigationStack {
                WallpapersView(model: customizations)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { showsSharedWallpapers = false } } }
            }
        }
        .fullScreenCover(isPresented: $model.isRespringing) { NeoSpringView() }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil && !showsChanges }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .alert(L("Respring now?"), isPresented: $asksRespring) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Respring")) { model.isRespringing = true }
        } message: { Text(L("This will attempt to restart SpringBoard using NeoSpring.")) }
        .alert(L("Import Plist"), isPresented: $showsImportConfirmation) {
            Button(L("Cancel"), role: .cancel) {
                if let offer = importOffer { model.discardImport(offer) }
                importOffer = nil
                pendingSharedImport = true
            }
            Button(L("Import")) {
                guard let offer = importOffer else { return }
                isCheckingSharedImport = true
                importOffer = nil
                pendingSharedImport = true
                Task {
                    await model.acceptImport(offer)
                    isCheckingSharedImport = false
                    await resumeSharedImports()
                }
            }
        } message: {
            Text(verbatim: (importOffer?.name ?? "") + "\n\n" + L("This plist has been verified for this device. Import it?"))
        }
        .alert(L("Import Wallpaper"), isPresented: $showsWallpaperConfirmation) {
            Button(L("Cancel"), role: .cancel) {
                if let offer = wallpaperOffer {
                    do { try offer.inbox.acknowledge(offer.entry) } catch { model.message = error.localizedDescription }
                    offer.cleanUp()
                }
                wallpaperOffer = nil
                pendingSharedImport = true
            }
            Button(L("Import")) {
                guard let offer = wallpaperOffer else { return }
                wallpaperOffer = nil
                isCheckingSharedImport = true
                Task {
                    let imported = await customizations.importWallpaper(offer.file, id: offer.id)
                    if imported {
                        do {
                            try offer.inbox.acknowledge(offer.entry)
                            showsSharedWallpapers = true
                        } catch { model.message = error.localizedDescription }
                    } else {
                        model.message = customizations.message
                        customizations.message = nil
                        offer.inbox.reject(offer.entry)
                    }
                    offer.cleanUp()
                    pendingSharedImport = true
                    isCheckingSharedImport = false
                    await resumeSharedImports()
                }
            }
        } message: {
            Text(verbatim: (wallpaperOffer?.name ?? "") + "\n\n" + L("Import this wallpaper pack? It will be added to Wallpaper Settings."))
        }
        .alert(L("Restore Imported Plist"), isPresented: $asksImportedRestore) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Restore"), role: .destructive) { Task { await model.restoreImportedPlist() } }
        } message: {
            Text(L("The current device file will be backed up before restoring. Restart the device afterward."))
        }
        .alert(L("Import Plist"), isPresented: $showsShareNotice) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L("Share this device's plist to LilaShift to edit its keys and values or restore a verified backup. Export a copy from LilaShift first to keep a device-bound proof."))
        }
        .onOpenURL { url in
            if url.scheme?.lowercased() == SharedAppGroups.hostURLScheme.lowercased(), url.host == "share" {
                Task { await checkSharedImport() }
            } else if url.isFileURL {
                do {
                    // Own the bytes before deferring presentation. The same
                    // durable confirmation queue handles Files and share events.
                    let capture = SharedPlistInbox.isWallpaperName(url.lastPathComponent)
                        ? SharedWallpaperImports.capture(url, in: try SharedWallpaperImports.inbox())
                        : DirectFileImports.capture(url, in: try DirectFileImports.inbox())
                    capturingDirectImports += 1
                    pendingSharedImport = true
                    Task {
                        do {
                            _ = try await withTaskCancellationHandler {
                                try await capture.value
                            } onCancel: { capture.cancel() }
                            capturingDirectImports -= 1
                            guard !Task.isCancelled else { return }
                            await resumeSharedImports()
                        } catch {
                            capturingDirectImports -= 1
                            if !Task.isCancelled && !(error is CancellationError) { model.message = error.localizedDescription }
                        }
                    }
                } catch { model.message = error.localizedDescription }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !isPreviewSession {
                launchCatalog.refreshIfLoaded()
                Task { await checkSharedImport() }
            }
        }
        .onChange(of: canPresentSharedImport) { _, ready in
            if ready && pendingSharedImport && !isCheckingSharedImport {
                Task { await resumeSharedImports() }
            }
        }
        .onChange(of: acceptedWelcome) { _, accepted in
            if accepted && !isPreviewSession { Task { await autoRead(); showShareNoticeIfNeeded() } }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await model.reloadBackups()
            #if targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--preview-document"), arguments.indices.contains(flag + 1) {
                await model.open(URL(fileURLWithPath: arguments[flag + 1]))
            }
            if let flag = arguments.firstIndex(of: "--preview-tab"), arguments.indices.contains(flag + 1), let tab = Int(arguments[flag + 1]) {
                selectedTab = tab
            }
            if arguments.contains("--preview-review") {
                if !arguments.contains("--preview-cache-option") { model.choices["pencil"] = .enable }
                showsChanges = true
            }
            if arguments.contains("--preview-cache-option") {
                model.stageCacheOption(.enable)
            }
            if let flag = arguments.firstIndex(of: "--preview-category"), arguments.indices.contains(flag + 1) {
                previewCategory = CapabilityCategory(rawValue: arguments[flag + 1])
            }
            if arguments.contains("--preview-document") || arguments.contains("--preview-tab") { return }
            #endif
            if acceptedWelcome { await autoRead(); showShareNoticeIfNeeded() }
        }
    }

    private var isPreviewSession: Bool {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--preview-tab") || arguments.contains("--preview-document")
        #else
        return false
        #endif
    }

    private func autoRead() async {
        guard !didAutoRead else { return }
        didAutoRead = true
        if await checkSharedImport() || model.hasDocument { return }
        await model.connect(showErrorAlert: false)
    }

    private var canPresentSharedImport: Bool {
        acceptedWelcome && !model.isBusy && model.changeCount == 0 && importOffer == nil
            && wallpaperOffer == nil && !showsWallpaperConfirmation && !showsSharedWallpapers
            && !customizations.busy && !customizations.isPresenting && customizations.message == nil
            && !showsImportConfirmation && !showsChanges && !model.isRespringing
            && sharesFile == nil && !asksRespring && !asksImportedRestore
            && !showsShareNotice && model.message == nil
    }

    private func resumeSharedImports() async {
        guard acceptedWelcome, !isPreviewSession else { return }
        if await checkSharedImport() { return }
        // Initial automatic reading may have yielded to an import that was
        // subsequently cancelled or rejected. Resume it when the queue empties.
        if didAutoRead && !model.hasDocument && !model.isBusy {
            await model.connect(showErrorAlert: false)
        }
    }

    @discardableResult
    private func checkSharedImport() async -> Bool {
        guard acceptedWelcome else { return false }
        guard !isCheckingSharedImport, importOffer == nil, wallpaperOffer == nil else { return true }
        do {
            let inboxes = [try DirectFileImports.inbox(), try SharedWallpaperImports.inbox()]
                + SharedAppGroups.inboxes + SharedAppGroups.wallpaperInboxes
            let entries = try SharedImportQueue.snapshot(in: inboxes)
            guard !entries.isEmpty else {
                pendingSharedImport = capturingDirectImports > 0
                return pendingSharedImport
            }
            guard canPresentSharedImport else {
                let firstNotice = !pendingSharedImport
                pendingSharedImport = true
                if model.changeCount > 0 && firstNotice && model.message == nil {
                    model.message = L("A shared file is waiting. Save or discard your current changes, then import it.")
                }
                return true
            }
            pendingSharedImport = false
            isCheckingSharedImport = true
            defer { isCheckingSharedImport = false }
            selectedTab = 0
            sharedImportNoticeShown = true
            let selection: SharedImportQueue.Selection<IncomingShareOffer> = await SharedImportQueue.next(in: entries) { inbox, entry in
                guard canPresentSharedImport else { return .deferred(nil) }
                if inbox.kind == .wallpaper {
                    do { return .ready(.wallpaper(try await SharedWallpaperImports.prepare(entry, from: inbox))) }
                    catch {
                        if SharedPlistError.canRetry(error) { return .deferred(error.localizedDescription) }
                        inbox.reject(entry)
                        return .rejected(error.localizedDescription)
                    }
                }
                switch await model.prepareSharedPlist(entry, from: inbox) {
                case .ready(let offer): return .ready(.plist(offer))
                case .deferred(let message): return .deferred(message)
                case .rejected(let message): return .rejected(message)
                }
            }
            switch selection {
            case .ready(let offer):
                // Verification may suspend while reading the device. Recheck
                // presentation after that await; the unacknowledged inbox file
                // remains available when the new modal/busy gate clears.
                guard canPresentSharedImport else {
                    if case .wallpaper(let wallpaper) = offer { wallpaper.cleanUp() }
                    pendingSharedImport = true
                    return true
                }
                pendingSharedImport = true
                switch offer {
                case .plist(let plist): importOffer = plist; showsImportConfirmation = true
                case .wallpaper(let wallpaper): wallpaperOffer = wallpaper; showsWallpaperConfirmation = true
                }
            case .deferred(let message):
                // A UI/busy gate can resume automatically. An unavailable device
                // identity waits for the next foreground/share event, avoiding
                // an isBusy -> retry -> isBusy loop on the same retained file.
                pendingSharedImport = message == nil
                if let message { model.message = message }
            case .empty(let lastRejection):
                pendingSharedImport = false
                if let lastRejection { model.message = lastRejection }
            }
            return selection.blocksAutomaticRead
        } catch {
            model.message = error.localizedDescription
            return true
        }
    }

    private func showShareNoticeIfNeeded() {
        guard !sharedImportNoticeShown, acceptedWelcome, !isPreviewSession,
              importOffer == nil, model.message == nil, !pendingSharedImport else { return }
        sharedImportNoticeShown = true
        showsShareNotice = true
    }

    private func presentShare(_ export: TemporaryExport) {
        guard sharesFile == nil, activeExport == nil else { export.cleanUp(); return }
        activeExport = export
        sharesFile = export
    }

    private var tools: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 6) {
                    Text(model.hasDocument ? model.displayedName : UIDevice.current.model)
                        .font(.subheadline.weight(.semibold))
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(readStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if model.hasDocument {
                        Button { Task { await model.connect() } } label: {
                            Label(L("Read Again"), systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.gestaltAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gestaltAccent.opacity(0.12), in: Capsule())
                        }
                        .disabled(model.isBusy || model.changeCount > 0)
                    }
                }

                ChinaUnlockCard { showsChanges = true }

                ChinaAIOnlyCard { showsChanges = true }

                ChinaESIMRegionCard { showsChanges = true }

                AppleIntelligenceCheckupCard { showsChanges = true }

                ModifiedValuesCard()

                if model.isReading {
                    GlassReadProgressCard(title: L("Reading device data…"))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Feature Categories"))
                        .font(.headline)
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(ToolGroup.categories) { group in
                                NavigationLink {
                                    ToolGroupView(group: group, systemSettings: systemSettings, customizations: customizations, launchCatalog: launchCatalog)
                                } label: {
                                    GlassCard(cornerRadius: GlassTokens.tileRadius) {
                                        GlassCategoryTile(
                                            title: group.title,
                                            detail: group.subtitle,
                                            symbol: group.symbol,
                                            tint: group.tint
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isBusy || (group.requiresDocument && !model.hasDocument))
                            }
                        }
                    }
                    NavigationLink {
                        ToolGroupView(group: .advancedDiagnostics, systemSettings: systemSettings, customizations: customizations, launchCatalog: launchCatalog)
                    } label: {
                        GlassCard(cornerRadius: GlassTokens.tileRadius) {
                            GlassCategoryTile(
                                title: ToolGroup.advancedDiagnostics.title,
                                detail: ToolGroup.advancedDiagnostics.subtitle,
                                symbol: ToolGroup.advancedDiagnostics.symbol,
                                tint: ToolGroup.advancedDiagnostics.tint
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.hasDocument || model.isBusy)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Actions"))
                        .font(.headline)
                    GlassCard(cornerRadius: GlassTokens.smallRadius) {
                        VStack(spacing: 0) {
                        if model.snapshot?.source == .local && model.snapshot?.ownershipVerified == true {
                            actionButton(label: L("Restore Imported Plist"), systemImage: "arrow.uturn.backward", enabled: model.canRestoreImportedPlist) { asksImportedRestore = true }
                            Divider()
                        }
                        actionButton(label: L("Apply Changes"), systemImage: "checkmark", badge: model.changeCount > 0 ? String(model.changeCount) : nil, accent: model.changeCount > 0 && !model.isBusy ? Color.gestaltAccent : nil, enabled: model.changeCount > 0 && !model.isBusy) { showsChanges = true }
                        Divider()
                        actionButton(label: L("Discard Changes"), systemImage: "xmark", accent: model.changeCount > 0 && !model.isBusy ? Color.red : nil, enabled: model.changeCount > 0 && !model.isBusy) { model.clearStaged() }
                        Divider()
                        actionButton(label: L("Create Backup"), systemImage: "externaldrive.badge.plus", enabled: model.hasDocument && !model.isBusy) { Task { await model.backup() } }
                        Divider()
                        actionButton(label: L("Export Plist"), systemImage: "square.and.arrow.up", enabled: model.hasDocument && !model.isBusy) {
                            if let export = model.exportDocument() { presentShare(export) }
                        }
                        Divider()
                        actionButton(label: L("Respring"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90", enabled: !model.isBusy) { asksRespring = true }
                        Divider()
                        NavigationLink { SessionLogView() } label: {
                            actionLabel(label: L("Log"), systemImage: "text.alignleft")
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }
                if model.needsRespring {
                    Label(L("Some changes require a device restart."), systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Tools LilaShift"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Label {
                        Text(L("Author @steam8871"))
                            .font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: "person.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gestaltAccent, in: Capsule())
                    if model.isBusy { ProgressView() }
                }
            }
        }
    }

    /// Two-column category grid; collapses to a single column at
    /// accessibility Dynamic Type sizes so text never overlaps or clips.
    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible(), spacing: 12)]
        } else {
            [GridItem(.adaptive(minimum: 160), spacing: 12)]
        }
    }

    private var readStatusText: String {
        guard model.hasDocument else { return L("Not read yet") }
        return model.sourceIsDevice ? L("Data read from this device") : L("Local File")
    }

    private func actionLabel(label: String, systemImage: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    private func actionButton(label: String, systemImage: String, badge: String? = nil, accent: Color? = nil, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent ?? Color.primary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

}

private struct ChinaUnlockCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    /// Light-purple glass tint for the hero card (#EAE1FF in light mode,
    /// a deep plum in dark mode). Text on the card uses the adaptive
    /// primary/secondary styles so contrast holds in both modes.
    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    var body: some View {
        let enabledAI = model.chinaUnlockEnabledAICapabilityIDs
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                GlassIconPedestal(systemImage: "lock.open.fill", tint: .gestaltAccent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("China Unlock"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Set up eSIM, region code and Apple Intelligence in one tap."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                statusColumn(title: "eSIM", value: esimStatus ?? L("Not read yet"))
                Divider().frame(height: 36).background(Color.primary.opacity(0.12))
                statusColumn(title: L("Region Code"), value: model.previewRegionCode ?? L("Not read yet"))
                Divider().frame(height: 36).background(Color.primary.opacity(0.12))
                statusColumn(title: L("Apple Intelligence"), value: model.hasDocument ? "\(model.chinaUnlockAIEnabledCount)/\(ChinaUnlock.aiCapabilities.count)" : L("Not read yet"))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ChinaUnlock.aiCapabilities) { capability in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(
                                L(capability.title),
                                systemImage: enabledAI.contains(capability.id) ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(enabledAI.contains(capability.id) ? Color.green : .secondary)
                            Text(L(capability.detail))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(L("Included AI Features"))
                    .font(.subheadline.weight(.medium))
            }

            if model.hasDocument {
                if model.isChinaUnlockStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore pre-unlock state")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaUnlockedInPreview
                    Button(L(restoring ? "Restore pre-unlock state" : "One-Tap Unlock")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy || model.previewESIMFlags == nil)
                        .opacity(model.isBusy || model.previewESIMFlags == nil ? 0.5 : 1)
                }

                if model.previewESIMFlags == nil {
                    Text(model.cacheLayoutError ?? L("eSIM settings are unavailable. You can still configure region and AI under Intelligence."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L(model.sourceIsDevice
                           ? "Review the changes, apply them, then restart the device."
                           : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(16)
        }
    }

    private var esimStatus: String? {
        guard model.hasDocument else { return nil }
        guard let flags = model.previewESIMFlags else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaUnlock() : model.stageChinaUnlock()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Standalone AI-only preset: stages only the six Apple Intelligence
/// presets (the AI part of the one-tap unlock), without eSIM or region.
/// Not blocked by the eSIM cache layout. Mirrors the one-tap card.
private struct ChinaAIOnlyCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                GlassIconPedestal(systemImage: "sparkles", tint: .gestaltAccent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("China AI"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Enable the six Apple Intelligence features on a China-model iPhone."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                statusColumn(title: L("Apple Intelligence"), value: model.hasDocument ? "\(model.chinaUnlockAIEnabledCount)/\(ChinaUnlock.aiCapabilities.count)" : L("Not read yet"))
            }

            if model.hasDocument {
                if model.isChinaAIOnlyStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore AI")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaAIOnlyApplied
                    Button(L(restoring ? "Restore AI" : "Enable China AI")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                }

                Text(L(model.sourceIsDevice
                       ? "Review the changes, apply them, then restart the device."
                       : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(16)
        }
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaAIOnly() : model.stageChinaAIOnly()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Standalone eSIM+region preset: stages only the eSIM cache flags and
/// the region code US (LL) — the eSIM+region part of the one-tap unlock,
/// without the six AI presets. Blocked by the eSIM cache layout, exactly
/// like the one-tap. Mirrors the one-tap card.
private struct ChinaESIMRegionCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                GlassIconPedestal(systemImage: "simcard.fill", tint: .gestaltAccent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("eSIM & Region"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Enable eSIM and set the region code to US (LL)."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                statusColumn(title: "eSIM", value: esimStatus ?? L("Not read yet"))
                Divider().frame(height: 36).background(Color.primary.opacity(0.12))
                statusColumn(title: L("Region Code"), value: model.previewRegionCode ?? L("Not read yet"))
            }

            if model.hasDocument {
                if model.isChinaESIMRegionStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore eSIM & Region")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaESIMRegionApplied
                    Button(L(restoring ? "Restore eSIM & Region" : "Enable eSIM & Region")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy || model.previewESIMFlags == nil)
                        .opacity(model.isBusy || model.previewESIMFlags == nil ? 0.5 : 1)
                }

                if model.previewESIMFlags == nil {
                    Text(model.cacheLayoutError ?? L("eSIM settings are unavailable. You can still configure region and AI under Intelligence."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L(model.sourceIsDevice
                           ? "Review the changes, apply them, then restart the device."
                           : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(16)
        }
    }

    private var esimStatus: String? {
        guard model.hasDocument else { return nil }
        guard let flags = model.previewESIMFlags else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaESIMRegion() : model.stageChinaESIMRegion()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Apple Intelligence readiness checkup (item 4): four factors with live
/// on-device state when the probe can answer, and a one-tap Fix button.
/// Read-only until Fix is tapped: Fix only stages through the normal
/// review flow, and slot repairs go through review + backup + readback.
/// Uses the existing Liquid Glass card and tokens; no new colors.
private struct AppleIntelligenceCheckupCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        Group {
            if let checkup = model.aiReadinessCheckup {
                GlassCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            GlassIconPedestal(systemImage: "sparkles", tint: .gestaltAccent, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Apple Intelligence readiness"))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(String(format: L("Ready %d/4"), checkup.readyCount))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(checkup.factors.indices, id: \.self) { index in
                            factorRow(checkup.factors[index])
                        }
                        if !model.aiConflicts.isEmpty {
                            ForEach(model.aiConflicts) { conflict in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(conflict.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        if !checkup.isReady {
                            Button(L("Fix")) {
                                if model.fixAIReadiness() && model.changeCount > 0 { onReviewChanges() }
                            }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(model.isBusy)
                            .opacity(model.isBusy ? 0.5 : 1)
                        }
                    }
                    .padding(16)
                }
                .onAppear { model.refreshLiveProbe() }
            }
        }
    }

    private func factorRow(_ factor: AIReadinessFactor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: factor.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(factor.isReady ? Color.green : Color.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.title)
                    .font(.subheadline.weight(.medium))
                Text(factor.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(liveStatusText(for: factor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The live line names the probe, not the feature: the AI factor's
    /// probe reads the CacheExtra `ai` key (see `refreshLiveProbe`), so
    /// "on" means the key reads on — it is not proof Apple Intelligence
    /// is actually working on the device.
    private func liveStatusText(for factor: AIReadinessFactor) -> String {
        switch factor.isLiveActive {
        case true: return L("Live probe: on")
        case false: return L("Live probe: off — restart to apply")
        case nil: return L("Live status unknown")
        }
    }
}

/// Read-only "Modified Values" card: lists every field in the
/// live-read document whose current value differs from its recorded
/// original, showing original → current. It stages nothing and writes
/// nothing. A field appears only when both its original and its
/// current value are known and verified; a field with no recorded
/// original is never shown with a made-up original. An empty list
/// after a comparison honestly means no modification was found,
/// because a baseline existed to compare against — but "no recorded
/// originals" is a different, honestly labeled state, never a claim
/// that nothing was modified.
private struct ModifiedValuesCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "list.bullet", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Modified Values"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Fields whose current value differs from the recorded original."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                switch model.modifiedValuesReport {
                case .noDocument:
                    Text(L("Read the device first to see modified values."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                case .noRecordedOriginals:
                    Text(L("No recorded originals. Whether anything was modified cannot be determined."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L("Only changes with a recorded original are listed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .compared(let rows):
                    if rows.isEmpty {
                        Text(L("No modifications found"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: L("Modified %d fields"), rows.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L(row.title))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 4) {
                                        Text(row.originalText)
                                        Text("→")
                                        Text(row.currentText)
                                    }
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                }
                            }
                        }
                    }
                    Text(L("Only changes with a recorded original are listed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}

/// Presentation groups for the Tools home screen. They regroup the
/// existing presets by task (screen, network, intelligence, charging,
/// iPad, personalization, diagnostics) without changing any preset
/// behavior: each group only filters `Capability.all` and reuses the
/// same staging, restore and review flow.
private enum ToolGroup: String, CaseIterable, Identifiable {
    case screenLock, networkEsim, intelligenceRegion, chargingButtons, ipadMultitasking, personalization, advancedDiagnostics
    var id: String { rawValue }

    /// The six preset groups shown in the two-column grid on the Tools home.
    static let categories: [ToolGroup] = [.screenLock, .networkEsim, .intelligenceRegion, .chargingButtons, .ipadMultitasking, .personalization]

    /// Maps the upstream preset category used by the simulator preview
    /// launch argument to the matching presentation group.
    init(for category: CapabilityCategory) {
        switch category {
        case .display: self = .screenLock
        case .device: self = .networkEsim
        case .intelligence: self = .intelligenceRegion
        case .ipad: self = .ipadMultitasking
        case .advanced: self = .advancedDiagnostics
        }
    }

    var title: String {
        switch self {
        case .screenLock: L("Screen & Lock Screen")
        case .networkEsim: L("Network & eSIM")
        case .intelligenceRegion: L("Apple Intelligence & Region")
        case .chargingButtons: L("Charging & Buttons")
        case .ipadMultitasking: L("iPad & Multitasking")
        case .personalization: L("Personalization")
        case .advancedDiagnostics: L("Advanced & Diagnostics")
        }
    }

    var subtitle: String {
        switch self {
        case .screenLock: L("Dynamic Island, Always-On Display")
        case .networkEsim: L("Digital SIM, Wi-Fi options")
        case .intelligenceRegion: L("Region code, translation and Clean Up")
        case .chargingButtons: L("Charge limit, tap to wake")
        case .ipadMultitasking: L("Stage Manager, Apple Pencil")
        case .personalization: L("Wallpapers, Lock Screen text, launch images")
        case .advancedDiagnostics: L("Model, sales region, run log")
        }
    }

    var description: String {
        switch self {
        case .screenLock: L("Lock screen display, screen brightness and display effects.")
        case .networkEsim: L("eSIM options, WAPI and call audio.")
        case .intelligenceRegion: L("Region code and Apple Intelligence features.")
        case .chargingButtons: L("Charging limits, buttons and alerts.")
        case .ipadMultitasking: L("iPad features on iPhone.")
        case .personalization: L("Wallpapers, Lock Screen text and app launch images.")
        case .advancedDiagnostics: L("Device identity, internal features and diagnostics.")
        }
    }

    var symbol: String {
        switch self {
        case .screenLock: "display"
        case .networkEsim: "simcard"
        case .intelligenceRegion: "sparkles"
        case .chargingButtons: "bolt.fill"
        case .ipadMultitasking: "ipad.landscape"
        case .personalization: "paintpalette"
        case .advancedDiagnostics: "wrench.and.screwdriver"
        }
    }

    var tint: Color {
        switch self {
        case .screenLock: .indigo
        case .networkEsim: .lavenderBlue
        case .intelligenceRegion: .purple
        case .chargingButtons: .green
        case .ipadMultitasking: .teal
        case .personalization: .pink
        case .advancedDiagnostics: .orange
        }
    }

    /// Personalization links work without a document; every other group
    /// needs a document read first.
    var requiresDocument: Bool { self != .personalization }

    var sections: [ToolGroupSection] {
        switch self {
        case .screenLock:
            [ToolGroupSection(title: L("Lock Screen Display"), capabilityIDs: ["aod", "aodVibrancy", "aodHighLuminance", "aodFlipbook", "aodFlipbookCount"]),
             ToolGroupSection(title: L("Display Effects"), capabilityIDs: ["dynamicIsland", "parallax", "hdrPhotoDisplay", "liquidGlass", "pwm", "displayPort"])]
        case .networkEsim:
            [ToolGroupSection(title: L("Digital SIM"), capabilityIDs: []),
             ToolGroupSection(title: L("Wi-Fi & Calls"), capabilityIDs: ["audioMix", "spatialFaceTimeAudio"])]
        case .intelligenceRegion:
            [ToolGroupSection(title: L("Region"), capabilityIDs: []),
             ToolGroupSection(title: L("Apple Intelligence"), capabilityIDs: ["ai", "siriOnDevice", "audioIntelligence", "personalTranslator", "photosCleanUp", "handwritingSynthesis", "alwaysListeningSiri"])]
        case .chargingButtons:
            [ToolGroupSection(title: L("Charging & Buttons"), capabilityIDs: ["chargeLimit", "tapToWake", "cameraControl", "actionButton", "bootChime", "collisionSOS"])]
        case .ipadMultitasking:
            [ToolGroupSection(title: L("Multitasking"), capabilityIDs: ["stageManager", "ipadApps", "pencil"])]
        case .personalization:
            []
        case .advancedDiagnostics:
            [ToolGroupSection(title: L("Internal Features"), capabilityIDs: ["internal", "storage", "srd", "internalSettings"]),
             ToolGroupSection(title: L("Diagnostics"), capabilityIDs: [])]
        }
    }

    var showsDynamicIslandPicker: Bool { self == .screenLock }
    var showsAdditionalOptions: Bool { self == .networkEsim }
    var showsWAPI: Bool { self == .networkEsim }
    var showsRegionPicker: Bool { self == .intelligenceRegion }
    var showsCustomizationLinks: Bool { self == .personalization }
    var showsLogLink: Bool { self == .advancedDiagnostics }
    var showsExperimentalNote: Bool { self == .ipadMultitasking || self == .advancedDiagnostics }
}

private struct ToolGroupSection: Identifiable {
    let title: String
    let capabilityIDs: [String]
    var id: String { title }
    var capabilities: [Capability] {
        capabilityIDs.compactMap { id in Capability.all.first { $0.id == id } }
    }
}

struct ToolGroupView: View {
    fileprivate let group: ToolGroup
    let systemSettings: SystemSettingsModel
    let customizations: CustomizationModel
    let launchCatalog: LaunchArtworkCatalogModel
    @EnvironmentObject private var model: GestaltManager
    @State private var asksInternalBuild = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(group.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.isReading {
                    GlassReadProgressCard(title: L("Reading related settings…"))
                }

                if group == .advancedDiagnostics {
                    sectionCard(title: L("Device Information")) {
                        modelNameRow
                        LabeledContent("iOS", value: "\(UIDevice.current.systemVersion) (\(VersionSupport.label))")
                        if let document = model.working {
                            LabeledContent("CacheExtra", value: String(document.extra.count))
                        }
                        Divider()
                        salesRegionPicker
                        Divider()
                        modelNumberPicker
                    }
                }

                ForEach(group.sections) { section in
                    sectionCard(title: section.title) {
                        if section.title == L("Display Effects") && group.showsDynamicIslandPicker {
                            dynamicIslandPicker
                            if !section.capabilities.isEmpty { Divider() }
                        }
                        if section.title == L("Region") && group.showsRegionPicker {
                            regionPicker
                        }
                        if section.title == L("Digital SIM") && group.showsAdditionalOptions {
                            AdditionalOptionsRow()
                        }
                        if section.title == L("Wi-Fi & Calls") && group.showsWAPI {
                            WAPIPresetRow()
                            if !section.capabilities.isEmpty { Divider() }
                        }
                        ForEach(section.capabilities) { capability in
                            PresetRow(capability: capability, onStageInternalBuild: { asksInternalBuild = true })
                            if capability.id != section.capabilities.last?.id { Divider() }
                        }
                        if section.title == L("Diagnostics") && group.showsLogLink {
                            NavigationLink { SessionLogView() } label: {
                                HStack {
                                    Label(L("Log"), systemImage: "text.alignleft")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if group.showsCustomizationLinks {
                    sectionCard(title: group.title) {
                        NavigationLink { SystemSettingsView(model: systemSettings) } label: {
                            GlassCategoryTile(
                                title: L("System Settings"),
                                detail: L("Add your own text at the bottom of the Lock Screen."),
                                symbol: "gearshape",
                                tint: .indigo
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        Divider()
                        NavigationLink { WallpapersView(model: customizations) } label: {
                            GlassCategoryTile(
                                title: L("Wallpaper Settings"),
                                detail: L("Import and apply wallpaper packs."),
                                symbol: "photo.on.rectangle.angled",
                                tint: .teal
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        Divider()
                        NavigationLink { LaunchArtworkApplicationsView(customizations: customizations, catalog: launchCatalog) } label: {
                            GlassCategoryTile(
                                title: L("App Launch Images"),
                                detail: L("Change the image shown when an app opens."),
                                symbol: "app.badge",
                                tint: .pink
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if group.showsExperimentalNote {
                    Text(L("Experimental settings. Back up before applying."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.large)
        .disabled(model.isBusy)
        .safeAreaInset(edge: .bottom) {
            if model.changeCount > 0 {
                GlassBottomBar {
                    NavigationLink { ChangeReviewView(isSheet: false) } label: {
                        Text(String(format: L("View %lld pending changes"), model.changeCount))
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
            }
        }
        .alert(L("Enable Internal Build?"), isPresented: $asksInternalBuild) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Enable"), role: .destructive) {
                guard !model.isBusy, model.hasDocument else { return }
                model.choices["storage"] = .enable
            }
        } message: {
            Text(L("This stages the system-wide InternalBuild flag. It can affect system services beyond the storage screen. You can review the change before applying it."))
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(cornerRadius: GlassTokens.smallRadius) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dynamicIslandPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Dynamic Island Layout"), selection: $model.subtype) {
                Text(L("Keep Current")).tag(0)
                Text("iPhone 14 Pro · 2556").tag(2556)
                Text("iPhone 14 Pro Max · 2796").tag(2796)
                Text("iPhone Air · 2736").tag(2736)
                Text("iPhone 16 Pro · 2622").tag(2622)
                Text("iPhone 16 Pro Max · 2868").tag(2868)
            }
            .pickerStyle(.menu)
            .onChange(of: model.subtype) { _, value in if value != 0 { model.choices["dynamicIsland"] = .keep } }
            Text(L("Choose the Dynamic Island layout size.")).font(.caption).foregroundStyle(.secondary)
            if let error = model.artworkEditingError {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.artworkEditingError != nil)
    }

    private var modelNameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Change Model Name"), isOn: $model.changesName)
            Text(L("Change the device model name shown by the system.")).font(.caption).foregroundStyle(.secondary)
            if model.changesName {
                TextField(L("Model Name"), text: $model.modelName).autocorrectionDisabled()
                Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.artworkEditingError {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.artworkEditingError != nil)
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Set the device region code for region-locked features.")).font(.caption).foregroundStyle(.secondary)
            Picker(L("Region Code"), selection: $model.regionCodeID) {
                ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
            }
            .pickerStyle(.menu)
            if model.regionCodeID != "keep" {
                Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Usually, changing the region code is enough. There is no need to change Sales Region."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("* If you previously changed Sales Region, restore your device's original sales region and apply it first."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var salesRegionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Set the sales-region suffix of the device model.")).font(.caption).foregroundStyle(.secondary)
            Picker(L("Sales Region"), selection: $model.regionID) {
                ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
            }
            .pickerStyle(.menu)
            if model.regionID != "keep" {
                Text(L("Restart the device after changing the region.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Changing the sales-region suffix may cause verification tools to report a mismatch with factory information."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var modelNumberPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Change the reported device model number.")).font(.caption).foregroundStyle(.secondary)
            Picker(L("Model Number"), selection: $model.modelID) {
                ForEach(ModelPreset.all) { Text(L($0.title)).tag($0.id) }
            }
            .pickerStyle(.menu)
            HStack(alignment: .firstTextBaseline) {
                if model.modelID != "keep" {
                    Text(L("A device restart may be required after changing the model number.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(L("Revert")) { Task { await model.restoreCapability(ModelPreset.restoration) } }
                    .font(.caption).buttonStyle(.borderless)
                    .disabled(!model.canRestore(ModelPreset.restoration))
            }
            Text(L("Listed values apply to iPhone Air, iPhone 18 Pro and iPhone 18 Pro Max only. Choosing a model number that does not match your hardware can make verification tools report a mismatch."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PresetRow: View {
    let capability: Capability
    let onStageInternalBuild: () -> Void
    @EnvironmentObject private var model: GestaltManager

    private var choice: PresetChoice { model.choices[capability.id] ?? .keep }
    private var canEnable: Bool { capability.availableChoices.contains(.enable) }

    private enum Status { case pending, configured, unconfigured, keep, notRead }
    private var status: Status {
        if !model.hasDocument { return .notRead }
        if choice != .keep { return .pending }
        if !canEnable { return .keep }
        return capability.isEnabled(in: model.preview) ? .configured : .unconfigured
    }

    var body: some View {
        GlassFeatureRow(
            symbol: symbol(for: capability),
            tint: tint(for: capability),
            title: L(capability.title),
            detail: L(capability.detail),
            caution: capability.caution,
            effectHint: choice != .keep ? L(capability.effectHint) : nil,
            statusText: statusText,
            statusTint: statusTint,
            actionTitle: status == .unconfigured ? L("Enable") : nil,
            actionEnabled: model.hasDocument,
            onAction: { stage(.enable, for: capability) },
            menu: AnyView(optionsMenu)
        )
    }

    private var statusText: String {
        switch status {
        case .pending: L("Pending")
        case .configured: L("Configured")
        case .unconfigured: L("Not Configured")
        case .keep: L("Keep Current")
        case .notRead: L("Not read yet")
        }
    }

    private var statusTint: Color {
        switch status {
        case .pending: .orange
        case .configured: .green
        case .unconfigured, .keep, .notRead: .secondary
        }
    }

    private var optionsMenu: some View {
        Menu {
            Text(L(capability.effectHint))
            ForEach(capability.availableChoices) { option in
                Button(L(optionTitle(option, for: capability))) { stage(option, for: capability) }
            }
            if model.canRestore(capability) {
                Button(L("Revert")) { Task { await model.restoreCapability(capability) } }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("More options"))
        }
    }

    private func tint(for capability: Capability) -> Color {
        switch capability.category {
        case .display: .lavenderBlue
        case .device: .teal
        case .ipad: .purple
        case .intelligence: .indigo
        case .advanced: .orange
        }
    }

    private func stage(_ choice: PresetChoice, for capability: Capability) {
        if capability.requiresEnableConfirmation, choice == .enable,
           model.choices[capability.id] != .enable {
            onStageInternalBuild()
            return
        }
        model.choices[capability.id] = choice
        if capability.id == "dynamicIsland" && choice != .keep { model.subtype = 0 }
    }

    private func optionTitle(_ choice: PresetChoice, for capability: Capability) -> String {
        if capability.id == "siriOnDevice" && choice == .disable { return "Restore Original" }
        return choice.title
    }

    private func symbol(for capability: Capability) -> String {
        switch capability.id {
        case "dynamicIsland": "display"
        case "aod", "aodVibrancy", "aodHighLuminance": "moon.fill"
        case "aodFlipbook", "aodFlipbookCount": "rectangle.stack.fill"
        case "parallax": "move.3d"
        case "hdrPhotoDisplay": "sun.max.fill"
        case "pwm": "lightbulb"
        case "displayPort": "cable.connector"
        case "liquidGlass": "drop.fill"
        case "bootChime": "speaker.wave.2.fill"
        case "chargeLimit": "battery.100.bolt"
        case "tapToWake": "hand.tap.fill"
        case "cameraControl": "camera.fill"
        case "actionButton": "button.programmable"
        case "collisionSOS": "sos"
        case "audioMix": "waveform"
        case "spatialFaceTimeAudio": "person.wave.2.fill"
        case "pencil": "pencil"
        case "stageManager": "rectangle.3.offgrid"
        case "ipadApps": "apps.ipad"
        case "ai", "siriOnDevice": "sparkles"
        case "audioIntelligence": "waveform"
        case "personalTranslator": "translate"
        case "photosCleanUp": "wand.and.stars"
        case "handwritingSynthesis": "pencil.and.scribble"
        case "alwaysListeningSiri": "ear.fill"
        case "internal": "wrench.and.screwdriver"
        case "storage": "internaldrive.fill"
        case "srd": "shield.fill"
        case "internalSettings": "gearshape.fill"
        default: "gearshape"
        }
    }
}


struct AdditionalOptionsRow: View {
    @EnvironmentObject private var model: GestaltManager

    private var support: Result<CachedOptionFlags, Error> {
        Result {
            guard let document = model.preview else { throw GestaltFailure("Load a document first.") }
            return try DeviceCacheOptions.flags(in: document)
        }
    }

    var body: some View {
        switch support {
        case .success:
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("Additional Options"), selection: Binding(
                    get: { model.cacheOptionChoice },
                    set: { _ = model.stageCacheOption($0) }
                )) {
                    ForEach(CacheOptionChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("cache-option-choice")
                Text(L("Enable or disable the eSIM-related system options."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("Some changes require a device restart."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Spacer(minLength: 8)
                    Button(L("Revert")) { Task { await model.restoreCacheOption() } }
                        .font(.caption).buttonStyle(.borderless)
                        .disabled(!model.canRestoreCacheOption)
                        .accessibilityIdentifier("cache-option-revert")
                }
            }
        case .failure(let error):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L("Additional Options")) { Text(L("Unsupported")).foregroundStyle(.secondary) }
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct WAPIPresetRow: View {
    @EnvironmentObject private var model: GestaltManager
    private var supported: Bool {
        guard let document = model.preview else { return false }
        return (try? DeviceCacheOptions.wapi(in: document)) != nil
    }
    var body: some View {
        if supported {
            VStack(alignment: .leading, spacing: 8) {
                Picker("WAPI", selection: Binding(get: { model.wapiChoice }, set: { model.stageWAPI($0) })) {
                    ForEach(WAPIChoice.allCases) { choice in Text(choice.title).tag(choice) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("wapi-choice")
                Text(L("Use the WAPI wireless security standard."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("Disabling may show Wi-Fi and change some network options. Restart to apply."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent("WAPI") { Text(L("Unsupported")).foregroundStyle(.secondary) }
        }
    }
}

struct FieldsView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var search = ""
    @State private var draft: FieldDraft?
    @State private var deletesKey: String?
    private var keys: [String] {
        (model.preview?.extra.keys.sorted() ?? []).filter { key in
            search.isEmpty || key.localizedCaseInsensitiveContains(search) || valueText(key).localizedCaseInsensitiveContains(search)
        }
    }
    private func valueText(_ key: String) -> String {
        guard let value = model.preview?.extra[key] else { return "" }
        let type = PlistValueKind.detect(value)
        if type == .data { return String(format: L("%lld bytes"), Int64((value as? Data)?.count ?? 0)) }
        return type.text(for: value)
    }
    var body: some View {
        List {
            if !model.hasDocument {
                ContentUnavailableView(L("No Document Open"), systemImage: "doc.text.magnifyingglass", description: Text(L("Read MobileGestalt in Tools, or share this device's plist to LilaShift.")))
            } else {
                Section {
                    ForEach(keys, id: \.self) { key in
                        Button {
                            guard let value = model.preview?.extra[key] else { return }
                            let kind = PlistValueKind.detect(value)
                            draft = FieldDraft(originalKey: key, key: key, kind: kind, text: kind.text(for: value), originalValue: value)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(key).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 4)
                                    if let value = model.preview?.extra[key] {
                                        Text(L(PlistValueKind.detect(value).rawValue)).font(.caption2).foregroundStyle(Color.gestaltAccent)
                                    }
                                }
                                Text(valueText(key)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 5)
                        }
                        .swipeActions(allowsFullSwipe: false) { Button(L("Delete")) { deletesKey = key }.tint(.red) }
                    }
                } header: { Text("CacheExtra") }
                if keys.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .navigationTitle(L("MG Control"))
        .searchable(text: $search, prompt: L("Search keys and values"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { draft = FieldDraft() } label: { Image(systemName: "plus").accessibilityLabel(L("Add Field")) }
                    .disabled(!model.hasDocument || model.isBusy)
            }
        }
        .sheet(item: $draft) { FieldEditorView(draft: $0).environmentObject(model) }.disabled(model.isBusy)
        .alert(L("Delete this field?"), isPresented: Binding(get: { deletesKey != nil }, set: { if !$0 { deletesKey = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletesKey = nil }
            Button(L("Delete"), role: .destructive) { if let key = deletesKey { model.removeField(key) }; deletesKey = nil }
        } message: { Text(L("The deletion is staged. The device file changes only after you apply.")) }
    }
}

struct FieldEditorView: View {
    @State var draft: FieldDraft
    @State private var error: String?
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Key")) {
                    TextField(L("Field Key"), text: $draft.key).font(.system(.subheadline, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section(L("Value")) {
                    Picker(L("Type"), selection: $draft.kind) { ForEach(PlistValueKind.allCases) { Text(L($0.rawValue)).tag($0) } }
                    TextEditor(text: $draft.text).font(.system(.subheadline, design: .monospaced))
                        .frame(minHeight: 150).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if draft.kind == .array || draft.kind == .dictionary {
                    Section { Text(L("Use an XML plist fragment, including the array or dict tags. Nested data and numeric types are preserved.")).font(.footnote).foregroundStyle(.secondary) }
                } else if draft.kind == .data {
                    Section { Text(L("Data values use Base64 encoding.")).font(.footnote).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(L(draft.originalKey == nil ? "Add Field" : "Edit Field"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Stage")) {
                        do { try model.stage(draft); dismiss() } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct ChangeReviewView: View {
    var isSheet = true
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    @State private var asksApply = false
    /// True from the moment the user confirms Apply until `apply()`
    /// returns. While true, the bottom bar shows the apply-progress card
    /// instead of the Apply button.
    @State private var applying = false
    var body: some View {
        Group {
            if isSheet { NavigationStack { contents } } else { contents }
        }
    }
    private var contents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Check which settings this will update."))
                    .font(.subheadline).foregroundStyle(.secondary)
                GlassCard(cornerRadius: GlassTokens.smallRadius) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L(model.sourceIsDevice ? "Write to this device" : "Save local document"), systemImage: model.sourceIsDevice ? "iphone" : "doc.text")
                            .font(.headline)
                        Text(L(model.sourceIsDevice ? "Backed up before writing, verified after writing." : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let message = model.message {
                    GlassCard(cornerRadius: GlassTokens.smallRadius, tint: Color.red.opacity(0.18)) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let validationError = model.previewValidationError {
                    GlassCard(cornerRadius: GlassTokens.smallRadius, tint: Color.red.opacity(0.18)) {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.isChinaUnlockStaged { chinaUnlockSummary }
                fieldChanges
                cacheChanges
                GlassCard(cornerRadius: GlassTokens.smallRadius) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button(L("Back to adjust")) { dismiss() }.disabled(model.isBusy)
                        Divider()
                        Button(L("Discard Changes"), role: .destructive) { model.clearStaged(); dismiss() }.disabled(model.isBusy)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L("After applying, restart, then check the related entries in system Settings."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Confirm Changes")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() }.disabled(model.isBusy) } }
            ToolbarItem(placement: .topBarTrailing) { if model.isBusy { ProgressView() } }
        }
        .safeAreaInset(edge: .bottom) { reviewBottomBar }
        .onChange(of: model.isBusy) { _, busy in if applying && !busy { applying = false } }
        .alert(L("Apply these changes?"), isPresented: $asksApply) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Apply")) { applying = true; Task { await model.apply(); applying = false; if model.changeCount == 0 { dismiss() } } }
        } message: { Text(L(model.sourceIsDevice ? "Incorrect system values can affect device behavior. A verified backup will be kept. No respring is triggered automatically." : "The current local document will be backed up before saving your edits.")) }
    }

    /// Fixed glass action bar: change count, data source and backup status
    /// above the apply button. The button label follows the data source
    /// (device vs local file); the official backup / confirm / write /
    /// verify flow behind it is unchanged, and a failed write reports its
    /// error through `model.message` instead of claiming success.
    /// While a write is in progress, the button is replaced by the
    /// apply-progress card (backup → write → verify → done), driven by
    /// the real write flow (see `applyProgressSteps`).
    private var reviewBottomBar: some View {
        GlassBottomBar {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(String(format: L("%lld fields changed"), model.changeCount))
                    Text("•").foregroundStyle(.secondary)
                    Text(L(model.sourceIsDevice ? "On Device" : "Local Document"))
                    Text("•").foregroundStyle(.secondary)
                    backupStatusText
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if applying {
                    GlassApplyProgressCard(
                        title: applyProgressTitle,
                        progress: applyProgressFraction,
                        steps: applyProgressSteps
                    )
                } else {
                    Button(L(model.sourceIsDevice ? "Apply to Device" : "Save Local Changes")) { asksApply = true }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.changeCount == 0 || model.isBusy || model.previewValidationError != nil)
                }
            }
        }
    }

    /// Apply progress derived from the real write flow, observed through
    /// the session log. `apply()` logs "[apply]" first; the commit then
    /// emits, in order, "Backup: … saved and verified", "Write: …",
    /// "Readback: comparing …" and "Readback: verified". No step is
    /// shown as done before its marker appears, and a failed step is
    /// shown as failed. Local files have no device write/readback, so
    /// their write and verify steps complete together when the save
    /// returns; nothing here invents a percentage.
    private var applyLogLines: [String] {
        guard let anchor = model.logs.lastIndex(where: { $0.contains("[apply]") }) else { return [] }
        return Array(model.logs[anchor...])
    }
    private var applyBackupDone: Bool {
        applyLogLines.contains { $0.contains("Backup: ") && $0.contains("saved and verified") }
    }
    private var applyVerifyStarted: Bool { applyLogLines.contains { $0.contains("Readback: comparing") } }
    private var applyVerifyDone: Bool { applyLogLines.contains { $0.contains("Readback: verified") } }
    private var applyFailed: Bool {
        applyLogLines.contains { $0.contains("Write/readback failed") || $0.contains("Recovery: restoring") }
    }
    private var applyFinishedOK: Bool { !model.isBusy && model.changeCount == 0 && applying }

    private var applyProgressSteps: [GlassApplyStep] {
        let backupDone = applyBackupDone
        let writeDone = applyVerifyStarted || applyVerifyDone || (applyFinishedOK && !model.sourceIsDevice)
        let verifyDone = applyVerifyDone || (applyFinishedOK && !model.sourceIsDevice)
        let allDone = applyFinishedOK
        func state(done: Bool, isCurrent: Bool) -> ApplyStepState {
            if applyFailed && isCurrent { return .failed }
            if done { return .done }
            return isCurrent ? .current : .pending
        }
        return [
            GlassApplyStep(title: L("Back Up"), state: state(done: backupDone, isCurrent: !backupDone)),
            GlassApplyStep(title: L("Write"), state: state(done: writeDone, isCurrent: backupDone && !writeDone)),
            GlassApplyStep(title: L("Verify"), state: state(done: verifyDone, isCurrent: writeDone && !verifyDone)),
            GlassApplyStep(title: L("Done"), state: state(done: allDone, isCurrent: verifyDone && !allDone)),
        ]
    }

    private var applyProgressFraction: Double {
        Double(applyProgressSteps.filter { $0.state == .done }.count) / 4.0
    }

    private var applyProgressTitle: String {
        let steps = applyProgressSteps
        if steps.allSatisfy({ $0.state == .done }) {
            return String(format: L("Apply Progress (Done %lld/4)"), 4)
        }
        let current = (steps.firstIndex { $0.state != .done } ?? 0) + 1
        return String(format: L("Apply Progress (Writing %lld/4)"), current)
    }

    private var backupStatusText: some View {
        Group {
            if let latest = model.backups.max(by: { $0.date < $1.date }) {
                Text(L("Latest backup")) + Text(" ") + Text(latest.date, style: .date)
            } else {
                Text(L("A backup is created before writing."))
            }
        }
    }

    /// The field keys written by the China Unlock group: the region code
    /// plus the six AI capability keys.
    private var chinaUnlockFieldKeys: Set<String> {
        var keys = Set(ChinaUnlock.aiCapabilities.flatMap(\.keys))
        keys.insert(GestaltKeys.regionCode)
        return keys
    }

    private var chinaUnlockSummary: some View {
        GlassCard(cornerRadius: GlassTokens.smallRadius) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("China Unlock")).font(.headline)
                summaryRow(
                icon: "simcard", tint: .teal,
                title: "eSIM",
                before: esimBeforeText,
                after: L("Will configure"),
                detail: L("Add a digital SIM in Settings.")
            )
            Divider()
            summaryRow(
                icon: "globe", tint: .lavenderBlue,
                title: L("Region Code"),
                before: regionDisplay(code: model.snapshot?.document.extra[GestaltKeys.regionCode] as? String),
                after: regionAfterText,
                detail: L("Set the device region code for region-locked features.")
            )
            Divider()
            summaryRow(
                icon: "sparkles", tint: .purple,
                title: L("Apple Intelligence"),
                before: "\(aiBeforeCount)/\(ChinaUnlock.aiCapabilities.count)",
                after: L("Configure 6 items"),
                detail: L("Enable six Apple Intelligence features, including translation, Clean Up and always-listening Hey Siri.")
            )
            DisclosureGroup(L("Technical Details")) {
                ForEach(chinaUnlockFieldKeys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        valueRow("Before", value: model.snapshot?.document.extra[key])
                        valueRow("After", value: model.preview?.extra[key])
                    }
                    .padding(.vertical, 6)
                }
                ForEach(model.cacheDataChanges.filter { $0.name != "wapi" }) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: change.name).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text(verbatim: change.keyPathText).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        valueRow("Before", value: NSNumber(value: change.before))
                        valueRow("After", value: NSNumber(value: change.after))
                    }
                    .padding(.vertical, 6)
                }
                unexplainedCacheBytesRow
                Text(L("eSIM requires eSIM hardware.")).font(.caption).foregroundStyle(.secondary)
            }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow(icon: String, tint: Color, title: String, before: String, after: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                GlassIconPedestal(systemImage: icon, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(before).foregroundStyle(.secondary)
                        Text("→").foregroundStyle(.secondary)
                        newValuePill(after)
                    }
                    .font(.subheadline)
                }
            }
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func newValuePill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gestaltAccent.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.gestaltAccent)
    }

    private var esimBeforeText: String {
        guard let snapshot = model.snapshot else { return L("Not present") }
        guard let flags = try? DeviceCacheOptions.flags(in: snapshot.document) else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    private var aiBeforeCount: Int {
        guard let fields = model.snapshot?.document.extra else { return 0 }
        return ChinaUnlock.aiCapabilities.filter { capability in
            capability.keys.allSatisfy { (fields[$0] as? NSNumber)?.intValue == 1 }
        }.count
    }

    private func regionDisplay(code: String?) -> String {
        guard let code, !code.isEmpty else { return L("Not present") }
        if let preset = RegionPreset.all.first(where: { $0.code == code }) {
            return "\(L(preset.title))（\(code)）"
        }
        return code
    }

    /// Region row's after-value: the one-tap unlock stages the region
    /// code only, so the after-value is just the LL display string.
    private var regionAfterText: String {
        regionDisplay(code: "LL")
    }

    private var fieldChanges: some View {
        let keys = model.changeKeys.filter { !(model.isChinaUnlockStaged && chinaUnlockFieldKeys.contains($0)) }
        let fieldGroups = Dictionary(grouping: keys, by: reviewTitle)
        let before = model.snapshot?.document.extra
        let after = model.preview?.extra
        return ForEach(fieldGroups.keys.sorted { L($0).localizedStandardCompare(L($1)) == .orderedAscending }, id: \.self) { title in
            let keys = fieldGroups[title, default: []]
            GlassCard(cornerRadius: GlassTokens.smallRadius) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L(title)).font(.headline)
                    if let capability = Capability.all.first(where: { $0.title == title }) {
                    if let choice = model.choices[capability.id], choice != .keep {
                        Text(L(choice.title)).fontWeight(.medium)
                    }
                    Text(L(capability.detail)).font(.subheadline).foregroundStyle(.secondary)
                }
                if title == "Region Code" {
                    LabeledContent(L("Before"), value: before?[GestaltKeys.regionCode] as? String ?? L("Not present"))
                    LabeledContent(L("After"), value: after?[GestaltKeys.regionCode] as? String ?? L("Not present"))
                }
                DisclosureGroup(L("Technical Details")) {
                    ForEach(keys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            valueRow("Before", value: before?[key])
                            valueRow("After", value: after?[key])
                        }
                        .padding(.vertical, 6)
                    }
                }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var cacheChanges: some View {
        let changes = model.cacheDataChanges.filter { !(model.isChinaUnlockStaged && $0.name != "wapi") }
        let cacheGroups = Dictionary(grouping: changes) { $0.name == "wapi" ? "WAPI" : "eSIM" }
        return ForEach(cacheGroups.keys.sorted(), id: \.self) { title in
            GlassCard(cornerRadius: GlassTokens.smallRadius) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: title).font(.headline)
                    if title == "eSIM" {
                    Text(L(model.isESIMUnlockedInPreview ? "Configured" : "Not Configured")).fontWeight(.medium)
                    Text(L("Add a digital SIM in Settings."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if title == "WAPI" {
                    Text(L("Use the WAPI wireless security standard."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                DisclosureGroup(L("Technical Details")) {
                    ForEach(cacheGroups[title, default: []]) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: change.name).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(verbatim: change.keyPathText).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            valueRow("Before", value: NSNumber(value: change.before))
                            valueRow("After", value: NSNumber(value: change.after))
                        }
                        .padding(.vertical, 6)
                    }
                    unexplainedCacheBytesRow
                    if title == "eSIM" {
                        Text(L("eSIM requires eSIM hardware.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func reviewTitle(for key: String) -> String {
        switch key {
        case GestaltKeys.regionCode: "Region Code"
        case GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo: "Sales Region"
        case GestaltKeys.modelNumber: "Model Number"
        default: Capability.all.first { $0.keys.contains(key) }?.title ?? "Other Fields"
        }
    }

    /// Red "other bytes" row for the review sheet: changed CacheData bytes
    /// outside the known slots, with their hex offsets. Visible even
    /// though the write will be refused — that is the point (diagnosis
    /// before Apply). The existing commit auto-rollback is unchanged and
    /// is not duplicated here.
    private var unexplainedCacheBytesRow: some View {
        Group {
            if let diff = model.cacheDataDiff, diff.hasUnexplained {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Other CacheData bytes changed"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    Text(verbatim: diff.unexplainedOffsets.map { String(format: "0x%X", $0) }.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
                    Text(L("Unrelated cache bytes changed — apply will be refused."))
                        .font(.caption).foregroundStyle(.red)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func valueRow(_ title: String, value: Any?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.map { PlistValueKind.detect($0).text(for: $0) } ?? L("Not present"))
                .font(.system(.caption, design: .monospaced)).lineLimit(6).textSelection(.enabled)
        }
    }
}


struct BackupsView: View {
    let share: (TemporaryExport) -> Void
    @EnvironmentObject private var model: GestaltManager
    @State private var restores: BackupRecord?
    @State private var deletes: BackupRecord?
    var body: some View {
        List {
            Section {
                Button { Task { await model.backup() } } label: { Label(L("Create Backup"), systemImage: "plus.circle.fill") }
                    .disabled(!model.hasDocument || model.isBusy)
            } footer: {
                if model.changeCount > 0 {
                    Text(L("Save or discard your current changes before opening another plist."))
                }
            }
            if model.backups.isEmpty {
                ContentUnavailableView(L("No Backups"), systemImage: "externaldrive.badge.timemachine", description: Text(L("A backup is created before each write.")))
            }
            ForEach(model.backups) { record in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: record.source == .device ? "iphone" : "doc.text").foregroundStyle(Color.gestaltAccent)
                            Text(L(record.reason)).fontWeight(.medium)
                            Spacer()
                        }
                        Text(record.date, format: .dateTime.year().month().day().hour().minute().second()).font(.subheadline)
                        Text(record.provenanceLabel).font(.caption).foregroundStyle(.secondary)
                        Text(L(record.source == .device ? "Device Backup" : "Local File Backup") + " · " + ByteCountFormatter.string(fromByteCount: Int64(record.byteCount), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L("Open")) { Task { await model.openBackup(record) } }
                                .disabled(model.changeCount > 0)
                            Spacer()
                            Button(L("Export")) { Task { if let url = await model.exportBackup(record) { share(url) } } }
                            Spacer()
                            Button(L("Restore")) { restores = record }
                                .disabled(model.changeCount > 0 || !model.hasDocument || (model.sourceIsDevice && record.source != .device))
                        }.font(.subheadline).buttonStyle(.borderless).padding(.top, 6)
                    }.padding(.vertical, 6)
                }.swipeActions(allowsFullSwipe: false) { Button(L("Delete")) { deletes = record }.tint(.red) }
            }
        }
        .navigationTitle(L("Backups")).disabled(model.isBusy)
        .task { await model.reloadBackups() }
        .refreshable { await model.reloadBackups() }
        .alert(L("Restore this backup?"), isPresented: Binding(get: { restores != nil }, set: { if !$0 { restores = nil } })) {
            Button(L("Cancel"), role: .cancel) { restores = nil }
            Button(L("Restore")) { if let record = restores { Task { await model.restore(record) } }; restores = nil }
                .disabled(model.isBusy || model.changeCount > 0)
        } message: {
            if let record = restores {
                Text(record.provenanceLabel + "\n" + L("The current document is backed up first. Device restores are verified after writing."))
            } else {
                Text(L("The current document is backed up first. Device restores are verified after writing."))
            }
        }
        .alert(L("Delete this backup?"), isPresented: Binding(get: { deletes != nil }, set: { if !$0 { deletes = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletes = nil }
            Button(L("Delete"), role: .destructive) { if let record = deletes { Task { await model.deleteBackup(record) } }; deletes = nil }
        } message: { Text(L("This removes the local backup permanently. It does not change the device file.")) }
    }
}

struct SessionLogView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var export: TemporaryExport?

    private func shareLog() {
        let text = model.logs.joined(separator: "\n") + "\n"
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = "GestaltX-session-\(Int(Date.now.timeIntervalSince1970)).log"
        export = try? TemporaryExport(data: Data(text.utf8), name: name)
    }

    var body: some View {
        ScrollView {
            Text(model.logs.isEmpty ? L("No activity yet.") : model.logs.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .environment(\.layoutDirection, .leftToRight)
        }
        .navigationTitle(L("Session Log"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shareLog() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(model.logs.isEmpty)
                    .accessibilityLabel(L("Share Log"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Clear")) { model.clearLog() }
            }
        }
        .sheet(item: $export) { ShareSheet(export: $0) }
    }
}

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("AppMark").resizable().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)).accessibilityHidden(true)
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let export: TemporaryExport
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [export.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in export.cleanUp() }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
