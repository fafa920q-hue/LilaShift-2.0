// SPDX-License-Identifier: GPL-3.0-only
// Hardened in-place writer for the device system plist.
//
// The previous device write was Foundation's non-atomic `Data.write(to:)`,
// which truncates the file to 0 bytes first and then streams the new
// content in: a crash, power loss or kill mid-stream leaves a 0-byte or
// partial `com.apple.MobileGestalt.plist`. This writer overwrites in place
// with `pwrite` (never truncating first), truncates only a shorter tail,
// flushes with `F_FULLFSYNC` (falling back to `fsync`), verifies with a
// full descriptor readback, and rolls the original bytes back in place on
// any failure.
//
// Adapted from Erosion-CN's in-place writer idea (`writeFileAtomically`);
// reimplemented for GestaltX's throwing-error style and its injectable
// `writeData` seam. Atomic temp-file + rename is deliberately not used
// for the device file: it needs directory-create access which some
// sandbox extensions lack, and it would replace the file's inode.
import Foundation
import Darwin

enum DevicePlistWriter {
    enum WriteError: LocalizedError, Equatable {
        case emptyData
        case unreadableOriginal
        case openFailed(Int32)
        case writeFailed(Int32)
        case truncateFailed(Int32)
        case syncFailed(Int32)
        case verificationFailed
        case rollbackFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .emptyData:
                return "Refused to write 0 bytes to the device file."
            case .unreadableOriginal:
                return "The original device file could not be read, so the write was stopped."
            case .openFailed(let errnoValue):
                return "Could not open the device file for writing (errno=\(errnoValue))."
            case .writeFailed(let errnoValue):
                return "Writing the device file failed (errno=\(errnoValue)). The previous file was restored."
            case .truncateFailed(let errnoValue):
                return "Trimming the device file failed (errno=\(errnoValue)). The previous file was restored."
            case .syncFailed(let errnoValue):
                return "Flushing the device file to storage failed (errno=\(errnoValue)). The previous file was restored."
            case .verificationFailed:
                return "The written device file did not match the readback. The previous file was restored."
            case .rollbackFailed(let errnoValue):
                return "The write failed and the previous file could not be restored (errno=\(errnoValue)). Keep the backup and recover the device file before trying again."
            }
        }
    }

    /// Writes `data` over the file at `url` in place, preserving its inode.
    /// Throws `WriteError` on failure; on any failure after the file was
    /// opened the original bytes are written back in place first.
    static func write(_ data: Data, to url: URL) throws {
        guard !data.isEmpty else { throw WriteError.emptyData }
        guard let original = try? Data(contentsOf: url), !original.isEmpty else {
            throw WriteError.unreadableOriginal
        }
        let fd = openFile(url)
        guard fd >= 0 else { throw WriteError.openFailed(errno) }
        defer { close(fd) }
        do {
            try pwriteAll(fd, data, startOffset: 0)
            if data.count < original.count {
                guard ftruncate(fd, off_t(data.count)) == 0 else {
                    throw WriteError.truncateFailed(errno)
                }
            }
            guard fullSync(fd) else { throw WriteError.syncFailed(errno) }
            guard lseek(fd, 0, SEEK_SET) == 0 else { throw WriteError.verificationFailed }
            let readback = try readAll(fd, count: data.count)
            guard readback == data else { throw WriteError.verificationFailed }
        } catch {
            // Best-effort in-place rollback of the original bytes. If the
            // rollback itself cannot complete, report that distinctly: the
            // caller must not claim the previous file is intact.
            do {
                try pwriteAll(fd, original, startOffset: 0)
                guard ftruncate(fd, off_t(original.count)) == 0 else {
                    throw WriteError.rollbackFailed(errno)
                }
                _ = fullSync(fd)
            } catch let rollbackError as WriteError {
                throw rollbackError
            } catch {
                throw WriteError.rollbackFailed(errno)
            }
            throw error
        }
    }

    /// `O_NOFOLLOW` covers only the final path component, which is the
    /// regular plist file; the `worse_query` directory swap is unaffected.
    /// If it ever fails on a device, retry without it: the path is fully
    /// constructed by us, never user input.
    private static func openFile(_ url: URL) -> Int32 {
        let opened = url.path.withCString { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) }
        if opened >= 0 { return opened }
        return url.path.withCString { open($0, O_RDWR | O_CLOEXEC) }
    }

    private static func fullSync(_ fd: Int32) -> Bool {
        if fcntl(fd, F_FULLFSYNC) == 0 { return true }
        return fsync(fd) == 0
    }

    private static func pwriteAll(_ fd: Int32, _ data: Data, startOffset: off_t) throws {
        var written = 0
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while written < data.count {
                let count = pwrite(fd, base.advanced(by: written), data.count - written, startOffset + off_t(written))
                if count < 0 {
                    if errno == EINTR { continue }
                    throw WriteError.writeFailed(errno)
                }
                if count == 0 { throw WriteError.writeFailed(0) }
                written += count
            }
        }
    }

    private static func readAll(_ fd: Int32, count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: 8192)
        var remaining = count
        while remaining > 0 {
            let wanted = min(buffer.count, remaining)
            let readCount = buffer.withUnsafeMutableBytes { raw in
                pread(fd, raw.baseAddress, wanted, off_t(count - remaining))
            }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw WriteError.verificationFailed
            }
            if readCount == 0 { throw WriteError.verificationFailed }
            result.append(buffer, count: readCount)
            remaining -= readCount
        }
        return result
    }
}
