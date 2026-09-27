# SwipeSelection 2.1.7 build and validation report

Build date: 2026-09-27. Documentation updated: 2026-09-27.
This documentation revision does not change the source code or the 2.1.7 binary.
Installation, usage and device retest steps are in [README.md](README.md).

## Outcome and evidence status

The user confirmed that **2.1.6 stopped the reported Telegram crash**, then
reported that Backspace at the start did nothing while Pinyin was composing.
Version **2.1.7** adds caret preparation for that Backspace case. Its build,
package checks and portable tests passed; its new behavior has not yet been
confirmed on the user's device.

| Evidence | What it establishes |
| --- | --- |
| Supplied Telegram 12.9.4 (34639) report, iOS 14.8 (18H17), iPhone12,8 | The 2.1.5 failure occurs in Foundation through Telegram/UIKit and a native Delete call |
| Matching 2.1.5 tweak UUID and disassembly | The tweak frame calls the original `handleDeleteAsRepeat:executionContext:` implementation |
| User feedback after 2.1.6 | The reported operation no longer crashes; Backspace at the beginning still had no effect |
| 2.1.7 portable tests | The preparation decision and a modeled single deletion produce the requested result |
| 2.1.7 build/package checks | Both architectures compile/link and packaged resources/signature digests validate |

The report does not identify the exact Telegram/Foundation methods or the
original Delete call's repeat argument and edit range. The success of 2.1.6 does
not establish which of its two protections was decisive.

## Current behavior

### Speed and preferences

The range is 0.10–2.00, default 1.00. The slider snaps to 0.05; numeric input is
rounded to 0.01. Valid in-range text saves during editing; finishing clamps
out-of-range numeric values and restores the saved value for invalid input.
Both movement and selection use `SSTakeMovementSteps` and the dragging finger's
translation. Character and word thresholds are `10 / speed` and `20 / speed`.
Fractional distance is accumulated; the per-event safety cap is 256 steps.

Settings writes the tweak's global `mobile` preference domain with explicit
no-container scope when those APIs are available, then publishes encoded speed
through notifyd. SpringBoard seeds notifyd from disk after respring/reboot.
Apps read speed at gesture start and retain it for that gesture. The domain is
`com.icraze.swipeselection`, key `SwipeSpeed`; the file fallback is
`/var/mobile/Library/Preferences/com.icraze.swipeselection.plist`.

### Swipe ownership and candidate requests

Each keyboard owns a per-gesture session bound weakly to the input delegate.
A focus change or keyboard detachment invalidates the session and its anchor.
Composition alone does not reject a gesture. Native text fields commit the
final range once per pan callback; WebKit uses movement commands without an
additional stale UITextRange write.

Candidate requests are gated only for an active claimed swipe on the same
attached keyboard/input. The preferred hook is
`shouldGenerateCandidatesAfterSelectionChange`; the signature-checked fallback
is `updateForChangedSelection`. Direct request hooks cover:

- `generateCandidates`
- `generateCandidatesWithOptions:`
- `generateCandidatesAsynchronously`
- `generateCandidatesAsynchronouslyWithRange:selectedCandidate:`

Ordinary predictions may be cancelled at swipe activation. An in-flight
composition request is allowed to finish; new requests are still gated.
Candidate result/completion handlers retain their original path. An eligible
finish/cancellation clears ownership before the final selection refresh.
Independent third-party keyboard candidate generators are outside this scope.

### Delete cancellation retained from 2.1.6

Native composition taps retain their original input-method sequence, including
the press that removes the last marked character. On the first claimed swipe,
the tweak cancels the active Delete state and calls `stopAutoDelete` before
changing the selection. Delete callbacks are rejected while the swipe owns the
keyboard, even if the press originally started in native composition mode.

The cancelled state survives touch cleanup so already-queued repeats remain
rejected after release. Skipped execution-context callbacks complete their
queue without Delete feedback. A new on-screen press installs fresh state;
a new non-repeat native/hardware sequence after release retires the old
cancellation. Input changes also invalidate it. Ordinary deferred taps keep
their single replay policy.

### Telegram edit guard retained from 2.1.6

At gesture start, the tweak detects the actual `ChatInputTextViewImpl` subclass,
requires it to act as its own delegate, and checks the complete signature of
`textView:shouldChangeTextInRange:replacementText:` before installing the hook.
The check applies to that runtime subclass, without a global UITextView or
Foundation string hook.

Incoming edits are validated against both UTF-16 text-storage and attributed-
snapshot lengths. Subtraction avoids overflow, and `NSNotFound` is explicitly
rejected. Invalid edits return `NO` before entering Telegram's callback; valid
ones call the original unchanged. An invalid range is not clamped to different
text. This guard remains installed for later edits after the gesture ends.

### Backspace preparation added in 2.1.7

Preparation occurs immediately before the original
`handleDeleteAsRepeat:executionContext:` call, after cancellation and tap-deferral
checks. It is limited to the same detected Telegram editor with its edit guard
installed. The conditions are active composition, nonempty text and a collapsed
caret at document offset 0.

The destination is the current marked-text end, falling back to the document
end if no nonempty marked range is available while composition is still reported.
For a composition in the middle of existing text, its own end preserves the
committed suffix. The live destination and matching text lengths are validated
before setting the caret. Focus, text length and the resulting selection are
checked afterward; an invalidated attempt completes its queue without a Delete.

The native handler then runs once. The tweak neither rewrites the rejected edit
range nor synthesizes another key press. No explicit candidate acceptance,
unmarking or direct composing-text replacement is added. Selected ranges,
empty input, other caret positions and ordinary committed-text input retain
their existing behavior.

For committed `你好` followed by composing `ma`, the expected sequence is
`|你好ma` → `你好m|` → `你好|` for two Backspace presses. The portable test models
this sequence; it does not execute UIKit's selection setter or input method.

### Legacy scroll guard

The 2.1.5 compatibility layer remains limited to invalid viewport requests
inside `ASEditableTextNode._layoutTextView` for its own
`ASPanningOverriddenUITextView`. It corrects an unsigned `selection end - 1`
underflow in older source. It changes only the scroll target and restores scope
in `@finally`, including nested calls. The supplied crash does not implicate
this layout path; it is not evidence for the successful 2.1.6 correction.

## Historical crash analysis

The provided `Telegram-2026-09-27-201907.ips` records a main-thread
`EXC_BAD_ACCESS (SIGSEGV)` at `0x2a0000008`. Its caller-to-failure chain is
SwipeSelection → UIKitCore → TelegramUIFramework → Foundation. There is no
exception backtrace identifying an Objective-C range exception.

The loaded tweak's arm64e UUID is
`03c81bf4-e040-3d09-ab51-fa69bc4eb48b`, matching the archived **2.1.5** binary.
Frame 9 has image-relative offset `0xa2c8` (41672), within the Delete hook
starting at `0xa23c`. At `0xa2c4`, `blraaz x8` calls the saved original handler;
`0xa2c8` is its return address. These addresses describe the historical 2.1.5
binary, not the current 2.1.7 build.

Source inspection found that 2.1.5 kept a composition Delete press native even
after a swipe took control, and discarded its state on touch cancellation.
This allowed queued deletes to run after caret movement. That policy gap is
reproduced by the regression tests. A malformed edit reaching Telegram's
attributed-string preview was a second plausible failure path. The report's
unsymbolicated Telegram/Foundation frames do not distinguish those possibilities.
Both were addressed in 2.1.6, which the user subsequently reported as crash-free
for the supplied reproduction.

## Build inputs

| Item | Value |
| --- | --- |
| Package | `com.icraze.swipeselection` |
| Version / package architecture | `2.1.7` / `iphoneos-arm` |
| Platform target | Rootful iOS 14; intended for the reported iOS 14.8/unc0ver setup |
| Binary slices | arm64 and legacy arm64e in tweak and Settings bundle |
| SDK | Theos `iPhoneOS14.5.sdk` |
| Toolchain | swift-toolchain-linux v2.1.0, Ubuntu 20.04 x86_64 asset |
| Compiler | Apple clang 13.0.0, revision `f765bf5b71fd3637a6f6d1d3e6ab95ca91892a0c` |
| Linker | ld64-609 |
| Logos | `777925d1add4ee3485a2432a6f6d5e3ded59de7b` |
| Theos headers | `13c1f17176d7efe6871551cd69a75b71ac4eeaf1` |
| Theos libraries | `6f2af307568e6b8c52181d26314b0cd69ffaf188` |

The build produced no compiler diagnostics under the helper's existing flags.
Those flags exclude deprecated UIKit APIs and unused parameters. The same five
legacy arm64e linker warnings remain:

```text
was built with an incompatible arm64e ABI compiler
```

The previous rootful toolchain/ABI was retained. Successful compilation and
signature checks alone do not establish runtime ABI compatibility.

## Verification of the existing 2.1.7 installer

The checks below were completed when 2.1.7 was built. This documentation update
reuses that verified binary; it is not a new build or a new device test.

- Compiled and linked both tweak and Settings bundle for both architectures.
- Extracted the final Debian package and checked CPU subtypes, class/selector
  presence, dependencies, preference resources, UIKit filter and version fields.
- Confirmed Debian upgrade ordering from 2.1.6 to 2.1.7.
- Verified every ad-hoc signature code-page digest: 60 for each tweak slice and
  36 for each preference slice, counting both code directories.
- Reviewed generated Logos original calls, queue completion, dynamic guard
  installation and Backspace preparation order.

All five portable suites passed with AddressSanitizer and
UndefinedBehaviorSanitizer. Leak scanning was disabled because the build
runtime could not inspect its process task directory.

| Suite | Coverage |
| --- | --- |
| `tests/movement.c` | All 191 speed values, event coalescing, reversals, word mode, limits and preference transport |
| `tests/delete.c` | Native composition taps, deferred replay, swipe takeover, queued repeats after release, fresh/native/hardware presses and keyboard isolation |
| `tests/swipe.c` | Composition remains eligible, focus/attachment isolation and 1,024 event traces |
| `tests/layout.c` | Legacy range underflow, valid pass-through, empty input, bounds and overflow |
| `tests/edit.c` | Start-of-input preparation, a modeled single deletion and subsequent deletion, selection/normal-text exclusions, invalid ranges, snapshot mismatch and UTF-16 edits |

These are host-side policy and arithmetic tests. They do not run UIKit, the
keyboard's asynchronous task queue, or the installed Telegram implementation.
No new runtime performance measurement was made.

## Remaining validation

The user has confirmed the 2.1.6 crash result. Confirmation is still needed for
2.1.7's new Backspace behavior and for the current build's browser/speed cases.
Use the [README device retest](README.md#device-retest), leaving the caret at the
beginning before the first Backspace.

A rejected malformed edit can still have no text effect. The guard does not
repair arbitrary input-method corruption. A non-repeat callback after touch
release is treated as fresh input because the native entry point does not
identify its originating touch. Full symbolication of Telegram/Foundation would
require matching symbols or binaries, which were not available in this build
environment.

## Source references inspected

The Telegram source inspection used `release-12.9.2`, revision
`6ad963e5b62d354da79040f388ae2b9132fb17b8`. It was the newest listed tag in the
2026-09-27 inspection; a 12.9.4 tag was not listed then. It provides supporting
context, not a symbol match to the installed 12.9.4 binary.

- [Telegram ChatInputTextNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TelegramUI/Components/Chat/ChatInputTextNode/Sources/ChatInputTextNode.swift): editor subclass, self-delegation and should-change forwarding.
- [Telegram ChatTextInputPanelNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/TelegramUI/Sources/ChatTextInputPanelNode.swift): attributed-string preview using the supplied edit range.
- [Older ASEditableTextNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/0b6a974d47fa9715acc714a4fc0e55061a7af902/submodules/AsyncDisplayKit/Source/ASEditableTextNode.mm): the legacy scroll-range underflow.
- [Later ASEditableTextNode](https://github.com/TelegramMessenger/Telegram-iOS/blob/6ad963e5b62d354da79040f388ae2b9132fb17b8/submodules/AsyncDisplayKit/Source/ASEditableTextNode.mm): position lookup with a nil check in the layout path.
- [Apple markedTextRange](https://developer.apple.com/documentation/uikit/uitextinput/markedtextrange): the selection belongs within the marked text during composition.
- [Cephei preferences](https://github.com/hbang/Cephei/blob/main/main/HBPreferences.m): reference for explicit global preference scope.
- [Toolchain release](https://github.com/kabiroberai/swift-toolchain-linux/releases/tag/v2.1.0), [Theos arm64e deployment](https://theos.dev/docs/arm64e-deployment), and [allemande rootful note](https://github.com/p0358/allemande#usage-with-theos): build/ABI background.

## Installer checksum

File: `com.icraze.swipeselection_2.1.7_iphoneos-arm.deb`

SHA-256:

```text
dec3069a3e8c093f7f586859e36ab09e111f3d7bd7c993cb8a9268150811831b
```
