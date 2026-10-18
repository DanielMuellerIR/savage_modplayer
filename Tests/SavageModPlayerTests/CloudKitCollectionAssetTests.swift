#if canImport(CloudKit)
    import XCTest
    import CloudKit
    @testable import SavageModPlayerCore

    @MainActor
    final class CloudKitCollectionAssetTests: XCTestCase {
        func testUnknownAudioAndLocalPathFieldsAreRemovedFromBothAssetDirections() throws {
            let (snapshot, file) = try fixture()
            let expected = try CollectionSyncCodec.encode(snapshot)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: expected) as? [String: Any])
            object["extraAudioData"] = Data([1, 2, 3]).base64EncodedString()
            object["localSourceURL"] = "file:///synthetic/private.mod"
            let untrusted = try JSONSerialization.data(withJSONObject: object)
            try untrusted.write(to: file)
            let (_, uploaded) = try CloudKitCollectionAssetBackend.uploadPayload(untrusted)
            let record = CloudKitCollectionAssetBackend.record(snapshot: snapshot, assetURL: file, ancestor: nil)
            let downloaded = try CloudKitCollectionAssetBackend.payload(record)
            XCTAssertEqual(uploaded, expected)
            XCTAssertEqual(downloaded, expected)
            XCTAssertFalse(String(decoding: uploaded, as: UTF8.self).contains("localSourceURL"))
            XCTAssertFalse(String(decoding: downloaded, as: UTF8.self).contains("extraAudioData"))
        }

        func testUploadRejectsLocalOnlyStateBeforeCreatingACloudContainer() async throws {
            let (snapshot, _) = try fixture()
            let account = CollectionSyncAccountToken(scope: String(repeating: "a", count: 64), epoch: UUID())
            let state = CollectionSyncLocalState(checkpoint: .init(account: account, base: snapshot, local: snapshot),
                                                registry: .init(account: account, collectionID: snapshot.collectionID, generation: snapshot.generation))
            let backend = try CloudKitCollectionAssetBackend(containerIdentifier: "iCloud.org.example.Synthetic")
            do {
                _ = try await backend.save(CollectionSyncLocalStateCodec.encode(state), replacing: nil)
                XCTFail("Local-only data must never reach CloudKit")
            } catch { XCTAssertEqual(error as? CollectionSyncError, .invalidSnapshot) }
        }

        private func fixture() throws -> (CollectionSyncSnapshot, URL) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "CloudAssetContract-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }
            let snapshot = CollectionSyncSnapshot(collectionID: UUID(), generation: UUID())
            let file = root.appendingPathComponent("metadata.json")
            try CollectionSyncCodec.encode(snapshot).write(to: file)
            return (snapshot, file)
        }

        func testActualSDKAssetAndRecordPayloadRoundTripWithoutAContainer() throws {
            let (snapshot, file) = try fixture()
            let record = CloudKitCollectionAssetBackend.record(
                snapshot: snapshot, assetURL: file, ancestor: nil)
            let data = try CloudKitCollectionAssetBackend.payload(record)
            XCTAssertEqual(try CollectionSyncCodec.decode(data), snapshot)
            XCTAssertEqual((record["payload"] as? CKAsset)?.fileURL, file)
            XCTAssertEqual(record.recordID.zoneID.zoneName, "SavageCollection")
            XCTAssertThrowsError(try CloudKitCollectionAssetBackend.decode(record))
            let config = CloudKitCollectionAssetBackend.configuration()
            XCTAssertEqual(config.timeoutIntervalForRequest, 30)
            XCTAssertEqual(config.timeoutIntervalForResource, 60)
            XCTAssertNoThrow(
                try CloudKitCollectionAssetBackend(
                    containerIdentifier: "iCloud.org.example.Synthetic"))
            XCTAssertThrowsError(
                try CloudKitCollectionAssetBackend(containerIdentifier: "https://invalid.example"))
        }

        func testAssetIdentitySchemaCorruptionAndOversizeAreRejected() throws {
            let (snapshot, file) = try fixture()
            let record = CloudKitCollectionAssetBackend.record(
                snapshot: snapshot, assetURL: file, ancestor: nil)
            record["generation"] = UUID().uuidString as CKRecordValue
            XCTAssertThrowsError(try CloudKitCollectionAssetBackend.payload(record))
            record["generation"] = snapshot.generation.uuidString as CKRecordValue
            record["schemaVersion"] = NSNumber(value: 1.5)
            XCTAssertThrowsError(try CloudKitCollectionAssetBackend.payload(record))
            record["schemaVersion"] = NSNumber(value: 1)
            try Data("{broken".utf8).write(to: file)
            XCTAssertThrowsError(try CloudKitCollectionAssetBackend.payload(record))
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(CollectionSyncCodec.maximumBytes + 1))
            try handle.close()
            XCTAssertThrowsError(try CloudKitCollectionAssetBackend.payload(record)) {
                XCTAssertEqual($0 as? CollectionSyncError, .oversized)
            }
        }

        func testSDKFailuresHaveBoundedRetryHintsAndNoRawServiceText() throws {
            let delayed = CKError(
                .requestRateLimited, userInfo: [CKErrorRetryAfterKey: NSNumber(value: 12)])
            XCTAssertEqual(
                CloudKitCollectionAssetBackend.translated(delayed) as? CollectionSyncTransportError,
                .temporarilyUnavailable(retryAfter: 12))
            for delay in [-1.0, Double.nan, Double.infinity, 3601] {
                let error = CKError(
                    .serviceUnavailable, userInfo: [CKErrorRetryAfterKey: NSNumber(value: delay)])
                XCTAssertEqual(
                    CloudKitCollectionAssetBackend.translated(error)
                        as? CollectionSyncTransportError, .temporarilyUnavailable(retryAfter: nil))
            }
            XCTAssertEqual(
                CloudKitCollectionAssetBackend.translated(CKError(.quotaExceeded))
                    as? CollectionSyncTransportError, .quotaExceeded)
            XCTAssertEqual(
                CloudKitCollectionAssetBackend.translated(CKError(.unknownItem))
                    as? CollectionSyncTransportError, .missingRecord)
            XCTAssertEqual(
                CloudKitCollectionAssetBackend.translated(CKError(.userDeletedZone))
                    as? CollectionSyncTransportError, .configurationRequired)
            let raw = CKError(
                .internalError, userInfo: [NSLocalizedDescriptionKey: "private-service-detail"])
            XCTAssertFalse(
                CloudKitCollectionAssetBackend.translated(raw).localizedDescription.contains(
                    "private-service-detail"))
        }

        func testMissingZoneIsAbsentWhileDeletedZonesAndInvalidContainersStayBlocked() {
            XCTAssertEqual(
                CloudKitCollectionAssetBackend.translated(CKError(.zoneNotFound))
                    as? CollectionSyncTransportError, .missingRecord)
            for code in [CKError.Code.userDeletedZone, .badContainer, .missingEntitlement] {
                XCTAssertEqual(
                    CloudKitCollectionAssetBackend.translated(CKError(code))
                        as? CollectionSyncTransportError, .configurationRequired)
            }
        }

        func testSingleRecordPartialFailurePreservesTheConditionalWriteConflict() {
            let error = CKError(
                .partialFailure,
                userInfo: [
                    CKPartialErrorsByItemIDKey: [
                        CloudKitCollectionAssetBackend.recordID: CKError(.serverRecordChanged)
                    ]
                ])
            XCTAssertEqual(
                CloudKitCollectionAssetBackend.translated(error) as? CollectionSyncTransportError,
                .conflict)
        }
    }
#endif
