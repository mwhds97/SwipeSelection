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
#import <objc/runtime.h>

// The keyboard owns the session; weak references cannot keep an old input view
// or recognizer alive after a focus change or keyboard dismissal.
@interface SSCandidateSession : NSObject
@property (nonatomic, weak) UIPanGestureRecognizer *gesture;
@property (nonatomic, weak) id inputDelegate;
@end

@implementation SSCandidateSession
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

static UIKeyboardImpl *SSKeyboardForLayout(UIKeyboardLayoutStar *layout) {
	Class keyboardClass = objc_getClass("UIKeyboardImpl");
	for (UIView *view = layout.superview; view; view = view.superview)
		if ([view isKindOfClass:keyboardClass]) return (UIKeyboardImpl *)view;
	UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
	return [keyboard _layout] == layout ? keyboard : nil;
}

static void SSClearDeleteSession(UIKeyboardLayoutStar *layout) {
	SSDeleteSession *session = layout.SS_deleteSession;
	if (session.keyboard.SS_deleteSession == session) session.keyboard.SS_deleteSession = nil;
	layout.SS_deleteSession = nil;
}

static SSDeleteSession *SSCurrentDeleteSession(UIKeyboardImpl *keyboard) {
	SSDeleteSession *session = keyboard.SS_deleteSession;
	if (session && (!session.touch || !session.inputDelegate ||
		session.inputDelegate != SSCurrentInputDelegate(keyboard))) {
		keyboard.SS_deleteSession = nil;
		return nil;
	}
	return session;
}

static BOOL SSDeferCandidatesForKeyboard(UIKeyboardImpl *keyboard) {
	// UI state is inspected only on the main thread. Unrelated/background
	// requests keep their normal behavior.
	if (![NSThread isMainThread]) return NO;
	SSCandidateSession *session = keyboard.SS_candidateSession;
	UIPanGestureRecognizer *gesture = session.gesture;
	id input = session.inputDelegate;
	if (!gesture || !input) return NO;
	return gesture.state == UIGestureRecognizerStateChanged &&
		gesture.cancelsTouchesInView && gesture.view == keyboard &&
		keyboard.window != nil && input == SSCurrentInputDelegate(keyboard);
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
	// One distance budget for moving, selecting, and WebKit.
	static UITextRange *startingtextRange = nil;
	static UITextPosition *pivotPoint = nil;
	static CGPoint previousTranslation;
	static SSMovement movement;

	// Basic info
	static BOOL shiftHeldDown = NO;
	static BOOL hasStarted = NO;
	static BOOL longPress = NO;
	static BOOL handWriting = NO;
	static BOOL haveCheckedHand = NO;
	static BOOL isFirstShiftDown = NO; // = first run of the code shift is held, then pick the pivot point
	static BOOL isMoreKey = NO;
	static BOOL isKanaKey = NO;
	static int touchesWhenShiting = 0;
	static BOOL cancelled = NO;
	static CGFloat gestureSpeed = SS_SPEED_DEFAULT;

	int touchesCount = [gesture numberOfTouches];

	UIKeyboardImpl *keyboardImpl = self;

	if ([keyboardImpl respondsToSelector:@selector(isLongPress)]) {
		BOOL nLongTouch = [keyboardImpl isLongPress];
		if (nLongTouch) {
			longPress = nLongTouch;
		}
	}

	// Get current layout
	id currentLayout = nil;
	if ([keyboardImpl respondsToSelector:@selector(_layout)]) {
		currentLayout = [keyboardImpl _layout];
	}

	// Check more key, unless it's already ues
	if (!isMoreKey && [currentLayout respondsToSelector:@selector(SS_disableSwipes)]) {
		isMoreKey = [currentLayout SS_disableSwipes];
	}

	// Hand writing recognition
	if (!haveCheckedHand && [currentLayout respondsToSelector:@selector(handwritingPlane)]) {
		handWriting = [currentLayout handwritingPlane];
	} else if (!handWriting && !haveCheckedHand && [currentLayout respondsToSelector:@selector(subviews)]) {
		NSArray *subviews = [((UIView *)currentLayout) subviews];
		for (UIView *subview in subviews) {

			if ([subview respondsToSelector:@selector(subviews)]) {
				NSArray *arrayToCheck = [subview subviews];

				for (id view in arrayToCheck) {
					NSString *classString = [NSStringFromClass([view class]) lowercaseString];
					if ([classString rangeOfString:@"handwriting"].location != NSNotFound) {
						handWriting = YES;
						break;
					}
				}
			}
		}
		haveCheckedHand = YES;
	}
	haveCheckedHand = YES;

	// Check for shift key being pressed
	if ([currentLayout respondsToSelector:@selector(SS_shouldSelect)] && !shiftHeldDown) {
		shiftHeldDown = [currentLayout SS_shouldSelect];
		if (shiftHeldDown) {
			isFirstShiftDown = YES;
			touchesWhenShiting = touchesCount;
		}
	}

	if ([currentLayout respondsToSelector:@selector(SS_isKanaKey)]) {
		isKanaKey = [currentLayout SS_isKanaKey];
	}

	// Get the text input
	id <UITextInputPrivate> privateInputDelegate = nil;
	if ([keyboardImpl respondsToSelector:@selector(privateInputDelegate)]) {
		privateInputDelegate = (id)keyboardImpl.privateInputDelegate;
	}
	if (!privateInputDelegate && [keyboardImpl respondsToSelector:@selector(inputDelegate)]) {
		privateInputDelegate = (id)keyboardImpl.inputDelegate;
	}

	// Viber custom text view, which is super buggy with the tockenizer stuff.
	if (privateInputDelegate != nil && [NSStringFromClass([privateInputDelegate class]) isEqualToString:@"VBEmoticonsContentTextView"]) {
		privateInputDelegate = nil;
		cancelled = YES; // Try disabling it
	}

	//
	// Start Gesture stuff
	//
	if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
		// Clear before the final refresh, so it sees the final caret/selection.
		self.SS_candidateSession = nil;
		if (hasStarted) {
			if ([privateInputDelegate respondsToSelector:@selector(selectedTextRange)]) {
				UITextRange *range = [privateInputDelegate selectedTextRange];
				if (range && !range.empty) {
					UITextInteractionAssistant *assistant = [(UIResponder *)privateInputDelegate interactionAssistant];
					if (assistant) {
						[[assistant selectionView] showCalloutBarAfterDelay:0];
					} else {
						CGRect screenBounds = [UIScreen mainScreen].bounds;
						CGRect rect = CGRectMake(screenBounds.size.width * 0.5, screenBounds.size.height * 0.5, 1, 1);

						if ([privateInputDelegate respondsToSelector:@selector(firstRectForRange:)]) {
							rect = [privateInputDelegate firstRectForRange:range];
						}

						UIView *view = nil;
						if ([privateInputDelegate isKindOfClass:[UIView class]]) {
							view = (UIView *)privateInputDelegate;
						} else if ([privateInputDelegate respondsToSelector:@selector(inputDelegate)]) {
							id v = [keyboardImpl inputDelegate];
							if (v != privateInputDelegate) {
								if ([v isKindOfClass:[UIView class]]) {
									view = (UIView *)v;
								}
							}
						}
						// Should fix this to actually get the onscreen rect
						UIMenuController *menu = [UIMenuController sharedMenuController];
						[menu setTargetRect:rect inView:view];
						[menu setMenuVisible:YES animated:YES];
					}
				}
			}

			// Generate suggestions once at the final position after the drag.
			if ([keyboardImpl respondsToSelector:@selector(updateForChangedSelection)]) {
				[keyboardImpl updateForChangedSelection];
			}
		}

		shiftHeldDown = NO;
		isMoreKey = NO;
		longPress = NO;
		hasStarted = NO;
		handWriting = NO;
		haveCheckedHand = NO;
		cancelled = NO;
		isFirstShiftDown = NO;
		startingtextRange = nil;
		pivotPoint = nil;
		SSResetMovement(&movement);

		touchesCount = 0;
		touchesWhenShiting = 0;
		gesture.cancelsTouchesInView = NO;
	} else if (longPress || handWriting || !privateInputDelegate || isMoreKey || isKanaKey || cancelled) {
		// If an active drag becomes ineligible, resume normal keyboard handling.
		if (self.SS_candidateSession) {
			self.SS_candidateSession = nil;
			if (privateInputDelegate && [self respondsToSelector:@selector(updateForChangedSelection)])
				[self updateForChangedSelection];
		}
		return;
	} else if (gesture.state == UIGestureRecognizerStateBegan) {
		self.SS_candidateSession = nil;
		SSResetMovement(&movement);
		pivotPoint = nil;
		startingtextRange = nil;
		// Read the shared value on every new swipe, even if a notification was
		// missed while the app was suspended. Keep it fixed during this swipe.
		SSReloadSpeed();
		gestureSpeed = ssSwipeSpeed;
		previousTranslation = CGPointZero;

		if ([privateInputDelegate respondsToSelector:@selector(selectedTextRange)]) {
			startingtextRange = [privateInputDelegate selectedTextRange];
		}
	} else if (gesture.state == UIGestureRecognizerStateChanged) {
		UITextRange *currentRange = startingtextRange;
		if ([privateInputDelegate respondsToSelector:@selector(selectedTextRange)]) {
			currentRange = nil;
			currentRange = [privateInputDelegate selectedTextRange];
		}

		CGPoint translation = [(SSPanGestureRecognizer *)gesture swipeTranslation];

		// Should we even run?
		CGFloat deadZone = 18;
		if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
			deadZone = 30;
		}

		// If hasn't started, and it's either moved to little or the user swiped up (accents) kill it.
		if (hasStarted == NO && ABS(translation.y) > deadZone) {
			if (ABS(translation.y) > ABS(translation.x)) {
				cancelled = YES;
			}
		}
		if ((hasStarted == NO && ABS(translation.x) < deadZone) || cancelled) {
			return;
		}

		// We are running so shut other things off/down
		gesture.cancelsTouchesInView = YES;
		if (!self.SS_candidateSession) {
			SSCandidateSession *session = [[SSCandidateSession alloc] init];
			session.gesture = gesture;
			session.inputDelegate = privateInputDelegate;
			self.SS_candidateSession = session;
			// Retire predictions requested before this drag so a late typing
			// result cannot repaint the candidate row midway through it.
			if ([self respondsToSelector:@selector(cancelCandidateRequests)])
				[self cancelCandidateRequests];
		}
		hasStarted = YES;

		int neededTouches = 2;
		if (shiftHeldDown && (touchesWhenShiting >= 2)) {
			neededTouches = 3;
		}

		BOOL words = touchesCount >= neededTouches;
		UITextGranularity granularity = words ? UITextGranularityWord : UITextGranularityCharacter;
		BOOL extendRange = shiftHeldDown;
		double deltaX = translation.x - previousTranslation.x;
		previousTranslation = translation;
		int steps = SSTakeMovementSteps(&movement, deltaX, gestureSpeed, words);
		if (!steps) return;
		BOOL right = steps > 0;
		int count = abs(steps);

		// WebKit edits selection asynchronously. Send each step once through
		// its edit-command path; do not also write a stale UITextRange.
		Class webClass = NSClassFromString(@"WKContentView");
		if (webClass && [privateInputDelegate isKindOfClass:webClass]) {
			WKContentView *webView = (WKContentView *)privateInputDelegate;
			BOOL wordCommands = words &&
				[webView respondsToSelector:@selector(_moveToStartOfWord:withHistory:)] &&
				[webView respondsToSelector:@selector(_moveToEndOfWord:withHistory:)];
			if (!wordCommands && (![webView respondsToSelector:@selector(_moveLeft:withHistory:)] ||
				![webView respondsToSelector:@selector(_moveRight:withHistory:)])) return;
			for (int i = 0; i < count; i++) {
				if (wordCommands) {
					if (right) [webView _moveToEndOfWord:extendRange withHistory:nil];
					else [webView _moveToStartOfWord:extendRange withHistory:nil];
				} else {
					if (right) [webView _moveRight:extendRange withHistory:nil];
					else [webView _moveLeft:extendRange withHistory:nil];
				}
			}
			isFirstShiftDown = NO;
			[self SS_revealSelection:webView];
			return;
		}

		if (!currentRange) return;
		UITextPosition *positionStart = currentRange.start;
		UITextPosition *positionEnd = currentRange.end;
		if (!positionStart || !positionEnd) return;
		if (extendRange && (isFirstShiftDown || !pivotPoint))
			pivotPoint = right ? positionStart : positionEnd;
		UITextPosition *position = nil;
		if (extendRange && pivotPoint) {
			BOOL startIsPivot = KH_positionsSame(privateInputDelegate, pivotPoint, positionStart);
			position = startIsPivot ? positionEnd : positionStart;
		} else {
			position = right ? positionEnd : positionStart;
		}
		isFirstShiftDown = NO;

		id <UITextInputTokenizer, UITextInput> tokenizer = nil;
		if ([privateInputDelegate respondsToSelector:@selector(positionFromPosition:toBoundary:inDirection:)]) {
			tokenizer = privateInputDelegate;
		} else if ([privateInputDelegate respondsToSelector:@selector(tokenizer)]) {
			tokenizer = (id <UITextInput, UITextInputTokenizer>)privateInputDelegate.tokenizer;
		}

		if (!tokenizer || !position) return;
		for (int i = 0; i < count; i++) {
			UITextDirection direction = right ? UITextStorageDirectionForward : UITextStorageDirectionBackward;
			if ([privateInputDelegate baseWritingDirectionForPosition:position inDirection:UITextStorageDirectionForward]
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
		if (!extendRange) pivotPoint = position;
		if (!pivotPoint) return;
		UITextRange *textRange = nil;
		if ([privateInputDelegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)]) {
			if ([privateInputDelegate comparePosition:position toPosition:pivotPoint] == NSOrderedAscending)
				textRange = [privateInputDelegate textRangeFromPosition:position toPosition:pivotPoint];
			else
				textRange = [privateInputDelegate textRangeFromPosition:pivotPoint toPosition:position];
		}
		// Commit only the final range for this callback. Selection layout and
		// keyboard context updates therefore run once even for a fast swipe.
		if (textRange && (!KH_positionsSame(privateInputDelegate, currentRange.start, textRange.start) ||
			!KH_positionsSame(privateInputDelegate, currentRange.end, textRange.end))) {
			startingtextRange = textRange;
			[privateInputDelegate setSelectedTextRange:textRange];
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
	if (!SSDeferLegacyDelete(session ? &session->state : NULL)) %orig;
}

-(void)handleDeleteAsRepeat:(BOOL)repeat executionContext:(UIKeyboardTaskExecutionContext *)executionContext {
	// Long press is simply meant to indicate if it's should repeat delete so repeat will do.
	isLongPressed = repeat;
	SSDeleteSession *session = SSCurrentDeleteSession(self);
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

	%orig;
}
%end


%hook _UIKeyboardTextSelectionInteraction
-(BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	id delegate = [[self owner] delegate];
	if ([delegate respondsToSelector:@selector(SS_pan)] && [[delegate SS_pan] state] == UIGestureRecognizerStateChanged) return NO;
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
