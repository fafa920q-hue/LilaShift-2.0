// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Native-write capability of the App Appearance backend.
///
/// The default is `.unknown`: no write capability is claimed until a real
/// probe verifies it. It must never be `.verifiedWritable` without a
/// verified write path, and a preview must never present itself as a
/// successful native edit.
enum AppAppearanceCapability: String, Equatable, Sendable {
    case unknown
    case readOnly
    case previewOnly
    case verifiedWritable
    case unsupported
    case failed

    /// The only safe starting state. A capability is never assumed.
    static var defaultCapability: AppAppearanceCapability { .unknown }
}

/// Image formats the appearance preview accepts. Detection is by magic
/// bytes only, so it never depends on a decoder succeeding, and it never
/// trusts a file extension.
enum AppAppearanceImageFormat: String, Equatable, Sendable {
    case png
    case jpeg
    case heic
    case unsupported

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .unsupported: return "—"
        }
    }

    static func detect(from data: Data) -> AppAppearanceImageFormat {
        guard !data.isEmpty else { return .unsupported }
        if data.count >= 8, data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if data.count >= 3, data.prefix(3) == Data([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.count >= 12, data[4..<8] == Data("ftyp".utf8) {
            // HEIC family brands, including the generic HEIF brands iOS
            // Photos may emit. A brand match only says the container is
            // HEIF; decodability is checked separately by validation.
            let brand = String(data: data[8..<12], encoding: .ascii) ?? ""
            if ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1"].contains(brand) { return .heic }
        }
        return .unsupported
    }
}

/// A validated appearance image: a supported format whose pixels could be
/// read. The original bytes are kept so the preview can render a
/// downsampled thumbnail without ever decoding the full image twice.
struct AppAppearanceValidatedImage: Equatable, Sendable {
    let format: AppAppearanceImageFormat
    let width: Int
    let height: Int
    let byteCount: Int
    let data: Data

    /// Matches the existing preview import cap (5 MB).
    static let maximumBytes = 5 * 1024 * 1024
    /// Matches the LaunchArtworkImages dimension cap (4096 px).
    static let maximumDimension = 4096

    enum ValidationError: Swift.Error, Equatable {
        case empty
        case tooLarge
        case unsupportedFormat
        case undecodable
        case dimensionsTooLarge
    }

    static func validate(_ data: Data) -> Result<AppAppearanceValidatedImage, ValidationError> {
        guard !data.isEmpty else { return .failure(.empty) }
        guard data.count <= maximumBytes else { return .failure(.tooLarge) }
        let format = AppAppearanceImageFormat.detect(from: data)
        guard format != .unsupported else { return .failure(.unsupportedFormat) }
        guard let size = pixelSize(of: data) else { return .failure(.undecodable) }
        guard size.width <= maximumDimension, size.height <= maximumDimension else { return .failure(.dimensionsTooLarge) }
        return .success(AppAppearanceValidatedImage(format: format, width: size.width, height: size.height, byteCount: data.count, data: data))
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// Renders the cropped preview as PNG bytes, downsampled so the longest
    /// side is at most `maxPixelSize`. The source is never fully decoded:
    /// ImageIO downsamples during decode, then the crop is applied to the
    /// small image. Returns nil when the source cannot be decoded.
    static func croppedThumbnailPNG(from data: Data, crop: AppAppearanceCrop, maxPixelSize: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        // Map the crop rect from original pixels to thumbnail pixels.
        // The thumbnail preserves the aspect ratio, so the scale is uniform
        // up to rounding; separate scales handle the rounding either way.
        let cropRect = crop.rect(for: CGSize(width: width, height: height))
        let scaleX = CGFloat(thumbnail.width) / CGFloat(width)
        let scaleY = CGFloat(thumbnail.height) / CGFloat(height)
        let thumbCrop = CGRect(x: cropRect.origin.x * scaleX, y: cropRect.origin.y * scaleY,
                               width: cropRect.width * scaleX, height: cropRect.height * scaleY)
            .intersection(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard thumbCrop.width >= 1, thumbCrop.height >= 1 else { return nil }
        let cropped = thumbnail.cropping(to: thumbCrop.integral) ?? thumbnail
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

extension AppAppearanceValidatedImage.ValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty: return L("This image is empty.")
        case .tooLarge:
            return String(format: L("This image is too large. Choose an image under %d MB."),
                          AppAppearanceValidatedImage.maximumBytes / (1024 * 1024))
        case .unsupportedFormat: return L("This image format is not supported. Use PNG, JPEG, or HEIC.")
        case .undecodable: return L("This image could not be used. Choose another image.")
        case .dimensionsTooLarge:
            return String(format: L("This image is too large in pixels. Choose an image up to %d pixels on its longest side."),
                          AppAppearanceValidatedImage.maximumDimension)
        }
    }
}

/// The crop applied to a preview image before it is shown. The rect is
/// computed from the real pixel size, so a crop is never guessed from a
/// thumbnail. All insets are fractions of the image size, clamped to
/// 0...0.4, and the result always keeps at least one pixel.
struct AppAppearanceCrop: Equatable, Codable, Sendable {
    enum Mode: String, Equatable, Codable, Sendable {
        case full
        case square
        case custom
    }

    var mode: Mode = .full
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    /// The uniform inset when all four sides agree, otherwise their
    /// average. The UI edits a single uniform inset; per-side values stay
    /// available for drafts and future editing.
    var uniformInset: CGFloat { (top + leading + bottom + trailing) / 4 }

    /// The crop rect in the image's own pixel coordinates.
    func rect(for size: CGSize) -> CGRect {
        let width = max(1, size.width), height = max(1, size.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        switch mode {
        case .full:
            return bounds
        case .square:
            let side = min(width, height)
            return CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        case .custom:
            let rect = CGRect(x: clamp(leading) * width, y: clamp(top) * height,
                              width: max(1, width * (1 - clamp(leading) - clamp(trailing))),
                              height: max(1, height * (1 - clamp(top) - clamp(bottom))))
            return rect.intersection(bounds)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(0.4, max(0, value)) }
}

/// One preview state: the imported image bytes (if any), the proposed name,
/// the crop, and the corner radius. This is the unit of undo history and
/// of draft saving. It never touches the installed app.
struct AppAppearancePreviewState: Equatable, Codable, Sendable {
    var imageData: Data?
    var name: String
    var crop: AppAppearanceCrop
    var cornerRadius: CGFloat

    static let maximumCornerRadius: CGFloat = 27
    static let empty = AppAppearancePreviewState()

    init(imageData: Data? = nil, name: String = "", crop: AppAppearanceCrop = AppAppearanceCrop(), cornerRadius: CGFloat = 12) {
        self.imageData = imageData
        self.name = name
        self.crop = crop
        self.cornerRadius = min(Self.maximumCornerRadius, max(0, cornerRadius))
    }
}

/// Undo history for the preview. The stack holds every distinct state;
/// undo returns to the previous one. The first entry is always the empty
/// state, so undo can never go below "nothing imported".
struct AppAppearancePreviewHistory: Equatable, Sendable {
    private(set) var states: [AppAppearancePreviewState] = [.empty]

    var current: AppAppearancePreviewState { states.last ?? .empty }
    var canUndo: Bool { states.count > 1 }

    mutating func push(_ state: AppAppearancePreviewState) {
        guard state != current else { return }
        states.append(state)
    }

    /// Updates the current state in place without adding a history entry.
    /// Used for continuous edits (typing a name) that must not flood the
    /// undo stack; discrete actions use `push`.
    mutating func updateCurrent(_ transform: (inout AppAppearancePreviewState) -> Void) {
        guard !states.isEmpty else { return }
        transform(&states[states.count - 1])
    }

    /// Removes the current state and returns the new current one, or nil
    /// when there is nothing to undo.
    mutating func undo() -> AppAppearancePreviewState? {
        guard states.count > 1 else { return nil }
        states.removeLast()
        return states.last
    }

    mutating func reset() { states = [.empty] }
}

/// A locally saved preview draft. It lives only in LilaShift's own
/// container, never in the target app's container, and it records a
/// SHA-256 digest of the image bytes so a tampered or truncated draft is
/// refused instead of shown.
struct AppAppearanceDraft: Equatable, Codable, Sendable {
    var version: Int
    var bundleID: String
    var state: AppAppearancePreviewState
    var imageDigest: String
    var savedAt: Date

    init(bundleID: String, state: AppAppearancePreviewState, savedAt: Date = Date()) {
        self.version = 1
        self.bundleID = bundleID
        self.state = state
        self.imageDigest = state.imageData.map { CustomizationFiles.digest($0) } ?? ""
        self.savedAt = savedAt
    }

    /// Saves this draft under the app's own container directory.
    /// The bundle ID must already be validated (it comes from the catalog).
    func save(to directory: URL) throws {
        guard LaunchArtworkDirectory.validIdentifier(bundleID) else {
            throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
        }
        try CustomizationFiles.saveVerified(self, to: directory.appendingPathComponent(bundleID + ".plist"))
    }

    /// Loads the draft for a bundle ID, or nil when none was saved.
    /// Throws when the file exists but is corrupt, foreign, or tampered.
    static func load(bundleID: String, from directory: URL) throws -> AppAppearanceDraft? {
        guard LaunchArtworkDirectory.validIdentifier(bundleID) else {
            throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
        }
        let url = directory.appendingPathComponent(bundleID + ".plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try PropertyListDecoder().decode(AppAppearanceDraft.self, from: CustomizationFiles.read(url))
        guard draft.version == 1, draft.bundleID == bundleID,
              draft.imageDigest == (draft.state.imageData.map { CustomizationFiles.digest($0) } ?? "") else {
            throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
        }
        return draft
    }

    static func hasDraft(bundleID: String, in directory: URL) -> Bool {
        guard LaunchArtworkDirectory.validIdentifier(bundleID) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(bundleID + ".plist").path)
    }
}
