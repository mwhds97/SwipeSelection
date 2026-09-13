#import "SSPreferences.h"
#import <dlfcn.h>
#import <notify.h>

typedef CFPropertyListRef (*SSCopyPreference)(CFStringRef, CFStringRef, CFStringRef,
                                            CFStringRef, CFStringRef);
typedef void (*SSSetPreference)(CFStringRef, CFPropertyListRef, CFStringRef,
                               CFStringRef, CFStringRef, CFStringRef);
typedef Boolean (*SSSynchronizePreferences)(CFStringRef, CFStringRef,
                                            CFStringRef, CFStringRef);
static SSCopyPreference ssCopyPreference;
static SSSetPreference ssSetPreference;
static SSSynchronizePreferences ssSynchronizePreferences;
static int ssNotifyToken = -1;

static void SSPreparePreferences(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ssCopyPreference = (SSCopyPreference)dlsym(RTLD_DEFAULT, "_CFPreferencesCopyValueWithContainer");
        ssSetPreference = (SSSetPreference)dlsym(RTLD_DEFAULT, "_CFPreferencesSetValueWithContainer");
        ssSynchronizePreferences = (SSSynchronizePreferences)dlsym(RTLD_DEFAULT,
            "_CFPreferencesSynchronizeWithContainer");
        if (notify_register_check("com.icraze.swipeselection/preferenceschanged", &ssNotifyToken)
            != NOTIFY_STATUS_OK) ssNotifyToken = -1;
    });
}

static double SSReadSavedSpeed(void) {
    SSPreparePreferences();
    // This domain belongs to the tweak. Never resolve it relative to a host app
    // or the root user's preferences directory.
    CFPropertyListRef value = ssCopyPreference
        ? ssCopyPreference(SSSpeedKey, SSPreferencesDomain, CFSTR("mobile"),
                           kCFPreferencesAnyHost, CFSTR("kCFPreferencesNoContainer"))
        : CFPreferencesCopyValue(SSSpeedKey, SSPreferencesDomain, CFSTR("mobile"),
                                 kCFPreferencesAnyHost);
    id number = CFBridgingRelease(value);
    if (!number) {
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:
            @"/var/mobile/Library/Preferences/com.icraze.swipeselection.plist"];
        number = saved[@"SwipeSpeed"];
    }
    if (![number isKindOfClass:[NSNumber class]] ||
        CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID())
        return SS_SPEED_DEFAULT;
    return SSNormalizeSpeed([number doubleValue]);
}

static void SSPublishSpeed(double speed) {
    SSPreparePreferences();
    if (ssNotifyToken >= 0) notify_set_state(ssNotifyToken, SSEncodeSpeed(speed));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          SSPreferencesChanged, NULL, NULL, true);
}

void SSPublishSavedSpeed(void) {
    SSPublishSpeed(SSReadSavedSpeed());
}

double SSReadSpeed(void) {
    SSPreparePreferences();
    uint64_t state = 0;
    double speed;
    if (ssNotifyToken >= 0 && notify_get_state(ssNotifyToken, &state) == NOTIFY_STATUS_OK &&
        SSDecodeSpeed(state, &speed)) return speed;
    return SSReadSavedSpeed();
}

BOOL SSWriteSpeed(double speed) {
    SSPreparePreferences();
    speed = SSNormalizeSpeed(speed);
    NSNumber *number = @(speed);
    if (ssSetPreference) {
        ssSetPreference(SSSpeedKey, (__bridge CFNumberRef)number, SSPreferencesDomain,
                        CFSTR("mobile"), kCFPreferencesAnyHost, CFSTR("kCFPreferencesNoContainer"));
    } else {
        CFPreferencesSetValue(SSSpeedKey, (__bridge CFNumberRef)number, SSPreferencesDomain,
                              CFSTR("mobile"), kCFPreferencesAnyHost);
    }
    Boolean saved = ssSetPreference && ssSynchronizePreferences
        ? ssSynchronizePreferences(SSPreferencesDomain, CFSTR("mobile"),
                                   kCFPreferencesAnyHost, CFSTR("kCFPreferencesNoContainer"))
        : CFPreferencesSynchronize(SSPreferencesDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
    if (!saved || SSReadSavedSpeed() != speed) return NO;
    SSPublishSpeed(speed);
    return YES;
}
