#ifndef SS_EDIT_RANGE_H
#define SS_EDIT_RANGE_H

#include <stdbool.h>
#include <stddef.h>

/* Both lengths are UTF-16 counts: UIKit's backing store and the attributed
 * snapshot used by Telegram's delegate. Never clamp an edit: changing its
 * range can remove unrelated text. Reject it before calling the delegate. */
static inline bool SSCanApplyTextEdit(size_t location, size_t length,
                                      size_t storageLength, size_t snapshotLength) {
    return location <= storageLength && length <= storageLength - location &&
           location <= snapshotLength && length <= snapshotLength - location;
}

/* A composing caret swiped to document start has no character before it.
 * Restore the composition's end BEFORE native Delete computes an edit range.
 * A selected range or a caret elsewhere keeps its normal deletion behavior. */
static inline bool SSShouldMoveComposingDeleteToEnd(bool composing,
                                                    size_t selectionLocation,
                                                    size_t selectionLength,
                                                    size_t documentLength) {
    return composing && documentLength > 0 && selectionLocation == 0 && selectionLength == 0;
}

#endif
