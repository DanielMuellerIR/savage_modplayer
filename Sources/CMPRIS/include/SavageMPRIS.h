#ifndef SAVAGE_MPRIS_H
#define SAVAGE_MPRIS_H
#include <stdint.h>
typedef struct SavageMPRIS SavageMPRIS;
typedef enum {
    SAVAGE_MPRIS_NONE, SAVAGE_MPRIS_PLAY, SAVAGE_MPRIS_PAUSE,
    SAVAGE_MPRIS_TOGGLE, SAVAGE_MPRIS_STOP, SAVAGE_MPRIS_NEXT,
    SAVAGE_MPRIS_PREVIOUS, SAVAGE_MPRIS_QUIT
} SavageMPRISCommand;
SavageMPRIS *savage_mpris_create(double sample_rate);
void savage_mpris_destroy(SavageMPRIS *service);
void savage_mpris_track(SavageMPRIS *service, const char *title, const char *uri,
                        uint64_t track_id, int can_next, int can_previous);
void savage_mpris_status(SavageMPRIS *service, const char *status);
SavageMPRISCommand savage_mpris_poll(SavageMPRIS *service);
// Diese beiden Funktionen verwenden ausschließlich lockfreie Atomics.
double savage_mpris_gain(const SavageMPRIS *service);
void savage_mpris_add_frames(SavageMPRIS *service, uint64_t frames);
#endif
