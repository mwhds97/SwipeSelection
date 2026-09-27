#ifndef SS_LAYOUT_RANGE_H
#define SS_LAYOUT_RANGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    size_t location;
    size_t length;
} SSLayoutRange;

static inline bool SSLayoutRangeIsValid(SSLayoutRange range, size_t textLength) {
    // Subtraction avoids overflow from NSMaxRange on malformed input.
    return range.location <= textLength && range.length <= textLength - range.location;
}

static inline SSLayoutRange SSClampedLayoutSelection(SSLayoutRange selection, size_t textLength) {
    if (selection.location > textLength) return (SSLayoutRange){0, 0};
    if (selection.length > textLength - selection.location)
        selection.length = textLength - selection.location;
    return selection;
}

static inline SSLayoutRange SSSafeLayoutScrollRange(SSLayoutRange request,
                                                   SSLayoutRange selection, size_t textLength) {
    if (SSLayoutRangeIsValid(request, textLength)) return request;
    // The layout code's end - 1 wraps at the beginning. Reveal the actual
    // selection instead of interpreting the wrapped value as a document end.
    return SSClampedLayoutSelection(selection, textLength);
}

#endif
