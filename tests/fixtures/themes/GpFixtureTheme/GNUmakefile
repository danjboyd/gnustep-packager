# A minimal GNUstep theme for tests/shared/ThemeInputs.Tests.ps1: built with
# gnustep-make and installed in the user domain, as a theme input would be.
ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = GpFixtureTheme
BUNDLE_EXTENSION = .theme
GpFixtureTheme_PRINCIPAL_CLASS = GpFixtureTheme
GpFixtureTheme_INSTALL_DIR = $(GNUSTEP_LIBRARY)/Themes
GpFixtureTheme_OBJC_FILES = GpFixtureTheme.m

include $(GNUSTEP_MAKEFILES)/bundle.make
