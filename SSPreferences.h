#ifndef SS_PREFERENCES_H
#define SS_PREFERENCES_H

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "SSSpeed.h"

#define SSPreferencesDomain CFSTR("com.icraze.swipeselection")
#define SSSpeedKey CFSTR("SwipeSpeed")
#define SSPreferencesChanged CFSTR("com.icraze.swipeselection/preferenceschanged")

FOUNDATION_EXTERN double SSReadSpeed(void);
FOUNDATION_EXTERN BOOL SSWriteSpeed(double speed);
/* Called by SpringBoard and Settings, which can read the persisted preference. */
FOUNDATION_EXTERN void SSPublishSavedSpeed(void);

#endif
