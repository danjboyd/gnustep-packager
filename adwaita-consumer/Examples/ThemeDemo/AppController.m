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

#import "AppController.h"
#import "ThemeDemoTableDataSource.h"

#import <Foundation/Foundation.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <GNUstepBase/GSObjCRuntime.h>

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

@interface NSComboBoxCell (ThemeDemoPrivate)
- (void) _performClickWithFrame: (NSRect)cellFrame
                         inView: (NSView *)controlView;
@end

static const CGFloat kDemoPadding = 20.0;
static CGFloat kDemoRowSpacing = 14.0;
static CGFloat kDemoControlHeight = 34.0;
static CGFloat kDemoWideControlWidth = 360.0;
static NSString *ThemeDemoSelectedPageKey = @"ThemeDemoSelectedPage";
static NSString *ThemeDemoOpenMenuKey = @"ThemeDemoOpenMenu";
static NSString *ThemeDemoQuitAfterKey = @"ThemeDemoQuitAfter";
static NSString *ThemeDemoWindowTitleKey = @"ThemeDemoWindowTitle";
static NSString *ThemeDemoCaptureMenuKey = @"ThemeDemoCaptureMenu";
static NSString *ThemeDemoCaptureMenuOutputKey = @"ThemeDemoCaptureMenuOutput";
static NSString *ThemeDemoCaptureMenuHighlightKey = @"ThemeDemoCaptureMenuHighlight";
static NSString *ThemeDemoDumpMenuGeometryKey = @"ThemeDemoDumpMenuGeometry";
static NSString *ThemeDemoDumpTabGeometryKey = @"ThemeDemoDumpTabGeometry";
static NSString *ThemeDemoDumpTypographyKey = @"ThemeDemoDumpTypography";
static NSString *ThemeDemoCommandScriptKey = @"ThemeDemoCommandScript";
static NSString *ThemeDemoCommandFIFOKey = @"ThemeDemoCommandFIFO";
static NSString *ThemeDemoScreenshotOutputKey = @"ThemeDemoScreenshotOutput";

static NSString *
ThemeDemoFontDescription(NSFont *font)
{
  if (font == nil)
    {
      return @"(nil)";
    }

  return [NSString stringWithFormat: @"%@ %.2f", [font fontName], [font pointSize]];
}

static void
ThemeDemoPrintLine(NSString *line)
{
  if (line == nil)
    {
      return;
    }

  fprintf (stderr, "%s\n", [line UTF8String]);
  fflush (stderr);
}

@interface AppController ()
- (void) buildMenuBar;
- (void) buildWindowAndTabs;
- (void) applyLaunchOptions;
- (BOOL) performRequestedCaptureIfNeeded;
- (BOOL) performRequestedGeometryDumpIfNeeded;
- (BOOL) performRequestedTabDumpIfNeeded;
- (BOOL) performRequestedTypographyDumpIfNeeded;
- (BOOL) performRequestedScreenshotIfNeeded;
- (void) openRequestedMenu;
- (void) startRequestedCommandInterfaceIfNeeded;
- (void) runRequestedCommandScript;
- (void) pollCommandFIFO: (NSTimer *)timer;
- (void) closeCommandFIFO;
- (void) executeCommandLine: (NSString *)line;
- (void) executeCommandLines: (NSString *)commands;
- (NSView *) textAuditControlNamed: (NSString *)name;
- (void) focusTextAuditControlNamed: (NSString *)name selectingAll: (BOOL)selectingAll;
- (void) selectFocusedTextAuditControl;
- (void) openDropdownNamed: (NSString *)name;
- (void) captureDropdownNamed: (NSString *)name toPath: (NSString *)path;
- (void) performPendingDropdownCapture: (NSTimer *)timer;
- (void) captureAlertToPath: (NSString *)path;
- (void) clickViewCenter: (NSView *)view;
- (BOOL) writeWindowScreenshotToPath: (NSString *)path;
- (BOOL) writeScreenScreenshotToPath: (NSString *)path;
- (BOOL) writeInternalScreenScreenshotToPath: (NSString *)path;
- (BOOL) imageAppearsBlank: (NSImage *)image;
- (BOOL) runScreenshotToolAtPath: (NSString *)toolPath
                         toPath: (NSString *)path;
- (BOOL) writeImage: (NSImage *)image toPNGPath: (NSString *)path;
- (void) sendMouseEventOfType: (NSEventType)type
              atWindowTopLeft: (NSPoint)point
                   clickCount: (NSInteger)clickCount;
- (void) clickWindowTopLeftPoint: (NSPoint)point;
- (void) sendKeyString: (NSString *)string;
- (void) selectPageNamed: (NSString *)name;
- (NSTabViewItem *) tabItemNamed: (NSString *)name;
- (IBAction) showControlsPage: (id)sender;
- (IBAction) showTextPage: (id)sender;
- (IBAction) showDataPage: (id)sender;
- (IBAction) showMenusPage: (id)sender;
- (IBAction) showStressPage: (id)sender;
- (NSTabViewItem *) controlsTabItem;
- (NSTabViewItem *) textTabItem;
- (NSTabViewItem *) dataTabItem;
- (NSTabViewItem *) menuTabItem;
- (NSTabViewItem *) stressTabItem;
- (NSView *) tabRootView;
- (NSMenu *) menuNamed: (NSString *)name;
- (BOOL) writePNGForMenu: (NSMenu *)menu
           highlightItem: (NSInteger)highlightIndex
                  toPath: (NSString *)path;
- (void) dumpGeometryForMenu: (NSMenu *)menu named: (NSString *)name;
- (void) dumpTabGeometry;
- (void) dumpTabGeometryAndTerminate;
- (void) dumpTypographyMetrics;
- (void) dumpTypographyMetricsAndTerminate;
- (NSView *) makeCanvasForRoot: (NSView *)root;
- (void) refreshDemoLayoutMetrics;
- (void) collectDescendantViewsOfClass: (Class)viewClass
                                inView: (NSView *)view
                              intoArray: (NSMutableArray *)results;
- (NSArray *) descendantViewsOfClass: (Class)viewClass
                              inView: (NSView *)view;
- (NSFont *) controlFont;
- (NSFont *) labelFont;
- (NSFont *) sectionTitleFont;
- (NSSize) defaultWindowContentSize;
- (NSTextField *) labelWithString: (NSString *)string frame: (NSRect)frame;
- (NSTextField *) sectionTitleLabelWithString: (NSString *)string frame: (NSRect)frame;
- (NSTextField *) fieldWithValue: (NSString *)value frame: (NSRect)frame;
- (void) populateControlsCanvas: (NSView *)canvas;
- (void) populateTextCanvas: (NSView *)canvas;
- (void) populateDataCanvas: (NSView *)canvas;
- (void) populateMenuCanvas: (NSView *)canvas;
- (void) populateStressCanvas: (NSView *)canvas;
- (void) sliderValueChanged: (id)sender;
- (void) stepperValueChanged: (id)sender;
- (void) radioSelectionChanged: (id)sender;
- (void) showDemoMenu: (id)sender;
- (void) segmentedChanged: (id)sender;
@end

@implementation AppController

- (id) init
{
  self = [super init];
  if (self != nil)
    {
      _commandFIFODescriptor = -1;
    }

  return self;
}

- (void) dealloc
{
  RELEASE (_window);
  RELEASE (_tabView);
  RELEASE (_tableDataSource);
  RELEASE (_progressIndicator);
  RELEASE (_sliderValueLabel);
  RELEASE (_stepperValueField);
  RELEASE (_demoMenu);
  RELEASE (_stressMenu);
  RELEASE (_segmentedControl);
  RELEASE (_demoMenuButton);
  RELEASE (_stressMenuButton);
  RELEASE (_primaryTextField);
  RELEASE (_passwordField);
  RELEASE (_searchField);
  RELEASE (_disabledTextField);
  RELEASE (_bodyTextView);
  RELEASE (_textComboBox);
  RELEASE (_pendingDropdownCaptureName);
  RELEASE (_pendingDropdownCapturePath);
  RELEASE (_commandFIFOBuffer);
  [self closeCommandFIFO];
  [super dealloc];
}

- (void) applicationWillFinishLaunching: (NSNotification *)notification
{
  [self buildMenuBar];
}

/* With -ThemeDemoLogFrames YES, each resize of the window as a line on
   stderr (run-mutter-check.sh counts them). */
- (void) logWindowResize: (NSNotification *)notification
{
  fprintf (stderr, "ThemeDemo-resize %s\n", [NSStringFromRect ([_window frame]) UTF8String]);
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  [self buildWindowAndTabs];
  if ([[NSUserDefaults standardUserDefaults] boolForKey: @"ThemeDemoLogFrames"])
    {
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(logWindowResize:)
                                                   name: NSWindowDidResizeNotification
                                                 object: _window];
    }
  if ([self performRequestedCaptureIfNeeded])
    {
      return;
    }
  if ([self performRequestedGeometryDumpIfNeeded])
    {
      return;
    }
  if ([self performRequestedTabDumpIfNeeded])
    {
      return;
    }
  if ([self performRequestedTypographyDumpIfNeeded])
    {
      return;
    }
  [_window makeKeyAndOrderFront: self];
  [_window makeFirstResponder: nil];
  [self applyLaunchOptions];
  if ([self performRequestedScreenshotIfNeeded])
    {
      return;
    }
  [self startRequestedCommandInterfaceIfNeeded];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)sender
{
  return YES;
}

/* A line on stderr when the app quits on its own, not killed
   (run-mutter-check.sh's Alt+F4 check). */
- (void) applicationWillTerminate: (NSNotification *)notification
{
  fprintf (stderr, "ThemeDemo-terminate\n");
}

#pragma mark - Menu & Window Setup

- (void) buildMenuBar
{
  NSMenu *mainMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"MainMenu"]);

  NSMenuItem *appItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"ThemeDemo"
                                                                action: NULL
                                                         keyEquivalent: @""]);
  [mainMenu addItem: appItem];

  NSMenu *appMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"ThemeDemo"]);
  [appMenu addItemWithTitle: @"About ThemeDemo"
                     action: @selector(orderFrontStandardAboutPanel:)
              keyEquivalent: @""];
  [appMenu addItem: [NSMenuItem separatorItem]];
  [appMenu addItemWithTitle: @"Quit ThemeDemo"
                     action: @selector(terminate:)
              keyEquivalent: @"q"];
  [appItem setSubmenu: appMenu];

  NSMenuItem *viewItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"View"
                                                                 action: NULL
                                                          keyEquivalent: @""]);
  NSMenu *viewMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"View"]);
  [viewMenu addItemWithTitle: @"Controls"
                      action: @selector(showControlsPage:)
               keyEquivalent: @"1"];
  [viewMenu addItemWithTitle: @"Typography and Spacing"
                      action: @selector(showTextPage:)
               keyEquivalent: @"2"];
  [viewMenu addItemWithTitle: @"Data Views"
                      action: @selector(showDataPage:)
               keyEquivalent: @"3"];
  [viewMenu addItemWithTitle: @"Menus"
                      action: @selector(showMenusPage:)
               keyEquivalent: @"4"];
  [viewMenu addItemWithTitle: @"Stress Cases"
                      action: @selector(showStressPage:)
               keyEquivalent: @"5"];
  [[viewMenu itemAtIndex: 0] setTarget: self];
  [[viewMenu itemAtIndex: 1] setTarget: self];
  [[viewMenu itemAtIndex: 2] setTarget: self];
  [[viewMenu itemAtIndex: 3] setTarget: self];
  [[viewMenu itemAtIndex: 4] setTarget: self];
  [viewItem setSubmenu: viewMenu];
  [mainMenu addItem: viewItem];

  NSMenuItem *windowItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Window"
                                                                   action: NULL
                                                            keyEquivalent: @""]);
  NSMenu *windowMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Window"]);
  [windowMenu addItemWithTitle: @"Miniaturize"
                        action: @selector(performMiniaturize:)
                 keyEquivalent: @"m"];
  [windowMenu addItemWithTitle: @"Zoom"
                        action: @selector(performZoom:)
                 keyEquivalent: @""];
  [windowMenu addItemWithTitle: @"Bring All to Front"
                        action: @selector(arrangeInFront:)
                 keyEquivalent: @""];
  [windowItem setSubmenu: windowMenu];
  [mainMenu addItem: windowItem];

  [NSApp setMainMenu: mainMenu];
  [NSApp setWindowsMenu: windowMenu];
}

- (void) buildWindowAndTabs
{
  NSRect frame;
  NSSize contentSize;
  NSUInteger style = (NSWindowStyleMaskTitled |
                      NSWindowStyleMaskClosable |
                      NSWindowStyleMaskResizable |
                      NSWindowStyleMaskMiniaturizable);
  [self refreshDemoLayoutMetrics];
  contentSize = [self defaultWindowContentSize];
  frame = NSMakeRect (0, 0, contentSize.width, contentSize.height);

  _window = [[NSWindow alloc] initWithContentRect: frame
                                        styleMask: style
                                          backing: NSBackingStoreBuffered
                                            defer: NO];
  [_window center];
  [_window setTitle: @"Adwaita Theme Demo"];
  [_window setReleasedWhenClosed: NO];
  [_window setContentMinSize: NSMakeSize (MAX (720.0, contentSize.width - 40.0),
                                          MAX (560.0, contentSize.height - 40.0))];

  NSView *contentView = [_window contentView];
  NSRect tabFrame = [contentView bounds];

  _tabView = [[NSTabView alloc] initWithFrame: tabFrame];
  [_tabView setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];

  [_tabView addTabViewItem: [self controlsTabItem]];
  [_tabView addTabViewItem: [self textTabItem]];
  [_tabView addTabViewItem: [self dataTabItem]];
  [_tabView addTabViewItem: [self menuTabItem]];
  [_tabView addTabViewItem: [self stressTabItem]];

  {
    NSRect contentRect = [_tabView contentRect];
    NSUInteger index = 0;
    NSUInteger count = [_tabView numberOfTabViewItems];

    for (index = 0; index < count; index++)
      {
        NSTabViewItem *item = [_tabView tabViewItemAtIndex: index];
        NSView *itemView = [item view];

        [itemView setFrame: contentRect];
        [itemView setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
      }
  }

  [contentView addSubview: _tabView];
}

- (NSTabViewItem *) tabItemNamed: (NSString *)name
{
  NSUInteger index = 0;
  NSUInteger count = [_tabView numberOfTabViewItems];

  if ([name length] == 0)
    {
      return nil;
    }

  for (index = 0; index < count; index++)
    {
      NSTabViewItem *item = [_tabView tabViewItemAtIndex: index];
      if ([[item identifier] isEqual: name])
        {
          return item;
        }
    }

  return nil;
}

- (void) selectPageNamed: (NSString *)name
{
  NSTabViewItem *item = [self tabItemNamed: name];

  if (item != nil)
    {
      [_tabView selectTabViewItem: item];
    }
}

- (void) applyLaunchOptions
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *page = [defaults stringForKey: ThemeDemoSelectedPageKey];
  NSString *openMenu = [defaults stringForKey: ThemeDemoOpenMenuKey];
  NSString *windowTitle = [defaults stringForKey: ThemeDemoWindowTitleKey];
  NSTimeInterval quitAfter = [defaults doubleForKey: ThemeDemoQuitAfterKey];

  if ([windowTitle length] > 0)
    {
      [_window setTitle: windowTitle];
    }

  if ([page length] > 0)
    {
      [self selectPageNamed: page];
    }

  if ([openMenu isEqualToString: @"stress"])
    {
      [self selectPageNamed: @"stress"];
      [self performSelector: @selector(openRequestedMenu) withObject: nil afterDelay: 0.35];
    }
  else if ([openMenu isEqualToString: @"demo"])
    {
      [self selectPageNamed: @"menus"];
      [self performSelector: @selector(openRequestedMenu) withObject: nil afterDelay: 0.35];
    }

  if (quitAfter > 0.0)
    {
      [NSApp performSelector: @selector(terminate:) withObject: self afterDelay: quitAfter];
    }
}

- (BOOL) performRequestedScreenshotIfNeeded
{
  NSString *outputPath = [[NSUserDefaults standardUserDefaults]
    stringForKey: ThemeDemoScreenshotOutputKey];

  if ([outputPath length] == 0)
    {
      return NO;
    }

  [_window displayIfNeeded];
  if ([self writeWindowScreenshotToPath: outputPath] == NO)
    {
      NSLog (@"Failed to capture ThemeDemo window to %@", outputPath);
    }

  [NSApp terminate: self];
  return YES;
}

- (void) startRequestedCommandInterfaceIfNeeded
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *fifoPath = [defaults stringForKey: ThemeDemoCommandFIFOKey];
  NSString *scriptPath = [defaults stringForKey: ThemeDemoCommandScriptKey];

  if ([scriptPath length] > 0)
    {
      [self performSelector: @selector(runRequestedCommandScript)
                 withObject: nil
                 afterDelay: 0.2];
    }

  if ([fifoPath length] > 0)
    {
      _commandFIFODescriptor = open ([fifoPath fileSystemRepresentation],
                                     O_RDONLY | O_NONBLOCK);
      if (_commandFIFODescriptor < 0)
        {
          NSLog (@"Failed to open ThemeDemo command FIFO %@: %s",
                 fifoPath,
                 strerror (errno));
          return;
        }

      _commandFIFOBuffer = [[NSMutableData alloc] init];
      _commandFIFOTimer = [NSTimer scheduledTimerWithTimeInterval: 0.05
                                                           target: self
                                                         selector: @selector(pollCommandFIFO:)
                                                         userInfo: nil
                                                          repeats: YES];
    }
}

- (void) runRequestedCommandScript
{
  NSString *path = [[NSUserDefaults standardUserDefaults]
    stringForKey: ThemeDemoCommandScriptKey];
  NSString *commands = nil;

  if ([path length] == 0)
    {
      return;
    }

  commands = [NSString stringWithContentsOfFile: path];
  if (commands == nil)
    {
      NSLog (@"Failed to read ThemeDemo command script %@", path);
      return;
    }

  [self executeCommandLines: commands];
}

- (void) pollCommandFIFO: (NSTimer *)timer
{
  char buffer[4096];
  ssize_t count = 0;

  (void)timer;

  if (_commandFIFODescriptor < 0)
    {
      return;
    }

  while ((count = read (_commandFIFODescriptor, buffer, sizeof (buffer))) > 0)
    {
      [_commandFIFOBuffer appendBytes: buffer length: count];
    }

  if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
    {
      NSLog (@"ThemeDemo command FIFO read failed: %s", strerror (errno));
      [self closeCommandFIFO];
      return;
    }

  while ([_commandFIFOBuffer length] > 0)
    {
      const char *bytes = [_commandFIFOBuffer bytes];
      NSUInteger length = [_commandFIFOBuffer length];
      NSUInteger index = 0;
      BOOL foundLine = NO;

      for (index = 0; index < length; index++)
        {
          if (bytes[index] == '\n')
            {
              NSData *lineData = nil;
              NSString *line = nil;

              lineData = [NSData dataWithBytes: bytes length: index];
              line = AUTORELEASE ([[NSString alloc] initWithData: lineData
                                                        encoding: NSUTF8StringEncoding]);
              [_commandFIFOBuffer replaceBytesInRange: NSMakeRange (0, index + 1)
                                            withBytes: NULL
                                               length: 0];
              [self executeCommandLine: line];
              foundLine = YES;
              break;
            }
        }

      if (foundLine == NO)
        {
          break;
        }
    }
}

- (void) closeCommandFIFO
{
  if (_commandFIFOTimer != nil)
    {
      [_commandFIFOTimer invalidate];
      _commandFIFOTimer = nil;
    }
  if (_commandFIFODescriptor >= 0)
    {
      close (_commandFIFODescriptor);
      _commandFIFODescriptor = -1;
    }
}

- (void) executeCommandLines: (NSString *)commands
{
  NSArray *lines = [commands componentsSeparatedByCharactersInSet:
    [NSCharacterSet newlineCharacterSet]];
  NSEnumerator *enumerator = [lines objectEnumerator];
  NSString *line = nil;

  while ((line = [enumerator nextObject]) != nil)
    {
      [self executeCommandLine: line];
    }
}

- (void) executeCommandLine: (NSString *)line
{
  NSString *trimmed = [line stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray *parts = nil;
  NSString *command = nil;

  if ([trimmed length] == 0 || [trimmed hasPrefix: @"#"])
    {
      return;
    }

  parts = [trimmed componentsSeparatedByCharactersInSet:
    [NSCharacterSet whitespaceCharacterSet]];
  command = [parts objectAtIndex: 0];

  if ([command isEqualToString: @"page"] && [parts count] >= 2)
    {
      [self selectPageNamed: [parts objectAtIndex: 1]];
      [_window displayIfNeeded];
    }
  else if (([command isEqualToString: @"click"]
      || [command isEqualToString: @"double-click"]) && [parts count] >= 3)
    {
      NSInteger clickCount = [command isEqualToString: @"double-click"] ? 2 : 1;
      [self clickWindowTopLeftPoint:
        NSMakePoint ([[parts objectAtIndex: 1] doubleValue],
                     [[parts objectAtIndex: 2] doubleValue])];
      if (clickCount == 2)
        {
          [self clickWindowTopLeftPoint:
            NSMakePoint ([[parts objectAtIndex: 1] doubleValue],
                         [[parts objectAtIndex: 2] doubleValue])];
        }
    }
  else if ([command isEqualToString: @"mouse-down"] && [parts count] >= 3)
    {
      [self sendMouseEventOfType: NSLeftMouseDown
                 atWindowTopLeft: NSMakePoint ([[parts objectAtIndex: 1] doubleValue],
                                               [[parts objectAtIndex: 2] doubleValue])
                      clickCount: 1];
    }
  else if ([command isEqualToString: @"mouse-up"] && [parts count] >= 3)
    {
      [self sendMouseEventOfType: NSLeftMouseUp
                 atWindowTopLeft: NSMakePoint ([[parts objectAtIndex: 1] doubleValue],
                                               [[parts objectAtIndex: 2] doubleValue])
                      clickCount: 1];
    }
  else if ([command isEqualToString: @"type"] || [command isEqualToString: @"key"])
    {
      NSRange range = [trimmed rangeOfString: @" "];
      if (range.location != NSNotFound)
        {
          [self sendKeyString: [trimmed substringFromIndex: NSMaxRange (range)]];
        }
    }
  else if ([command isEqualToString: @"focus"] && [parts count] >= 2)
    {
      [self focusTextAuditControlNamed: [parts objectAtIndex: 1] selectingAll: NO];
    }
  else if ([command isEqualToString: @"blur-to"] && [parts count] >= 2)
    {
      [self focusTextAuditControlNamed: [parts objectAtIndex: 1] selectingAll: NO];
    }
  else if ([command isEqualToString: @"select-all"])
    {
      [self selectFocusedTextAuditControl];
    }
  else if ([command isEqualToString: @"open-dropdown"] && [parts count] >= 2)
    {
      [self openDropdownNamed: [parts objectAtIndex: 1]];
    }
  else if ([command isEqualToString: @"capture-dropdown"] && [parts count] >= 3)
    {
      [self captureDropdownNamed: [parts objectAtIndex: 1]
                          toPath: [parts objectAtIndex: 2]];
    }
  else if ([command isEqualToString: @"tooltip"] && [parts count] >= 3)
    {
      /* A tool tip shown as GSToolTips shows it, then moved so its top
         left corner is at X Y (X11 screen coordinates), for a test to
         look at what's behind it. */
      NSView *anchor = [_window contentView];
      NSString *text = @"Zoom: Fit to Window";
      NSTimer *fake = [NSTimer timerWithTimeInterval: 1000 target: self selector: @selector(description)
                                            userInfo: text repeats: NO];
      NSEnumerator *enumerator;
      NSWindow *window;

      [anchor setToolTip: text];
      _toolTips = [NSClassFromString (@"GSToolTips") performSelector: @selector(tipsForView:) withObject: anchor];
      [_toolTips performSelector: @selector(_timedOut:) withObject: fake];
      enumerator = [[NSApp windows] objectEnumerator];
      while ((window = [enumerator nextObject]) != nil)
        {
          if ([window isKindOfClass: NSClassFromString (@"GSTTPanel")] && [window isVisible])
            {
              [window setFrameTopLeftPoint:
                        NSMakePoint ([[parts objectAtIndex: 1] doubleValue],
                                     NSHeight ([[window screen] frame]) - [[parts objectAtIndex: 2] doubleValue])];
            }
        }
    }
  else if ([command isEqualToString: @"tooltip-hide"])
    {
      [_toolTips performSelector: @selector(_endDisplay)];
      [[_window contentView] setToolTip: nil];
      _toolTips = nil;
    }
  else if ([command isEqualToString: @"alert"])
    {
      /* An alert over the main window, for a test to look at; it logs how
         it was closed. */
      NSAlert *alert = AUTORELEASE ([[NSAlert alloc] init]);
      NSInteger result;

      [alert setMessageText: @"Remove this library?"];
      [alert setInformativeText: @"Its photos stay on the disk."];
      [alert addButtonWithTitle: @"Remove"];
      [alert addButtonWithTitle: @"Cancel"];
      result = [alert runModal];
      fprintf (stderr, "ThemeDemo-alert-closed %ld\n", (long)result);
    }
  else if ([command isEqualToString: @"capture-alert"] && [parts count] >= 2)
    {
      [self captureAlertToPath: [parts objectAtIndex: 1]];
    }
  else if ([command isEqualToString: @"screenshot"] && [parts count] >= 2)
    {
      [_window displayIfNeeded];
      if ([self writeWindowScreenshotToPath: [parts objectAtIndex: 1]] == NO)
        {
          NSLog (@"Failed to write screenshot %@", [parts objectAtIndex: 1]);
        }
    }
  else if ([command isEqualToString: @"screenshot-screen"] && [parts count] >= 2)
    {
      [_window displayIfNeeded];
      if ([self writeScreenScreenshotToPath: [parts objectAtIndex: 1]] == NO)
        {
          NSLog (@"Failed to write screen screenshot %@", [parts objectAtIndex: 1]);
        }
    }
  else if ([command isEqualToString: @"wait"] && [parts count] >= 2)
    {
      NSDate *until = [NSDate dateWithTimeIntervalSinceNow:
        [[parts objectAtIndex: 1] doubleValue]];
      while ([until timeIntervalSinceNow] > 0.0)
        {
          [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                   beforeDate: until];
        }
    }
  else if ([command isEqualToString: @"display"])
    {
      [_window displayIfNeeded];
    }
  else if ([command isEqualToString: @"quit"])
    {
      [NSApp terminate: self];
    }
  else
    {
      NSLog (@"Unknown ThemeDemo command: %@", trimmed);
    }
}

- (NSView *) textAuditControlNamed: (NSString *)name
{
  if ([name isEqualToString: @"primary"])
    {
      return _primaryTextField;
    }
  if ([name isEqualToString: @"password"])
    {
      return _passwordField;
    }
  if ([name isEqualToString: @"search"])
    {
      return _searchField;
    }
  if ([name isEqualToString: @"combo"])
    {
      return _textComboBox;
    }
  if ([name isEqualToString: @"disabled"])
    {
      return _disabledTextField;
    }
  if ([name isEqualToString: @"body"])
    {
      return _bodyTextView;
    }

  return nil;
}

- (void) focusTextAuditControlNamed: (NSString *)name selectingAll: (BOOL)selectingAll
{
  NSView *view = [self textAuditControlNamed: name];
  NSView *previous = _commandFocusedTextControl;

  if (view == nil || _window == nil)
    {
      NSLog (@"Unknown ThemeDemo text audit target: %@", name);
      return;
    }

  if (previous != nil && previous != view)
    {
      [previous setNeedsDisplay: YES];
      if ([previous superview] != nil)
        {
          [[previous superview] setNeedsDisplayInRect: [previous frame]];
        }
    }

  [NSApp activateIgnoringOtherApps: YES];
  [_window makeKeyAndOrderFront: self];

  if ([view isKindOfClass: [NSComboBox class]])
    {
      [_window makeFirstResponder: view];
    }
  else if ([view isKindOfClass: [NSTextField class]])
    {
      NSTextField *field = (NSTextField *)view;

      if ([field isEnabled] && ([field isEditable] || [field isSelectable]))
        {
          [field selectText: self];
          if (selectingAll == NO)
            {
              NSText *editor = [field currentEditor];
              if (editor != nil)
                {
                  [editor setSelectedRange:
                    NSMakeRange ([[editor string] length], 0)];
                }
            }
        }
      else
        {
          [_window makeFirstResponder: view];
        }
    }
  else
    {
      [_window makeFirstResponder: view];
    }

  _commandFocusedTextControl = view;
  [view setNeedsDisplay: YES];
  [_window displayIfNeeded];
}

- (void) selectFocusedTextAuditControl
{
  id firstResponder = [_window firstResponder];

  if ([firstResponder isKindOfClass: [NSText class]])
    {
      NSText *editor = (NSText *)firstResponder;
      [editor setSelectedRange: NSMakeRange (0, [[editor string] length])];
    }
  else if ([_commandFocusedTextControl isKindOfClass: [NSTextField class]])
    {
      [(NSTextField *)_commandFocusedTextControl selectText: self];
    }
  else if ([_commandFocusedTextControl isKindOfClass: [NSTextView class]])
    {
      NSTextView *textView = (NSTextView *)_commandFocusedTextControl;
      [textView setSelectedRange: NSMakeRange (0, [[textView string] length])];
    }

  if (_commandFocusedTextControl != nil)
    {
      [_commandFocusedTextControl setNeedsDisplay: YES];
    }
  [_window displayIfNeeded];
}

- (void) openDropdownNamed: (NSString *)name
{
  if ([name isEqualToString: @"combo"] && _textComboBox != nil)
    {
      NSComboBoxCell *cell = (NSComboBoxCell *)[_textComboBox cell];
      NSRect bounds = [_textComboBox bounds];

      [cell _performClickWithFrame: bounds
                             inView: _textComboBox];
      return;
    }

  NSLog (@"Unknown ThemeDemo dropdown audit target: %@", name);
}

- (void) captureDropdownNamed: (NSString *)name toPath: (NSString *)path
{
  NSTimer *timer = nil;

  ASSIGN (_pendingDropdownCaptureName, name);
  ASSIGN (_pendingDropdownCapturePath, path);

  timer = [NSTimer timerWithTimeInterval: 0.4
                                  target: self
                                selector: @selector(performPendingDropdownCapture:)
                                userInfo: nil
                                 repeats: NO];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSEventTrackingRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];

  [self openDropdownNamed: name];
}

- (void) performPendingDropdownCapture: (NSTimer *)timer
{
  NSString *path = _pendingDropdownCapturePath;
  NSString *name = _pendingDropdownCaptureName;
  BOOL wroteScreenshot = NO;

  (void)timer;
  (void)name;

  if ([path length] > 0)
    {
      wroteScreenshot = [self writeInternalScreenScreenshotToPath: path];
      if (wroteScreenshot == NO)
        {
          NSLog (@"Internal dropdown capture failed for %@; falling back to gnome-screenshot",
                 path);
          wroteScreenshot = [self runScreenshotToolAtPath: @"/usr/bin/gnome-screenshot"
                                                   toPath: path];
        }
    }

  if (wroteScreenshot == NO)
    {
      NSLog (@"Failed to capture dropdown %@ to %@", name, path);
    }

  RELEASE (_pendingDropdownCaptureName);
  _pendingDropdownCaptureName = nil;
  RELEASE (_pendingDropdownCapturePath);
  _pendingDropdownCapturePath = nil;
  [NSApp terminate: self];
}

- (void) captureAlertToPath: (NSString *)path
{
  NSTask *task = AUTORELEASE ([[NSTask alloc] init]);
  NSString *escapedPath = [path stringByReplacingOccurrencesOfString: @"'"
                                                          withString: @"'\\''"];
  NSString *script = [NSString stringWithFormat:
    @"sleep 0.4; /usr/bin/gnome-screenshot -f '%@'; pkill -f 'ThemeDemo.app/ThemeDemo'",
    escapedPath];
  NSAlert *alert = AUTORELEASE ([[NSAlert alloc] init]);

  [task setLaunchPath: @"/bin/sh"];
  [task setArguments: [NSArray arrayWithObjects: @"-c", script, nil]];
  NS_DURING
    {
      [task launch];
    }
  NS_HANDLER
    {
    }
  NS_ENDHANDLER

  [alert setMessageText: @"Do you want to save the changes made to this document?"];
  [alert setInformativeText: @"Your changes will be lost if you don't save them."];
  [alert addButtonWithTitle: @"Save"];
  [alert addButtonWithTitle: @"Cancel"];
  [alert addButtonWithTitle: @"Don't Save"];
  [alert runModal];
}

- (void) clickViewCenter: (NSView *)view
{
  NSRect bounds = [view bounds];
  NSPoint center = NSMakePoint (NSMidX (bounds), NSMidY (bounds));
  NSPoint windowPoint = [view convertPoint: center toView: nil];
  NSPoint contentPoint = [[_window contentView] convertPoint: windowPoint fromView: nil];
  NSRect contentBounds = [[_window contentView] bounds];
  CGFloat scale = [_window userSpaceScaleFactor];

  if (scale <= 0.0)
    {
      scale = 1.0;
    }

  [self clickWindowTopLeftPoint:
    NSMakePoint (contentPoint.x * scale,
                 (NSHeight (contentBounds) - contentPoint.y) * scale)];
}

- (BOOL) writeWindowScreenshotToPath: (NSString *)path
{
  NSView *contentView = [_window contentView];
  NSRect bounds = [contentView bounds];
  NSBitmapImageRep *bitmap = nil;
  NSData *pngData = nil;
  NSString *directory = [path stringByDeletingLastPathComponent];

  [_window displayIfNeeded];
  [contentView displayIfNeeded];

  bitmap = [contentView bitmapImageRepForCachingDisplayInRect: bounds];
  if (bitmap == nil)
    {
      GSDisplayServer *server = GSCurrentServer ();
      NSImage *image = nil;

      if (server != nil)
        {
          image = [server contentsOfScreen: 0 inRect: [_window frame]];
        }

      return (image != nil) ? [self writeImage: image toPNGPath: path] : NO;
    }

  [contentView cacheDisplayInRect: bounds toBitmapImageRep: bitmap];
  pngData = [bitmap representationUsingType: NSPNGFileType
                                 properties: [NSDictionary dictionary]];
  if ([pngData length] == 0)
    {
      return NO;
    }

  if ([directory length] > 0)
    {
      [[NSFileManager defaultManager] createDirectoryAtPath: directory
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: NULL];
    }

  return [pngData writeToFile: path atomically: YES];
}

- (BOOL) writeScreenScreenshotToPath: (NSString *)path
{
  if ([self writeInternalScreenScreenshotToPath: path])
    {
      return YES;
    }

  return [self runScreenshotToolAtPath: @"/usr/bin/gnome-screenshot" toPath: path];
}

- (BOOL) writeInternalScreenScreenshotToPath: (NSString *)path
{
  GSDisplayServer *server = GSCurrentServer ();
  NSRect screenRect = [[NSScreen mainScreen] frame];
  NSImage *image = nil;

  if (server == nil)
    {
      return NO;
    }

  image = [server contentsOfScreen: 0 inRect: screenRect];
  if ([self imageAppearsBlank: image])
    {
      return NO;
    }

  return (image != nil) ? [self writeImage: image toPNGPath: path] : NO;
}

- (BOOL) imageAppearsBlank: (NSImage *)image
{
  NSData *tiffData = [image TIFFRepresentation];
  NSBitmapImageRep *bitmap = nil;
  NSInteger width = 0;
  NSInteger height = 0;
  NSInteger samples = 0;
  NSInteger x = 0;
  NSInteger y = 0;
  NSColor *firstColor = nil;

  if ([tiffData length] == 0)
    {
      return YES;
    }

  bitmap = AUTORELEASE ([[NSBitmapImageRep alloc] initWithData: tiffData]);
  if (bitmap == nil)
    {
      return YES;
    }

  width = [bitmap pixelsWide];
  height = [bitmap pixelsHigh];
  if (width <= 0 || height <= 0)
    {
      return YES;
    }

  firstColor = [bitmap colorAtX: 0 y: 0];
  if (firstColor == nil)
    {
      return YES;
    }

  for (y = 0; y < height; y += MAX (1, height / 24))
    {
      for (x = 0; x < width; x += MAX (1, width / 24))
        {
          NSColor *color = [bitmap colorAtX: x y: y];

          samples++;
          if (color == nil || [color isEqual: firstColor] == NO)
            {
              return NO;
            }
        }
    }

  return (samples > 0);
}

- (BOOL) runScreenshotToolAtPath: (NSString *)toolPath
                         toPath: (NSString *)path
{
  NSTask *task = nil;
  NSString *directory = [path stringByDeletingLastPathComponent];

  if ([[NSFileManager defaultManager] isExecutableFileAtPath: toolPath] == NO)
    {
      return NO;
    }

  if ([directory length] > 0)
    {
      [[NSFileManager defaultManager] createDirectoryAtPath: directory
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: NULL];
    }

  task = AUTORELEASE ([[NSTask alloc] init]);
  [task setLaunchPath: toolPath];
  [task setArguments: [NSArray arrayWithObjects: @"-f", path, nil]];

  NS_DURING
    {
      [task launch];
      [task waitUntilExit];
    }
  NS_HANDLER
    {
      return NO;
    }
  NS_ENDHANDLER

  return ([task terminationStatus] == 0
    && [[NSFileManager defaultManager] fileExistsAtPath: path]);
}

- (BOOL) writeImage: (NSImage *)image toPNGPath: (NSString *)path
{
  NSData *tiffData = [image TIFFRepresentation];
  NSBitmapImageRep *bitmap = nil;
  NSData *pngData = nil;
  NSString *directory = [path stringByDeletingLastPathComponent];

  if ([tiffData length] == 0)
    {
      return NO;
    }

  bitmap = AUTORELEASE ([[NSBitmapImageRep alloc] initWithData: tiffData]);
  if (bitmap == nil)
    {
      return NO;
    }

  pngData = [bitmap representationUsingType: NSPNGFileType
                                 properties: [NSDictionary dictionary]];
  if ([pngData length] == 0)
    {
      return NO;
    }

  if ([directory length] > 0)
    {
      [[NSFileManager defaultManager] createDirectoryAtPath: directory
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: NULL];
    }

  return [pngData writeToFile: path atomically: YES];
}

- (void) sendMouseEventOfType: (NSEventType)type
              atWindowTopLeft: (NSPoint)point
                   clickCount: (NSInteger)clickCount
{
  NSView *contentView = [_window contentView];
  NSRect bounds = [contentView bounds];
  CGFloat scale = [_window userSpaceScaleFactor];
  NSPoint userPoint = point;
  NSPoint contentPoint = NSZeroPoint;
  NSPoint windowPoint = NSZeroPoint;
  NSView *targetView = nil;
  if (scale <= 0.0)
    {
      scale = 1.0;
    }

  userPoint.x = point.x / scale;
  userPoint.y = point.y / scale;
  contentPoint = NSMakePoint (userPoint.x, NSHeight (bounds) - userPoint.y);
  windowPoint = [contentView convertPoint: contentPoint toView: nil];
  targetView = [contentView hitTest: contentPoint];

  NSEvent *event = [NSEvent mouseEventWithType: type
                                      location: windowPoint
                                 modifierFlags: 0
                                     timestamp: [NSDate timeIntervalSinceReferenceDate]
                                  windowNumber: [_window windowNumber]
                                       context: nil
                                   eventNumber: 0
                                   clickCount: clickCount
                                     pressure: (type == NSLeftMouseDown) ? 1.0 : 0.0];

  [NSApp activateIgnoringOtherApps: YES];
  [_window makeKeyAndOrderFront: self];
  if (targetView != nil)
    {
      if (type == NSLeftMouseDown)
        {
          if ([targetView acceptsFirstResponder])
            {
              [_window makeFirstResponder: targetView];
            }
          if ([targetView isKindOfClass: [NSControl class]])
            {
              [_window makeFirstResponder: targetView];
            }
          if ([targetView isKindOfClass: [NSTextField class]]
            && [(NSTextField *)targetView isEditable])
            {
              [(NSTextField *)targetView selectText: self];
              _commandFocusedTextControl = targetView;
            }
        }
      else if (type == NSLeftMouseUp)
        {
          if ([targetView isKindOfClass: [NSButton class]])
            {
              [(NSButton *)targetView performClick: self];
            }
        }
    }
  else
    {
      [_window sendEvent: event];
    }
}

- (void) clickWindowTopLeftPoint: (NSPoint)point
{
  [self sendMouseEventOfType: NSLeftMouseDown
             atWindowTopLeft: point
                  clickCount: 1];
  [self sendMouseEventOfType: NSLeftMouseUp
             atWindowTopLeft: point
                  clickCount: 1];
  [_window displayIfNeeded];
}

- (void) sendKeyString: (NSString *)string
{
  NSUInteger index = 0;

  for (index = 0; index < [string length]; index++)
    {
      NSString *character = [string substringWithRange: NSMakeRange (index, 1)];
      NSEvent *down = [NSEvent keyEventWithType: NSKeyDown
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                      timestamp: [NSDate timeIntervalSinceReferenceDate]
                                   windowNumber: [_window windowNumber]
                                        context: nil
                                     characters: character
                    charactersIgnoringModifiers: character
                                      isARepeat: NO
                                        keyCode: 0];
      NSEvent *up = [NSEvent keyEventWithType: NSKeyUp
                                     location: NSZeroPoint
                                modifierFlags: 0
                                    timestamp: [NSDate timeIntervalSinceReferenceDate]
                                 windowNumber: [_window windowNumber]
                                      context: nil
                                   characters: character
                  charactersIgnoringModifiers: character
                                    isARepeat: NO
                                      keyCode: 0];

      [_window sendEvent: down];
      [_window sendEvent: up];
    }

  [_window displayIfNeeded];
}

- (BOOL) performRequestedCaptureIfNeeded
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *menuName = [defaults stringForKey: ThemeDemoCaptureMenuKey];
  NSString *outputPath = [defaults stringForKey: ThemeDemoCaptureMenuOutputKey];
  NSInteger highlightIndex = [defaults integerForKey: ThemeDemoCaptureMenuHighlightKey];
  NSMenu *menu = nil;
  BOOL success = NO;

  if ([menuName length] == 0 || [outputPath length] == 0)
    {
      return NO;
    }

  menu = [self menuNamed: menuName];
  if (menu == nil)
    {
      NSLog (@"Unknown menu '%@' requested for capture", menuName);
      [NSApp terminate: self];
      return YES;
    }

  success = [self writePNGForMenu: menu
                    highlightItem: highlightIndex
                           toPath: outputPath];
  if (success == NO)
    {
      NSLog (@"Failed to capture menu '%@' to %@", menuName, outputPath);
    }

  [NSApp terminate: self];
  return YES;
}

- (BOOL) performRequestedGeometryDumpIfNeeded
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *menuName = [defaults stringForKey: ThemeDemoDumpMenuGeometryKey];
  NSMenu *menu = nil;

  if ([menuName length] == 0)
    {
      return NO;
    }

  menu = [self menuNamed: menuName];
  if (menu == nil)
    {
      NSLog (@"Unknown menu '%@' requested for geometry dump", menuName);
      [NSApp terminate: self];
      return YES;
    }

  [self dumpGeometryForMenu: menu named: menuName];
  [NSApp terminate: self];
  return YES;
}

- (BOOL) performRequestedTabDumpIfNeeded
{
  if ([[NSUserDefaults standardUserDefaults] stringForKey: ThemeDemoDumpTabGeometryKey] == nil)
    {
      return NO;
    }

  [_window makeKeyAndOrderFront: self];
  [_window displayIfNeeded];
  [_tabView displayIfNeeded];
  [self performSelector: @selector(dumpTabGeometryAndTerminate)
             withObject: nil
             afterDelay: 0.2];
  return YES;
}

- (BOOL) performRequestedTypographyDumpIfNeeded
{
  if ([[NSUserDefaults standardUserDefaults] stringForKey: ThemeDemoDumpTypographyKey] == nil)
    {
      return NO;
    }

  [_window makeKeyAndOrderFront: self];
  [_window displayIfNeeded];
  [_tabView displayIfNeeded];
  [self dumpTypographyMetrics];
  [NSApp terminate: self];
  return YES;
}

- (void) openRequestedMenu
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *openMenu = [defaults stringForKey: ThemeDemoOpenMenuKey];

  if ([openMenu isEqualToString: @"stress"] && _stressMenuButton != nil)
    {
      [self showDemoMenu: _stressMenuButton];
    }
  else if ([openMenu isEqualToString: @"demo"] && _demoMenuButton != nil)
    {
      [self showDemoMenu: _demoMenuButton];
    }
}

- (IBAction) showControlsPage: (id)sender
{
  (void)sender;
  [self selectPageNamed: @"controls"];
}

- (IBAction) showTextPage: (id)sender
{
  (void)sender;
  [self selectPageNamed: @"text"];
}

- (IBAction) showDataPage: (id)sender
{
  (void)sender;
  [self selectPageNamed: @"data"];
}

- (IBAction) showMenusPage: (id)sender
{
  (void)sender;
  [self selectPageNamed: @"menus"];
}

- (IBAction) showStressPage: (id)sender
{
  (void)sender;
  [self selectPageNamed: @"stress"];
}

#pragma mark - Tab Construction

- (NSView *) tabRootView
{
  NSRect frame = [_tabView contentRect];
  NSView *root = AUTORELEASE ([[NSView alloc] initWithFrame: frame]);

  [root setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  return root;
}

- (NSMenu *) menuNamed: (NSString *)name
{
  if ([name isEqualToString: @"demo"])
    {
      return _demoMenu;
    }
  if ([name isEqualToString: @"stress"])
    {
      return _stressMenu;
    }

  return nil;
}

- (BOOL) writePNGForMenu: (NSMenu *)menu
           highlightItem: (NSInteger)highlightIndex
                  toPath: (NSString *)path
{
  id representation = nil;
  NSView *menuView = nil;
  NSWindow *captureWindow = nil;
  NSBitmapImageRep *bitmap = nil;
  NSImage *image = nil;
  NSData *pngData = nil;
  NSRect bounds;
  NSString *directory = [path stringByDeletingLastPathComponent];

  [menu update];
  [menu sizeToFit];

  representation = [menu menuRepresentation];
  if ([representation isKindOfClass: [NSView class]] == NO)
    {
      return NO;
    }

  menuView = (NSView *)representation;

  if ([representation respondsToSelector: @selector(setHighlightedItemIndex:)])
    {
      [(id)representation setHighlightedItemIndex: highlightIndex];
    }
  if ([representation respondsToSelector: @selector(update)])
    {
      [(id)representation update];
    }
  if ([representation respondsToSelector: @selector(sizeToFit)])
    {
      [(id)representation sizeToFit];
    }

  bounds = [menuView bounds];
  if (NSIsEmptyRect (bounds))
    {
      bounds = [menuView frame];
    }
  if (NSIsEmptyRect (bounds))
    {
      return NO;
    }

  captureWindow = AUTORELEASE ([[NSWindow alloc] initWithContentRect: bounds
                                                           styleMask: NSWindowStyleMaskBorderless
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO]);
  [captureWindow setReleasedWhenClosed: NO];
  [captureWindow setFrameOrigin: NSMakePoint (-4000.0, -4000.0)];
  [captureWindow setContentView: menuView];
  [captureWindow display];
  [menuView display];

  bitmap = [menuView bitmapImageRepForCachingDisplayInRect: bounds];
  if (bitmap == nil)
    {
      image = AUTORELEASE ([[NSImage alloc] initWithSize: bounds.size]);
      [image lockFocus];
      [menuView drawRect: NSMakeRect (0.0, 0.0, bounds.size.width, bounds.size.height)];
      [image unlockFocus];
      bitmap = AUTORELEASE ([[NSBitmapImageRep alloc] initWithData: [image TIFFRepresentation]]);
      if (bitmap == nil)
        {
          [captureWindow orderOut: nil];
          return NO;
        }
    }
  else
    {
      [menuView cacheDisplayInRect: bounds toBitmapImageRep: bitmap];
    }
  pngData = [bitmap representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]];
  if ([pngData length] == 0)
    {
      [captureWindow orderOut: nil];
      return NO;
    }

  if ([directory length] > 0)
    {
      [[NSFileManager defaultManager] createDirectoryAtPath: directory
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: NULL];
    }

  [captureWindow orderOut: nil];
  return [pngData writeToFile: path atomically: YES];
}

- (void) dumpGeometryForMenu: (NSMenu *)menu named: (NSString *)name
{
  NSMenuView *representation = (NSMenuView *)[menu menuRepresentation];
  NSInteger index = 0;
  NSInteger count = [menu numberOfItems];

  [menu update];
  [menu sizeToFit];

  if ([representation respondsToSelector: @selector(update)])
    {
      [(id)representation update];
    }
  if ([representation respondsToSelector: @selector(sizeToFit)])
    {
      [(id)representation sizeToFit];
    }

  NSLog (@"MENU %@ inner=%@ stateOffset=%.1f stateWidth=%.1f titleOffset=%.1f titleWidth=%.1f keyOffset=%.1f keyWidth=%.1f",
         name,
         NSStringFromRect ([representation innerRect]),
         [representation stateImageOffset],
         [representation stateImageWidth],
         [representation imageAndTitleOffset],
         [representation imageAndTitleWidth],
         [representation keyEquivalentOffset],
         [representation keyEquivalentWidth]);

  for (index = 0; index < count; index++)
    {
      NSMenuItem *item = [menu itemAtIndex: index];
      NSMenuItemCell *cell = [representation menuItemCellForItemAtIndex: index];
      NSRect itemRect = [representation rectOfItemAtIndex: index];

      NSLog (@"ITEM %ld title='%@' submenu=%@ state=%ld enabled=%@ frame=%@ titleRect=%@ stateRect=%@ keyRect=%@",
             (long)index,
             [item title],
             [item hasSubmenu] ? @"YES" : @"NO",
             (long)[item state],
             [item isEnabled] ? @"YES" : @"NO",
             NSStringFromRect (itemRect),
             NSStringFromRect ([cell titleRectForBounds: itemRect]),
             NSStringFromRect ([cell stateImageRectForBounds: itemRect]),
             NSStringFromRect ([cell keyEquivalentRectForBounds: itemRect]));
    }
}

- (void) dumpTabGeometry
{
  NSRect bounds = [_tabView bounds];
  NSRect contentRect = [_tabView contentRect];
  NSTabViewItem *selected = [_tabView selectedTabViewItem];
  NSArray *items = [_tabView tabViewItems];
  NSArray *probeHeights = [NSArray arrayWithObjects:
                             [NSNumber numberWithDouble: 8.0],
                             [NSNumber numberWithDouble: 28.0],
                             [NSNumber numberWithDouble: NSMaxY (bounds) - 28.0],
                             [NSNumber numberWithDouble: NSMaxY (bounds) - 8.0],
                             nil];
  NSUInteger probeIndex = 0;

  NSLog (@"TAB bounds=%@ contentRect=%@ flipped=%@ selected='%@' selectedViewFrame=%@",
         NSStringFromRect (bounds),
         NSStringFromRect (contentRect),
         [_tabView isFlipped] ? @"YES" : @"NO",
         [selected label],
         NSStringFromRect ([[selected view] frame]));

  for (probeIndex = 0; probeIndex < [probeHeights count]; probeIndex++)
    {
      CGFloat y = [[probeHeights objectAtIndex: probeIndex] doubleValue];
      NSMutableString *line = [NSMutableString stringWithFormat: @"TABPROBE y=%.1f", y];
      CGFloat x = 20.0;

      while (x < NSWidth (bounds))
        {
          NSTabViewItem *item = [_tabView tabViewItemAtPoint: NSMakePoint (x, y)];
          NSString *label = (item != nil) ? [item label] : @"-";

          [line appendFormat: @"  %.0f:%@", x, label];
          x += 110.0;
        }

      NSLog (@"%@", line);
    }

  {
    NSUInteger index = 0;

    for (index = 0; index < [items count]; index++)
      {
        NSTabViewItem *item = [items objectAtIndex: index];
        NSRect tabRect = [item _tabRect];
        NSPoint clickPoint = NSMakePoint (NSMidX (tabRect), NSMidY (tabRect));
        NSPoint windowPoint = [_tabView convertPoint: clickPoint toView: nil];
        NSEvent *event = nil;

        event = [NSEvent mouseEventWithType: NSLeftMouseDown
                                   location: windowPoint
                              modifierFlags: 0
                                  timestamp: 0.0
                               windowNumber: [_window windowNumber]
                                    context: nil
                                eventNumber: (NSInteger)index
                                 clickCount: 1
                                   pressure: 1.0];

        NSLog (@"TABITEM %lu '%@' rect=%@ hit='%@'",
               (unsigned long)index,
               [item label],
               NSStringFromRect (tabRect),
               [[_tabView tabViewItemAtPoint: clickPoint] label]);

        [_tabView mouseDown: event];
        NSLog (@"TABSELECT %lu '%@' selectedAfterClick='%@' viewFrame=%@",
               (unsigned long)index,
               [item label],
               [[_tabView selectedTabViewItem] label],
               NSStringFromRect ([[[ _tabView selectedTabViewItem] view] frame]));
      }

    if (selected != nil)
      {
        [_tabView selectTabViewItem: selected];
      }
  }
}

- (void) dumpTypographyMetrics
{
  NSTabViewItem *controlsItem = [self tabItemNamed: @"controls"];
  NSView *controlsRoot = [controlsItem view];
  NSMutableArray *matchingFontNames = [NSMutableArray array];
  NSArray *buttons = nil;
  NSArray *textFields = nil;
  NSArray *popups = nil;
  NSArray *segmentedControls = nil;
  NSArray *availableFonts = [[NSFontManager sharedFontManager] availableFonts];
  NSEnumerator *enumerator = nil;
  NSButton *defaultButton = nil;
  NSButton *checkbox = nil;
  NSButton *radioButton = nil;
  NSTextField *sectionLabel = nil;
  NSTextField *editableTextField = nil;
  NSTextField *readonlyTextField = nil;
  NSPopUpButton *popup = nil;
  NSSegmentedControl *segmented = nil;

  if (controlsRoot == nil)
    {
      ThemeDemoPrintLine (@"TYPOGRAPHY no controls tab view available");
      return;
    }

  enumerator = [availableFonts objectEnumerator];
  while ((controlsRoot != nil) && YES)
    {
      NSString *fontName = [enumerator nextObject];

      if (fontName == nil)
        {
          break;
        }

      if ([fontName rangeOfString: @"Cantarell" options: NSCaseInsensitiveSearch].location != NSNotFound
        || [fontName rangeOfString: @"DejaVu" options: NSCaseInsensitiveSearch].location != NSNotFound)
        {
          [matchingFontNames addObject: fontName];
        }
    }

  buttons = [self descendantViewsOfClass: [NSButton class] inView: controlsRoot];
  textFields = [self descendantViewsOfClass: [NSTextField class] inView: controlsRoot];
  popups = [self descendantViewsOfClass: [NSPopUpButton class] inView: controlsRoot];
  segmentedControls = [self descendantViewsOfClass: [NSSegmentedControl class] inView: controlsRoot];

  enumerator = [buttons objectEnumerator];
  while (defaultButton == nil || checkbox == nil || radioButton == nil)
    {
      NSButton *button = [enumerator nextObject];
      if (button == nil)
        {
          break;
        }

      if ([[button title] isEqualToString: @"Default"])
        {
          defaultButton = button;
        }
      else if (checkbox == nil
        && [[button title] isEqualToString: @"Enable advanced options"])
        {
          checkbox = button;
        }
      else if (radioButton == nil
        && [[button title] isEqualToString: @"Radio Option A"])
        {
          radioButton = button;
        }
    }

  enumerator = [textFields objectEnumerator];
  while (sectionLabel == nil || editableTextField == nil || readonlyTextField == nil)
    {
      NSTextField *field = [enumerator nextObject];

      if (field == nil)
        {
          break;
        }

      if ([field isEditable] == NO
        && [field isSelectable] == NO
        && [field isBezeled] == NO
        && [field drawsBackground] == NO)
        {
          if ([[field stringValue] isEqualToString: @"Buttons"])
            {
              sectionLabel = field;
            }
        }
      else if (readonlyTextField == nil
        && [field isEditable] == NO
        && [field isSelectable] == NO)
        {
          readonlyTextField = field;
        }
      else if (editableTextField == nil
        && [field isEditable])
        {
          editableTextField = field;
        }
    }

  popup = ([popups count] > 0) ? [popups objectAtIndex: 0] : nil;
  segmented = ([segmentedControls count] > 0) ? [segmentedControls objectAtIndex: 0] : nil;

  if (_window != nil)
    {
      NSScreen *screen = [_window screen];
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY scale windowUser=%.2f windowBacking=%.2f screenUser=%.2f screenBacking=%.2f",
                                      [_window userSpaceScaleFactor],
                                      [_window backingScaleFactor],
                                      [screen userSpaceScaleFactor],
                                      [screen backingScaleFactor]]);
    }

  ThemeDemoPrintLine ([NSString stringWithFormat:
                                  @"TYPOGRAPHY defaults user=%@ control=%@ label=%@ system=%@",
                                  ThemeDemoFontDescription ([NSFont userFontOfSize: 0.0]),
                                  ThemeDemoFontDescription ([NSFont controlContentFontOfSize: 0.0]),
                                  ThemeDemoFontDescription ([NSFont labelFontOfSize: 0.0]),
                                  ThemeDemoFontDescription ([NSFont systemFontOfSize: [NSFont systemFontSize]])]);
  ThemeDemoPrintLine ([NSString stringWithFormat:
                                  @"TYPOGRAPHY demoMetrics controlFont=%@ labelFont=%@ controlHeight=%.1f rowSpacing=%.1f wideControlWidth=%.1f",
                                  ThemeDemoFontDescription ([self controlFont]),
                                  ThemeDemoFontDescription ([self labelFont]),
                                  kDemoControlHeight,
                                  kDemoRowSpacing,
                                  kDemoWideControlWidth]);
  ThemeDemoPrintLine ([NSString stringWithFormat:
                                  @"TYPOGRAPHY availableFonts matching=%@",
                                  [matchingFontNames componentsJoinedByString: @", "]]);

  if (defaultButton != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=button title='%@' font=%@ cellFont=%@ frame=%@ cellSize=%@",
                                      [defaultButton title],
                                      ThemeDemoFontDescription ([defaultButton font]),
                                      ThemeDemoFontDescription ([(NSButtonCell *)[defaultButton cell] font]),
                                      NSStringFromRect ([defaultButton frame]),
                                      NSStringFromSize ([(NSButtonCell *)[defaultButton cell] cellSize])]);
    }
  if (checkbox != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=checkbox title='%@' font=%@ cellFont=%@ frame=%@",
                                      [checkbox title],
                                      ThemeDemoFontDescription ([checkbox font]),
                                      ThemeDemoFontDescription ([(NSButtonCell *)[checkbox cell] font]),
                                      NSStringFromRect ([checkbox frame])]);
    }
  if (radioButton != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=radio title='%@' font=%@ cellFont=%@ frame=%@",
                                      [radioButton title],
                                      ThemeDemoFontDescription ([radioButton font]),
                                      ThemeDemoFontDescription ([(NSButtonCell *)[radioButton cell] font]),
                                      NSStringFromRect ([radioButton frame])]);
    }
  if (sectionLabel != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=label title='%@' font=%@ frame=%@",
                                      [sectionLabel stringValue],
                                      ThemeDemoFontDescription ([sectionLabel font]),
                                      NSStringFromRect ([sectionLabel frame])]);
    }
  if (editableTextField != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=textfield value='%@' font=%@ cellFont=%@ frame=%@",
                                      [editableTextField stringValue],
                                      ThemeDemoFontDescription ([editableTextField font]),
                                      ThemeDemoFontDescription ([(NSTextFieldCell *)[editableTextField cell] font]),
                                      NSStringFromRect ([editableTextField frame])]);
    }
  if (readonlyTextField != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=readonly-textfield value='%@' font=%@ cellFont=%@ frame=%@",
                                      [readonlyTextField stringValue],
                                      ThemeDemoFontDescription ([readonlyTextField font]),
                                      ThemeDemoFontDescription ([(NSTextFieldCell *)[readonlyTextField cell] font]),
                                      NSStringFromRect ([readonlyTextField frame])]);
    }
  if (segmented != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=segmented font=%@ cellFont=%@ frame=%@ selectedSegment=%ld",
                                      ThemeDemoFontDescription ([segmented font]),
                                      ThemeDemoFontDescription ([(NSSegmentedCell *)[segmented cell] font]),
                                      NSStringFromRect ([segmented frame]),
                                      (long)[segmented selectedSegment]]);
    }
  if (popup != nil)
    {
      ThemeDemoPrintLine ([NSString stringWithFormat:
                                      @"TYPOGRAPHY widget=popup title='%@' font=%@ cellFont=%@ frame=%@",
                                      [popup titleOfSelectedItem],
                                      ThemeDemoFontDescription ([popup font]),
                                      ThemeDemoFontDescription ([(NSPopUpButtonCell *)[popup cell] font]),
                                      NSStringFromRect ([popup frame])]);
    }
}


- (void) dumpTabGeometryAndTerminate
{
  [_window displayIfNeeded];
  [_tabView displayIfNeeded];
  [self dumpTabGeometry];
  [NSApp terminate: self];
}

- (void) dumpTypographyMetricsAndTerminate
{
  [_window displayIfNeeded];
  [_tabView displayIfNeeded];
  [self dumpTypographyMetrics];
  [NSApp terminate: self];
}

- (NSTabViewItem *) controlsTabItem
{
  NSView *root = [self tabRootView];
  [self populateControlsCanvas: [self makeCanvasForRoot: root]];

  NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"controls"]);
  [item setLabel: @"Controls"];
  [item setView: root];
  return item;
}

- (NSTabViewItem *) textTabItem
{
  NSView *root = [self tabRootView];
  [self populateTextCanvas: [self makeCanvasForRoot: root]];

  NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"text"]);
  [item setLabel: @"Text & Inputs"];
  [item setView: root];
  return item;
}

- (NSTabViewItem *) dataTabItem
{
  NSView *root = [self tabRootView];
  [self populateDataCanvas: [self makeCanvasForRoot: root]];

  NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"data"]);
  [item setLabel: @"Data Views"];
  [item setView: root];
  return item;
}

- (NSTabViewItem *) menuTabItem
{
  NSView *root = [self tabRootView];
  [self populateMenuCanvas: [self makeCanvasForRoot: root]];

  NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"menus"]);
  [item setLabel: @"Menus"];
  [item setView: root];
  return item;
}

- (NSTabViewItem *) stressTabItem
{
  NSView *root = [self tabRootView];
  [self populateStressCanvas: [self makeCanvasForRoot: root]];

  NSTabViewItem *item = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"stress"]);
  [item setLabel: @"Stress"];
  [item setView: root];
  return item;
}

- (NSView *) makeCanvasForRoot: (NSView *)root
{
  NSRect bounds = [root bounds];
  NSRect inset = NSInsetRect (bounds, kDemoPadding, kDemoPadding);
  NSView *canvas = AUTORELEASE ([[NSView alloc] initWithFrame: inset]);
  [canvas setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  [root addSubview: canvas];
  return canvas;
}

- (void) refreshDemoLayoutMetrics
{
  CGFloat baseFontSize = [[self controlFont] pointSize];

  if (baseFontSize <= 0.0)
    {
      baseFontSize = [NSFont systemFontSize];
    }

  kDemoControlHeight = ceil (MAX (34.0, baseFontSize + 20.0));
  kDemoRowSpacing = ceil (MAX (12.0, floor (baseFontSize * 1.25)));
  kDemoWideControlWidth = 360.0;
}

- (void) collectDescendantViewsOfClass: (Class)viewClass
                                inView: (NSView *)view
                              intoArray: (NSMutableArray *)results
{
  NSArray *subviews = nil;
  NSEnumerator *enumerator = nil;
  NSView *subview = nil;

  if (view == nil || viewClass == Nil || results == nil)
    {
      return;
    }

  if ([view isKindOfClass: viewClass])
    {
      [results addObject: view];
    }

  subviews = [view subviews];
  enumerator = [subviews objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      [self collectDescendantViewsOfClass: viewClass inView: subview intoArray: results];
    }
}

- (NSArray *) descendantViewsOfClass: (Class)viewClass
                              inView: (NSView *)view
{
  NSMutableArray *results = [NSMutableArray array];

  [self collectDescendantViewsOfClass: viewClass inView: view intoArray: results];
  return results;
}

- (NSFont *) controlFont
{
  NSFont *font = [NSFont userFontOfSize: 0.0];

  if (font == nil)
    {
      font = [NSFont controlContentFontOfSize: 0.0];
    }

  if (font == nil)
    {
      font = [NSFont systemFontOfSize: [NSFont systemFontSize]];
    }

  return font;
}

- (NSFont *) labelFont
{
  NSFont *font = [NSFont labelFontOfSize: 0.0];

  if (font == nil)
    {
      font = [self controlFont];
    }

  return font;
}

- (NSFont *) sectionTitleFont
{
  NSFont *font = [self labelFont];
  NSFontManager *fontManager = [NSFontManager sharedFontManager];

  if (fontManager != nil && font != nil)
    {
      NSFont *boldFont = [fontManager convertFont: font toHaveTrait: NSBoldFontMask];
      CGFloat titleSize = MAX ([font pointSize] + 2.0,
                               round ([font pointSize] * 1.18));

      if (boldFont != nil)
        {
          font = boldFont;
        }
      font = [fontManager convertFont: font toSize: titleSize];
    }

  return font;
}

- (NSSize) defaultWindowContentSize
{
  CGFloat width = ceil (MAX (760.0, kDemoWideControlWidth + 190.0));
  CGFloat height = ceil (MAX (620.0,
                              (kDemoControlHeight * 10.5)
                              + (kDemoRowSpacing * 8.0)
                              + 110.0));

  return NSMakeSize (width, height);
}

- (NSTextField *) labelWithString: (NSString *)string frame: (NSRect)frame
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame: frame]);
  [label setStringValue: string];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];
  [label setEditable: NO];
  [label setSelectable: NO];
  [label setFont: [self labelFont]];
  return label;
}

- (NSTextField *) sectionTitleLabelWithString: (NSString *)string frame: (NSRect)frame
{
  NSTextField *label = [self labelWithString: string frame: frame];
  [label setFont: [self sectionTitleFont]];
  return label;
}

- (NSTextField *) fieldWithValue: (NSString *)value frame: (NSRect)frame
{
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame: frame]);
  [field setStringValue: value];
  [field setFont: [self controlFont]];
  return field;
}

#pragma mark - Canvas Population

- (void) populateControlsCanvas: (NSView *)canvas
{
  NSRect bounds = [canvas bounds];
  CGFloat y = NSMaxY (bounds) - kDemoPadding;
  CGFloat stepperWidth = ceil (MAX (84.0, kDemoControlHeight * 2.35));
  CGFloat stepperOverlap = 10.0;
  CGFloat stepperFieldWidth = ceil (MAX (140.0, kDemoWideControlWidth - stepperWidth + stepperOverlap));
  CGFloat stepperX = kDemoPadding + 90;

  [canvas addSubview: [self sectionTitleLabelWithString: @"Buttons" frame: NSMakeRect (kDemoPadding, y - kDemoControlHeight, 180, kDemoControlHeight)]];
  y -= ((kDemoControlHeight * 2.0) + kDemoRowSpacing);

  NSButton *defaultButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 160, kDemoControlHeight)]);
  [defaultButton setTitle: @"Default"];
  [defaultButton setBezelStyle: NSRoundedBezelStyle];
  [defaultButton setFont: [self controlFont]];
  if (_window != nil)
    {
      [_window setDefaultButtonCell: [defaultButton cell]];
    }
  [canvas addSubview: defaultButton];

  NSButton *secondaryButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding + 180, y, 160, kDemoControlHeight)]);
  [secondaryButton setTitle: @"Secondary"];
  [secondaryButton setBezelStyle: NSRoundedBezelStyle];
  [secondaryButton setFont: [self controlFont]];
  [canvas addSubview: secondaryButton];

  NSButton *disabledButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding + 360, y, 160, kDemoControlHeight)]);
  [disabledButton setTitle: @"Disabled"];
  [disabledButton setEnabled: NO];
  [disabledButton setBezelStyle: NSRoundedBezelStyle];
  [disabledButton setFont: [self controlFont]];
  [canvas addSubview: disabledButton];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSButton *checkbox = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 220, kDemoControlHeight)]);
  [checkbox setButtonType: NSSwitchButton];
  [checkbox setTitle: @"Enable advanced options"];
  [checkbox setState: NSOnState];
  [checkbox setFont: [self controlFont]];
  [canvas addSubview: checkbox];

  NSButton *mixedCheckbox = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding + 240, y, 220, kDemoControlHeight)]);
  [mixedCheckbox setButtonType: NSSwitchButton];
  [mixedCheckbox setTitle: @"Mixed state"];
  [mixedCheckbox setAllowsMixedState: YES];
  [mixedCheckbox setState: NSMixedState];
  [mixedCheckbox setFont: [self controlFont]];
  [canvas addSubview: mixedCheckbox];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSButton *radioA = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 180, kDemoControlHeight)]);
  [radioA setButtonType: NSRadioButton];
  [radioA setTitle: @"Radio Option A"];
  [radioA setState: NSOnState];
  [radioA setFont: [self controlFont]];
  [radioA setTarget: self];
  [radioA setAction: @selector(radioSelectionChanged:)];
  [canvas addSubview: radioA];

  NSButton *radioB = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding + 200, y, 180, kDemoControlHeight)]);
  [radioB setButtonType: NSRadioButton];
  [radioB setTitle: @"Radio Option B"];
  [radioB setState: NSOffState];
  [radioB setFont: [self controlFont]];
  [radioB setTarget: self];
  [radioB setAction: @selector(radioSelectionChanged:)];
  [canvas addSubview: radioB];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  [canvas addSubview: [self labelWithString: @"Segmented" frame: NSMakeRect (kDemoPadding, y, 100, kDemoControlHeight)]];

  NSSegmentedControl *segmented = AUTORELEASE ([[NSSegmentedControl alloc] initWithFrame: NSMakeRect (kDemoPadding + 110, y, 260, kDemoControlHeight)]);
  [segmented setSegmentCount: 3];
  [segmented setLabel: @"One" forSegment: 0];
  [segmented setLabel: @"Two" forSegment: 1];
  [segmented setLabel: @"Three" forSegment: 2];
  [segmented setSegmentStyle: NSSegmentStyleRounded];
  [(NSSegmentedCell *)[segmented cell] setFont: [self controlFont]];
  [(NSSegmentedCell *)[segmented cell] setTrackingMode: NSSegmentSwitchTrackingSelectOne];
  [segmented setSelectedSegment: 0];
  [segmented setTarget: self];
  [segmented setAction: @selector(segmentedChanged:)];
  RETAIN (segmented);
  _segmentedControl = segmented;
  [canvas addSubview: segmented];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  [canvas addSubview: [self labelWithString: @"Slider" frame: NSMakeRect (kDemoPadding, y, 80, kDemoControlHeight)]];

  NSSlider *slider = AUTORELEASE ([[NSSlider alloc] initWithFrame: NSMakeRect (kDemoPadding + 90, y, 220, kDemoControlHeight)]);
  [slider setMinValue: 0.0];
  [slider setMaxValue: 100.0];
  [slider setDoubleValue: 45.0];
  [slider setTarget: self];
  [slider setAction: @selector(sliderValueChanged:)];
  [canvas addSubview: slider];

  _sliderValueLabel = [self labelWithString: @"45" frame: NSMakeRect (kDemoPadding + 320, y, 40, kDemoControlHeight)];
  RETAIN (_sliderValueLabel);
  [canvas addSubview: _sliderValueLabel];

  y -= (kDemoControlHeight + kDemoRowSpacing * 2.0);

  [canvas addSubview: [self labelWithString: @"Progress" frame: NSMakeRect (kDemoPadding, y, 80, kDemoControlHeight)]];

  NSProgressIndicator *progress = AUTORELEASE ([[NSProgressIndicator alloc] initWithFrame: NSMakeRect (kDemoPadding + 90, y, 240, kDemoControlHeight)]);
  [progress setMinValue: 0.0];
  [progress setMaxValue: 100.0];
  [progress setDoubleValue: 60.0];
  [progress setIndeterminate: NO];
  [progress setBezeled: YES];
  RETAIN (progress);
  _progressIndicator = progress;
  [canvas addSubview: progress];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  [canvas addSubview: [self labelWithString: @"Pop-up" frame: NSMakeRect (kDemoPadding, y, 80, kDemoControlHeight)]];

  NSPopUpButton *popup = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (kDemoPadding + 90, y, kDemoWideControlWidth, kDemoControlHeight)
                                                                 pullsDown: NO]);
  [popup addItemWithTitle: @"Adwaita"];
  [popup addItemWithTitle: @"Adwaita-dark"];
  [popup addItemWithTitle: @"High Contrast"];
  [popup setFont: [self controlFont]];
  [canvas addSubview: popup];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  [canvas addSubview: [self labelWithString: @"Stepper" frame: NSMakeRect (kDemoPadding, y, 80, kDemoControlHeight)]];

  _stepperValueField = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (stepperX, y, stepperFieldWidth, kDemoControlHeight)]);
  [_stepperValueField setStringValue: @"3"];
  [_stepperValueField setEditable: NO];
  [_stepperValueField setSelectable: NO];
  [_stepperValueField setDrawsBackground: NO];
  [_stepperValueField setFont: [self controlFont]];
  RETAIN (_stepperValueField);
  [canvas addSubview: _stepperValueField];

  NSStepper *stepper = AUTORELEASE ([[NSStepper alloc] initWithFrame: NSMakeRect (stepperX + stepperFieldWidth - stepperOverlap, y, stepperWidth, kDemoControlHeight)]);
  [stepper setIncrement: 1.0];
  [stepper setMinValue: 0.0];
  [stepper setMaxValue: 10.0];
  [stepper setIntValue: 3];
  [stepper setTarget: self];
  [stepper setAction: @selector(stepperValueChanged:)];
  [canvas addSubview: stepper];
}

- (void) populateTextCanvas: (NSView *)canvas
{
  NSRect bounds = [canvas bounds];
  CGFloat y = NSMaxY (bounds) - kDemoPadding;

  [canvas addSubview: [self sectionTitleLabelWithString: @"Text Inputs" frame: NSMakeRect (kDemoPadding, y - kDemoControlHeight, 180, kDemoControlHeight)]];
  y -= ((kDemoControlHeight * 2.0) + kDemoRowSpacing);

  _primaryTextField = [self fieldWithValue: @"Primary text field"
                                     frame: NSMakeRect (kDemoPadding, y, 300, kDemoControlHeight)];
  RETAIN (_primaryTextField);
  [canvas addSubview: _primaryTextField];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSSecureTextField *secure = AUTORELEASE ([[NSSecureTextField alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 300, kDemoControlHeight)]);
  [secure setStringValue: @"password"];
  [secure setFont: [self controlFont]];
  RETAIN (secure);
  _passwordField = secure;
  [canvas addSubview: secure];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 300, kDemoControlHeight)]);
  [combo addItemWithObjectValue: @"First option"];
  [combo addItemWithObjectValue: @"Second option"];
  [combo addItemWithObjectValue: @"Third option"];
  [combo setEditable: NO];
  [combo selectItemAtIndex: 1];
  if ([combo objectValueOfSelectedItem] != nil)
    {
      [combo setStringValue: [[combo objectValueOfSelectedItem] description]];
    }
  [combo setFont: [self controlFont]];
  RETAIN (combo);
  _textComboBox = combo;
  [canvas addSubview: combo];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSSearchField *search = AUTORELEASE ([[NSSearchField alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 300, kDemoControlHeight)]);
  [search setStringValue: @"Search query"];
  [search setFont: [self controlFont]];
  RETAIN (search);
  _searchField = search;
  [canvas addSubview: search];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSTextField *disabledField = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 300, kDemoControlHeight)]);
  [disabledField setStringValue: @"Disabled input"];
  [disabledField setEnabled: NO];
  [disabledField setFont: [self controlFont]];
  RETAIN (disabledField);
  _disabledTextField = disabledField;
  [canvas addSubview: disabledField];

  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSRect textRect = NSMakeRect (kDemoPadding, y - 220.0, NSWidth (bounds) - (kDemoPadding * 2.0), 220.0);
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: textRect]);
  [scroll setBorderType: NSBezelBorder];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: NO];
  [scroll setAutohidesScrollers: YES];

  NSTextView *textView = AUTORELEASE ([[NSTextView alloc] initWithFrame: [[scroll contentView] bounds]]);
  [textView setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  [textView setFont: [self controlFont]];
  [textView setString: @"NSTextView\n\nUse this page to inspect paragraph spacing, text selection, caret visibility, and how the theme handles dense multiline content.\n\nThe goal in Phases 2 and 3 is not custom widget chrome yet. It is typography, spacing, and visual rhythm."];
  RETAIN (textView);
  _bodyTextView = textView;
  [scroll setDocumentView: textView];
  [scroll reflectScrolledClipView: [scroll contentView]];
  [canvas addSubview: scroll];
}

- (void) populateDataCanvas: (NSView *)canvas
{
  _tableDataSource = [ThemeDemoTableDataSource new];

  NSRect bounds = [canvas bounds];
  CGFloat labelHeight = kDemoControlHeight;
  CGFloat gutter = 20.0;
  CGFloat width = floor ((NSWidth (bounds) - gutter) / 2.0);
  CGFloat contentHeight = NSHeight (bounds) - ((kDemoPadding * 2.0) + labelHeight + kDemoRowSpacing);
  NSRect tableRect = NSMakeRect (0.0,
                                 kDemoPadding,
                                 width,
                                 contentHeight);
  NSRect outlineRect = NSMakeRect (width + gutter,
                                   kDemoPadding,
                                   width,
                                   contentHeight);

  [canvas addSubview: [self sectionTitleLabelWithString: @"Table View"
                                      frame: NSMakeRect (0.0,
                                                         NSMaxY (bounds) - labelHeight,
                                                         width,
                                                         labelHeight)]];
  [canvas addSubview: [self sectionTitleLabelWithString: @"Outline View"
                                      frame: NSMakeRect (NSMinX (outlineRect),
                                                         NSMaxY (bounds) - labelHeight,
                                                         width,
                                                         labelHeight)]];

  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: tableRect]);
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setAutohidesScrollers: YES];
  [scroll setBorderType: NSBezelBorder];
  [scroll setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];

  NSTableView *tableView = AUTORELEASE ([[NSTableView alloc] initWithFrame: [[scroll contentView] bounds]]);
  [tableView setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  [tableView setDataSource: _tableDataSource];
  [tableView setDelegate: _tableDataSource];
  [tableView setUsesAlternatingRowBackgroundColors: YES];

  NSTableColumn *controlColumn = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"control"]);
  [[controlColumn headerCell] setStringValue: @"Control"];
  [[controlColumn dataCell] setFont: [self controlFont]];
  [controlColumn setWidth: 220.0];
  [tableView addTableColumn: controlColumn];

  NSTableColumn *stateColumn = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"state"]);
  [[stateColumn headerCell] setStringValue: @"State"];
  [[stateColumn dataCell] setFont: [self controlFont]];
  [stateColumn setWidth: 260.0];
  [tableView addTableColumn: stateColumn];

  NSTableColumn *notesColumn = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"notes"]);
  [[notesColumn headerCell] setStringValue: @"Notes"];
  [[notesColumn dataCell] setFont: [self controlFont]];
  [notesColumn setWidth: 360.0];
  [tableView addTableColumn: notesColumn];

  [scroll setDocumentView: tableView];
  [scroll reflectScrolledClipView: [scroll contentView]];
  [canvas addSubview: scroll];

  NSScrollView *outlineScroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: outlineRect]);
  [outlineScroll setHasVerticalScroller: YES];
  [outlineScroll setHasHorizontalScroller: NO];
  [outlineScroll setAutohidesScrollers: YES];
  [outlineScroll setBorderType: NSBezelBorder];
  [outlineScroll setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];

  NSOutlineView *outlineView = AUTORELEASE ([[NSOutlineView alloc] initWithFrame: [[outlineScroll contentView] bounds]]);
  [outlineView setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  [outlineView setUsesAlternatingRowBackgroundColors: YES];
  [outlineView setDataSource: _tableDataSource];
  [outlineView setDelegate: _tableDataSource];

  NSTableColumn *titleColumn = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"title"]);
  [[titleColumn headerCell] setStringValue: @"Section"];
  [[titleColumn dataCell] setFont: [self controlFont]];
  [titleColumn setWidth: 220.0];
  [outlineView addTableColumn: titleColumn];

  NSTableColumn *detailColumn = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"details"]);
  [[detailColumn headerCell] setStringValue: @"What To Check"];
  [[detailColumn dataCell] setFont: [self controlFont]];
  [detailColumn setWidth: 280.0];
  [outlineView addTableColumn: detailColumn];
  [outlineView setOutlineTableColumn: titleColumn];
  [outlineView reloadData];
  [outlineView expandItem: nil expandChildren: YES];

  [outlineScroll setDocumentView: outlineView];
  [outlineScroll reflectScrolledClipView: [outlineScroll contentView]];
  [canvas addSubview: outlineScroll];
}

- (void) populateMenuCanvas: (NSView *)canvas
{
  CGFloat y = NSMaxY ([canvas bounds]) - kDemoPadding;

  [canvas addSubview: [self sectionTitleLabelWithString: @"Scrollbars" frame: NSMakeRect (kDemoPadding, y - kDemoControlHeight, 180, kDemoControlHeight)]];
  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSScrollView *scrollDemo = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (kDemoPadding, y - 220.0, 360.0, 220.0)]);
  [scrollDemo setBorderType: NSBezelBorder];
  [scrollDemo setHasHorizontalScroller: YES];
  [scrollDemo setHasVerticalScroller: YES];
  [scrollDemo setAutohidesScrollers: YES];

  NSTextView *scrollText = AUTORELEASE ([[NSTextView alloc] initWithFrame: [[scrollDemo contentView] bounds]]);
  [scrollText setFont: [self controlFont]];
  [scrollText setEditable: NO];
  [scrollText setHorizontallyResizable: YES];
  [scrollText setVerticallyResizable: YES];
  [scrollText setMinSize: NSMakeSize (NSWidth ([[scrollDemo contentView] bounds]), NSHeight ([[scrollDemo contentView] bounds]))];
  [scrollText setMaxSize: NSMakeSize (10000.0, 10000.0)];
  [[scrollText textContainer] setWidthTracksTextView: NO];
  [[scrollText textContainer] setHeightTracksTextView: NO];
  [[scrollText textContainer] setContainerSize: NSMakeSize (10000.0, 10000.0)];
  [scrollText setFrameSize: NSMakeSize (960.0, 720.0)];
  [scrollText setString: @"Scroll through this text to preview both orientations of the themed scrollbars under the GNOME theme.\n\nThis first paragraph is intentionally ordinary so the active vertical scrollbar remains easy to read during normal multiline content review.\n\nHorizontal overflow sample: /workspace/very-long-project-name/configuration/profiles/default/environment/overrides/synchronization/diagnostics/panel/layout/with/a/path/that/should/not/wrap/inside/the/demo/scroll/view.txt\n\nAdditional notes:\n1. The text view is deliberately taller than the viewport.\n2. The long path above is deliberately wider than the viewport.\n3. This keeps both scrollbars active so the page no longer falls back to disabled GNUstep scrollbars.\n\nLine 05: selection, caret, and viewport edges should still feel balanced.\nLine 06: the scrollbar track width should read as intentional, not accidental.\nLine 07: this page is a live control-surface check, not placeholder lorem ipsum.\nLine 08: leaving real overflow in place makes visual review far more reliable.\nLine 09: if either scrollbar disappears here, the demo content regressed.\nLine 10: this should now be long enough for sustained vertical scrolling."];
  [scrollDemo setDocumentView: scrollText];
  [scrollDemo reflectScrolledClipView: [scrollDemo contentView]];
  [canvas addSubview: scrollDemo];

  y -= (240.0 + kDemoRowSpacing);

  [canvas addSubview: [self sectionTitleLabelWithString: @"Menu Preview" frame: NSMakeRect (kDemoPadding, y, 180, kDemoControlHeight)]];
  y -= (kDemoControlHeight + kDemoRowSpacing);

  NSButton *showMenuButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (kDemoPadding, y, 220, kDemoControlHeight)]);
  [showMenuButton setTitle: @"Show Demo Menu"];
  [showMenuButton setBezelStyle: NSRoundedBezelStyle];
  [showMenuButton setTarget: self];
  [showMenuButton setAction: @selector(showDemoMenu:)];
  [showMenuButton setTag: 0];
  ASSIGN (_demoMenuButton, showMenuButton);
  [canvas addSubview: showMenuButton];

  if (_demoMenu == nil)
    {
      _demoMenu = [NSMenu new];
      [_demoMenu setAutoenablesItems: NO];

      NSMenuItem *recentItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Open Recent"
                                                                       action: NULL
                                                                keyEquivalent: @""]);
      NSMenu *submenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Open Recent"]);
      [submenu addItemWithTitle: @"Project Alpha" action: NULL keyEquivalent: @""];
      [submenu addItemWithTitle: @"Project Beta" action: NULL keyEquivalent: @""];
      [submenu addItem: [NSMenuItem separatorItem]];
      [submenu addItemWithTitle: @"Clear Menu" action: NULL keyEquivalent: @""];
      [recentItem setSubmenu: submenu];
      [_demoMenu addItem: recentItem];

      NSMenuItem *checkedItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Automatically sync workspace"
                                                                        action: NULL
                                                                 keyEquivalent: @"s"]);
      [checkedItem setKeyEquivalentModifierMask: (NSCommandKeyMask | NSAlternateKeyMask)];
      [checkedItem setState: NSOnState];
      [_demoMenu addItem: checkedItem];

      NSMenuItem *mixedItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Workspace indexing pending"
                                                                      action: NULL
                                                               keyEquivalent: @"i"]);
      [mixedItem setKeyEquivalentModifierMask: (NSCommandKeyMask | NSShiftKeyMask)];
      [mixedItem setState: NSMixedState];
      [_demoMenu addItem: mixedItem];

      [_demoMenu addItemWithTitle: @"Preferences…" action: NULL keyEquivalent: @","]; 
      [_demoMenu addItemWithTitle: @"Keyboard Shortcuts" action: NULL keyEquivalent: @"?"];
      [_demoMenu addItem: [NSMenuItem separatorItem]];

      NSMenuItem *disabledItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Sign Out"
                                                                         action: NULL
                                                                  keyEquivalent: @"s"]);
      [disabledItem setEnabled: NO];
      [_demoMenu addItem: disabledItem];
    }
}

- (void) populateStressCanvas: (NSView *)canvas
{
  NSRect bounds = [canvas bounds];
  CGFloat y = NSMaxY (bounds) - kDemoPadding;
  CGFloat labelWidth = 200.0;
  CGFloat fieldX = kDemoPadding + labelWidth + 12.0;

  [canvas addSubview: [self sectionTitleLabelWithString: @"Density and Stress" frame: NSMakeRect (kDemoPadding, y - kDemoControlHeight, 240, kDemoControlHeight)]];
  y -= ((kDemoControlHeight * 2.0) + kDemoRowSpacing);

  [canvas addSubview: [self labelWithString: @"Very long primary action label that should still feel balanced"
                                      frame: NSMakeRect (kDemoPadding, y, labelWidth, kDemoControlHeight)]];

  NSButton *longButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (fieldX, y, 320, kDemoControlHeight)]);
  [longButton setTitle: @"Create and synchronize workspace settings"];
  [longButton setBezelStyle: NSRoundedBezelStyle];
  [canvas addSubview: longButton];

  y -= (kDemoControlHeight + 8.0);

  [canvas addSubview: [self labelWithString: @"Secondary label with a slightly longer caption"
                                      frame: NSMakeRect (kDemoPadding, y, labelWidth, kDemoControlHeight)]];
  [canvas addSubview: [self fieldWithValue: @"Long field value used to test horizontal padding"
                                      frame: NSMakeRect (fieldX, y, 320, kDemoControlHeight)]];

  y -= (kDemoControlHeight + 8.0);

  [canvas addSubview: [self labelWithString: @"Disabled content should remain readable"
                                      frame: NSMakeRect (kDemoPadding, y, labelWidth, kDemoControlHeight)]];
  NSTextField *disabledField = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (fieldX, y, 320, kDemoControlHeight)]);
  [disabledField setStringValue: @"Disabled but still legible"];
  [disabledField setEnabled: NO];
  [disabledField setFont: [self controlFont]];
  [canvas addSubview: disabledField];

  y -= (kDemoControlHeight + 8.0);

  [canvas addSubview: [self labelWithString: @"Pop-up labels and arrows"
                                      frame: NSMakeRect (kDemoPadding, y, labelWidth, kDemoControlHeight)]];
  NSPopUpButton *popup = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (fieldX, y, 420, kDemoControlHeight)
                                                                 pullsDown: NO]);
  [popup addItemWithTitle: @"Adwaita default action with a longer title"];
  [popup addItemWithTitle: @"A second item that forces wider menu geometry"];
  [popup addItemWithTitle: @"Short item"];
  [popup setFont: [self controlFont]];
  [canvas addSubview: popup];

  y -= (kDemoControlHeight + kDemoRowSpacing * 2.0);

  [canvas addSubview: [self labelWithString: @"Stress Menu" frame: NSMakeRect (kDemoPadding, y, 140, kDemoControlHeight)]];

  NSButton *stressMenuButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (fieldX, y, 260, kDemoControlHeight)]);
  [stressMenuButton setTitle: @"Show Long-Label Menu"];
  [stressMenuButton setBezelStyle: NSRoundedBezelStyle];
  [stressMenuButton setTarget: self];
  [stressMenuButton setAction: @selector(showDemoMenu:)];
  [stressMenuButton setTag: 1];
  ASSIGN (_stressMenuButton, stressMenuButton);
  [canvas addSubview: stressMenuButton];

  if (_stressMenu == nil)
    {
      _stressMenu = [NSMenu new];
      [_stressMenu setAutoenablesItems: NO];

      [_stressMenu addItemWithTitle: @"Open the project settings window with all advanced options"
                             action: NULL
                      keyEquivalent: @""];

      NSMenuItem *checkedItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Keep diagnostics overlay visible during synchronization"
                                                                        action: NULL
                                                                 keyEquivalent: @"d"]);
      [checkedItem setKeyEquivalentModifierMask: (NSCommandKeyMask | NSShiftKeyMask)];
      [checkedItem setState: NSOnState];
      [_stressMenu addItem: checkedItem];

      NSMenuItem *mixedItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Mirror remote workspace settings when available"
                                                                      action: NULL
                                                               keyEquivalent: @"m"]);
      [mixedItem setKeyEquivalentModifierMask: (NSCommandKeyMask | NSAlternateKeyMask)];
      [mixedItem setState: NSMixedState];
      [_stressMenu addItem: mixedItem];

      NSMenuItem *submenuItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Export workspace state"
                                                                        action: NULL
                                                                 keyEquivalent: @""]);
      NSMenu *submenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Export workspace state"]);
      [submenu addItemWithTitle: @"Export as human-readable configuration snapshot"
                         action: NULL
                  keyEquivalent: @""];
      [submenu addItemWithTitle: @"Export as compressed archive for backup and transfer"
                         action: NULL
                  keyEquivalent: @""];
      [submenuItem setSubmenu: submenu];
      [_stressMenu addItem: submenuItem];

      [_stressMenu addItem: [NSMenuItem separatorItem]];

      NSMenuItem *disabledItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Sign out of synchronized services"
                                                                         action: NULL
                                                                  keyEquivalent: @"S"]);
      [disabledItem setEnabled: NO];
      [_stressMenu addItem: disabledItem];
    }

  y -= (kDemoControlHeight + kDemoRowSpacing * 2.0);

  NSRect textRect = NSMakeRect (kDemoPadding, y - 200.0, NSWidth (bounds) - (kDemoPadding * 2.0), 200.0);
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: textRect]);
  [scroll setBorderType: NSBezelBorder];
  [scroll setHasVerticalScroller: YES];
  [scroll setAutohidesScrollers: YES];

  NSTextView *textView = AUTORELEASE ([[NSTextView alloc] initWithFrame: [[scroll contentView] bounds]]);
  [textView setFont: [self controlFont]];
  [textView setString: @"Use this page to decide whether typography and spacing are genuinely fixed.\n\nIf the theme only looks good on the tidy demo pages but still collapses under long labels, long menu items, mixed states, and disabled fields, Phase 3 is not done yet."];
  [textView setEditable: NO];
  [scroll setDocumentView: textView];
  [scroll reflectScrolledClipView: [scroll contentView]];
  [canvas addSubview: scroll];
}

#pragma mark - Actions

- (void) sliderValueChanged: (id)sender
{
  double value = [sender doubleValue];
  [_sliderValueLabel setStringValue: [NSString stringWithFormat: @"%.0f", value]];
  if (_progressIndicator != nil)
    {
      [_progressIndicator setDoubleValue: value];
    }
}

- (void) radioSelectionChanged: (id)sender
{
  NSView *container = [sender superview];

  if (container == nil)
    {
      return;
    }

  {
    NSEnumerator *enumerator = [[container subviews] objectEnumerator];
    NSView *view = nil;

    while ((view = [enumerator nextObject]) != nil)
      {
        if ([view isKindOfClass: [NSButton class]] == NO)
          {
            continue;
          }

        if ([(NSButton *)view action] != _cmd)
          {
            continue;
          }

        [(NSButton *)view setState: (view == sender) ? NSOnState : NSOffState];
      }
  }
}

- (void) stepperValueChanged: (id)sender
{
  if (_stepperValueField != nil)
    {
      [_stepperValueField setStringValue: [NSString stringWithFormat: @"%.0f", [sender doubleValue]]];
    }
}

- (void) showDemoMenu: (id)sender
{
  NSView *view = (NSView *)sender;
  NSMenu *menu = ([sender respondsToSelector: @selector(tag)] && [sender tag] == 1) ? _stressMenu : _demoMenu;

  if (menu == nil || view == nil)
    {
      return;
    }

  [menu sizeToFit];

  {
    NSEvent *event = [NSApp currentEvent];

    if (event != nil && [event window] == [view window])
      {
        [NSMenu popUpContextMenu: menu withEvent: event forView: view];
        return;
      }
  }

  if ([view superview] != nil)
    {
      NSRect frame = [view frame];
      NSPoint point = NSMakePoint (NSMinX (frame), NSMinY (frame) - 4.0);

      [menu popUpMenuPositioningItem: nil atLocation: point inView: [view superview]];
    }
  else
    {
      [menu popUpMenuPositioningItem: nil
                          atLocation: NSMakePoint (0.0, 0.0)
                              inView: view];
    }
}

- (void) segmentedChanged: (id)sender
{
  NSSegmentedControl *control = (NSSegmentedControl *)sender;
  NSInteger index = [control selectedSegment];

  if (_progressIndicator != nil && index >= 0)
    {
      double fraction = ((double)(index + 1) / (double)[control segmentCount]) * 100.0;
      [_progressIndicator setDoubleValue: fraction];
    }
}

@end
