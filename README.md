# SwipeSelection

`Modified by ChatGPT 6.0 Astra`

Swipe along the keyboard to move the caret or select text, with a speed slider
and numeric field in Settings. This project modifies the supplied SwipeSelection
2.0 source. Original credits: Kyle Howells (author), iCraze (maintainer).

Documentation updated on 2026-09-27. This documentation update keeps the 2.1.7
source code and installer unchanged.

## Install

Target: **rootful iOS 14**, with arm64 and legacy arm64e slices. The reported
device is an iPhone SE (2020), iOS 14.8 with unc0ver. Telegram testing concerns
version **12.9.4 (34639)**.

1. Install [com.icraze.swipeselection_2.1.7_iphoneos-arm.deb](packages/com.icraze.swipeselection_2.1.7_iphoneos-arm.deb)
   using your package installer. It upgrades `com.icraze.swipeselection`.
2. Respring once after installation.
3. Open **Settings → SwipeSelection** to adjust the speed.

The package declares MobileSubstrate-compatible hooking, PreferenceLoader
2.2.2 or later, and iOS 14 or later as dependencies. Its build target is rootful
iOS 14; that minimum-version dependency is not a compatibility claim for every
later iOS release or a rootless jailbreak.

## Speed controls

| Control | Behavior |
| --- | --- |
| Range | 0.10×–2.00× |
| Default | 1.00× |
| Slider | Snaps to 0.05 increments |
| Numeric field | Saves values rounded to 0.01; accepts dot or comma decimals |
| Save/apply | Saves automatically; takes effect at the next swipe |

Tap **Done** on the numeric keyboard to finish editing. Valid in-range values
save while typing. On finishing, numeric values outside the range are clamped;
empty, negative or malformed entries restore the last saved value. For example,
`0` becomes `0.10`, and `3` becomes `2.00`. A missing or invalid stored preference
uses `1.00`.

Movement and selection use the same speed setting and the dragging finger's
travel distance. The speed remains fixed for the duration of a swipe. A stationary
finger holding Shift or Delete does not reduce the measured drag distance.

Preferences use the `mobile` domain `com.icraze.swipeselection`, key `SwipeSpeed`,
with the file path:

```text
/var/mobile/Library/Preferences/com.icraze.swipeselection.plist
```

## Gestures and composition

- One dragging finger moves by character boundaries; additional touches enable
  word movement according to the modifier/touch count.
- Holding Shift or using Delete-drag extends the selection.
- Pinyin composition remains eligible for moving and selecting text.
- The activation distance is 18 points on iPhone and 30 on iPad. Native long
  presses, handwriting, More and Kana layouts retain their existing exclusions.
- Each gesture belongs to its original input field. Losing focus or detaching
  the keyboard invalidates that gesture's selection anchor and candidate gate.

The multiplier controls distance per movement step. Character steps use
`10 / speed` points and word steps use `20 / speed` points. A 200-point character
drag therefore budgets 2, 20 or 40 steps at 0.10×, 1.00× or 2.00×, subject to
field boundaries and gesture eligibility. Moving and selecting share that budget.
Native fields use tokenizer boundaries; WebKit uses its movement commands.

## Candidate suppression

New candidate-generation requests are gated while a claimed swipe remains active
on the same keyboard and input field. Ordinary prediction requests may be
cancelled when the swipe takes control. An already-running **composition**
request is allowed to finish; new requests remain gated during the drag.

An eligible swipe ending or being cancelled on the same attached input triggers
a final selection refresh after its ownership is cleared. Normal typing uses
the original keyboard pipeline. The implementation covers selection-policy
requests plus direct and asynchronous candidate-generation entry points, which
also addresses the Google/Bing post-commit request path.

This targets the built-in keyboard pipeline. Independent candidate generation
inside a third-party keyboard extension may follow a different path. No new
performance measurement was made for 2.1.7.

## Backspace and Telegram behavior

Composition Backspace taps use the native input-method sequence, including the
press that removes the last composing character. If a swipe takes control of a
Delete press, auto-delete stops and cancelled repeats are rejected, including
queued repeats after touch release. A fresh press starts a new Delete sequence.
Ordinary-text taps can be deferred for Delete-drag selection and replayed once
when eligible.

The Telegram edit guard validates incoming edit ranges before its text-view
delegate runs. Invalid requests are rejected; valid requests use the original
callback. This guard and the Delete cancellation policy remain in 2.1.7.

**2.1.7 adds Backspace preparation at the beginning during composition.** In the
supported Telegram editor, when the caret is collapsed at document offset 0 and
text is still composing, it moves to the composing text's end before invoking
one native Delete. With committed `你好` and composing `ma`, the intended result
is:

```text
Before:                  |你好ma
After one Backspace:     你好m|
After another Backspace: 你好|
```

Here `|` marks the caret. The destination is the marked-text end when available;
otherwise it is the document end while the input manager still reports
composition. An embedded composition uses its own end, preserving the following
committed text. Empty fields, nonempty selections, other caret positions and
ordinary committed-text input keep their existing deletion behavior.

This preparation is limited to the dynamically detected Telegram text-view class
whose edit guard was installed after checking its method signature. It runs after
swipe-cancellation and tap-deferral checks. The tweak adds no synthetic second
Delete, automatic candidate acceptance or direct composing-text replacement.

## Validation status

| Item | Evidence available |
| --- | --- |
| Candidate suppression in an earlier build | User reported that it works well |
| Telegram crash with 2.1.5 | Supplied `.ips` identifies the native Delete call path |
| Telegram crash protection in 2.1.6 | User confirmed that the reported operation no longer crashes |
| New Backspace behavior in 2.1.7 | Built and covered by portable policy tests; device confirmation pending |
| Equal speed and preference transport | Portable checks cover all 191 hundredth-step speed values |
| Google/Bing composition Backspace and post-commit suppression | Fixes retained; current-build device retest pending |
| Package | Both architectures, resources and signature digests verified |

The tests run without UIKit or a physical iPhone. Their results do not establish
all runtime behavior. The [build report](BUILD-REPORT.md) records the exact build,
crash evidence, retained guards and remaining limits.

## Device retest

1. Install 2.1.7 and respring. In Telegram, commit `你好`, then type `ma` and leave
   it composing with candidates visible.
2. Swipe to the **beginning**, release the swipe, and leave the caret there.
3. Press Backspace once. Expect `你好m` with the caret at the end. Press it again;
   expect `你好` with the caret at the end.
4. Check candidate acceptance and normal typing. Also check Backspace with a
   selected range, at other caret positions, and after the composition is gone.
5. Test Delete-drag, release, a fresh Delete tap, and long-press repeat. Verify
   that moving and selecting remain available during composition.
6. In Google/Bing search boxes, delete while Pinyin candidates are visible,
   including the last composing character; then commit text and swipe immediately
   without leaving the field. Check candidate recovery after release.
7. Compare movement and selection at 0.10×, 1.00× and 2.00× in a native field and
   browser. Repeat composing swipes in another previously working app.

If a crash returns, provide the complete new `.ips` or `.crash` report and the
app version. With Filza, reports are normally under
`/var/mobile/Library/Logs/CrashReporter/`. On iOS 14 they are also accessible from
**Settings → Privacy → Analytics & Improvements → Analytics Data**.

## Build and local checks

With Theos, an iOS SDK, and a toolchain suitable for the target arm64e ABI:

```sh
make clean package FINALPACKAGE=1
```

The supplied Linux helper builds the same source:

```sh
python3 build.py \
  --toolchain /path/to/ios-toolchain/bin \
  --sdk /path/to/iPhoneOS14.5.sdk \
  --logos /path/to/logos \
  --headers /path/to/theos-headers \
  --libraries /path/to/theos-lib
```

The helper needs Python 3, Perl and the Logos Perl dependencies, `dpkg-deb`,
an iOS clang/linker toolchain with `lipo` and `ldid`, the SDK, and the Theos
Logos/headers/libraries checkouts. Exact revisions and the existing legacy arm64e
linker warnings are recorded in [BUILD-REPORT.md](BUILD-REPORT.md).

Run the five portable suites from the project root:

```sh
cc -std=c11 -Wall -Wextra -Werror tests/movement.c -lm -o /tmp/ss-movement
/tmp/ss-movement
cc -std=c11 -Wall -Wextra -Werror tests/delete.c -o /tmp/ss-delete
/tmp/ss-delete
cc -std=c11 -Wall -Wextra -Werror tests/swipe.c -o /tmp/ss-swipe
/tmp/ss-swipe
cc -std=c11 -Wall -Wextra -Werror tests/layout.c -o /tmp/ss-layout
/tmp/ss-layout
cc -std=c11 -Wall -Wextra -Werror tests/edit.c -o /tmp/ss-edit
/tmp/ss-edit
```

## Revision history

| Version | Main change and disposition |
| --- | --- |
| 2.1.7 | Prepares the composing caret at the start before native Backspace; current installer |
| 2.1.6 | Delete/swipe cancellation and Telegram edit-range validation; user confirmed crash resolved |
| 2.1.5 | Restored composing swipes, preserved in-flight composition requests, added a legacy scroll guard; reported crash persisted |
| 2.1.4 | Temporarily blocked composing swipes; that behavior was reverted at the user's request |
| 2.1.3 | Native composition Backspace and browser candidate-request gates |
| 2.1.2 | Preference delivery, shared movement/selection distance and event accumulation |
| 2.1.1 | Earlier candidate-suppression implementation reported working by the user |

## Installer checksum

SHA-256 for `com.icraze.swipeselection_2.1.7_iphoneos-arm.deb`:

```text
dec3069a3e8c093f7f586859e36ab09e111f3d7bd7c993cb8a9268150811831b
```
