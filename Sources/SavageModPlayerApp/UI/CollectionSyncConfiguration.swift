import SavageModPlayerCore

enum CollectionSyncConfiguration {
    static func service() -> CollectionSyncService? {
        #if SAVAGE_CLOUDKIT_ENABLED
        return CloudKitCollectionSyncFactory.service()
        #else
        return nil
        #endif
    }
}
