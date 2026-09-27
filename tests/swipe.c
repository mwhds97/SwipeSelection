#include "../SSSwipeState.h"
#include <assert.h>
#include <stdio.h>

// Exercise the production policy with the event order from the recording.
// UIKit itself (marked ranges, callbacks and recognizers) needs device testing.
int main(void) {
    SSSwipeState swipe = SSSwipePending;
    // The recorded sequence: committed 你好 and composing ma. Composition
    // no longer rejects a swipe or breaks an already claimed gesture.
    assert(SSObserveSwipe(&swipe, true, true));
    assert(SSClaimSwipe(&swipe));
    for (int move = 0; move < 5; ++move) {
        assert(SSObserveSwipe(&swipe, true, true));
        assert(swipe == SSSwipeClaimed);
    }
    // Commitment during this gesture needs no new finger-down either.
    assert(SSObserveSwipe(&swipe, true, true));
    assert(SSFinishSwipe(&swipe, true, true));
    assert(!SSFinishSwipe(&swipe, true, true));

    // Changing focus or detaching the keyboard invalidates only that session.
    for (int fault = 0; fault < 2; ++fault) {
        SSSwipeState otherKeyboard = SSSwipePending;
        swipe = SSSwipePending;
        assert(SSClaimSwipe(&swipe));
        assert(!SSObserveSwipe(&swipe, fault != 0, fault != 1));
        assert(!SSObserveSwipe(&swipe, true, true));
        assert(!SSFinishSwipe(&swipe, true, true));
        assert(SSObserveSwipe(&otherKeyboard, true, true));
        assert(SSClaimSwipe(&otherKeyboard));
        assert(SSFinishSwipe(&otherKeyboard, true, true));
    }

    // Invalid conditions first observed at release must also skip refresh.
    for (int fault = 0; fault < 2; ++fault) {
        swipe = SSSwipePending;
        assert(SSClaimSwipe(&swipe));
        assert(!SSFinishSwipe(&swipe, fault != 0, fault != 1));
    }
    swipe = SSSwipePending;
    assert(!SSFinishSwipe(&swipe, true, true));

    // Exhaust every five-event sequence of focus/attachment
    // changes. Once any unsafe condition occurs, no later event may reclaim.
    for (unsigned trace = 0; trace < (1u << 10); ++trace) {
        swipe = SSSwipePending;
        bool rejected = false;
        for (unsigned event = 0; event < 5; ++event) {
            unsigned flags = (trace >> (event * 2)) & 3u;
            bool sameInput = !(flags & 1u);
            bool attached = !(flags & 2u);
            rejected |= !sameInput || !attached;
            assert(SSObserveSwipe(&swipe, sameInput, attached) == !rejected);
            assert(SSClaimSwipe(&swipe) == !rejected);
        }
        assert(SSFinishSwipe(&swipe, true, true) == !rejected);
    }
    puts("PASS: composing swipe stays active; focus/attachment isolation and 1024 event traces");
    return 0;
}
