// **************************************************** //
// **************************************************** //
// **********        Design outline          ********** //
// **************************************************** //
// **************************************************** //
//
// 1 finger moves the cursour
// 2 fingers moves it one word at a time
//
// Should be able to move between 1 and 2 fingers without lifting your hand.
// If a selection has been made and you move right the selection starts moving from the end.
// - else it starts at the beginning.
//
// Holding shift selects text between the starting point and the destination.
// - the starting point is the reverse of the non selection movement.
// - - movement to the right starts at the start of existing selections.
//
// Movement upwards when in 2 finger mode should jump to the nearest word in the new line.
// - But another movement up again (without sideways movement) will jump to the nearest word to the originals x location,
// - - this ensures that the cursour doesn't jump about moving far away from it's start point.
//

#import "Tweak.h"
#import "SSPreferences.h"
#import "SSMovement.h"
#import "SSDeleteState.h"
#import "SSSwipeState.h"
#import "SSLayoutRange.h"
#import "SSEditRange.h"
#import <objc/runtime.h>

static void SSInstallAsyncTextCompatibility(void);
static void SSInstallTextEditCompatibility(id input);
// Set only after the signature-checked Telegram edit guard is installed.
static Class ssTextEditClass;

// The keyboard owns the session; weak references cannot keep an old input view
// or recognizer alive after a focus change or keyboard dismissal.
@interface SSCandidateSession : NSObject
@property (nonatomic, weak) UIPanGestureRecognizer *gesture;
@property (nonatomic, weak) id inputDelegate;
@end

@implementation SSCandidateSession
@end

// Opaque text positions and movement state belong to one gesture and one
// input delegate. Never share them between keyboards or reuse them after focus
// changes. Composition is allowed throughout the drag.
@interface SSPanSession : NSObject {
@public
	SSSwipeState state;
	UITextPosition *pivotPoint;
	CGPoint previousTranslation;
	SSMovement movement;
	BOOL shiftHeldDown, longPress, handWriting, haveCheckedHand;
	BOOL isFirstShiftDown, isMoreKey, isKanaKey;
	int touchesWhenShiting;
	CGFloat gestureSpeed;
}
@property (nonatomic, weak) id inputDelegate;
@end

@implementation SSPanSession
@end

@interface SSDeleteSession : NSObject {
@public
	SSDeleteState state;
}
@property (nonatomic, weak) UIKeyboardImpl *keyboard;
@property (nonatomic, weak) id inputDelegate;
@property (nonatomic, weak) UITouch *touch;
@end

@implementation SSDeleteSession
@end

static id SSCurrentInputDelegate(UIKeyboardImpl *keyboard) {
	id input = nil;
	if ([keyboard respondsToSelector:@selector(privateInputDelegate)])
		input = keyboard.privateInputDelegate;
	if (!input && [keyboard respondsToSelector:@selector(inputDelegate)])
		input = keyboard.inputDelegate;
	return input;
}

static BOOL SSHasComposition(UIKeyboardImpl *keyboard) {
	// The input manager knows about composition before WebKit's asynchronous
	// markedTextRange necessarily catches up with it.
	if ([keyboard respondsToSelector:@selector(hasMarkedText)] && keyboard.hasMarkedText)
		return YES;
	// A web page can replace its DOM value before its marked range catches
	// up. Also honor an active candidate-selection buffer in the input manager.
	if ([keyboard respondsToSelector:@selector(inputManagerState)]) {
		TIKeyboardInputManagerState *state = keyboard.inputManagerState;
		if ([state respondsToSelector:@selector(usesCandidateSelection)] && state.usesCandidateSelection &&
			[state respondsToSelector:@selector(inputCount)] && state.inputCount > 0 &&
			[state respondsToSelector:@selector(inputString)] && state.inputString.length > 0) return YES;
	}
	id input = SSCurrentInputDelegate(keyboard);
	if ([input respondsToSelector:@selector(markedTextRange)]) {
		UITextRange *range = [input markedTextRange];
		if (range && !range.empty) return YES;
	}
	return NO;
}

static BOOL SSPrepareComposingDelete(UIKeyboardImpl *keyboard) {
	if (![NSThread isMainThread] || !ssTextEditClass) return YES;
	id input = SSCurrentInputDelegate(keyboard);
	if (![input isKindOfClass:ssTextEditClass]) return YES;
	UITextView *view = input;
	if (view.delegate != input) return YES;
	NSRange selection = view.selectedRange;
	NSUInteger length = view.textStorage.length;
	if (!SSShouldMoveComposingDeleteToEnd(SSHasComposition(keyboard),
		selection.location, selection.length, length)) return YES;

	// In the reported case marked text is at the document end. If the user
	// is composing inside existing text, stay at that marked range's end so
	// the input method edits its own buffer rather than unrelated suffix text.
	UITextRange *marked = view.markedTextRange;
	UITextPosition *end = marked && !marked.empty ? marked.end : view.endOfDocument;
	UITextPosition *beginning = view.beginningOfDocument;
	if (!beginning || !end) return YES;
	NSInteger offset = [view offsetFromPosition:beginning toPosition:end];
	if (offset <= 0 || (NSUInteger)offset > length || view.attributedText.length != length) return YES;
	UITextRange *caret = [view textRangeFromPosition:end toPosition:end];
	if (!caret) return YES;
	if (input != SSCurrentInputDelegate(keyboard)) return NO;
	view.selectedTextRange = caret;
	// A selection callback may change focus/text. Do not let this key affect
	// a different input or use a destination invalidated by a reentrant edit.
	if (input != SSCurrentInputDelegate(keyboard) || view.textStorage.length != length) return NO;
	NSRange actual = view.selectedRange;
	return actual.location == (NSUInteger)offset && actual.length == 0;
}

static UIKeyboardImpl *SSKeyboardForLayout(UIKeyboardLayoutStar *layout) {
	Class keyboardClass = objc_getClass("UIKeyboardImpl");
	for (UIView *view = layout.superview; view; view = view.superview)
		if ([view isKindOfClass:keyboardClass]) return (UIKeyboardImpl *)view;
	UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
	return [keyboard _layout] == layout ? keyboard : nil;
}

static void SSClearDeleteSession(UIKeyboardLayoutStar *layout) {
	SSDeleteSession *session = layout.SS_deleteSession;
	if (session) {
		SSReleaseDelete(&session->state);
		// A cancelled touch can still have an auto-delete task in UIKit's
		// queue. Retain its cancellation until a fresh Delete sequence.
		if (!session->state.cancelledBySwipe && session.keyboard.SS_deleteSession == session)
			session.keyboard.SS_deleteSession = nil;
	}
	layout.SS_deleteSession = nil;
}

static SSDeleteSession *SSCurrentDeleteSession(UIKeyboardImpl *keyboard) {
	SSDeleteSession *session = keyboard.SS_deleteSession;
	if (session && ((!session.touch && !session->state.cancelledBySwipe) || !session.inputDelegate ||
		session.inputDelegate != SSCurrentInputDelegate(keyboard))) {
		keyboard.SS_deleteSession = nil;
		return nil;
	}
	return session;
}

static void SSStopDeleteForSwipe(UIKeyboardImpl *keyboard) {
	SSDeleteSession *session = SSCurrentDeleteSession(keyboard);
	if (session) SSCancelDeleteForSwipe(&session->state);
	// Set the cancellation before stopping the timer: UIKit may reenter
	// touch cleanup synchronously. Already-queued callbacks are gated too.
	if ([keyboard respondsToSelector:@selector(stopAutoDelete)]) [keyboard stopAutoDelete];
}

static BOOL SSPanCanContinue(UIKeyboardImpl *keyboard, UIPanGestureRecognizer *gesture,
	SSPanSession *session) {
	BOOL ownsSession = keyboard.SS_panSession == session;
	if (SSObserveSwipe(&session->state, ownsSession && session.inputDelegate &&
		session.inputDelegate == SSCurrentInputDelegate(keyboard),
		keyboard.window != nil && gesture.view == keyboard)) return YES;
	session->pivotPoint = nil;
	if (ownsSession) {
		keyboard.SS_candidateSession = nil;
		gesture.cancelsTouchesInView = NO;
	}
	return NO;
}

static void SSShowSelectionMenu(UIKeyboardImpl *keyboard, id input) {
	if (![input respondsToSelector:@selector(selectedTextRange)]) return;
	UITextRange *range = [input selectedTextRange];
	if (!range || range.empty) return;
	// Custom text inputs need not implement UIKit's private assistant APIs.
	id assistant = [input respondsToSelector:@selector(interactionAssistant)] ?
		[input interactionAssistant] : nil;
	id selectionView = [assistant respondsToSelector:@selector(selectionView)] ?
		[assistant selectionView] : nil;
	if ([selectionView respondsToSelector:@selector(showCalloutBarAfterDelay:)]) {
		[selectionView showCalloutBarAfterDelay:0];
		return;
	}
	UIView *view = [input isKindOfClass:[UIView class]] ? input : nil;
	if (!view || !view.window || ![input respondsToSelector:@selector(firstRectForRange:)]) return;
	CGRect rect = [input firstRectForRange:range];
	if (CGRectIsNull(rect) || CGRectIsInfinite(rect) || !isfinite(rect.origin.x) ||
		!isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height) ||
		input != SSCurrentInputDelegate(keyboard) || SSHasComposition(keyboard)) return;
	UIMenuController *menu = [UIMenuController sharedMenuController];
	[menu setTargetRect:rect inView:view];
	[menu setMenuVisible:YES animated:YES];
}

static BOOL SSDeferCandidatesForKeyboard(UIKeyboardImpl *keyboard) {
	// UI state is inspected only on the main thread. Unrelated/background
	// requests keep their normal behavior.
	if (![NSThread isMainThread]) return NO;
	SSCandidateSession *session = keyboard.SS_candidateSession;
	UIPanGestureRecognizer *gesture = session.gesture;
	id input = session.inputDelegate;
	SSPanSession *pan = keyboard.SS_panSession;
	if (!gesture || !input || !pan) return NO;
	// Composition does not cancel the swipe or disable candidate suppression.
	// Still check focus and attachment on every request.
	if (!SSPanCanContinue(keyboard, gesture, pan) || input != pan.inputDelegate) return NO;
	return gesture.state == UIGestureRecognizerStateChanged &&
		gesture.cancelsTouchesInView && pan->state == SSSwipeClaimed;
}

// Never install a hook under an assumed private signature. Older systems can
// use the existing no-argument selection-refresh entry point as a fallback.
static BOOL SSHasNoArgumentMethod(Class cls, SEL selector, BOOL booleanResult) {
	Method method = class_getInstanceMethod(cls, selector);
	if (!method || method_getNumberOfArguments(method) != 2) return NO;
	char returnType[8] = {0};
	method_getReturnType(method, returnType, sizeof(returnType));
	return booleanResult ? (returnType[0] == 'B' || returnType[0] == 'c')
	                     : returnType[0] == 'v';
}

static BOOL SSHasVoidMethod(Class cls, SEL selector, const char *first, const char *second) {
	Method method = class_getInstanceMethod(cls, selector);
	if (!method || method_getNumberOfArguments(method) != 2 + (first != NULL) + (second != NULL)) return NO;
	NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
	return strcmp(signature.methodReturnType, @encode(void)) == 0 &&
		(!first || strcmp([signature getArgumentTypeAtIndex:2], first) == 0) &&
		(!second || strcmp([signature getArgumentTypeAtIndex:3], second) == 0);
}

static BOOL SSHasObjectMethod(Class cls, SEL selector, const char *first, const char *second) {
	Method method = class_getInstanceMethod(cls, selector);
	if (!method || method_getNumberOfArguments(method) != 2 + (first != NULL) + (second != NULL)) return NO;
	NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
	return strcmp(signature.methodReturnType, @encode(id)) == 0 &&
		(!first || strcmp([signature getArgumentTypeAtIndex:2], first) == 0) &&
		(!second || strcmp([signature getArgumentTypeAtIndex:3], second) == 0);
}

// Updated only on the main thread, where keyboard gestures are handled.
static CGFloat ssSwipeSpeed = SS_SPEED_DEFAULT;

static void SSReloadSpeed(void) {
	ssSwipeSpeed = SSReadSpeed();
}

static void SSPreferencesDidChange(CFNotificationCenterRef center, void *observer,
	CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	dispatch_async(dispatch_get_main_queue(), ^{
		SSReloadSpeed();
	});
}

%hook UIKeyboardImpl
%property (nonatomic,strong) UIPanGestureRecognizer *SS_pan;
%property (nonatomic,strong) SSCandidateSession *SS_candidateSession;
%property (nonatomic,strong) SSDeleteSession *SS_deleteSession;
%property (nonatomic,strong) SSPanSession *SS_panSession;

-(id)initWithFrame:(CGRect)rect {
	UIKeyboardImpl *orig = %orig;

	if (orig && !orig.SS_pan) {
		SSPanGestureRecognizer *pan = [[SSPanGestureRecognizer alloc] initWithTarget:orig action:@selector(SS_KeyboardGestureDidPan:)];
		pan.cancelsTouchesInView = NO;
		[orig addGestureRecognizer:pan];
		[orig setSS_pan:pan];
	}

	return orig;
}

-(instancetype)initWithFrame:(CGRect)arg1 forCustomInputView:(BOOL)arg2 {
	UIKeyboardImpl *orig = %orig;

	if (orig && !orig.SS_pan) {
		SSPanGestureRecognizer *pan = [[SSPanGestureRecognizer alloc] initWithTarget:orig action:@selector(SS_KeyboardGestureDidPan:)];
		pan.cancelsTouchesInView = NO;
		[orig addGestureRecognizer:pan];
		[orig setSS_pan:pan];
	}

	return orig;
}

%new
-(void)SS_KeyboardGestureDidPan:(UIPanGestureRecognizer *)gesture {
	UIKeyboardImpl *keyboardImpl = self;
	id <UITextInputPrivate> privateInputDelegate = SSCurrentInputDelegate(self);
	if (gesture.state == UIGestureRecognizerStateBegan) {
		SSInstallAsyncTextCompatibility();
		SSInstallTextEditCompatibility(privateInputDelegate);
		self.SS_candidateSession = nil;
		gesture.cancelsTouchesInView = NO;
		SSPanSession *fresh = [[SSPanSession alloc] init];
		fresh.inputDelegate = privateInputDelegate;
		SSResetMovement(&fresh->movement);
		SSReloadSpeed();
		fresh->gestureSpeed = ssSwipeSpeed;
		self.SS_panSession = fresh;
	}
	SSPanSession *session = self.SS_panSession;
	if (!session) return;

	if (gesture.state == UIGestureRecognizerStateEnded ||
		gesture.state == UIGestureRecognizerStateCancelled ||
		gesture.state == UIGestureRecognizerStateFailed) {
		BOOL refresh = SSFinishSwipe(&session->state, privateInputDelegate &&
			privateInputDelegate == session.inputDelegate,
			self.window != nil && gesture.view == self);
		// Clear all ownership before any callback into the input method. A
		// reentrant focus/selection update cannot see the old anchor or claim.
		self.SS_candidateSession = nil;
		self.SS_panSession = nil;
		session->pivotPoint = nil;
		gesture.cancelsTouchesInView = NO;
		if (!refresh) return;
		if ([self respondsToSelector:@selector(updateForChangedSelection)])
			[self updateForChangedSelection];
		if (gesture.state == UIGestureRecognizerStateEnded &&
			privateInputDelegate == SSCurrentInputDelegate(self) && !SSHasComposition(self))
			SSShowSelectionMenu(self, privateInputDelegate);
		return;
	}

	// Keep composing swipes enabled. Only a lost input/keyboard invalidates
	// this gesture; Delete ownership is handled independently below.
	if (!SSPanCanContinue(self, gesture, session)) return;
	int touchesCount = (int)gesture.numberOfTouches;
	if ([keyboardImpl respondsToSelector:@selector(isLongPress)]) {
		BOOL nLongTouch = [keyboardImpl isLongPress];
		if (nLongTouch) {
			session->longPress = nLongTouch;
		}
	}

	// Get current layout
	id currentLayout = nil;
	if ([keyboardImpl respondsToSelector:@selector(_layout)]) {
		currentLayout = [keyboardImpl _layout];
	}

	// Check more key, unless it's already ues
	if (!session->isMoreKey && [currentLayout respondsToSelector:@selector(SS_disableSwipes)]) {
		session->isMoreKey = [currentLayout SS_disableSwipes];
	}

	// Hand writing recognition
	if (!session->haveCheckedHand && [currentLayout respondsToSelector:@selector(handwritingPlane)]) {
		session->handWriting = [currentLayout handwritingPlane];
	} else if (!session->handWriting && !session->haveCheckedHand && [currentLayout respondsToSelector:@selector(subviews)]) {
		NSArray *subviews = [((UIView *)currentLayout) subviews];
		for (UIView *subview in subviews) {

			if ([subview respondsToSelector:@selector(subviews)]) {
				NSArray *arrayToCheck = [subview subviews];

				for (id view in arrayToCheck) {
					NSString *classString = [NSStringFromClass([view class]) lowercaseString];
					if ([classString rangeOfString:@"handwriting"].location != NSNotFound) {
						session->handWriting = YES;
						break;
					}
				}
			}
		}
		session->haveCheckedHand = YES;
	}
	session->haveCheckedHand = YES;

	// Check for shift key being pressed
	if ([currentLayout respondsToSelector:@selector(SS_shouldSelect)] && !session->shiftHeldDown) {
		session->shiftHeldDown = [currentLayout SS_shouldSelect];
		if (session->shiftHeldDown) {
			session->isFirstShiftDown = YES;
			session->touchesWhenShiting = touchesCount;
		}
	}

	if ([currentLayout respondsToSelector:@selector(SS_isKanaKey)]) {
		session->isKanaKey = [currentLayout SS_isKanaKey];
	}

	// These layouts and long presses belong to the native keyboard.
	if (session->longPress || session->handWriting || session->isMoreKey ||
		session->isKanaKey || [NSStringFromClass([privateInputDelegate class])
			isEqualToString:@"VBEmoticonsContentTextView"]) {
		BOOL refresh = session->state == SSSwipeClaimed;
		session->state = SSSwipeBypassed;
		session->pivotPoint = nil;
		self.SS_candidateSession = nil;
		gesture.cancelsTouchesInView = NO;
		if (refresh && [self respondsToSelector:@selector(updateForChangedSelection)])
			[self updateForChangedSelection];
		return;
	}
	if (gesture.state == UIGestureRecognizerStateChanged) {
		// Read this input's current range; never fall back to a cached range
		// from a previous callback, keyboard, or document.
		if (![privateInputDelegate respondsToSelector:@selector(selectedTextRange)]) return;
		CGPoint translation = [(SSPanGestureRecognizer *)gesture swipeTranslation];

		// Should we even run?
		CGFloat deadZone = 18;
		if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
			deadZone = 30;
		}

		// If hasn't started, and it's either moved to little or the user swiped up (accents) kill it.
		if (session->state != SSSwipeClaimed && ABS(translation.y) > deadZone) {
			if (ABS(translation.y) > ABS(translation.x)) {
				session->state = SSSwipeBypassed;
			}
		}
		if ((session->state != SSSwipeClaimed && ABS(translation.x) < deadZone) || session->state == SSSwipeBypassed) {
			return;
		}

		Class webClass = NSClassFromString(@"WKContentView");
		BOOL webInput = webClass && [privateInputDelegate isKindOfClass:webClass];
		if (!webInput && (![privateInputDelegate respondsToSelector:@selector(comparePosition:toPosition:)] ||
			![privateInputDelegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)] ||
			![privateInputDelegate respondsToSelector:@selector(setSelectedTextRange:)])) return;
		BOOL firstClaim = session->state != SSSwipeClaimed;
		if (!SSPanCanContinue(self, gesture, session) || !SSClaimSwipe(&session->state)) return;
		if (firstClaim) SSStopDeleteForSwipe(self);
		gesture.cancelsTouchesInView = YES;
		if (!self.SS_candidateSession) {
			SSCandidateSession *candidates = [[SSCandidateSession alloc] init];
			candidates.gesture = gesture;
			candidates.inputDelegate = privateInputDelegate;
			self.SS_candidateSession = candidates;
			// Retire ordinary predictions. An in-flight composition request can
			// own marked-text state, so let that request finish normally. New
			// requests are still gated while dragging, including during Pinyin.
			if (!SSHasComposition(self) && [self respondsToSelector:@selector(cancelCandidateRequests)])
				[self cancelCandidateRequests];
		}
		if (!SSPanCanContinue(self, gesture, session)) return;

		int neededTouches = 2;
		if (session->shiftHeldDown && (session->touchesWhenShiting >= 2)) {
			neededTouches = 3;
		}

		BOOL words = touchesCount >= neededTouches;
		UITextGranularity granularity = words ? UITextGranularityWord : UITextGranularityCharacter;
		BOOL extendRange = session->shiftHeldDown;
		double deltaX = translation.x - session->previousTranslation.x;
		session->previousTranslation = translation;
		int steps = SSTakeMovementSteps(&session->movement, deltaX, session->gestureSpeed, words);
		if (!steps) return;
		BOOL right = steps > 0;
		int count = abs(steps);

		// WebKit edits selection asynchronously. Send each step once through
		// its edit-command path; do not also write a stale UITextRange.
		if (webInput) {
			WKContentView *webView = (WKContentView *)privateInputDelegate;
			BOOL wordCommands = words &&
				[webView respondsToSelector:@selector(_moveToStartOfWord:withHistory:)] &&
				[webView respondsToSelector:@selector(_moveToEndOfWord:withHistory:)];
			if (!wordCommands && (![webView respondsToSelector:@selector(_moveLeft:withHistory:)] ||
				![webView respondsToSelector:@selector(_moveRight:withHistory:)])) return;
			for (int i = 0; i < count; i++) {
				if (!SSPanCanContinue(self, gesture, session)) return;
				if (wordCommands) {
					if (right) [webView _moveToEndOfWord:extendRange withHistory:nil];
					else [webView _moveToStartOfWord:extendRange withHistory:nil];
				} else {
					if (right) [webView _moveRight:extendRange withHistory:nil];
					else [webView _moveLeft:extendRange withHistory:nil];
				}
			}
			session->isFirstShiftDown = NO;
			if (SSPanCanContinue(self, gesture, session)) [self SS_revealSelection:webView];
			return;
		}

		UITextRange *currentRange = [privateInputDelegate selectedTextRange];
		if (!SSPanCanContinue(self, gesture, session) || !currentRange) return;
		UITextPosition *positionStart = currentRange.start;
		UITextPosition *positionEnd = currentRange.end;
		if (!positionStart || !positionEnd) return;
		if (extendRange && (session->isFirstShiftDown || !session->pivotPoint))
			session->pivotPoint = right ? positionStart : positionEnd;
		UITextPosition *position = nil;
		if (extendRange && session->pivotPoint) {
			BOOL startIsPivot = KH_positionsSame(privateInputDelegate, session->pivotPoint, positionStart);
			position = startIsPivot ? positionEnd : positionStart;
		} else {
			position = right ? positionEnd : positionStart;
		}
		session->isFirstShiftDown = NO;

		id <UITextInputTokenizer, UITextInput> tokenizer = nil;
		if ([privateInputDelegate respondsToSelector:@selector(positionFromPosition:toBoundary:inDirection:)]) {
			tokenizer = privateInputDelegate;
		} else if ([privateInputDelegate respondsToSelector:@selector(tokenizer)]) {
			tokenizer = (id <UITextInput, UITextInputTokenizer>)privateInputDelegate.tokenizer;
		}

		if (![tokenizer respondsToSelector:@selector(positionFromPosition:toBoundary:inDirection:)] || !position) return;
		for (int i = 0; i < count; i++) {
			UITextDirection direction = right ? UITextStorageDirectionForward : UITextStorageDirectionBackward;
			if ([privateInputDelegate respondsToSelector:@selector(baseWritingDirectionForPosition:inDirection:)] &&
				[privateInputDelegate baseWritingDirectionForPosition:position inDirection:UITextStorageDirectionForward]
				== UITextWritingDirectionRightToLeft)
				direction = right ? UITextStorageDirectionBackward : UITextStorageDirectionForward;
			UITextPosition *next = KH_tokenizerMovePositionWithGranularitInDirection(tokenizer, position, granularity, direction);
			if (words && (!next || KH_positionsSame(privateInputDelegate, position, next))) {
				// Some tokenizers return the current word boundary. Cross it
				// by one grapheme, then continue to the next word boundary.
				UITextPosition *character = KH_tokenizerMovePositionWithGranularitInDirection(
					tokenizer, position, UITextGranularityCharacter, direction);
				if (character && !KH_positionsSame(privateInputDelegate, position, character)) {
					next = KH_tokenizerMovePositionWithGranularitInDirection(tokenizer, character, granularity, direction);
					if (!next) next = character;
				}
			}
			if (!next || KH_positionsSame(privateInputDelegate, position, next)) break;
			position = next;
		}
		if (!extendRange) session->pivotPoint = position;
		if (!session->pivotPoint) return;
		UITextRange *textRange = nil;
		if ([privateInputDelegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)]) {
			if ([privateInputDelegate comparePosition:position toPosition:session->pivotPoint] == NSOrderedAscending)
				textRange = [privateInputDelegate textRangeFromPosition:position toPosition:session->pivotPoint];
			else
				textRange = [privateInputDelegate textRangeFromPosition:session->pivotPoint toPosition:position];
		}
		if (!SSPanCanContinue(self, gesture, session)) return;
		// Commit only the final range for this callback. Selection layout and
		// keyboard context updates therefore run once even for a fast swipe.
		if (textRange && (!KH_positionsSame(privateInputDelegate, currentRange.start, textRange.start) ||
			!KH_positionsSame(privateInputDelegate, currentRange.end, textRange.end))) {
			[privateInputDelegate setSelectedTextRange:textRange];
			if (SSPanCanContinue(self, gesture, session))
				[self SS_revealSelection:(UIView *)privateInputDelegate];
		}
	}
}

%new
-(void)SS_revealSelection:(UIView *)inputView {
	UIFieldEditor *fieldEditor = [objc_getClass("UIFieldEditor") sharedFieldEditor];
	if (fieldEditor && [fieldEditor respondsToSelector:@selector(revealSelection)]) {
		[fieldEditor revealSelection];
	}

	if ([inputView respondsToSelector:@selector(_scrollRectToVisible:animated:)]) {
		if ([inputView respondsToSelector:@selector(caretRect)]) {
			CGRect caretRect = [inputView caretRect];
			[inputView _scrollRectToVisible:caretRect animated:NO];
		}
	} else if ([inputView respondsToSelector:@selector(scrollSelectionToVisible:)]) {
		[inputView scrollSelectionToVisible:YES];
	}
}

%end


%hook UIKeyboardLayoutStar
%property (nonatomic, strong) SSDeleteSession *SS_deleteSession;
/*==============touchesBegan================*/
-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	UIKBKey *keyObject = [self keyHitTest:[touch locationInView:self]];
	NSString *key = [[keyObject representedString] lowercaseString];

	isMoreKey = [key isEqualToString:@"more"];
	isKanaKey = [kanaKeys containsObject:key];

	for (UITouch *pressedTouch in touches) {
		NSString *pressedKey = [[[self keyHitTest:[pressedTouch locationInView:self]] representedString] lowercaseString];
		if (![pressedKey isEqualToString:@"delete"]) continue;
		SSClearDeleteSession(self);
		UIKeyboardImpl *keyboard = SSKeyboardForLayout(self);
		if (!keyboard) break;
		SSDeleteSession *session = [[SSDeleteSession alloc] init];
		session.keyboard = keyboard;
		session.inputDelegate = SSCurrentInputDelegate(keyboard);
		session.touch = pressedTouch;
		// Snapshot once per physical press: native deletion can clear the
		// final marked character before touchesEnded arrives.
		session->state = SSBeginDelete(!session.inputDelegate || SSHasComposition(keyboard));
		self.SS_deleteSession = session;
		keyboard.SS_deleteSession = session;
		break;
	}

	%orig;
}

/*==============touchesMoved================*/
-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	UIKBKey *keyObject = [self keyHitTest:[touch locationInView:self]];
	NSString *key = [[keyObject representedString] lowercaseString];

	// Delete key (or the arabic key which is where the shift key would be)
	if ([key isEqualToString:@"delete"] || [key isEqualToString:@"ء"]) {
		shiftByOtherKey = YES;
	}

	isMoreKey = [key isEqualToString:@"more"];

	%orig;
}

-(void)touchesCancelled:(id)arg1 withEvent:(id)arg2 {
	%orig;
	SSDeleteSession *session = self.SS_deleteSession;
	if (!session.touch || [arg1 containsObject:session.touch]) SSClearDeleteSession(self);

	shiftByOtherKey = NO;
	isLongPressed = NO;
	isMoreKey = NO;
}

/*==============touchesEnded================*/
-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	SSDeleteSession *session = self.SS_deleteSession;
	BOOL endsDelete = session.touch && [touches containsObject:session.touch];
	%orig;

	if (endsDelete) {
		UIKeyboardImpl *keyboard = session.keyboard;
		NSString *key = [[[self keyHitTest:[session.touch locationInView:self]] representedString] lowercaseString];
		BOOL sameInput = keyboard && session.inputDelegate &&
			session.inputDelegate == SSCurrentInputDelegate(keyboard);
		BOOL claimedSwipe = keyboard.SS_pan.cancelsTouchesInView || keyboard.SS_candidateSession != nil;
		if (SSReplayDelete(&session->state, sameInput, [key isEqualToString:@"delete"],
			claimedSwipe, SSHasComposition(keyboard))) {
			session->state.replaying = true;
			if ([keyboard respondsToSelector:@selector(handleDelete)]) {
				[keyboard handleDelete];
			} else if ([keyboard respondsToSelector:@selector(handleDeleteAsRepeat:)]) {
				[keyboard handleDeleteAsRepeat:NO];
			} else if ([keyboard respondsToSelector:@selector(handleDeleteWithNonZeroInputCount)]) {
				[keyboard handleDeleteWithNonZeroInputCount];
			}
		}
		SSClearDeleteSession(self);
	}

	shiftByOtherKey = NO;
	isLongPressed = NO;
	isMoreKey = NO;
}

%new
-(BOOL)SS_shouldSelect {
	return ([self isShiftKeyBeingHeld] || shiftByOtherKey);
}

%new
-(BOOL)SS_disableSwipes {
	return isMoreKey;
}

%new
-(BOOL)SS_isKanaKey {
	return isKanaKey;
}
%end


%hook UIKeyboardImpl
// Doesn't work to get long press on delete key but does for other keys.
-(BOOL)isLongPress {
	isLongPressed = %orig;
	return isLongPressed;
}

-(void)handleDelete {
	SSDeleteSession *session = SSCurrentDeleteSession(self);
	if (SSCancelDeleteCallback(session ? &session->state : NULL, false,
		SSDeferCandidatesForKeyboard(self))) return;
	if (!SSDeferLegacyDelete(session ? &session->state : NULL)) %orig;
}

-(void)handleDeleteAsRepeat:(BOOL)repeat executionContext:(UIKeyboardTaskExecutionContext *)executionContext {
	SSDeleteSession *session = SSCurrentDeleteSession(self);
	if (SSCancelDeleteCallback(session ? &session->state : NULL, repeat,
		SSDeferCandidatesForKeyboard(self))) {
		// A skipped native task still has to complete. Do not play Delete
		// feedback or report a long press for a callback owned by a swipe.
		[[executionContext executionQueue] finishExecution];
		return;
	}
	isLongPressed = repeat;
	if (SSDeferDelete(session ? &session->state : NULL, repeat)) {
		if ([[self _layout] respondsToSelector:@selector(idiom)]) {
			if ([(UIKeyboardLayout *)[self _layout] idiom] == 2) {
				[[UIDevice currentDevice] _playSystemSound:1123LL];
			} else {
				if (IS_IOS_OR_NEWER(iOS_16_0)) [self playDeleteKeyFeedbackRepeat:repeat rapid:NO];
				else if (IS_IOS_OR_NEWER(iOS_14_0)) [self playDeleteKeyFeedback:repeat];
				else if (IS_IOS_OR_NEWER(iOS_13_0)) [self playKeyClickSound:repeat];
				else if (IS_IOS_OR_NEWER(iOS_11_0)) [[self feedbackGenerator] _playFeedbackForActionType:3 withCustomization:nil];
				else if (IS_IOS_OR_NEWER(iOS_10_0)) [[self feedbackBehavior] _playFeedbackForActionType:3 withCustomization:nil];
			}
		}
		[[executionContext executionQueue] finishExecution];
		return;
	}

	// Prepare the caret only for a real native deletion, after cancellation
	// and tap-deferral checks. The input method performs exactly one Delete;
	// do not change the app's rejected range or synthesize a second key press.
	if (!SSPrepareComposingDelete(self)) {
		[[executionContext executionQueue] finishExecution];
		return;
	}
	%orig;
}
%end


%hook _UIKeyboardTextSelectionInteraction
-(BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	id delegate = [[self owner] delegate];
	// Only an eligible, claimed swipe blocks native text selection.
	if ([delegate isKindOfClass:objc_getClass("UIKeyboardImpl")] &&
		SSDeferCandidatesForKeyboard(delegate)) return NO;
	return %orig;
}
%end


%group SSNativeCandidatePolicy
%hook UIKeyboardImpl
-(BOOL)shouldGenerateCandidatesAfterSelectionChange {
	if (SSDeferCandidatesForKeyboard(self)) return NO;
	return %orig;
}
%end
%end

%group SSSelectionRefreshFallback
%hook UIKeyboardImpl
-(void)updateForChangedSelection {
	if (SSDeferCandidatesForKeyboard(self)) return;
	%orig;
}
%end
%end

// Web input can request candidates after text/context synchronization rather
// than through shouldGenerateCandidatesAfterSelectionChange. Gate the request
// entry points too. No result callback or execution-context method is dropped.
%group SSCandidateRequest
%hook UIKeyboardImpl
-(void)generateCandidates {
	if (SSDeferCandidatesForKeyboard(self)) return;
	%orig;
}
%end
%end

%group SSCandidateRequestWithOptions
%hook UIKeyboardImpl
-(void)generateCandidatesWithOptions:(int)options {
	if (SSDeferCandidatesForKeyboard(self)) return;
	%orig;
}
%end
%end

%group SSAsyncCandidateRequest
%hook UIKeyboardImpl
-(void)generateCandidatesAsynchronously {
	if (SSDeferCandidatesForKeyboard(self)) return;
	%orig;
}
%end
%end

%group SSAsyncCandidateRequestWithRange
%hook UIKeyboardImpl
-(void)generateCandidatesAsynchronouslyWithRange:(NSRange)range selectedCandidate:(id)candidate {
	if (SSDeferCandidatesForKeyboard(self)) return;
	%orig;
}
%end
%end

// Telegram's modern editor is a UITextView that acts as its own delegate.
// Its should-change callback builds an attributed-string preview using the
// incoming NSRange. Check that range BEFORE entering Swift/Foundation. This
// protects both active composition and a later Delete after the swipe ends.
// Install on the actual runtime subclass; its Swift module name can differ
// between builds. There is no global UITextView/NSAttributedString hook.
@interface SSChatInputTextView : UITextView <UITextViewDelegate>
@end

%group SSTextEditCompatibility
%hook SSChatInputTextView
-(BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
	if ([NSThread isMainThread] && textView == (id)self) {
		if (range.location == NSNotFound || !SSCanApplyTextEdit(range.location, range.length,
			textView.textStorage.length, textView.attributedText.length)) return NO;
	}
	return %orig;
}
%end
%end

static void SSInstallTextEditCompatibility(id input) {
	static BOOL installed = NO;
	if (installed || ![NSThread isMainThread]) return;
	Class base = objc_getClass("ChatInputTextViewImpl");
	if (!base || ![base isSubclassOfClass:[UITextView class]] || ![input isKindOfClass:base]) return;
	UITextView *view = input;
	if (view.delegate != input) return;
	Class viewClass = object_getClass(input);
	SEL selector = @selector(textView:shouldChangeTextInRange:replacementText:);
	Method method = class_getInstanceMethod(viewClass, selector);
	if (!method || method_getNumberOfArguments(method) != 5) return;
	NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
	const char *result = signature.methodReturnType;
	if ((strcmp(result, @encode(BOOL)) != 0 && strcmp(result, "c") != 0 && strcmp(result, "B") != 0) ||
		strcmp([signature getArgumentTypeAtIndex:2], @encode(id)) != 0 ||
		strcmp([signature getArgumentTypeAtIndex:3], @encode(NSRange)) != 0 ||
		strcmp([signature getArgumentTypeAtIndex:4], @encode(id)) != 0) return;
	%init(SSTextEditCompatibility, SSChatInputTextView = viewClass);
	ssTextEditClass = viewClass;
	installed = YES;
}

// Telegram's AsyncDisplayKit layout computes selection end - 1. At offset
// zero this wraps to NSUIntegerMax, which older builds pass as a scroll
// range. Guard only scroll requests inside that node's layout. Later builds
// use a position lookup and check for nil, which needs no interception.
@interface SSLayoutNode : NSObject
-(UITextView *)textView;
-(void)_layoutTextView;
@end

@interface SSLayoutTextView : UITextView
@end

// Accessed on the main thread only. Local strong references keep each nested
// layout's view alive, and @finally restores scope without swallowing errors.
static __unsafe_unretained UITextView *ssLayoutView;

%group SSAsyncTextCompatibility
%hook SSLayoutNode
-(void)_layoutTextView {
	if (![NSThread isMainThread]) {
		%orig;
		return;
	}
	UITextView *view = [self textView];
	if (![view isKindOfClass:[UITextView class]]) {
		%orig;
		return;
	}
	UITextView *previous = ssLayoutView;
	ssLayoutView = view;
	@try {
		%orig;
	} @finally {
		ssLayoutView = previous;
	}
}
%end

%hook SSLayoutTextView
-(void)scrollRangeToVisible:(NSRange)range {
	if (![NSThread isMainThread] || self != ssLayoutView) {
		%orig;
		return;
	}
	UITextView *previous = ssLayoutView;
	ssLayoutView = nil; // Do not reinterpret any internal UIKit calls.
	@try {
		UITextView *textView = (UITextView *)self;
		NSUInteger length = textView.textStorage.length;
		SSLayoutRange target = {range.location, range.length};
		if (!SSLayoutRangeIsValid(target, length)) {
			NSRange selection = textView.selectedRange;
			target = SSSafeLayoutScrollRange(target,
				(SSLayoutRange){selection.location, selection.length}, length);
		}
		%orig(NSMakeRange(target.location, target.length));
	} @finally { ssLayoutView = previous; }
}

%end
%end

static void SSInstallAsyncTextCompatibility(void) {
	static BOOL installed = NO;
	if (installed || ![NSThread isMainThread]) return;
	Class nodeClass = objc_getClass("ASEditableTextNode");
	Class viewClass = objc_getClass("ASPanningOverriddenUITextView");
	if (!nodeClass || !viewClass || ![viewClass isSubclassOfClass:[UITextView class]]) return;
	if (!SSHasNoArgumentMethod(nodeClass, @selector(_layoutTextView), NO) ||
		!SSHasObjectMethod(nodeClass, @selector(textView), NULL, NULL) ||
		!SSHasVoidMethod(viewClass, @selector(scrollRangeToVisible:), @encode(NSRange), NULL)) return;
	%init(SSAsyncTextCompatibility, SSLayoutNode = nodeClass, SSLayoutTextView = viewClass);
	installed = YES;
}

%ctor {
	NSString *path = [[NSProcessInfo processInfo] arguments][0];
	BOOL isApp = [path rangeOfString:@"/Application"].location != NSNotFound;
	BOOL isSpringBoard = [path rangeOfString:@"SpringBoard.app"].location != NSNotFound;
	if (isApp || isSpringBoard) {
		// SpringBoard seeds notifyd from disk after each respring/reboot and
		// retains a registration while sandboxed apps read the shared state.
		if (isSpringBoard) SSPublishSavedSpeed();
		SSReloadSpeed();
		CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
			NULL, SSPreferencesDidChange, SSPreferencesChanged, NULL,
			CFNotificationSuspensionBehaviorDeliverImmediately);
		// Refresh after suspension even if a Darwin notification was missed.
		[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
				SSReloadSpeed();
			}];
		kanaKeys = [NSSet setWithArray:@[@"あ",@"か",@"さ",@"た",@"な",@"は",@"ま",@"や",@"ら",@"わ",@"、"]];
		%init;
		SSInstallAsyncTextCompatibility();
		Class keyboardClass = objc_getClass("UIKeyboardImpl");
		if (SSHasNoArgumentMethod(keyboardClass, @selector(shouldGenerateCandidatesAfterSelectionChange), YES)) {
			%init(SSNativeCandidatePolicy);
		} else if (SSHasNoArgumentMethod(keyboardClass, @selector(updateForChangedSelection), NO)) {
			%init(SSSelectionRefreshFallback);
		}
		if (SSHasVoidMethod(keyboardClass, @selector(generateCandidates), NULL, NULL)) {
			%init(SSCandidateRequest);
		}
		if (SSHasVoidMethod(keyboardClass, @selector(generateCandidatesWithOptions:), @encode(int), NULL)) {
			%init(SSCandidateRequestWithOptions);
		}
		if (SSHasVoidMethod(keyboardClass, @selector(generateCandidatesAsynchronously), NULL, NULL)) {
			%init(SSAsyncCandidateRequest);
		}
		if (SSHasVoidMethod(keyboardClass, @selector(generateCandidatesAsynchronouslyWithRange:selectedCandidate:), @encode(NSRange), @encode(id))) {
			%init(SSAsyncCandidateRequestWithRange);
		}
	}
}
