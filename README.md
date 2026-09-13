# SwipeSelection

`Modified by ChatGPT 6.0 Astra`

A modification of the supplied SwipeSelection 2.0 source. Original credits:
Kyle Howells (author), iCraze (maintainer).

## Install and use

This package targets **rootful iOS 14**, including an iPhone SE (2020) on
iOS 14.8 with unc0ver. It contains both arm64 and arm64e slices.

1. Install `com.icraze.swipeselection_2.1.3_iphoneos-arm.deb` using your
   package installer. It upgrades the existing `com.icraze.swipeselection`
   package. PreferenceLoader is a declared dependency.
2. Respring once after installation, then open **Settings → SwipeSelection**.
3. Drag the slider or enter a number in the text box. **1.00** restores the
   default multiplier. Tap the keyboard's **Done** button to finish editing.

The range is **0.10×–2.00×**. The slider uses 0.05 steps; the text box accepts
values to 0.01 precision. Lower values slow cursor movement; higher values
increase it. Both controls update together. Changes save automatically and
apply to the next swipe, without another respring.

Positive numeric entries outside the range are clamped when editing ends.
Empty or invalid text restores the last valid value. Both `1.25` and `1,25`
are accepted. A missing or nonnumeric stored preference uses 1.00.
Saved values above the new maximum are read as 2.00.

## Fixes in 2.1.3

- **Backspace during composition:** an active marked-text or candidate-selection
  buffer uses the input method's native Delete sequence. The tweak no longer
  swallows that initial deletion and substitutes a release-time `handleDelete`.
  The choice is recorded for the whole press, including the press that removes
  the last composing character.
- **Delete selection and repeat:** ordinary text still supports dragging from
  Delete to select. A deferred tap is replayed only if the same input delegate
  is active, the finger ends on Delete, and no selection drag or native repeat
  took over. State belongs to a physical press and keyboard, replacing the
  old global delete counter. Cancelling the touch clears its state.
- **Keyboard hit testing:** touch positions are converted into the layout's
  coordinate system before identifying a key, including layouts with a form
  accessory toolbar.
- **Browser candidates after committing text:** suppression now also gates
  the direct and asynchronous candidate-request entry points during a claimed
  swipe. Previously it only gated the selection-change policy; browser text
  and context updates could take another request path. Existing candidate
  requests are cancelled when the swipe is claimed, and the normal final
  selection refresh runs after release.

The supplied recordings show Delete highlighted while the Pinyin input stays
unchanged, and candidates changing after committing `你好吗`. Re-entering the
field restores the previous suppression behavior. The key icon remains visible
in both states; its presence alone does not identify the failure.

These changes address the vulnerable paths identified in the source. The
recordings do not provide a UIKit call trace, and **2.1.3 still needs testing
on the user's device**. No Google/Bing keyboard type or AutoFill setting is
overridden.

## Speed fixes retained from 2.1.2

- **Speed delivery:** Settings writes the tweak's global `mobile` preference
  domain with an explicit no-container scope, then publishes the value through
  notifyd. SpringBoard restores this shared value after a respring or reboot.
  Apps read it at the start of every swipe, so a host app's preference container
  or a missed notification cannot leave the gesture using a cached default.
- **Equal movement and selection:** both use the dragging finger's distance.
  A stationary finger holding Shift or Delete no longer reduces that distance
  by becoming part of the touch-centre calculation.
- **Consistent speed at different event rates:** one shared accumulator keeps
  fractional distance and consumes every whole step. Native fields commit one
  final selection range per callback, even when multiple steps are needed.
  The previous one-step-per-callback limit and discarded remainder are removed.
- **WebKit:** uses the same step budget and explicit selection flag. Each step
  goes through one WebKit movement command; no stale native range is written
  over it. Word mode uses WebKit's word commands when available.
- **Gesture cleanup:** resets the selection anchor for each gesture and avoids
  installing duplicate recognizers when keyboard initializers call one another.

The controls remain a single slider and numeric field with a **0.10–2.00**
range. Speed is fixed for each swipe. The activation distance remains 18 points
on iPhone and 30 on iPad, now measured from the dragging finger's touch origin.
Long-press, Shift/Delete selection, and multi-finger word mode remain available.

The multiplier changes the distance needed for each step, rather than adding
an animation delay. Character steps use `10 / speed` points; word steps use
`20 / speed` points. For example, a 200-point uninterrupted character drag
budgets 2 steps at 0.10, 20 at 1.00, and 40 at 2.00, before document boundaries.
Moving and selecting use exactly the same budget. Native movement follows
tokenizer character boundaries instead of assuming one UTF-16 unit per character.

The preferences implementation requires no additional framework dependency.
The explicit global domain follows the API usage documented in
[Cephei's preference implementation](https://github.com/hbang/Cephei/blob/main/main/HBPreferences.m).
Cross-process state sharing uses iOS's `notify_set_state` / `notify_get_state` APIs.

## Candidate suppression

The user confirmed that candidate suppression in **2.1.1 works well**, then
reported the browser composition cases in 2.1.2. The original policy hook and
its lifecycle checks are retained; 2.1.3 adds candidate-request gating. On completion or
cancellation, the tweak refreshes suggestions at the final caret position.

The optimization uses iOS's `shouldGenerateCandidatesAfterSelectionChange`
policy method, whose signature was checked against iOS 14.4 and 14.5 runtime
headers. It leaves the keyboard's selection/context handling and asynchronous
completion callbacks in place. Normal typing keeps the original policy.

The override applies only while the claimed recognizer is moving on the same
keyboard and input field. Weak session references avoid retaining old fields.
Ended/cancelled/failed gestures, a detached keyboard, and changed focus do not
suppress candidates. If the policy method is absent, a signature-checked
fallback defers the no-argument `updateForChangedSelection` entry point until
the final refresh. The added hooks cover `generateCandidates`,
`generateCandidatesWithOptions:`, `generateCandidatesAsynchronously`, and
`generateCandidatesAsynchronouslyWithRange:selectedCandidate:`. Each hook is
installed only after checking its return and argument types at runtime.
Candidate result handlers, WebKit selection notifications, and text-context
completion handlers continue through the original methods.

This targets the built-in iOS keyboard pipeline. A candidate request already
running before the drag may still complete. Independent candidate generation
inside a third-party keyboard extension is outside this hook. Actual candidate
behavior of this new build still requires on-device testing; no new performance
measurement was made here.

## Build

With a complete Theos installation and an iOS SDK:

```sh
make clean package FINALPACKAGE=1
```

The Makefile targets iOS 14 and builds arm64 + arm64e. Use an appropriate
toolchain for the target jailbreak. This is a rootful package; changing its
package architecture alone does not make it a rootless package.

The included Linux build helper uses the same source:

```sh
python3 build.py \
  --toolchain /path/to/ios-toolchain/bin \
  --sdk /path/to/iPhoneOS14.5.sdk \
  --logos /path/to/logos \
  --headers /path/to/theos-headers \
  --libraries /path/to/theos-lib
```

Dependencies: Python 3, Perl and the Logos Perl dependencies, `dpkg-deb`,
an iOS clang/linker toolchain including `lipo` and `ldid`, the iOS SDK,
and the [Logos](https://github.com/theos/logos),
[Theos headers](https://github.com/theos/headers), and
[Theos libraries](https://github.com/theos/lib) repositories.

## Validation and limits

Run the portable regression tests against the production movement and Delete helpers:

```sh
cc -std=c11 -Wall -Wextra -Werror tests/movement.c -lm -o /tmp/ss-movement
/tmp/ss-movement
cc -std=c11 -Wall -Wextra -Werror tests/delete.c -o /tmp/ss-delete
/tmp/ss-delete
```

These compare identical drags delivered in many small events or a few combined
events, in both directions and modes, at all 191 hundredth-step speed values.
They also check speed encoding, rounding, bounds, mode changes, and invalid input.
Delete tests cover native composition, the last marked character, separate
presses and keyboards, normal tap replay, repeat, selection, and interruption.

See `BUILD-REPORT.md` for the exact build inputs and package checks.
The new browser behavior has **not been tested on a physical iPhone** in this
environment. After installing and respringing, repeat the Google/Bing cases:
type Pinyin, delete while candidates are visible, delete the final composing
character, accept `你好吗`, then swipe immediately without leaving the field.
Check that suggestions resume after release and that ordinary typing still
works. Also check long-press Delete, Delete-drag selection, and the existing
0.10, 1.00, and 2.00 speeds in a native field and browser.

The supplied package uses the Linux toolchain's legacy arm64e output for
rootful jailbreaks. Its linker emits an arm64e ABI compatibility warning;
it is retained in the build report. For background, see
[Theos arm64e deployment](https://theos.dev/docs/arm64e-deployment) and the
[allemande author's rootful compatibility note](https://github.com/p0358/allemande#usage-with-theos).
