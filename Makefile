export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0
export THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak
SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/aggregate.mk
