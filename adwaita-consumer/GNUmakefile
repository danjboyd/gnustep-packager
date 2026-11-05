# Copyright (C) 2025-2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; see the file COPYING.LIB.
# If not, see <http://www.gnu.org/licenses/>.

ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif
ifeq ($(GNUSTEP_MAKEFILES),)
 $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

GIO_PACKAGES = gio-2.0 glib-2.0 gobject-2.0
GIO_CFLAGS = $(shell pkg-config --cflags $(GIO_PACKAGES))
GIO_LIBS = $(shell pkg-config --libs $(GIO_PACKAGES))
# Xlib, for asking the window manager to move, resize and maximise windows
# with the header bar (Source/Adapters/GnomeThemeWindowManager.m).
X11_CFLAGS = $(shell pkg-config --cflags x11)
X11_LIBS = $(shell pkg-config --libs x11)

ADDITIONAL_OBJCFLAGS += -Wno-import $(GIO_CFLAGS) $(X11_CFLAGS)
ADDITIONAL_CFLAGS += $(GIO_CFLAGS)
ADDITIONAL_LDFLAGS += $(GIO_LIBS) $(X11_LIBS)

PACKAGE_NAME = Adwaita
BUNDLE_NAME = Adwaita
BUNDLE_EXTENSION = .theme
VERSION = 0.1.0-alpha22

Adwaita_PRINCIPAL_CLASS = GnomeTheme
Adwaita_INSTALL_DIR = $(GNUSTEP_LIBRARY)/Themes
# The theme's Info-gnustep.plist is AdwaitaInfo.plist, which gnustep-make
# merges into the one it generates. Listed as a resource, it raced the
# generated file and a clean build could ship without GSThemeDomain (#45).
# THIRD-PARTY-NOTICES: the licenses of the GNOME icons in ThemeImages,
# which aren't the theme's LGPL-2.1-or-later.
Adwaita_RESOURCE_FILES = \
	Resources/ThemeImages \
	Resources/ThemeTiles \
	THIRD-PARTY-NOTICES

Adwaita_OBJC_FILES = \
	Source/GnomeTheme.m \
	Source/Settings/GnomeThemeSettings.m \
	Source/Settings/GnomeThemeMetrics.m \
	Source/Settings/GnomeThemeSystemFonts.m \
	Source/Rendering/GnomeThemePalette.m \
	Source/Rendering/GnomeThemeControls.m \
	Source/Rendering/GnomeThemeAlerts.m \
	Source/Rendering/GnomeThemePrimaryMenu.m \
	Source/Rendering/GnomeThemeHeaderBar.m \
	Source/Adapters/GnomeThemeWindowManager.m \
	Source/Adapters/GnomeThemeFileChooser.m \
	Source/Adapters/GnomeThemePrintDialog.m \
	Source/Adapters/GnomeThemeSettingsMonitor.m \
	Source/Rendering/GnomeThemeMenusAndData.m \
	Source/Rendering/GnomeThemeLists.m \
	Source/Rendering/GnomeThemePopovers.m \
	Source/Rendering/GnomeThemeWindowTypes.m \
	Source/Rendering/GnomeThemeSymbolicImages.m \
	Source/Rendering/GnomeThemeOverlayScrollers.m \
	Source/Rendering/GnomeThemeNibMetrics.m \
	Source/Rendering/GnomeThemeWindowTabs.m \
	Source/Rendering/GnomeThemeAboutPanel.m

# Window tabs: Apple's NSWindow tabbing API from the shared code in
# danjboyd/gnustep-window-tabbing, copied into Source/WindowTabbing at the
# commit in its VERSION by Tools/vendor-window-tabbing.sh. The directory is
# relative, and the files are added before bundle.make reads the lists.
GSWINDOWTABBING_DIR = Source/WindowTabbing
include $(GSWINDOWTABBING_DIR)/GSWindowTabbing.make
Adwaita_OBJC_FILES += $(GSWINDOWTABBING_OBJC_FILES)
ADDITIONAL_INCLUDE_DIRS += $(GSWINDOWTABBING_INCLUDE_DIRS)

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble

.PHONY: demo installdemo probe check-quirks check-hidpi check-nib-metrics check-text-scaling check-live-settings check-color-scheme check-file-chooser check-print-dialog check-menu-timing check-scroller-drag check-context-menu check-mutter check-mutter-shadow check-wms palette installpalette adwaita-demo adwaita-metrics

demo:
	$(MAKE) -C Examples/ThemeDemo

probe:
	$(MAKE) -C Examples/QuirkProbe

# Menu bar and primary menu, each with the window manager's title bar and
# with the theme's header bar; then the header bar's checks in the dark
# palette and in high contrast over the light and the dark palette.
check-quirks:
	bash Tests/Scripts/run-quirk-probe.sh
	QUIRK_PROBE_MENU_STYLE=unset QUIRK_PROBE_ARGS="-ProbeMenuDefault YES" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_MENU_STYLE=unset QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO -ProbeMenuDefault YES" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_STYLE=dark QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO -ProbeOnly header-bar" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_STYLE=high-contrast QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO -ProbeOnly header-bar" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_STYLE=high-contrast-dark QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO -ProbeOnly header-bar" bash Tests/Scripts/run-quirk-probe.sh --no-build

# At GSScaleFactor 2 and 1: the theme's font hinting (metrics hinting off
# when scaled, as libs-back's own default). At 1.5 too: a window's edges at a
# fractional scale.
check-hidpi:
	QUIRK_PROBE_ARGS="-GSScaleFactor 2 -GSX11HandlesWindowDecorations NO -ProbeOnly hidpi-fonts" bash Tests/Scripts/run-quirk-probe.sh
	QUIRK_PROBE_ARGS="-GSScaleFactor 1.5 -GSX11HandlesWindowDecorations NO -ProbeOnly hidpi-fonts" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO -ProbeOnly hidpi-fonts" bash Tests/Scripts/run-quirk-probe.sh --no-build

# Metrics per window (#24): check-quirks checks a window loaded from a Gorm
# file with no choice made; these give every window GNOME's metrics, then
# compact ones.
check-nib-metrics:
	QUIRK_PROBE_ARGS="-GnomeThemeMetrics gnome -ProbeOnly nib-metrics" bash Tests/Scripts/run-quirk-probe.sh
	QUIRK_PROBE_ARGS="-GnomeThemeMetrics compact -ProbeOnly nib-metrics" bash Tests/Scripts/run-quirk-probe.sh --no-build

# GNOME's Large Text (#53): fonts and metrics at text-scaling-factor 1.25
# and 2.0; check-quirks checks 1.0.
# GNOME's settings changed while an app runs: dark style and Large Text on
# and off, in the probe's own GSettings keyfile (#64).
check-live-settings:
	QUIRK_PROBE_ARGS="-ProbeOnly live-settings" bash Tests/Scripts/run-quirk-probe.sh
	QUIRK_PROBE_ARGS="-GSX11HandlesWindowDecorations NO -ProbeOnly live-settings" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_ACCENT=teal QUIRK_PROBE_ARGS="-ProbeOnly accent -ProbeAccent teal" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_STYLE=dark QUIRK_PROBE_ACCENT=purple QUIRK_PROBE_ARGS="-ProbeOnly accent -ProbeAccent purple" bash Tests/Scripts/run-quirk-probe.sh --no-build

# A per-app scheme over GNOME's (#78): -GnomeThemeColorScheme each way,
# GTK_THEME's variant each way, the default winning over GTK_THEME, and
# high contrast over a forced dark palette.
check-color-scheme:
	QUIRK_PROBE_ARGS="-GnomeThemeColorScheme force-dark -ProbeForcedScheme dark -ProbeOnly forced-scheme" bash Tests/Scripts/run-quirk-probe.sh
	QUIRK_PROBE_STYLE=dark QUIRK_PROBE_ARGS="-GnomeThemeColorScheme force-light -ProbeForcedScheme light -ProbeOnly forced-scheme" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_GTK_THEME=Adwaita:dark QUIRK_PROBE_ARGS="-ProbeForcedScheme dark -ProbeOnly forced-scheme" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_STYLE=dark QUIRK_PROBE_GTK_THEME=Adwaita:light QUIRK_PROBE_ARGS="-ProbeForcedScheme light -ProbeOnly forced-scheme" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_GTK_THEME=Adwaita:dark QUIRK_PROBE_ARGS="-GnomeThemeColorScheme force-light -ProbeForcedScheme light -ProbeOnly forced-scheme" bash Tests/Scripts/run-quirk-probe.sh --no-build
	QUIRK_PROBE_STYLE=high-contrast QUIRK_PROBE_ARGS="-GnomeThemeColorScheme force-dark -ProbeForcedScheme dark -ProbeOnly forced-scheme" bash Tests/Scripts/run-quirk-probe.sh --no-build

check-text-scaling:
	QUIRK_PROBE_TEXT_SCALE=1.25 QUIRK_PROBE_ARGS="-ProbeOnly text-scaling" bash Tests/Scripts/run-quirk-probe.sh
	QUIRK_PROBE_TEXT_SCALE=2.0 QUIRK_PROBE_ARGS="-ProbeOnly text-scaling" bash Tests/Scripts/run-quirk-probe.sh --no-build

# Open and save panels as GNOME's file chooser, against a stand-in portal
# on a private session bus, and GNUstep's panels without one.
check-file-chooser:
	bash Tests/Scripts/run-file-chooser-check.sh

# The print panel as GNOME's print dialog, against a stand-in portal on a
# private session bus, and GNUstep's panel without one.
check-print-dialog:
	bash Tests/Scripts/run-print-dialog-check.sh

# The CPU time to fill and size a 1,500-item pop-up menu, against GNUstep's theme
# in the same process (#46).
check-menu-timing:
	QUIRK_PROBE_ARGS="-ProbeOnly menu-timing" bash Tests/Scripts/run-quirk-probe.sh

# Overlay scrollers: the corner where two meet, and dragging a knob keeps
# it shown and scrolling, also when the app tiles its scroll view as it
# scrolls.
check-scroller-drag:
	QUIRK_PROBE_ARGS="-ProbeOnly scroller-drag" bash Tests/Scripts/run-quirk-probe.sh

# Context menus open by the pointer as GTK 4's do, kept on screen (#20).
# Tests/Scripts/measure-context-menu.sh compares with GTK's under Mutter.
check-context-menu:
	QUIRK_PROBE_ARGS="-ProbeOnly context-menu" bash Tests/Scripts/run-quirk-probe.sh

# The header bar with Mutter as the window manager (GNOME Shell on a private
# Xvfb display; see the script).
check-mutter:
	bash Tests/Scripts/run-mutter-check.sh

# The same against a libs-gui and libs-back that draw GNOME's shadow
# (phase 2b in Docs/HANDOFF_HEADER_BAR.md), with checks of the shadow,
# corners, maximised and restored margins, resize band and click-through.
# Skipped when they aren't there.
MUTTER_CHECK_GUI ?= $(HOME)/git/gnustep/libs-gui-csd/Source/obj
MUTTER_CHECK_BACK ?= $(HOME)/git/gnustep/libs-back-csd/Source/libgnustep-back-032.bundle
check-mutter-shadow:
	MUTTER_CHECK_GUI="$(MUTTER_CHECK_GUI)" MUTTER_CHECK_BACK="$(MUTTER_CHECK_BACK)" \
	  bash Tests/Scripts/run-mutter-check.sh --shadow

# The same checks under KWin, Xfwm4 (each with its compositor) and Openbox
# with picom, with stock and with the shadow-drawing libraries
# (plugins-themes-Adwaita#14). Openbox doesn't list _GTK_FRAME_EXTENTS, so
# its windows get no margin.
check-wms:
	status=0; for wm in kwin xfwm4 openbox; do \
	  bash Tests/Scripts/run-mutter-check.sh --no-build --wm $$wm || status=1; \
	  MUTTER_CHECK_GUI="$(MUTTER_CHECK_GUI)" MUTTER_CHECK_BACK="$(MUTTER_CHECK_BACK)" \
	    bash Tests/Scripts/run-mutter-check.sh --no-build --shadow --wm $$wm || status=1; \
	done; exit $$status

installdemo:
	$(MAKE) -C Examples/ThemeDemo install

# The Gorm palette of controls at GNOME's sizes (see the README).
palette:
	$(MAKE) -C Palettes/Adwaita

installpalette:
	$(MAKE) -C Palettes/Adwaita install

adwaita-demo:
	python3 Reference/AdwaitaDemo/adwaita_demo.py

adwaita-metrics:
	python3 Reference/AdwaitaDemo/adwaita_demo.py --dump-metrics
