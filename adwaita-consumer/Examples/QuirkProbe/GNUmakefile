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

APP_NAME = QuirkProbe
QuirkProbe_APPLICATION_ICON =
QuirkProbe_PRINCIPAL_CLASS = NSApplication

QuirkProbe_OBJC_FILES = \
	main.m \
	QuirkProbe.m \
	QuirkProbeFileChooser.m \
	QuirkProbePrintDialog.m \
	QuirkProbeMenuTiming.m \
	QuirkProbeScrollerDrag.m \
	QuirkProbeContextMenu.m \
	QuirkProbeNibMetrics.m \
	QuirkProbeLiveSettings.m \
	QuirkProbeLists.m \
	QuirkProbePopovers.m \
	QuirkProbeToolbarOverflow.m

QuirkProbe_HEADER_FILES = \
	QuirkProbe.h

ADDITIONAL_OBJCFLAGS += -Wno-import

include $(GNUSTEP_MAKEFILES)/application.make
