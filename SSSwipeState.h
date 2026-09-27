#ifndef SS_SWIPE_STATE_H
#define SS_SWIPE_STATE_H

#include <stdbool.h>

// A gesture belongs to its original input until the finger is lifted. Losing
// focus or the keyboard invalidates it; active composition does not.
typedef enum {
    SSSwipePending,
    SSSwipeClaimed,
    SSSwipeBypassed
} SSSwipeState;

static inline bool SSObserveSwipe(SSSwipeState *state, bool sameInput, bool attached) {
    if (!sameInput || !attached) *state = SSSwipeBypassed;
    return *state != SSSwipeBypassed;
}

static inline bool SSClaimSwipe(SSSwipeState *state) {
    if (*state == SSSwipeBypassed) return false;
    *state = SSSwipeClaimed;
    return true;
}

static inline bool SSFinishSwipe(SSSwipeState *state, bool sameInput, bool attached) {
    bool refresh = SSObserveSwipe(state, sameInput, attached) &&
                   *state == SSSwipeClaimed;
    *state = SSSwipeBypassed;
    return refresh;
}

#endif
