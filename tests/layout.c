#include "../SSLayoutRange.h"
#include <assert.h>
#include <stdio.h>

static void equal(SSLayoutRange a, SSLayoutRange b) {
    assert(a.location == b.location && a.length == b.length);
}

int main(void) {
    // Reproduce ASEditableTextNode's unsigned end - 1, with the caret at the
    // beginning of "你好ma" (4 UTF-16 units).
    SSLayoutRange selection = {0, 0};
    SSLayoutRange legacy = {selection.location + selection.length - 1, 1};
    assert(legacy.location == SIZE_MAX);
    assert(!SSLayoutRangeIsValid(legacy, 4));
    equal(SSSafeLayoutScrollRange(legacy, selection, 4), selection);
    equal(selection, (SSLayoutRange){0, 0}); // Actual selection is unchanged.

    equal(SSSafeLayoutScrollRange(legacy, selection, 0), (SSLayoutRange){0, 0});
    equal(SSSafeLayoutScrollRange((SSLayoutRange){1, SIZE_MAX},
                                 (SSLayoutRange){2, 1}, 4), (SSLayoutRange){2, 1});
    equal(SSSafeLayoutScrollRange(legacy, (SSLayoutRange){2, SIZE_MAX}, 4),
          (SSLayoutRange){2, 2});
    equal(SSSafeLayoutScrollRange(legacy, (SSLayoutRange){(size_t)INTPTR_MAX, 0}, 4),
          (SSLayoutRange){0, 0});


    for (size_t length = 0; length <= 32; ++length) {
        for (size_t start = 0; start <= length; ++start) {
            for (size_t count = 0; count <= length - start; ++count) {
                SSLayoutRange selected = {start, count};
                SSLayoutRange old = {start + count - 1, 1};
                SSLayoutRange repaired = SSSafeLayoutScrollRange(old, selected, length);
                assert(SSLayoutRangeIsValid(repaired, length));
                if (start + count > 0) equal(repaired, old);
                else equal(repaired, selected);
            }
        }
        // Valid requests pass through exactly. Invalid requests use the live
        // selection. Include requests whose end exceeds the document.
        for (size_t start = 0; start <= length + 2; ++start) {
            for (size_t count = 0; count <= length + 2; ++count) {
                SSLayoutRange request = {start, count};
                SSLayoutRange caret = {length, 0};
                SSLayoutRange target = SSSafeLayoutScrollRange(request, caret, length);
                bool valid = start <= length && count <= length - start;
                assert(SSLayoutRangeIsValid(target, length));
                equal(target, valid ? request : caret);
            }
        }
    }

    puts("PASS: Telegram layout underflow, valid-range pass-through, empty text, bounds and overflow");
    return 0;
}
