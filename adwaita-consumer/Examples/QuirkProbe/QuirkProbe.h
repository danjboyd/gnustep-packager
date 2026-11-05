/*
   Copyright (C) 2025-2026 Daniel Boyd

   This file is part of the GNUstep Adwaita theme.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/AppKit.h>

/* Regression checks for theme bugs found by apps (first by
   OneDriveServiceManager). Each check renders controls offscreen and measures
   the result, so it doesn't depend on reference screenshots. Results go to
   stdout as PASS/FAIL/KNOWN/SKIP lines; the exit status is the number of
   failures. Run it through Tests/Scripts/run-quirk-probe.sh. */
@interface QuirkProbe : NSObject <NSToolbarDelegate, NSTableViewDataSource>
{
  NSString *_outputDirectory;
  NSMutableArray *_windows;
  NSWindow *_controlsWindow;
  NSWindow *_toolbarWindow;
  NSWindow *_lateWindow;
  NSWindow *_launchPrefsWindow;
  NSWindow *_latePrefsWindow;
  NSWindow *_optOutWindow;
  NSWindow *_optInWindow;
  NSWindow *_tableWindow;
  NSWindow *_headerWindow;
  NSTableView *_defaultGridTable;
  NSTableView *_explicitGridTable;
  NSPopUpButton *_popUpButton;
  NSMutableArray *_sizedButtons;
  NSMutableArray *_fixedButtons;
  NSStepper *_tallStepper;
  NSStepper *_maxedStepper;
  NSStepper *_wideStepper;
  NSColorWell *_colorWell;
  NSButton *_toolbarViewButton;
  NSTextField *_wrappingLabel;
  NSTextField *_newlineLabel;
  NSTextField *_pathLabel;
  NSTextField *_truncatedPathLabel;
  NSString *_alertText;
  NSArray *_primaryExtraItems;
  NSUInteger _passed;
  NSUInteger _failed;
  NSUInteger _known;
  NSUInteger _skipped;
}
@end

/* -ProbeOnly file-chooser (QuirkProbeFileChooser.m). */
@interface QuirkProbe (FileChooser)
- (void) checkFileChooser;
@end

/* -ProbeOnly print-dialog (QuirkProbePrintDialog.m). */
@interface QuirkProbe (PrintDialog)
- (void) checkPrintDialog;
@end

@interface QuirkProbe (MenuTiming)
- (void) checkMenuTiming;
@end

@interface QuirkProbe (ScrollerDrag)
- (void) checkScrollerDrag;
@end

/* -ProbeOnly nib-metrics, and in the full run (QuirkProbeNibMetrics.m). */
@interface QuirkProbe (Lists)
- (void) checkDropDownList;
- (void) checkSourceList;
- (void) checkDropDownEmpty;
- (void) showListsDemo;
@end

/* -ProbeOnly popover-demo, and in the full run (QuirkProbePopovers.m). */
@interface QuirkProbe (Popovers)
- (void) checkPopoverPanel;
- (void) showPopoverDemo;
@end

@interface QuirkProbe (ToolbarOverflow)
- (void) checkToolbarPriorityOverflow;
- (void) checkHeaderBarToolbarPriorityOverflow;
@end

@interface QuirkProbe (NibMetrics)
- (void) checkNibMetrics;
@end

@interface QuirkProbe (LiveSettings)
- (void) checkLiveSettings;
- (void) checkForcedColorScheme;
- (void) checkHiDPIFontHinting;
- (void) checkAccentAtLaunch;
@end

@interface QuirkProbe (ContextMenu)
- (void) checkContextMenu;
- (void) showContextMenuDemo;
@end
