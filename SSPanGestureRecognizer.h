#import <UIKit/UIKit.h>
#import <version.h>

@interface SSPanGestureRecognizer : UIPanGestureRecognizer
@property (nonatomic, readonly) CGPoint swipeTranslation;
@end
