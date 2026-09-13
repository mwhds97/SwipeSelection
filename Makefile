TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

TWEAK_NAME = SwipeSelection
SwipeSelection_CFLAGS = -fobjc-arc
SwipeSelection_FILES = Tweak.xm SSPanGestureRecognizer.m SSPreferences.m
SwipeSelection_FRAMEWORKS = UIKit Foundation CoreFoundation CoreGraphics

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
