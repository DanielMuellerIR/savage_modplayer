import Foundation
import SavageModPlayerCore

enum CollectionSyncConfiguration {
    static func service() -> CollectionSyncService? {
        #if SAVAGE_CLOUDKIT_ENABLED
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "CollectionSyncContainerIdentifier") as? String,
              let backend = try? CloudKitCollectionAssetBackend(containerIdentifier: identifier) else { return nil }
        return .init(backend: backend, prepareNewCollection: { try await backend.createZone(account: $0) })
        #else
        return nil
        #endif
    }
}
