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
    puts("PASS: native composition deletion, final marked character, deferred taps, repeat, selection, and separate presses");
    return 0;
}
