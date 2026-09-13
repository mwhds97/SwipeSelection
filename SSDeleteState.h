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
} SSDeleteState;

static inline SSDeleteState SSBeginDelete(bool native) {
    SSDeleteState state = {native, false, false, false, false};
    return state;
}

static inline bool SSDeferLegacyDelete(SSDeleteState *state) {
    if (!state || state->native || state->replaying || state->repeated) return false;
    state->deferred = true;
    return true;
}

static inline bool SSDeferDelete(SSDeleteState *state, bool repeat) {
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
    return state && !state->native && state->deferred && !state->repeated &&
        !state->replaying && sameInput && endedOnDelete && !claimedSwipe && !composing;
}

#endif
