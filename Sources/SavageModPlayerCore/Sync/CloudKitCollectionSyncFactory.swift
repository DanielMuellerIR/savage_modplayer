#if canImport(CloudKit) && canImport(Combine)
import Foundation

public enum CloudKitCollectionSyncFactory {
    public static func service(bundle: Bundle = .main) -> CollectionSyncService? {
        guard let identifier = bundle.object(forInfoDictionaryKey: "CollectionSyncContainerIdentifier") as? String,
              let backend = try? CloudKitCollectionAssetBackend(containerIdentifier: identifier) else { return nil }
        return .init(backend: backend, prepareNewCollection: { try await backend.createZone(account: $0) })
    }
}
#endif
