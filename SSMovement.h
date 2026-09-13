#ifndef SS_MOVEMENT_H
#define SS_MOVEMENT_H

#include "SSSpeed.h"

#define SS_MAX_STEPS_PER_EVENT 256

typedef struct {
    double remainder;
    int granularity;
} SSMovement;

static inline void SSResetMovement(SSMovement *movement) {
    movement->remainder = 0.0;
    movement->granularity = -1;
}

/* The same distance budget drives movement and selection. No distance is lost
 * when iOS combines multiple touch samples into one callback. */
static inline int SSTakeMovementSteps(SSMovement *movement, double delta,
                                      double speed, bool words) {
    if (!isfinite(delta)) return 0;
    int mode = words ? 1 : 0;
    if (movement->granularity != mode) movement->remainder = 0.0;
    movement->granularity = mode;
    double threshold = (words ? 20.0 : 10.0) / SSNormalizeSpeed(speed);
    double total = movement->remainder + delta;
    double units = total / threshold;
    double whole = floor(fabs(units) + 1e-9);
    if (!isfinite(whole) || whole > SS_MAX_STEPS_PER_EVENT) {
        movement->remainder = 0.0;
        return total < 0 ? -SS_MAX_STEPS_PER_EVENT : SS_MAX_STEPS_PER_EVENT;
    }
    int steps = (total < 0 ? -1 : 1) * (int)whole;
    movement->remainder = total - steps * threshold;
    if (fabs(movement->remainder) < 1e-8) movement->remainder = 0.0;
    return steps;
}

#endif
