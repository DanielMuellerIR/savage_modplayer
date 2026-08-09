#ifndef C_SAVAGE_ATOMICS_H
#define C_SAVAGE_ATOMICS_H

#include <stdbool.h>
#include <stdint.h>

typedef struct SavageAtomicUInt64 SavageAtomicUInt64;

SavageAtomicUInt64 *savage_atomic_u64_create(uint64_t initial_value);
void savage_atomic_u64_destroy(SavageAtomicUInt64 *atomic_value);
bool savage_atomic_u64_is_lock_free(const SavageAtomicUInt64 *atomic_value);

uint64_t savage_atomic_u64_load_relaxed(const SavageAtomicUInt64 *atomic_value);
uint64_t savage_atomic_u64_load_acquire(const SavageAtomicUInt64 *atomic_value);
void savage_atomic_u64_store_relaxed(SavageAtomicUInt64 *atomic_value, uint64_t value);
void savage_atomic_u64_store_release(SavageAtomicUInt64 *atomic_value, uint64_t value);
uint64_t savage_atomic_u64_exchange_acq_rel(SavageAtomicUInt64 *atomic_value, uint64_t value);

#endif
