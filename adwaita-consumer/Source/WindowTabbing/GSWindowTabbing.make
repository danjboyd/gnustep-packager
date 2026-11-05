# GSWindowTabbing.make: compiles window tabbing into a theme (or an app).
#
# In a theme's GNUmakefile, after including common.make:
#
#   GSWINDOWTABBING_DIR = path/to/gnustep-window-tabbing
#   include $(GSWINDOWTABBING_DIR)/GSWindowTabbing.make
#   MyTheme_OBJC_FILES += $(GSWINDOWTABBING_OBJC_FILES)
#   ADDITIONAL_INCLUDE_DIRS += $(GSWINDOWTABBING_INCLUDE_DIRS)
#
# and call GSWindowTabbingInstall() once, early: from the theme's
# -initWithBundle:, before calling super's (see GSWindowTabbing.h).
#
# GSWINDOWTABBING_DIR must be a relative path (objects go to
# ./obj/<target>.obj/<source path>), and the += lines must come before
# bundle.make / application.make is included, or these sources aren't built.

GSWINDOWTABBING_DIR ?= .

GSWINDOWTABBING_OBJC_FILES = \
  $(GSWINDOWTABBING_DIR)/Source/NSWindowTab.m \
  $(GSWINDOWTABBING_DIR)/Source/NSWindowTabGroup.m \
  $(GSWINDOWTABBING_DIR)/Source/GSWindowTabbingWindow.m \
  $(GSWINDOWTABBING_DIR)/Source/GSWindowTabbingDecorationView.m \
  $(GSWINDOWTABBING_DIR)/Source/GSWindowTabBarView.m \
  $(GSWINDOWTABBING_DIR)/Source/GSWindowTabBarLayout.m \
  $(GSWINDOWTABBING_DIR)/Source/GSWindowTabbingTheme.m \
  $(GSWINDOWTABBING_DIR)/Source/GSWindowTabbingInstall.m

GSWINDOWTABBING_INCLUDE_DIRS = -I$(GSWINDOWTABBING_DIR)/Headers
