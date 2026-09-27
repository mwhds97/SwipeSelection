#ifndef SS_DELETE_STATE_H
#define SS_DELETE_STATE_H

#include <stdbool.h>

/* One physical Delete press. Composition keeps the native event sequence;
 * only a normal text press can be delayed to allow Delete-drag selection. */
typedef struct {
    bool native;
    bool deferred;
    bool repeated;
    bool replaying;
    bool replayConsumed;
    bool cancelledBySwipe;
    bool released;
} SSDeleteState;

static inline SSDeleteState SSBeginDelete(bool native) {
    SSDeleteState state = {native, false, false, false, false, false, false};
    return state;
}

static inline void SSCancelDeleteForSwipe(SSDeleteState *state) {
    if (state) state->cancelledBySwipe = true;
}

static inline void SSReleaseDelete(SSDeleteState *state) {
    if (state) state->released = true;
}

/* A claimed swipe owns the key, including native composition Delete presses.
 * Keep rejecting queued repeats after UIKit cancels/releases the touch. A new
 * non-repeat event after release starts a new native sequence (e.g. a hardware
 * key); a new on-screen press installs a completely new SSDeleteState. */
static inline bool SSCancelDeleteCallback(SSDeleteState *state, bool repeat,
                                           bool claimedSwipe) {
    if (claimedSwipe) {
        SSCancelDeleteForSwipe(state);
        return true;
    }
    if (!state || !state->cancelledBySwipe) return false;
    if (repeat || !state->released) return true;
    *state = SSBeginDelete(true);
    return false;
}

static inline bool SSDeferLegacyDelete(SSDeleteState *state) {
    if (state && state->cancelledBySwipe) return true;
    if (!state || state->native || state->replaying || state->repeated) return false;
    state->deferred = true;
    return true;
}

static inline bool SSDeferDelete(SSDeleteState *state, bool repeat) {
    if (state && state->cancelledBySwipe) return true;
    if (!state || state->native) return false;
    if (repeat) {
        state->repeated = true;
        return false;
    }
    if (state->replaying) {
        if (state->replayConsumed) return true;
        state->replayConsumed = true;
        return false;
    }
    return SSDeferLegacyDelete(state);
}

static inline bool SSReplayDelete(const SSDeleteState *state, bool sameInput,
                                  bool endedOnDelete, bool claimedSwipe,
                                  bool composing) {
    return state && !state->cancelledBySwipe && !state->native && state->deferred && !state->repeated &&
        !state->replaying && sameInput && endedOnDelete && !claimedSwipe && !composing;
}

#endif
