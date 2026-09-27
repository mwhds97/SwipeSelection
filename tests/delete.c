#include "../SSDeleteState.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>

int main(void) {
    // Pinyin/candidate-mode backspace must enter the native handler on key
    // down, including the press that removes the final composition character.
    SSDeleteState composing = SSBeginDelete(true);
    assert(!SSDeferLegacyDelete(&composing));
    assert(!SSDeferDelete(&composing, false));
    assert(!SSReplayDelete(&composing, true, true, false, true));
    assert(!SSReplayDelete(&composing, true, true, false, false));
    assert(!SSDeferDelete(&composing, true));

    // A normal Delete tap is deferred for selection, then replayed once.
    SSDeleteState normal = SSBeginDelete(false);
    assert(!SSReplayDelete(&normal, true, true, false, false));
    assert(SSDeferLegacyDelete(&normal));
    assert(SSDeferDelete(&normal, false));
    assert(SSReplayDelete(&normal, true, true, false, false));
    normal.replaying = true;
    assert(!SSDeferLegacyDelete(&normal));
    assert(!SSDeferDelete(&normal, false));
    assert(SSDeferDelete(&normal, false));
    assert(!SSReplayDelete(&normal, true, true, false, false));

    // A new press cannot inherit the old global one-delete budget. A second
    // keyboard's native composition press is independent of a deferred press.
    SSDeleteState next = SSBeginDelete(false);
    assert(SSDeferDelete(&next, false));
    assert(SSReplayDelete(&next, true, true, false, false));
    composing = SSBeginDelete(true);
    assert(!SSDeferDelete(&composing, false));
    assert(SSReplayDelete(&next, true, true, false, false));

    // Native auto-repeat owns deletion once a long press starts. A trailing
    // non-repeat callback must not cause an extra replay on release.
    SSDeleteState held = SSBeginDelete(false);
    assert(SSDeferDelete(&held, false));
    for (int i = 0; i < 10; i++) assert(!SSDeferDelete(&held, true));
    assert(!SSDeferLegacyDelete(&held));
    assert(!SSDeferDelete(&held, false));
    assert(!SSReplayDelete(&held, true, true, false, false));

    // A selection drag, release off Delete, changed delegate, or newly active
    // composition must not receive a synthetic deletion at touch-up.
    SSDeleteState interrupted = SSBeginDelete(false);
    assert(SSDeferDelete(&interrupted, false));
    assert(!SSReplayDelete(&interrupted, true, true, true, false));
    assert(!SSReplayDelete(&interrupted, true, false, false, false));
    assert(!SSReplayDelete(&interrupted, false, true, false, false));
    assert(!SSReplayDelete(&interrupted, true, true, false, true));

    // Cancelled/finished touches have no session; ordinary and hardware
    // deletion must then pass through, without consuming anyone else's press.
    assert(!SSDeferLegacyDelete(NULL));
    assert(!SSDeferDelete(NULL, false));
    assert(!SSDeferDelete(NULL, true));
    assert(!SSReplayDelete(NULL, true, true, false, false));

    // Regression: Pinyin Delete begins natively. After a swipe takes over,
    // its repeat must not enter UIKit with the selection moved elsewhere.
    for (int native = 0; native <= 1; native++) {
        SSDeleteState drag = SSBeginDelete(native);
        assert(!SSCancelDeleteCallback(&drag, false, false));
        assert(SSDeferDelete(&drag, false) == !native);
        SSCancelDeleteForSwipe(&drag);
        assert(SSCancelDeleteCallback(&drag, true, true));
        assert(SSCancelDeleteCallback(&drag, false, true));
        assert(SSDeferDelete(&drag, true));
        assert(SSDeferLegacyDelete(&drag));
        assert(!SSReplayDelete(&drag, true, true, false, false));

        // UIKit cancels the original key touch after the recognizer wins.
        // Queued repeats remain cancelled even after the pan ends, without
        // relying on the UITouch still existing or candidates being visible.
        SSReleaseDelete(&drag);
        for (int i = 0; i < 10; i++)
            assert(SSCancelDeleteCallback(&drag, true, false));
        assert(!SSReplayDelete(&drag, true, true, false, false));

        // A new hardware/non-touch Delete sequence is usable immediately.
        assert(!SSCancelDeleteCallback(&drag, false, false));
        assert(!SSDeferDelete(&drag, false));
        assert(!SSCancelDeleteCallback(&drag, true, false));
        assert(!SSDeferDelete(&drag, true));

        // A fresh on-screen press always replaces the cancelled state.
        SSCancelDeleteForSwipe(&drag);
        drag = SSBeginDelete(true);
        assert(!SSCancelDeleteCallback(&drag, false, false));
        assert(!SSDeferDelete(&drag, false));
    }
    SSDeleteState cancelled = SSBeginDelete(true);
    assert(SSCancelDeleteCallback(&cancelled, false, true));
    assert(SSCancelDeleteCallback(&cancelled, true, false));
    assert(SSCancelDeleteCallback(&cancelled, false, false));
    assert(SSCancelDeleteCallback(NULL, true, true));
    assert(!SSCancelDeleteCallback(NULL, true, false));
    SSDeleteState independent = SSBeginDelete(true);
    assert(!SSCancelDeleteCallback(&independent, true, false));
    assert(!SSDeferDelete(&independent, true));

    puts("PASS: native composition taps, swipe cancellation, queued repeats after release, fresh/hardware presses, independent keyboards, and deferred tap replay");
    return 0;
}
