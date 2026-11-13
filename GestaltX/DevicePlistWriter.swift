// SPDX-License-Identifier: GPL-3.0-only
// Hardened in-place writer for the device system plist.
//
// The previous device write was Foundation's `Data.write(to:)` without
// the `.atomic` option, which truncates the file to 0 bytes first and
// then streams the new content in: a crash, power loss or kill mid-stream
// leaves a 0-byte or partial `com.apple.MobileGestalt.plist`. This writer
// overwrites in place with `pwrite` (never truncating first), truncates
// only a shorter tail, flushes with `F_FULLFSYNC` (falling back to
// `fsync`), verifies with a full descriptor readback, and rolls the
// original bytes back in place on any detected failure.
//
// What this writer does NOT promise: ordinary `pwrite` has no absolute
// power-loss atomicity. A crash or power loss in the middle of the
// overwrite can still leave a torn mix of old and new bytes, and no
// readback performed after the fact can detect a torn write that already
// completed. The protection here is narrower and honest: no
// truncate-first 0-byte window, a pinned inode (see below), a durable
// flush, a readback that catches failures visible to this process, and an
// in-place rollback for those. Recovery from a torn write the writer
// itself cannot see relies on the pre-write backup taken by
// `GestaltFileStore.commit` before it calls this writer.
//
// Adapted from Erosion-CN's in-place writer idea; reimplemented for
// GestaltX's throwing-error style and its injectable `writeData` seam.
// Temp-file + rename is deliberately not used for the device file: it
// needs directory-create access which some sandbox extensions lack, and
// it would replace the file's inode.
import Foundation
import Darwin

enum DevicePlistWriter {
    enum WriteError: LocalizedError, Equatable {
        case emptyData
        case unreadableOriginal
        case staleOriginal
        case openFailed(Int32)
        case notRegularFile
        case unexpectedTarget
        case identityMismatch
        case unsafePermissions
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
            case .staleOriginal:
                return L("MobileGestalt changed since it was loaded. Refresh before applying your edits.")
            case .openFailed(let errnoValue):
                return "Could not open the device file for writing (errno=\(errnoValue))."
            case .notRegularFile:
                return "The device file is not a regular file, so the write was stopped."
            case .unexpectedTarget:
                return "The device file path is not the expected MobileGestalt cache path, so the write was stopped."
            case .identityMismatch:
                return "The device file changed while it was being opened, so the write was stopped."
            case .unsafePermissions:
                return "The device file has unsafe permissions, so the write was stopped."
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

    /// Test-only fault injection for `write`. Every flag defaults to off
    /// and production callers never pass one; the flags exist so the
    /// failure paths (short write, failed write/sync/truncate, readback
    /// mismatch, failed open) can be exercised without a device.
    /// Forward-write and rollback faults are separate so a test can exercise
    /// a failed transaction with either a successful or failed recovery.
    struct FaultInjection: Sendable {
        var failOpen = false
        var shortWriteOnce = false
        var failWrite = false
        var failSync = false
        var failTruncate = false
        var corruptReadback = false
        var failRollbackSync = false
        var corruptRollbackReadback = false
    }

    /// Writes `data` over the file at `url` in place, preserving its inode.
    /// Throws `WriteError` on failure; on any failure after the file was
    /// opened the original bytes are written back in place first.
    ///
    /// Safety checks, in order: the target must be a regular file (checked
    /// with `lstat`, which does not follow a final-component symlink), must
    /// not be world-writable and must not carry setuid/setgid bits, and the
    /// opened descriptor must be the same device/inode that was statted
    /// before the open (a swap between the check and the open is refused).
    /// When `expectedURL` is given, the target's canonical
    /// (symlink-resolved) path must equal the expected canonical path, so
    /// a symlinked parent directory leading somewhere else is refused too.
    /// Pass `expectedURL` from the production caller; it defaults to nil
    /// so existing callers and tests that write fixture files keep working.
    /// The original bytes are read back through the pinned descriptor, not
    /// with `Data(contentsOf:)`, so the bytes a rollback would restore are
    /// guaranteed to belong to the inode that was opened.
    static func write(_ data: Data, to url: URL, expectedURL: URL? = nil,
                      expectedOriginal: Data? = nil, faults: FaultInjection = FaultInjection()) throws {
        guard !data.isEmpty else { throw WriteError.emptyData }
        if let expectedURL {
            guard canonicalPath(url) == canonicalPath(expectedURL) else {
                throw WriteError.unexpectedTarget
            }
        }
        // Pre-open identity with lstat: the final component is not
        // followed, so a symlink is refused here as well as by O_NOFOLLOW
        // in openFile below.
        var before = stat()
        var preStatErrno: Int32 = 0
        let preStatOK = url.path.withCString { ptr in
            if lstat(ptr, &before) == 0 { return true }
            preStatErrno = errno
            return false
        }
        guard preStatOK else { throw WriteError.openFailed(preStatErrno) }
        guard (before.st_mode & S_IFMT) == S_IFREG else { throw WriteError.notRegularFile }
        // Only the permission bits that can never be legitimate on a plist
        // data file are refused. No owner check is added: the owner of the
        // daemon-created cache file is not a documented invariant, and
        // opening with O_RDWR already fails for a file this process cannot
        // write.
        guard (before.st_mode & S_IWOTH) == 0,
              (before.st_mode & (S_ISUID | S_ISGID)) == 0 else {
            throw WriteError.unsafePermissions
        }
        let fd = try openFile(url, faults: faults)
        defer { close(fd) }
        var after = stat()
        guard fstat(fd, &after) == 0 else { throw WriteError.openFailed(errno) }
        guard (after.st_mode & S_IFMT) == S_IFREG else { throw WriteError.notRegularFile }
        guard after.st_dev == before.st_dev, after.st_ino == before.st_ino else {
            throw WriteError.identityMismatch
        }
        guard after.st_size > 0 else { throw WriteError.unreadableOriginal }
        let original: Data
        do {
            original = try readAll(fd, count: Int(after.st_size))
        } catch {
            throw WriteError.unreadableOriginal
        }
        if let expectedOriginal, original != expectedOriginal { throw WriteError.staleOriginal }
        try verifyTarget(fd, at: url, size: original.count)
        do {
            try pwriteAll(fd, data, startOffset: 0, faults: faults)
            if data.count < original.count {
                if faults.failTruncate { throw WriteError.truncateFailed(EIO) }
                guard ftruncate(fd, off_t(data.count)) == 0 else {
                    throw WriteError.truncateFailed(errno)
                }
            }
            guard fullSync(fd, faults: faults) else {
                throw WriteError.syncFailed(faults.failSync ? EIO : errno)
            }
            let readback = try readAll(fd, count: data.count)
            guard !faults.corruptReadback, readback == data else {
                throw WriteError.verificationFailed
            }
            try verifyTarget(fd, at: url, size: data.count)
        } catch {
            // Recover only through the original descriptor. Confirm the
            // original bytes, length and path before reporting recovery.
            do {
                try verifyTarget(fd, at: url)
                try pwriteAll(fd, original, startOffset: 0, faults: FaultInjection())
                guard ftruncate(fd, off_t(original.count)) == 0 else {
                    throw WriteError.rollbackFailed(errno)
                }
                guard fullSync(fd, faults: FaultInjection(failSync: faults.failRollbackSync)) else {
                    throw WriteError.rollbackFailed(faults.failRollbackSync ? EIO : errno)
                }
                let recovered = try readAll(fd, count: original.count)
                guard !faults.corruptRollbackReadback, recovered == original else {
                    throw WriteError.rollbackFailed(EIO)
                }
                try verifyTarget(fd, at: url, size: original.count)
            } catch let rollbackError as WriteError {
                switch rollbackError {
                case .rollbackFailed:
                    throw rollbackError
                case .writeFailed(let code):
                    throw WriteError.rollbackFailed(code)
                default:
                    throw WriteError.rollbackFailed(EIO)
                }
            } catch {
                throw WriteError.rollbackFailed(errno)
            }
            throw error
        }
    }

    private static func verifyTarget(_ fd: Int32, at url: URL, size: Int? = nil) throws {
        var path = stat()
        var descriptor = stat()
        guard url.path.withCString({ lstat($0, &path) }) == 0,
              fstat(fd, &descriptor) == 0,
              path.st_dev == descriptor.st_dev, path.st_ino == descriptor.st_ino,
              path.st_mode == descriptor.st_mode else { throw WriteError.identityMismatch }
        if let size, descriptor.st_size != off_t(size) { throw WriteError.verificationFailed }
    }

    /// Resolves symlinks in both the target and the expected path, so the
    /// comparison is by canonical file, not by spelling: the same file
    /// reached through a symlinked parent directory compares equal, while
    /// a different file reached through one does not.
    private static func canonicalPath(_ url: URL) -> String {
        URL(fileURLWithPath: url.path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Opens with O_NOFOLLOW and no fallback. There is deliberately no
    /// retry without O_NOFOLLOW: if the safe open fails, the write fails
    /// instead of silently opening a less-safe descriptor.
    private static func openFile(_ url: URL, faults: FaultInjection) throws -> Int32 {
        if faults.failOpen { throw WriteError.openFailed(EACCES) }
        var capturedErrno: Int32 = 0
        let opened = url.path.withCString { ptr in
            let fd = open(ptr, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
            if fd < 0 { capturedErrno = errno }
            return fd
        }
        guard opened >= 0 else { throw WriteError.openFailed(capturedErrno) }
        return opened
    }

    private static func fullSync(_ fd: Int32, faults: FaultInjection) -> Bool {
        if faults.failSync { return false }
        if fcntl(fd, F_FULLFSYNC) == 0 { return true }
        return fsync(fd) == 0
    }

    private static func pwriteAll(_ fd: Int32, _ data: Data, startOffset: off_t,
                                  faults: FaultInjection) throws {
        var written = 0
        var shortWriteDone = false
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while written < data.count {
                if faults.failWrite { throw WriteError.writeFailed(EIO) }
                // A short write is normal: loop until every byte lands.
                // The fault below forces exactly one short (1-byte) write
                // so tests can prove the loop, not just assume it.
                var wanted = data.count - written
                if faults.shortWriteOnce, !shortWriteDone, wanted > 1 { wanted = 1 }
                let count = pwrite(fd, base.advanced(by: written), wanted,
                                   startOffset + off_t(written))
                if count < 0 {
                    if errno == EINTR { continue }
                    throw WriteError.writeFailed(errno)
                }
                if count == 0 { throw WriteError.writeFailed(0) }
                shortWriteDone = true
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
