#include "../SSEditRange.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Model the destructive operation performed by a should-change delegate.
// It must never be reached for an invalid range; text is not clipped/repaired.
static uint16_t text[32] = {0x4f60, 0x597d, 'm', 'a', 0xd83d, 0xde00};
static size_t textLength = 6, delegateCalls;
static bool edit(size_t location, size_t length, size_t snapshotLength,
                 uint16_t replacement) {
    if (!SSCanApplyTextEdit(location, length, textLength, snapshotLength)) return false;
    delegateCalls++;
    size_t inserted = replacement ? 1 : 0;
    memmove(text + location + inserted, text + location + length,
            (textLength - location - length) * sizeof(text[0]));
    if (inserted) text[location] = replacement;
    textLength = textLength - length + inserted;
    return true;
}

int main(void) {
    // The reported case: committed ni-hao + composing "ma", caret at 0.
    // Prepare its end, then let native Delete remove "a" exactly once.
    assert(SSShouldMoveComposingDeleteToEnd(true, 0, 0, 4));
    assert(!SSShouldMoveComposingDeleteToEnd(false, 0, 0, 4));
    assert(!SSShouldMoveComposingDeleteToEnd(true, 0, 0, 0));
    assert(!SSShouldMoveComposingDeleteToEnd(true, 0, 2, 4));
    assert(!SSShouldMoveComposingDeleteToEnd(true, SIZE_MAX, 0, 4));
    assert(!SSShouldMoveComposingDeleteToEnd(true, 2, 0, 4));
    assert(!SSShouldMoveComposingDeleteToEnd(true, 4, 0, 4));

    uint16_t original[32];
    memcpy(original, text, sizeof(text));
    const size_t invalid[][2] = {
        {SIZE_MAX, 1}, {SIZE_MAX >> 1, 1}, {0, SIZE_MAX},
        {6, 1}, {5, 2}, {7, 0}, {3, SIZE_MAX - 2}
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        assert(!edit(invalid[i][0], invalid[i][1], 6, 0));
        assert(delegateCalls == 0 && textLength == 6);
        assert(memcmp(original, text, sizeof(text)) == 0);
    }
    // The app preview may be shorter than UIKit's current backing store.
    assert(!edit(4, 2, 4, 0));
    assert(delegateCalls == 0 && memcmp(original, text, sizeof(text)) == 0);

    // Normal edits after a rejection still run: delete one composing letter,
    // replace the other, delete an emoji's two UTF-16 units, insert at end.
    assert(edit(3, 1, 6, 0));
    assert(textLength == 5 && text[2] == 'm' && text[3] == 0xd83d);
    assert(edit(2, 1, 5, 'n'));
    assert(textLength == 5 && text[2] == 'n');
    assert(edit(3, 2, 5, 0));
    assert(textLength == 3);
    assert(edit(3, 0, 3, '!'));
    assert(textLength == 4 && text[3] == '!');
    assert(delegateCalls == 4);

    assert(SSCanApplyTextEdit(0, 0, 0, 0));
    assert(!SSCanApplyTextEdit(0, 1, 0, 0));
    assert(SSCanApplyTextEdit(SIZE_MAX - 1, 1, SIZE_MAX, SIZE_MAX));
    assert(!SSCanApplyTextEdit(SIZE_MAX - 1, 2, SIZE_MAX, SIZE_MAX));
    assert(!SSCanApplyTextEdit(1, SIZE_MAX, SIZE_MAX, SIZE_MAX));

    text[0] = 0x4f60; text[1] = 0x597d; text[2] = 'm'; text[3] = 'a';
    textLength = 4; delegateCalls = 0;
    size_t caret = 0;
    if (SSShouldMoveComposingDeleteToEnd(true, caret, 0, textLength)) caret = textLength;
    assert(caret == 4);
    assert(edit(caret - 1, 1, textLength, 0));
    caret--;
    assert(textLength == 3 && text[0] == 0x4f60 && text[1] == 0x597d && text[2] == 'm');
    assert(delegateCalls == 1 && caret == 3);
    // The next native Delete continues from there without another jump.
    assert(!SSShouldMoveComposingDeleteToEnd(true, caret, 0, textLength));
    assert(edit(caret - 1, 1, textLength, 0));
    caret--;
    assert(delegateCalls == 2 && textLength == 2 && caret == 2);

    puts("PASS: composing Backspace from start, one native deletion, continued deletion, selections/normal text, invalid edit bounds, snapshot mismatch and UTF-16 edits");
    return 0;
}
