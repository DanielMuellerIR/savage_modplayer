#include "CSavageAtomics.h"

#include <stdatomic.h>
#include <stdlib.h>

struct SavageAtomicUInt64 {
    _Atomic(uint64_t) value;
};

SavageAtomicUInt64 *savage_atomic_u64_create(uint64_t initial_value) {
    SavageAtomicUInt64 *atomic_value = malloc(sizeof(*atomic_value));
    if (atomic_value == NULL) {
        return NULL;
    }
    atomic_init(&atomic_value->value, initial_value);
    return atomic_value;
}

void savage_atomic_u64_destroy(SavageAtomicUInt64 *atomic_value) {
    free(atomic_value);
}

bool savage_atomic_u64_is_lock_free(const SavageAtomicUInt64 *atomic_value) {
    return atomic_is_lock_free(&atomic_value->value);
}

uint64_t savage_atomic_u64_load_relaxed(const SavageAtomicUInt64 *atomic_value) {
    return atomic_load_explicit(&atomic_value->value, memory_order_relaxed);
}

uint64_t savage_atomic_u64_load_acquire(const SavageAtomicUInt64 *atomic_value) {
    return atomic_load_explicit(&atomic_value->value, memory_order_acquire);
}

void savage_atomic_u64_store_relaxed(SavageAtomicUInt64 *atomic_value, uint64_t value) {
    atomic_store_explicit(&atomic_value->value, value, memory_order_relaxed);
}

void savage_atomic_u64_store_release(SavageAtomicUInt64 *atomic_value, uint64_t value) {
    atomic_store_explicit(&atomic_value->value, value, memory_order_release);
}

uint64_t savage_atomic_u64_exchange_acq_rel(SavageAtomicUInt64 *atomic_value, uint64_t value) {
    return atomic_exchange_explicit(&atomic_value->value, value, memory_order_acq_rel);
}
