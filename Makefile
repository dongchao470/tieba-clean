THEOS_PACKAGE_SCHEME = roothide
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = TBClient
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TiebaClean
$(TWEAK_NAME)_FILES = Tweak.xm Diag2.xm
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation
$(TWEAK_NAME)_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
