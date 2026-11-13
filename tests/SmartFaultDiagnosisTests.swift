// SPDX-License-Identifier: GPL-3.0-only
// Tests for Smart Fault Diagnosis (智能故障诊断): known-issue
// diagnoses carry a documented cause with evidence; unknown issues
// are reported as "cause not yet determined" with what was observed
// — never a guessed cause; suggested fixes are never presented as
// guarantees.
//
// Fixtures reuse `CoreModuleFixtures` (real documents, layouts and
// profiles built from explicit data — nothing is faked) and build
// health reports, fingerprint comparisons and acceptance reports
// directly from their public initializers.
import Foundation
import XCTest
@testable import GestaltX

final class SmartFaultDiagnosisTests: XCTestCase {
    // MARK: - Fixtures

    /// A profile for a known model. Pass `.unknown` for the layout
    /// to simulate an unresolvable cache layout.
    private func profile(
        layout: ProfileValue<MobileGestaltCacheLayout> = .known(CoreModuleFixtures.layout),
        productType: String = "iPhone14,7"
    ) -> DeviceProfile {
        DeviceProfile(
            productType: .known(productType),
            modelNumber: .known("A1234"),
            osVersion: .known("27.0.1"),
            osBuild: .known("23A344"),
            regionCode: .known("CH"),
            salesRegionSuffix: .known("CH/A"),
            isNativeAppleIntelligence: .known(false),
            modelDecision: DeviceModelSupport.decision(for: productType, originalRegModel: nil),
            cacheLayout: layout,
            cacheReadState: .read(cacheUUID: CoreModuleFixtures.uuid,
                                  byteCount: CoreModuleFixtures.layout.byteCount),
            liveAIEnabled: .unknown(reason: "test"),
            liveRegionCode: .known("CH"),
            appGroupAvailable: .known(true),
            shareExtensionPresent: .known(false),
            backupCount: 0,
            hasTrustedBackup: false,
            changeRecordCount: 0)
    }

    private func healthDimension(_ dimension: HealthDimension, level: HealthScoreLevel) -> HealthDimensionScore {
        let score: Int?
        switch level {
        case .healthy: score = 90
        case .fair: score = 60
        case .poor: score = 30
        case .unknown: score = nil
        }
        return HealthDimensionScore(
            dimension: dimension, score: score, level: level,
            reasons: ["test reason for \(dimension.rawValue)"])
    }

    private func health(
        cacheIntegrity: HealthScoreLevel = .healthy,
        compatibility: HealthScoreLevel = .healthy,
        backup: HealthScoreLevel = .healthy,
        modificationRisk: HealthScoreLevel = .healthy
    ) -> SystemHealthScore {
        SystemHealthScore(
            dimensions: [
                healthDimension(.cacheIntegrity, level: cacheIntegrity),
                healthDimension(.compatibility, level: compatibility),
                healthDimension(.backup, level: backup),
                healthDimension(.modificationRisk, level: modificationRisk),
            ],
            overallScore: 80, overallLevel: .healthy, summary: "test")
    }

    private func backupRecord(reason: String = "test") -> BackupRecord {
        BackupRecord(id: UUID(), date: Date(timeIntervalSince1970: 0), reason: reason,
                     source: .device, deviceID: "test-device", byteCount: 6480,
                     sha256: nil, provenance: .verifiedFactory)
    }

    /// A healthy input: a known device, one verified backup, no
    /// faults in any input. Diagnosing it must find no issues.
    private func healthyInput() -> FaultDiagnosisInput {
        let record = backupRecord()
        return FaultDiagnosisInput(
            profile: profile(),
            health: health(),
            backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .verified, layoutMatchesCurrent: true)])
    }

    private func regionRecord() -> RecordedChange {
        RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "regionCode", key: GestaltKeys.regionCode,
            layer: .cacheExtra, original: .string("CH"), new: .string("LL"),
            backupProvenance: .preModification, verified: true)
    }

    private func event(kind: OperationEventKind, key: String? = nil, detail: String = "test detail") -> OperationEvent {
        OperationEvent(kind: kind, key: key, detail: detail)
    }

    // MARK: - No issues / never read

    func testHealthyInputReportsNoIssues() {
        let report = SmartFaultDiagnosis.diagnose(healthyInput())
        XCTAssertTrue(report.diagnoses.isEmpty, "A healthy input must produce no diagnoses")
        XCTAssertFalse(report.hasIssues)
        XCTAssertEqual(report.summary, L("No issues were found in the available data."))
        XCTAssertFalse(report.eventsConnected, "No operation events were supplied")
    }

    func testNeverReadDiagnosis() {
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .verified, layoutMatchesCurrent: true)]))
        XCTAssertEqual(report.diagnoses.count, 1, "Only the never-read diagnosis should fire")
        let diagnosis = report.diagnoses[0]
        XCTAssertEqual(diagnosis.code, "never-read")
        XCTAssertEqual(diagnosis.severity, .info)
        XCTAssertTrue(diagnosis.cause.isKnown, "Never having read is a known state, not a mystery")
    }

    // MARK: - Region reverted (known)

    func testRegionRevertedKnownCause() throws {
        let current = try CoreModuleFixtures.document()
        let acceptance = PostModificationAcceptance.accept(
            records: [regionRecord()], current: current, restartConfirmed: true)
        XCTAssertEqual(acceptance.revertedKeys, [GestaltKeys.regionCode])
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), acceptance: acceptance,
            backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .verified, layoutMatchesCurrent: true)]))
        let diagnosis = report.diagnosis(code: "region-reverted")
        XCTAssertNotNil(diagnosis, "A reverted region after a confirmed restart must be diagnosed")
        XCTAssertEqual(diagnosis?.severity, .warning)
        XCTAssertTrue(diagnosis?.cause.isKnown == true, "The region revert is a documented known issue")
        XCTAssertFalse(diagnosis?.evidence.isEmpty == true, "The diagnosis must cite its evidence")
        XCTAssertTrue(diagnosis?.relatedKeys.contains(GestaltKeys.regionCode) == true)
    }

    func testRegionRevertedNeedsRestartConfirmation() throws {
        let current = try CoreModuleFixtures.document()
        let acceptance = PostModificationAcceptance.accept(
            records: [regionRecord()], current: current, restartConfirmed: false)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), acceptance: acceptance))
        XCTAssertNil(report.diagnosis(code: "region-reverted"),
                     "Without a confirmed restart the revert is not claimed as the known restart behavior")
    }

    func testRegionRevertedFromEvent() {
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(),
            events: [event(kind: .regionReverted, key: GestaltKeys.regionCode,
                           detail: "Region read CH again after restart")]))
        XCTAssertNotNil(report.diagnosis(code: "region-reverted"),
                        "A region-reverted operation event is sufficient evidence")
    }

    // MARK: - Layout unresolved (known, deduped)

    func testLayoutUnresolvedKnownCause() {
        let unresolved = profile(layout: .unknown(reason: "test: layout cannot be resolved"))
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(profile: unresolved))
        let diagnosis = report.diagnosis(code: "layout-unresolved")
        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.severity, .warning)
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
        XCTAssertTrue(diagnosis?.evidence.contains("test: layout cannot be resolved") == true,
                      "The layout's own unknown reason is the evidence")
    }

    func testLayoutUnresolvedDedupedAcrossInputs() {
        let unresolved = profile(layout: .unknown(reason: "test: layout cannot be resolved"))
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: unresolved,
            events: [event(kind: .guardLayoutUnresolved, detail: "guard refused staging")]))
        let matches = report.diagnoses.filter { diagnosis in diagnosis.code == "layout-unresolved" }
        XCTAssertEqual(matches.count, 1, "The same issue seen through two inputs is reported once")
        XCTAssertEqual(matches[0].evidence.count, 2, "Evidence from both inputs is kept")
    }

    // MARK: - AdvAI slot (known)

    func testAdvAISlotFromConflictEvaluation() {
        let evaluation = LilaFeatureEvaluation(
            featureID: "audioIntelligence", title: "Audio Intelligence",
            eligibility: .conflict, reason: "test guard reason", riskLevel: .medium)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), evaluations: [evaluation]))
        let diagnosis = report.diagnosis(code: "adv-ai-slot")
        XCTAssertNotNil(diagnosis, "A conflict evaluation for an AdvAI feature must be diagnosed")
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
        XCTAssertTrue(diagnosis?.evidence.contains("test guard reason") == true)
        XCTAssertTrue(diagnosis?.relatedKeys.contains(DeviceCacheOptions.audioIntelligenceKey) == true)
    }

    func testAdvAISlotFromSlotEvent() {
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(),
            events: [event(kind: .slotUnresolvable, key: DeviceCacheOptions.audioIntelligenceKey,
                           detail: "slot #178 did not resolve")]))
        XCTAssertNotNil(report.diagnosis(code: "adv-ai-slot"))
    }

    func testAdvAISlotFromUnreadableAcceptance() throws {
        // The offline profile layout does not resolve the AdvAI slots,
        // so the audio-intelligence item is unreadable after re-read.
        let audioRecord = RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "audioIntelligence",
            key: DeviceCacheOptions.audioIntelligenceKey, layer: .cacheData,
            original: .bool(false), new: .bool(true),
            backupProvenance: .preModification, verified: true)
        let current = try CoreModuleFixtures.document()
        let acceptance = PostModificationAcceptance.accept(
            records: [audioRecord], current: current, restartConfirmed: true)
        XCTAssertEqual(acceptance.items.first?.outcome, .unreadable)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), acceptance: acceptance))
        XCTAssertNotNil(report.diagnosis(code: "adv-ai-slot"),
                        "An unreadable AdvAI item is the slot problem, not a generic unreadable field")
        XCTAssertNil(report.diagnosis(code: "acceptance-unreadable"),
                     "The AdvAI item must not also produce the generic unreadable diagnosis")
    }

    // MARK: - Hardware-identity guard (known)

    func testHardwareIdentityGuardKnownCause() {
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(),
            events: [event(kind: .guardHardwareIdentity,
                           detail: "This proposal touches a hardware-identity field.")]))
        let diagnosis = report.diagnosis(code: "hardware-identity-guard")
        XCTAssertNotNil(diagnosis)
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
        XCTAssertTrue(diagnosis?.suggestedFix.contains("Remove") == true)
    }

    // MARK: - Backups (known)

    func testBackupMissingKnownCause() {
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .notFound, layoutMatchesCurrent: nil)]))
        let diagnosis = report.diagnosis(code: "backup-missing")
        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.severity, .error)
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
        XCTAssertFalse(diagnosis?.evidence.isEmpty == true)
    }

    func testBackupCorruptKnownCause() {
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record,
                status: .failed(reason: L("The backup could not be verified. No system changes were made.")),
                layoutMatchesCurrent: nil)]))
        let diagnosis = report.diagnosis(code: "backup-corrupt")
        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.severity, .error)
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
    }

    func testBackupCorruptFromEvent() {
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), backupRecords: [record],
            backupVerifications: [],
            events: [event(kind: .backupFailed, detail: "digest mismatch")]))
        // Verifications are empty, so the unverified rule would also
        // fire — the corrupt diagnosis must still be present.
        XCTAssertNotNil(report.diagnosis(code: "backup-corrupt"))
        XCTAssertNotNil(report.diagnosis(code: "backup-unverified"))
    }

    func testBackupLayoutMismatchKnownCause() {
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .verified, layoutMatchesCurrent: false)]))
        let diagnosis = report.diagnosis(code: "backup-layout-mismatch")
        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.severity, .warning)
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
    }

    func testBackupNoneAndUnverified() {
        let noBackups = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(profile: profile()))
        XCTAssertNotNil(noBackups.diagnosis(code: "backup-none"))
        XCTAssertNil(noBackups.diagnosis(code: "backup-unverified"))

        let unverified = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), backupRecords: [backupRecord()]))
        XCTAssertNotNil(unverified.diagnosis(code: "backup-unverified"))
        XCTAssertNil(unverified.diagnosis(code: "backup-none"))
    }

    // MARK: - Fingerprint

    func testFingerprintInvalidatedKnownCause() {
        let change = FingerprintChange(
            field: "osBuild", displayName: L("Build"),
            old: "23A344", new: "23B123", invalidatesSupportScope: true)
        let comparison = FingerprintComparison(
            changes: [change], differentDevice: false, invalidatesSupportScope: true)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), fingerprintComparison: comparison))
        let diagnosis = report.diagnosis(code: "fingerprint-invalidated")
        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.severity, .warning)
        XCTAssertTrue(diagnosis?.cause.isKnown == true)
        XCTAssertTrue(diagnosis?.evidence.contains("Build: 23A344 → 23B123") == true,
                      "The changed field is the evidence, got: \(diagnosis?.evidence ?? [])")
    }

    func testFingerprintChangedOnlyIsUndetermined() {
        let change = FingerprintChange(
            field: "regionCode", displayName: L("Region code"),
            old: "CH", new: "LL", invalidatesSupportScope: false)
        let comparison = FingerprintComparison(
            changes: [change], differentDevice: false, invalidatesSupportScope: false)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), fingerprintComparison: comparison))
        let diagnosis = report.diagnosis(code: "device-state-changed")
        XCTAssertNotNil(diagnosis)
        XCTAssertEqual(diagnosis?.severity, .info)
        XCTAssertFalse(diagnosis?.cause.isKnown == true,
                       "A bare value change has no known cause — only the observation")
        XCTAssertTrue(diagnosis?.cause.text.contains("Cause not yet determined.") == true)
        XCTAssertNil(report.diagnosis(code: "fingerprint-invalidated"))
    }

    // MARK: - Acceptance: live disagreement and unreadable

    func testLiveDisagreementKnownCause() throws {
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let acceptance = PostModificationAcceptance.accept(
            records: [regionRecord()], current: current,
            liveValues: [GestaltKeys.regionCode: .string("CH")],
            restartConfirmed: true)
        XCTAssertEqual(acceptance.items.first?.liveAgrees, false)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), acceptance: acceptance))
        let diagnosis = report.diagnosis(code: "live-disagreement")
        XCTAssertNotNil(diagnosis, "File LL vs live CH must be diagnosed")
        XCTAssertEqual(diagnosis?.severity, .warning)
        XCTAssertTrue(diagnosis?.cause.isKnown == true,
                      "The file-vs-live distinction is documented, not a guess")
    }

    func testAcceptanceUnreadableUndetermined() throws {
        // A post-restart document whose layout cannot resolve leaves
        // the green-tea CacheData item unreadable.
        let greenTeaRecord = RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "esim", key: DeviceCacheOptions.greenTeaKey,
            layer: .cacheData, original: .bool(true), new: .bool(false),
            backupProvenance: .preModification, verified: true)
        let current = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": "00000000-0000-0000-0000-000000000000",
            "CacheData": CoreModuleFixtures.cacheData(greenTea: true, notGreenTea: false, wapi: true),
            "CacheExtra": [GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
        let acceptance = PostModificationAcceptance.accept(
            records: [greenTeaRecord], current: current, restartConfirmed: true)
        XCTAssertEqual(acceptance.items.first?.outcome, .unreadable)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(), acceptance: acceptance))
        let diagnosis = report.diagnosis(code: "acceptance-unreadable")
        XCTAssertNotNil(diagnosis)
        XCTAssertFalse(diagnosis?.cause.isKnown == true,
                       "Why the field could not be re-read is not known — only that it could not be read")
    }

    // MARK: - Health dimensions (undetermined)

    func testHealthDimensionDiagnosesAreUndetermined() {
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(),
            health: health(cacheIntegrity: .poor, compatibility: .unknown,
                           modificationRisk: .poor)))
        let cache = report.diagnosis(code: "cache-integrity")
        XCTAssertNotNil(cache, "A poor cache-integrity dimension must be diagnosed")
        XCTAssertFalse(cache?.cause.isKnown == true)
        XCTAssertFalse(cache?.evidence.isEmpty == true, "The dimension reasons are the evidence")
        let compatibility = report.diagnosis(code: "compatibility-unknown")
        XCTAssertNotNil(compatibility)
        XCTAssertFalse(compatibility?.cause.isKnown == true)
        let risk = report.diagnosis(code: "modification-risk")
        XCTAssertNotNil(risk)
        XCTAssertFalse(risk?.cause.isKnown == true)
    }

    func testCompatibilityUnknownFromProfileWithoutHealth() {
        // A device the profiler could not identify has no product
        // type, so compatibility is unknown even with no health score.
        let noIdentity = DeviceProfile(
            productType: .unknown(reason: "Device identity is unavailable."),
            modelNumber: .unknown(reason: "Device identity is unavailable."),
            osVersion: .unknown(reason: "Device identity is unavailable."),
            osBuild: .unknown(reason: "Device identity is unavailable."),
            regionCode: .unknown(reason: "No document has been read."),
            salesRegionSuffix: .unknown(reason: "No document has been read."),
            isNativeAppleIntelligence: .unknown(reason: "Device identity is unavailable."),
            modelDecision: DeviceModelSupport.decision(for: "", originalRegModel: nil),
            cacheLayout: .known(CoreModuleFixtures.layout),
            cacheReadState: .notRead,
            liveAIEnabled: .unknown(reason: "Live status unknown"),
            liveRegionCode: .unknown(reason: "Live status unknown"),
            appGroupAvailable: .unknown(reason: "Signing state could not be read."),
            shareExtensionPresent: .unknown(reason: "Signing state could not be read."),
            backupCount: 0, hasTrustedBackup: false, changeRecordCount: 0)
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(profile: noIdentity))
        XCTAssertNotNil(report.diagnosis(code: "compatibility-unknown"),
                        "An unknown product type is a compatibility unknown even without a health score")
    }

    // MARK: - Failed operations: never a guessed cause

    func testFailedOperationsAreUndetermined() {
        // A verified backup is supplied so no backup diagnosis joins
        // the report: every diagnosis here must be a failed operation.
        let record = backupRecord()
        let report = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile(),
            backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .verified, layoutMatchesCurrent: true)],
            events: [
                event(kind: .readFailed, detail: "Read failed: the device could not be reached."),
                event(kind: .writeFailed, detail: "Write verification failed after commit."),
                event(kind: .restoreFailed, detail: "Restore failed: the backup could not be read."),
            ]))
        XCTAssertEqual(report.diagnoses.filter { diagnosis in diagnosis.code == "read-failed" }.count, 1)
        XCTAssertEqual(report.diagnoses.filter { diagnosis in diagnosis.code == "write-failed" }.count, 1)
        XCTAssertEqual(report.diagnoses.filter { diagnosis in diagnosis.code == "restore-failed" }.count, 1)
        for diagnosis in report.diagnoses {
            XCTAssertFalse(diagnosis.cause.isKnown,
                           "\(diagnosis.code) must not invent a cause")
            XCTAssertTrue(diagnosis.cause.text.contains("Cause not yet determined."),
                          "\(diagnosis.code) must say the cause is not yet determined, got: \(diagnosis.cause.text)")
            XCTAssertEqual(diagnosis.severity, .error, "A failed operation is an error")
        }
    }

    // MARK: - No guaranteed fixes, severity order

    func testNoDiagnosisClaimsAGuaranteedFix() {
        let record = backupRecord()
        let input = FaultDiagnosisInput(
            profile: profile(layout: .unknown(reason: "test: layout cannot be resolved")),
            health: health(cacheIntegrity: .poor, compatibility: .unknown,
                           modificationRisk: .poor),
            fingerprintComparison: FingerprintComparison(
                changes: [FingerprintChange(
                    field: "osBuild", displayName: L("Build"),
                    old: "23A344", new: "23B123", invalidatesSupportScope: true)],
                differentDevice: false, invalidatesSupportScope: true),
            backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .notFound, layoutMatchesCurrent: nil)],
            events: [
                event(kind: .writeFailed, detail: "Write verification failed after commit."),
                event(kind: .guardHardwareIdentity, detail: "This proposal touches a hardware-identity field."),
            ])
        let report = SmartFaultDiagnosis.diagnose(input)
        XCTAssertFalse(report.diagnoses.isEmpty)
        for diagnosis in report.diagnoses {
            let fix = diagnosis.suggestedFix.lowercased()
            XCTAssertFalse(fix.contains("guarantee"),
                           "\(diagnosis.code) must never present a fix as a guarantee: \(diagnosis.suggestedFix)")
            XCTAssertFalse(fix.contains("will fix") || fix.contains("will work"),
                           "\(diagnosis.code) must never claim a fix will work: \(diagnosis.suggestedFix)")
            XCTAssertFalse(diagnosis.title.contains("100%") || diagnosis.whatHappened.contains("100%"),
                           "\(diagnosis.code) must never claim 100%")
        }
        XCTAssertTrue(report.summary.contains("errors"), "The summary counts severities, got: \(report.summary)")
    }

    func testDiagnosesAreSortedBySeverity() {
        let record = backupRecord()
        let input = FaultDiagnosisInput(
            profile: profile(),
            fingerprintComparison: FingerprintComparison(
                changes: [FingerprintChange(
                    field: "regionCode", displayName: L("Region code"),
                    old: "CH", new: "LL", invalidatesSupportScope: false)],
                differentDevice: false, invalidatesSupportScope: false),
            backupRecords: [record],
            backupVerifications: [BackupVerification(
                record: record, status: .notFound, layoutMatchesCurrent: nil)],
            events: [event(kind: .readFailed, detail: "Read failed.")])
        let report = SmartFaultDiagnosis.diagnose(input)
        // Errors (backup-missing, read-failed) before warnings, before
        // the info-level device-state-changed diagnosis.
        let orders = report.diagnoses.map { diagnosis in diagnosis.severity.sortOrder }
        XCTAssertEqual(orders, orders.sorted(), "Diagnoses must be ordered errors, warnings, notes")
        XCTAssertEqual(report.errorCount, 2)
        XCTAssertEqual(report.infoCount, 1)
    }
}
