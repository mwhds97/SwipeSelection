#ifndef SS_SPEED_H
#define SS_SPEED_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>

#define SS_SPEED_MIN 0.10
#define SS_SPEED_MAX 2.00
#define SS_SPEED_DEFAULT 1.00

/* Shared by the keyboard and Settings so corrupt preferences cannot cause
 * a zero distance threshold or unbounded movement. */
static inline double SSNormalizeSpeed(double speed) {
    if (!isfinite(speed)) return SS_SPEED_DEFAULT;
    if (speed < SS_SPEED_MIN) speed = SS_SPEED_MIN;
    if (speed > SS_SPEED_MAX) speed = SS_SPEED_MAX;
    return round(speed * 100.0) / 100.0;
}

/* A tagged scalar shared through notifyd, independent of an app's container. */
static inline uint64_t SSEncodeSpeed(double speed) {
    return UINT64_C(0x5353504400000000) | (uint64_t)llround(SSNormalizeSpeed(speed) * 100.0);
}

static inline bool SSDecodeSpeed(uint64_t state, double *speed) {
    uint64_t value = state & UINT64_C(0xffffffff);
    if ((state & UINT64_C(0xffffffff00000000)) != UINT64_C(0x5353504400000000) ||
        value < 10 || value > 200) return false;
    *speed = value / 100.0;
    return true;
}

#endif
