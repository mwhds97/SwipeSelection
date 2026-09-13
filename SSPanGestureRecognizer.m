#import "SSPanGestureRecognizer.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface SSPanGestureRecognizer ()
@property (nonatomic, strong) NSMapTable<UITouch *, NSValue *> *touchOrigins;
@property (nonatomic, strong) UITouch *dragTouch;
@property (nonatomic) CGPoint swipeTranslation;
@end

@implementation SSPanGestureRecognizer

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.touchOrigins) self.touchOrigins = [NSMapTable strongToStrongObjectsMapTable];
    for (UITouch *touch in touches)
        [self.touchOrigins setObject:[NSValue valueWithCGPoint:[touch locationInView:self.view]] forKey:touch];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.dragTouch) {
        // Choose the finger actually dragging, not a stationary Shift/Delete
        // finger. Four points avoids locking onto minor modifier-key jitter.
        CGFloat longest = 4.0;
        CGPoint chosenDelta = CGPointZero;
        for (UITouch *touch in touches) {
            NSValue *origin = [self.touchOrigins objectForKey:touch];
            if (!origin) continue;
            CGPoint point = [touch locationInView:self.view];
            CGPoint start = origin.CGPointValue;
            if (fabs(point.x - start.x) >= longest) {
                longest = fabs(point.x - start.x);
                self.dragTouch = touch;
                chosenDelta = CGPointMake(point.x - start.x, point.y - start.y);
            }
        }
        self.swipeTranslation = CGPointMake(self.swipeTranslation.x + chosenDelta.x,
                                             self.swipeTranslation.y + chosenDelta.y);
    } else if ([touches containsObject:self.dragTouch]) {
        CGPoint point = [self.dragTouch locationInView:self.view];
        CGPoint previous = [self.dragTouch previousLocationInView:self.view];
        self.swipeTranslation = CGPointMake(self.swipeTranslation.x + point.x - previous.x,
                                             self.swipeTranslation.y + point.y - previous.y);
    }
    [super touchesMoved:touches withEvent:event];
}

- (void)forgetTouches:(NSSet<UITouch *> *)touches {
    BOOL lostDragFinger = self.dragTouch && [touches containsObject:self.dragTouch];
    for (UITouch *touch in touches) [self.touchOrigins removeObjectForKey:touch];
    if (lostDragFinger) {
        self.dragTouch = nil;
        for (UITouch *touch in self.touchOrigins.keyEnumerator.allObjects)
            [self.touchOrigins setObject:[NSValue valueWithCGPoint:[touch locationInView:self.view]] forKey:touch];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self forgetTouches:touches];
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self forgetTouches:touches];
    [super touchesCancelled:touches withEvent:event];
}

- (void)reset {
    [super reset];
    self.dragTouch = nil;
    self.touchOrigins = nil;
    self.swipeTranslation = CGPointZero;
}

-(BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer {
	if ([preventingGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && (![NSStringFromClass([preventingGestureRecognizer class]) isEqualToString:@"AKFlickGestureRecognizer"])) {
		return YES;
	}
	return NO;
}

-(BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
	return NO;
}
@end
