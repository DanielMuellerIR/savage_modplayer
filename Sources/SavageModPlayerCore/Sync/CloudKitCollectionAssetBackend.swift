#if canImport(CloudKit)
    import Foundation
    import CloudKit
    import CryptoKit

    public struct CloudKitCollectionAssetBackend: CollectionSyncAssetBackend {
        private let containerIdentifier: String
        static let zoneID = CKRecordZone.ID(
            zoneName: "SavageCollection", ownerName: CKCurrentUserDefaultName)
        static let recordID = CKRecord.ID(recordName: "snapshot", zoneID: zoneID)

        public init(containerIdentifier: String) throws {
            guard containerIdentifier.hasPrefix("iCloud."),
                (8...255).contains(containerIdentifier.utf8.count),
                containerIdentifier.utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0)
                        || (48...57).contains($0) || [45, 46, 95].contains($0)
                })
            else {
                throw CollectionSyncTransportError.configurationRequired
            }
            self.containerIdentifier = containerIdentifier
        }

        public func currentAccountScope() async throws -> String {
            do {
                try Task.checkCancellation()
                let container = CKContainer(identifier: containerIdentifier)
                return try await container.configuredWith(configuration: Self.configuration()) {
                    scoped in
                    guard try await scoped.accountStatus() == .available else {
                        throw CollectionSyncTransportError.accountUnavailable
                    }
                    let id = try await scoped.userRecordID()
                    return SHA256.hash(
                        data: Data((containerIdentifier + "\0" + id.recordName).utf8)
                    )
                    .map { String(format: "%02x", $0) }.joined()
                }
            } catch { throw Self.translated(error) }
        }

        // Die Anwendung muss die Zone ausdrücklich einrichten. Ein fehlender oder
        // gelöschter Cloud-Speicher wird beim normalen Lesen nicht neu angelegt.
        public func createZone(account token: CollectionSyncAccountToken) async throws {
            try token.validate()
            guard try await currentAccountScope() == token.scope else {
                throw CollectionSyncError.staleAccount
            }
            do {
                let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
                _ = try await database.configuredWith(configuration: Self.configuration()) {
                    scoped in
                    try await scoped.save(CKRecordZone(zoneID: Self.zoneID))
                }
            } catch { throw Self.translated(error) }
            guard try await currentAccountScope() == token.scope else {
                throw CollectionSyncError.staleAccount
            }
        }

        public func fetch() async throws -> CollectionSyncCloudAsset? {
            do {
                try Task.checkCancellation()
                let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
                guard let record = try await readRecord(database) else { return nil }
                return try Self.decode(record)
            } catch { throw Self.translated(error) }
        }

        public func save(_ data: Data, replacing changeTag: String?) async throws
            -> CollectionSyncCloudAsset
        {
            do { return try await saveValidated(data, replacing: changeTag) } catch {
                throw Self.translated(error)
            }
        }

        private func saveValidated(_ data: Data, replacing changeTag: String?) async throws
            -> CollectionSyncCloudAsset
        {
            try Task.checkCancellation()
            let (snapshot, payload) = try Self.uploadPayload(data)
            if let changeTag { try CollectionSyncTransportClient.validateTag(changeTag) }
            let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
            let current = try await readRecord(database)
            guard current?.recordChangeTag == changeTag else {
                throw CollectionSyncTransportError.conflict
            }
            if let current {
                let previous = try CollectionSyncCodec.decode(Self.decode(current).data)
                guard previous.collectionID == snapshot.collectionID else {
                    throw CollectionSyncError.mismatchedCollection
                }
                guard previous.generation == snapshot.generation else {
                    throw CollectionSyncError.staleGeneration
                }
                guard Set(previous.cells.map(\.id)).isSubset(of: Set(snapshot.cells.map(\.id)))
                else { throw CollectionSyncError.incompleteSnapshot }
            }
            try Task.checkCancellation()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "CollectionSyncUpload-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
            )
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("metadata.json")
            try payload.write(to: file, options: .withoutOverwriting)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: file.path)
            let record = Self.record(snapshot: snapshot, assetURL: file, ancestor: current)
            do {
                let saved = try await database.configuredWith(configuration: Self.configuration()) {
                    scoped in
                    let result = try await scoped.modifyRecords(
                        saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged,
                        atomically: true)
                    guard let item = result.saveResults[Self.recordID] else {
                        throw CollectionSyncTransportError.invalidResponse
                    }
                    return try item.get()
                }
                guard saved.recordID == Self.recordID, let tag = saved.recordChangeTag else {
                    throw CollectionSyncTransportError.invalidResponse
                }
                try CollectionSyncTransportClient.validateTag(tag)
                return .init(data: payload, changeTag: tag)
            } catch { throw Self.translated(error) }
        }

        private func readRecord(_ database: CKDatabase) async throws -> CKRecord? {
            do {
                try Task.checkCancellation()
                return try await database.configuredWith(configuration: Self.configuration()) {
                    scoped in
                    try await scoped.record(for: Self.recordID)
                }
            } catch {
                let error = Self.translated(error)
                if error as? CollectionSyncTransportError == .missingRecord { return nil }
                throw error
            }
        }

        static func configuration() -> CKOperation.Configuration {
            let value = CKOperation.Configuration()
            value.timeoutIntervalForRequest = 30
            value.timeoutIntervalForResource = 60
            return value
        }

        static func record(snapshot: CollectionSyncSnapshot, assetURL: URL, ancestor: CKRecord?)
            -> CKRecord
        {
            let record = ancestor ?? CKRecord(recordType: "CollectionState", recordID: recordID)
            record["schemaVersion"] = NSNumber(value: 1)
            record["collectionID"] = snapshot.collectionID.uuidString as CKRecordValue
            record["generation"] = snapshot.generation.uuidString as CKRecordValue
            record["revision"] = UUID().uuidString as CKRecordValue
            record["payload"] = CKAsset(fileURL: assetURL)
            return record
        }

        static func decode(_ record: CKRecord) throws -> CollectionSyncCloudAsset {
            guard let tag = record.recordChangeTag else {
                throw CollectionSyncTransportError.invalidResponse
            }
            try CollectionSyncTransportClient.validateTag(tag)
            return .init(data: try payload(record), changeTag: tag)
        }

        static func uploadPayload(_ data: Data) throws -> (CollectionSyncSnapshot, Data) {
            let snapshot = try CollectionSyncCodec.decode(data)
            // JSONDecoder ignoriert unbekannte Felder. Nur erneutes Codieren
            // verhindert, dass solche Zusatzdaten versehentlich hochgeladen werden.
            return (snapshot, try CollectionSyncCodec.encode(snapshot))
        }

        static func payload(_ record: CKRecord) throws -> Data {
            guard record.recordType == "CollectionState", record.recordID == recordID,
                (record["schemaVersion"] as? NSNumber)?.doubleValue == 1,
                let collection = record["collectionID"] as? String,
                let collectionID = UUID(uuidString: collection),
                let generation = record["generation"] as? String,
                let generationID = UUID(uuidString: generation),
                let revision = record["revision"] as? String, UUID(uuidString: revision) != nil,
                let asset = record["payload"] as? CKAsset, let url = asset.fileURL
            else { throw CollectionSyncTransportError.invalidResponse }
            let file = try LibraryFileReader(url)
            defer { file.close() }
            guard file.stamp.size <= Int64(CollectionSyncCodec.maximumBytes) else {
                throw CollectionSyncError.oversized
            }
            let data = try file.read(
                limit: CollectionSyncCodec.maximumBytes, isCancelled: { Task.isCancelled })
            let snapshot = try CollectionSyncCodec.decode(data)
            guard snapshot.collectionID == collectionID, snapshot.generation == generationID else {
                throw CollectionSyncTransportError.invalidResponse
            }
            return try CollectionSyncCodec.encode(snapshot)
        }

        static func translated(_ error: Error, depth: Int = 0) -> Error {
            if error is CollectionSyncError || error is CollectionExchangeError
                || error is CollectionSyncTransportError || error is CancellationError
            {
                return error
            }
            guard let cloud = error as? CKError else {
                return CollectionSyncTransportError.serviceFailure
            }
            if cloud.code == .partialFailure, depth < 4,
                let values = cloud.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
                values.count == 1,
                let nested = values.values.first
            {
                return translated(nested, depth: depth + 1)
            }
            switch cloud.code {
            // Auch eine neue private Zone fehlt beim ersten Lesen. Nur die
            // ausdrückliche Einrichtung darf sie danach anlegen; ein vorhandener
            // Checkpoint behandelt den fehlenden Record weiterhin als Fehler.
            case .unknownItem, .zoneNotFound: return CollectionSyncTransportError.missingRecord
            case .serverRecordChanged: return CollectionSyncTransportError.conflict
            case .notAuthenticated: return CollectionSyncTransportError.accountUnavailable
            case .quotaExceeded: return CollectionSyncTransportError.quotaExceeded
            case .operationCancelled: return CancellationError()
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
                .zoneBusy:
                let delay = (cloud.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
                return CollectionSyncTransportError.temporarilyUnavailable(
                    retryAfter: delay.flatMap { $0.isFinite && (0...3600).contains($0) ? $0 : nil })
            case .userDeletedZone, .badContainer, .badDatabase, .missingEntitlement,
                .permissionFailure, .serverRejectedRequest:
                return CollectionSyncTransportError.configurationRequired
            default: return CollectionSyncTransportError.serviceFailure
            }
        }
    }
#endif
