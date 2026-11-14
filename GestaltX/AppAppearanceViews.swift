// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Combine
import PhotosUI

/// Preview-only model for a Home Screen icon and name. It never writes to
/// the installed app, SpringBoard, LaunchServices, or IconServices: the
/// native-write capability stays `.unknown` and `canApplyNatively` stays
/// false. The model only imports an image, validates it, renders a
/// downsampled thumbnail for display, and keeps undo history plus a local
/// draft in LilaShift's own container.
@MainActor
final class AppAppearancePreviewModel: ObservableObject {
    @Published private(set) var history = AppAppearancePreviewHistory()
    @Published private(set) var displayImage: UIImage?
    @Published private(set) var imageInfo: String?
    @Published var errorMessage: String?
    @Published private(set) var draftStatus: String?
    @Published private(set) var busy = false
    @Published private(set) var name: String = ""
    @Published private(set) var cropMode: AppAppearanceCrop.Mode = .full
    /// Transient slider values while a drag is in progress. They override
    /// the committed state for display until the drag ends and commits, so
    /// a drag is one undoable action instead of one entry per tick.
    @Published var editingInset: CGFloat?
    @Published var editingRadius: CGFloat?

    private var displayTask: Task<Void, Never>?

    var state: AppAppearancePreviewState { history.current }
    var canUndo: Bool { history.canUndo }
    /// The native-write capability is unknown until a real backend probe
    /// exists. It is never assumed writable.
    var capability: AppAppearanceCapability { .unknown }

    var effectiveCrop: AppAppearanceCrop {
        guard let inset = editingInset else { return state.crop }
        var crop = state.crop
        crop.mode = .custom
        crop.top = inset; crop.leading = inset; crop.bottom = inset; crop.trailing = inset
        return crop
    }

    var effectiveCornerRadius: CGFloat { editingRadius ?? state.cornerRadius }

    private var draftsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/AppAppearance/Drafts", isDirectory: true)
    }

    func hasDraft(for bundleID: String) -> Bool {
        AppAppearanceDraft.hasDraft(bundleID: bundleID, in: draftsDirectory)
    }

    /// Imports an image for preview. A failure keeps the previous state
    /// and reports the specific reason; it never clears the preview or
    /// pretends the import succeeded.
    func importImage(_ item: PhotosPickerItem) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = L("This image could not be used. Choose another image.")
            return
        }
        switch AppAppearanceValidatedImage.validate(data) {
        case .success(let validated):
            var next = state
            next.imageData = validated.data
            push(next)
            errorMessage = nil
            draftStatus = nil
        case .failure(let reason):
            errorMessage = reason.errorDescription
        }
    }

    /// Typing a name updates the current state in place; it does not add
    /// a history entry per keystroke.
    func setName(_ newName: String) {
        name = newName
        history.updateCurrent { $0.name = newName }
    }

    func setCropMode(_ mode: AppAppearanceCrop.Mode) {
        guard mode != state.crop.mode else { return }
        var next = state
        next.crop.mode = mode
        push(next)
    }

    /// Commits the inset slider's final value as one undoable action.
    func commitInset() {
        guard let inset = editingInset else { return }
        editingInset = nil
        var next = state
        next.crop.mode = .custom
        next.crop.top = inset; next.crop.leading = inset; next.crop.bottom = inset; next.crop.trailing = inset
        push(next)
    }

    /// Commits the corner-radius slider's final value as one undoable action.
    func commitRadius() {
        guard let radius = editingRadius else { return }
        editingRadius = nil
        var next = state
        next.cornerRadius = radius
        push(next)
    }

    func undo() {
        guard history.undo() != nil else { return }
        syncEditingState()
        refreshDisplayImage()
    }

    func reset() {
        history.reset()
        syncEditingState()
        refreshDisplayImage()
        draftStatus = nil
        errorMessage = nil
    }

    func saveDraft(for bundleID: String) {
        do {
            try AppAppearanceDraft(bundleID: bundleID, state: state).save(to: draftsDirectory)
            draftStatus = L("Draft saved.")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDraft(for bundleID: String) {
        do {
            guard let draft = try AppAppearanceDraft.load(bundleID: bundleID, from: draftsDirectory) else {
                draftStatus = L("No draft found.")
                return
            }
            history = AppAppearancePreviewHistory()
            history.push(draft.state)
            syncEditingState()
            refreshDisplayImage()
            draftStatus = L("Draft loaded.")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func push(_ next: AppAppearancePreviewState) {
        history.push(next)
        syncEditingState()
        refreshDisplayImage()
    }

    private func syncEditingState() {
        name = state.name
        cropMode = state.crop.mode
    }

    private func refreshDisplayImage() {
        displayTask?.cancel()
        guard let data = state.imageData else {
            displayImage = nil
            imageInfo = nil
            return
        }
        if case .success(let validated) = AppAppearanceValidatedImage.validate(data) {
            imageInfo = String(format: L("Image: %@ · %d × %d · %d KB"),
                               validated.format.displayName, validated.width, validated.height, validated.byteCount / 1024)
        } else {
            imageInfo = nil
        }
        let crop = effectiveCrop
        displayTask = Task {
            let png = await Task.detached(priority: .userInitiated) {
                AppAppearanceValidatedImage.croppedThumbnailPNG(from: data, crop: crop)
            }.value
            guard !Task.isCancelled else { return }
            if let png, let image = UIImage(data: png) {
                displayImage = image
            } else {
                displayImage = nil
            }
        }
    }
}

/// The App Appearance preview section. It is strictly a local preview:
/// the installed app, its Home Screen icon, SpringBoard, LaunchServices,
/// and IconServices are never modified, and the native-write path stays
/// hard-disabled. The launch-image editor is a different feature.
struct AppAppearancePreviewView: View {
    let app: LaunchArtworkApp
    @StateObject private var model = AppAppearancePreviewModel()
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Section {
            Text(L("Native write capability: Unknown — not verified"))
                .font(.caption).foregroundStyle(.secondary)
            TextField(L("Custom Home Screen Name"), text: Binding(get: { model.name }, set: { model.setName($0) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.name.isEmpty {
                let proposal = AppAppearanceProposal(bundleID: app.id, currentName: app.name, proposedName: model.name)
                if proposal.check == .invalidName {
                    Text(L("Use 1–32 characters without control characters."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            // No preferredItemEncoding: the default keeps the original
            // bytes, so a HEIC photo stays HEIC and its format is detected
            // instead of being silently transcoded to JPEG.
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(L("Choose Preview Icon"), systemImage: "app.badge")
            }
            if let info = model.imageInfo {
                Text(info).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
            Picker(L("Crop"), selection: Binding(get: { model.cropMode }, set: { model.setCropMode($0) })) {
                Text(L("Full Image")).tag(AppAppearanceCrop.Mode.full)
                Text(L("Square")).tag(AppAppearanceCrop.Mode.square)
                Text(L("Custom")).tag(AppAppearanceCrop.Mode.custom)
            }
            .pickerStyle(.segmented)
            if model.cropMode == .custom {
                HStack {
                    Text(L("Crop inset"))
                    Slider(value: Binding(
                        get: { Double(model.editingInset ?? model.state.crop.uniformInset) },
                        set: { model.editingInset = CGFloat($0) }
                    ), in: 0...0.4, step: 0.01, onEditingChanged: { editing in
                        if !editing { model.commitInset() }
                    })
                    Text("\(Int((model.editingInset ?? model.state.crop.uniformInset) * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            HStack {
                Text(L("Corner radius"))
                Slider(value: Binding(
                    get: { Double(model.editingRadius ?? model.state.cornerRadius) },
                    set: { model.editingRadius = CGFloat($0) }
                ), in: 0...Double(AppAppearancePreviewState.maximumCornerRadius), step: 1, onEditingChanged: { editing in
                    if !editing { model.commitRadius() }
                })
                Text("\(Int(model.editingRadius ?? model.state.cornerRadius))")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Group {
                    if let icon = model.displayImage {
                        Image(uiImage: icon).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(Image(systemName: "app").foregroundStyle(.secondary))
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: model.effectiveCornerRadius))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? app.name : model.name).lineLimit(1)
                    Text(app.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                Button(L("Undo")) { model.undo() }.disabled(!model.canUndo)
                Button(L("Reset"), role: .destructive) { model.reset() }.disabled(model.state == .empty)
                Spacer()
                Button(L("Save Draft")) { model.saveDraft(for: app.id) }
                Button(L("Load Draft")) { model.loadDraft(for: app.id) }.disabled(!model.hasDraft(for: app.id))
            }
            .font(.caption)
            if let status = model.draftStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("App Icon & Name · Preview Only"))
        } footer: {
            Text(L("Preview only. This does not change the installed app, its Home Screen icon, SpringBoard, or LaunchServices."))
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task { await model.importImage(item) }
        }
        .disabled(model.busy)
    }
}
