import CSavageAtomics

// Minimaler 64-Bit-Atomikhalter fuer den Echtzeitpfad. Er alloziert genau
// einmal beim Aufbau des Playback-Zustands; load/store/exchange selbst rufen
// nur C11-Atomikoperationen auf und nehmen keinen Lock.
final class LockFreeAtomicUInt64: @unchecked Sendable {
    private let storage: OpaquePointer

    init(_ initialValue: UInt64) {
        guard let storage = savage_atomic_u64_create(initialValue) else {
            preconditionFailure("Atomikspeicher konnte nicht angelegt werden")
        }
        precondition(
            savage_atomic_u64_is_lock_free(storage),
            "Der Echtzeit-Renderpfad benoetigt lockfreie 64-Bit-Atomik")
        self.storage = storage
    }

    deinit {
        savage_atomic_u64_destroy(storage)
    }

    @inline(__always)
    func loadRelaxed() -> UInt64 {
        savage_atomic_u64_load_relaxed(storage)
    }

    @inline(__always)
    func loadAcquire() -> UInt64 {
        savage_atomic_u64_load_acquire(storage)
    }

    @inline(__always)
    func storeRelaxed(_ value: UInt64) {
        savage_atomic_u64_store_relaxed(storage, value)
    }

    @inline(__always)
    func storeRelease(_ value: UInt64) {
        savage_atomic_u64_store_release(storage, value)
    }

    @inline(__always)
    func exchangeAcquiringAndReleasing(_ value: UInt64) -> UInt64 {
        savage_atomic_u64_exchange_acq_rel(storage, value)
    }
}
