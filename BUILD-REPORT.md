# SwipeSelection 2.1.3 build report

Built on 2026-09-13, continuing the 2.1.2 changes to the supplied archive.

## Target and inputs

- Package: `com.icraze.swipeselection`, version `2.1.3`, `iphoneos-arm`.
- Target: rootful iOS 14.0 or newer; intended for the user's iOS 14.8 setup.
- Architectures: arm64 and legacy arm64e, in both the tweak and Settings bundle.
- SDK: iPhoneOS14.5.sdk, from the Theos SDK repository.
- Compiler: Apple LLVM clang 13.0.0, revision
  `f765bf5b71fd3637a6f6d1d3e6ab95ca91892a0c`.
- Linker: ld64-609 from the Linux iOS toolchain.
- Toolchain distribution: [swift-toolchain-linux v2.1.0](https://github.com/kabiroberai/swift-toolchain-linux/releases/tag/v2.1.0).
- Logos revision: `777925d1add4ee3485a2432a6f6d5e3ded59de7b`.
- Theos headers revision: `13c1f17176d7efe6871551cd69a75b71ac4eeaf1`.
- Theos libraries revision: `6f2af307568e6b8c52181d26314b0cd69ffaf188`.

## Results

- Compiled and linked the tweak and preference bundle for both architectures.
- No compiler diagnostics with the build helper's warning flags. Legacy
  deprecated UIKit calls and unused hook parameters are excluded by those flags.
- Verified both Mach-O architecture slices, defined Objective-C classes,
  and framework dependencies in the actual package.
- Verified every code-page hash in both binaries' ad-hoc signatures.
- Verified the PreferenceLoader entry, principal controller, custom cell,
  preference resources, and unchanged UIKit injection filter.
- Confirmed Debian treats 2.1.3 as an upgrade from 2.1.2.
- Ran `tests/movement.c` and `tests/delete.c` against the production helpers,
  with AddressSanitizer and UndefinedBehaviorSanitizer. Leak scanning was
  disabled because this environment cannot inspect the process task directory.
- At every hundredth-step speed from 0.10 through 2.00, compared a drag path
  delivered as 401 small samples per segment with the same path delivered as
  3 combined samples per segment. Both step counts and fractional remainders
  matched after every segment, including reversals, in character and word modes.
- Verified a 200-point character drag budgets 2, 10, 20, and 40 steps at
  0.10, 0.50, 1.00, and 2.00 respectively. Tested both directions, exact
  thresholds, mode changes, reset, and bounded handling of enormous deltas.
- Checked the 0.10–2.00 bounds, default, migration from a stored value of 5.00,
  nonfinite values, rounding, round-trip encoding of all 191 speeds, and
  rejection of unset, untagged, and out-of-range shared state.
- Verified notification transport imports and the shared preference functions
  in both architectures of both binaries. Preference writes explicitly use
  the `mobile` user and no-container scope, synchronize that same scope, and
  verify the value before publication. Reads prefer the shared notifyd value.
- Verified the range text, bundle versions, dragging-finger translation selector,
  WebKit word commands, and candidate-policy hook symbols in the package.
- Checked native Delete pass-through for active composition, including release
  after its last character disappears; ordinary deferred tap replay; duplicate
  replay filtering; repeat; selection takeover; release off the key; changed
  delegate; and independent presses and keyboards. These tests exercise the
  production decision code, not UIKit's implementation of composition.
- Compared the original candidate-policy hook and active-session predicate
  with the 2.1.2 source archive: unchanged. New hooks gate four candidate-request
  entry points, and swipe activation cancels pre-existing candidate requests.
- Confirmed that speed preference transport, Settings controls, movement
  integration, and dragging-finger tracking are unchanged from 2.1.2.
- Reviewed lifecycle cleanup: the session is cleared before the final
  selection refresh, including cancellation and failure. The active predicate
  also requires a claimed, moving recognizer attached to the same keyboard and
  the same live input delegate. Ordinary typing and changed input focus retain
  the native candidate policy.
- Confirmed the policy method exists with a Boolean, no-argument signature in
  [iOS 14.4 headers](https://github.com/xybp888/iOS-Header/blob/master/14.4/PrivateFrameworks/UIKitCore.framework/UIKeyboardImpl.h)
  and [iOS 14.5 headers](https://github.com/xybp888/iOS-Header/blob/master/14.5/PrivateFrameworks/UIKitCore.framework/UIKeyboardImpl.h).
  A runtime signature check selects the native policy hook or the no-argument
  selection-refresh fallback. No completion-handler or execution-context
  method is suppressed by the candidate hooks.

## Browser investigation

Reviewed all three recordings frame by frame at half-second intervals:

- `backspace-fail.MP4`: Pinyin is entered, then Delete visibly highlights on
  repeated presses while the input remains `ni hao ma` and candidates remain.
- `candidate-suppress-fail.MP4`: accepting the candidate commits `你好吗`;
  subsequent caret movement changes the keyboard's candidate row.
- `candidate-suppress-recover.MP4`: re-entering the existing field restores
  the reported suppression behavior. The key icon is still present.

The old source intercepted initial Delete events without checking for active
composition, then called `handleDelete` on release. It also used a global
replay counter shared across presses. The new code detects composition using
the keyboard's marked-text state, its candidate-selection input buffer, and
the delegate's marked range. That decision is latched for the physical press.
Composition deletions use the original handlers and are not replayed.

The previous candidate hook covered only a selection policy method. The new
request gates also cover direct and asynchronous candidate generation while
the same claimed swipe is active. They are checked against the iOS 14.4/14.5
headers and each actual runtime method signature before installation.

[WebKit's 2021 source](https://github.com/WebKit/WebKit/blob/43e9aac7b44bdd419e7db650856f4916b2ff8e37/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm)
shows movement commands pairing `beginSelectionChange` with a later
`endSelectionChange`, plus a separate autocorrection-context request path.
Those notifications and context completions remain intact. The input manager
buffer accessors were checked against the
[iOS 14.5 state header](https://github.com/xybp888/iOS-Header/blob/master/14.5/PrivateFrameworks/TextInput.framework/TIKeyboardInputManagerState.h).

The recordings establish symptoms, not the exact private call sequence in the
user's browser. Request-path coverage is a source-based fix; it is not an
on-device trace or a verified runtime resolution.

## Remaining limits

The linker reports this warning for each arm64e object:

```text
was built with an incompatible arm64e ABI compiler
```

The cached Linux toolchain emits legacy arm64e binaries. This output is intended
for the user's rootful jailbreak; no rootless ABI conversion was applied.
Compilation, metadata, and signature checks do not establish runtime ABI
compatibility. See the references in `README.md`.

No physical iPhone was available. The 2.1.3 browser composition detection and
candidate-request hooks have not been verified inside UIKit on a device.
Portable tests establish the Delete policy and distance calculation; they
cannot establish actual browser/IME call order, pending request timing, or
rendering performance. No new performance measurement was made here.

First repeat the supplied Google/Bing cases: delete Pinyin while composition
is active, delete its last character, commit a candidate, then swipe immediately
without leaving the field. Check prediction recovery after release, native
typing, long-press Delete, and Delete-drag selection in ordinary text.

Also test 0.10, 1.00, and 2.00 in a native text field and Safari, including changing
direction and selecting text. Compare equal-length drags, both with one finger
starting on Shift/Delete and with a stationary modifier finger. Check word mode,
emoji, beginning/end of text, and crossing the selection anchor. Change speed
while another app is suspended, then verify its next swipe; also respring once
to check persistence. While dragging, selection-triggered candidate
requests should be suppressed; suggestions should resume at the final caret
position after release. Also test a cancelled gesture, changing input fields,
ordinary typing afterward, and any active marked-text composition used by the
input method. A pre-existing in-flight candidate request may still finish.
Third-party keyboard extensions can have independent candidate generators.

## Package SHA-256

`5090993eb169442ef0115596311b529821390c87882c880ebdc47e3dd3128799`
