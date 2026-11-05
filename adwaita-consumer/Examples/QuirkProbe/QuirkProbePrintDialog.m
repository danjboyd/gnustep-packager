/*
   Copyright (C) 2026 Daniel Boyd

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

/* -ProbeOnly print-dialog: the print panel as GNOME's print dialog
   (plugins-themes-Adwaita#52), against the stand-in portal of
   Tests/Scripts/fake-print-portal.py, which logs each request to
   -ProbePrintLog (each Print with the file it wrote the document to).
   With -ProbePrintNoPortal YES there is no portal, and the panel must be
   GNUstep's. Run by Tests/Scripts/run-print-dialog-check.sh, with the
   LPR printing bundle (-GSPrinting GSLPR), so that nothing asks CUPS. */

#import "QuirkProbe.h"

#import <objc/runtime.h>

@interface QuirkProbe (PrintDialogResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) finish;
@end

@interface NSPrintPanel (QuirkProbePrintDialog)
- (BOOL) gnomeThemeUsesPrintDialog;
@end

/* Four pages, each with its number. */
@interface QuirkProbePagedView : NSView
@end

@implementation QuirkProbePagedView
- (BOOL) knowsPageRange: (NSRangePointer)range
{
  *range = NSMakeRange (1, 4);
  return YES;
}

- (NSRect) rectForPage: (NSInteger)page
{
  return NSMakeRect (0, (4 - page) * 100.0, 200.0, 100.0);
}

- (void) drawRect: (NSRect)rect
{
  NSInteger page;

  [[NSColor whiteColor] set];
  NSRectFill (rect);
  for (page = 1; page <= 4; page++)
    {
      [[NSString stringWithFormat: @"Page %ld", (long)page]
        drawAtPoint: NSMakePoint (20, (4 - page) * 100.0 + 40)
        withAttributes: nil];
    }
}
@end

/* The sheet's answer. */
@interface QuirkProbePrintRunDelegate : NSObject
{
@public
  BOOL called;
  BOOL success;
}
@end

@implementation QuirkProbePrintRunDelegate
/* libs-gui (0.32, and master 549f639) calls this as
   didRun (delegate, selector, success, contextInfo), without Cocoa's
   operation argument: the success comes first. */
- (void) printOperationDidRun: (NSPrintOperation *)operation success: (BOOL)ok contextInfo: (void *)context
{
  called = YES;
  success = ((uintptr_t)operation == YES);
}
@end

@implementation QuirkProbe (PrintDialog)

- (void) printCheck: (NSString *)ident that: (BOOL)ok detail: (NSString *)detail
{
  if (ok)
    {
      [self pass: ident detail: nil];
    }
  else
    {
      [self fail: ident detail: detail];
    }
}

/* The portal's requests so far. */
- (NSArray *) printRequests
{
  NSString *log = [NSString stringWithContentsOfFile:
                              [[NSUserDefaults standardUserDefaults] stringForKey: @"ProbePrintLog"]];
  NSMutableArray *requests = [NSMutableArray array];
  NSEnumerator *lines = [[log componentsSeparatedByString: @"\n"] objectEnumerator];
  NSString *line;

  while ((line = [lines nextObject]) != nil)
    {
      if ([line length] > 0)
        {
          id entry = [NSJSONSerialization JSONObjectWithData: [line dataUsingEncoding: NSUTF8StringEncoding]
                                                     options: 0
                                                       error: NULL];

          if (entry != nil)
            {
              [requests addObject: entry];
            }
        }
    }
  return requests;
}

- (NSPrintInfo *) portraitA4PrintInfo
{
  NSPrintInfo *info = AUTORELEASE ([[NSPrintInfo sharedPrintInfo] copy]);

  [info setPaperName: @"A4"];
  [info setPaperSize: NSMakeSize (595, 842)];
  [info setOrientation: NSPortraitOrientation];
  [[info dictionary] setObject: [NSNumber numberWithInt: 1] forKey: NSPrintCopies];
  [[info dictionary] setObject: [NSNumber numberWithBool: YES] forKey: NSPrintAllPages];
  return info;
}

/* GNUstep's own run of the print panel, replaced while the no-portal
   check runs: it counts the runs and cancels them (running the real one
   on a display with no input would never end). */
static NSUInteger QuirkProbeGNUstepPrintPanelRuns = 0;

static NSInteger
QuirkProbeCountingPrintPanelRun (id panel, SEL selector, NSPrintInfo *info)
{
  QuirkProbeGNUstepPrintPanelRuns++;
  return NSCancelButton;
}

/* With no portal, the theme's print panel runs GNUstep's. */
- (void) checkPrintDialogWithoutPortal
{
  Method method = class_getInstanceMethod ([NSPrintPanel class], @selector(runModalWithPrintInfo:));
  IMP original;
  NSPrintOperation *operation;
  QuirkProbePagedView *view = AUTORELEASE ([[QuirkProbePagedView alloc] initWithFrame: NSMakeRect (0, 0, 200, 400)]);
  BOOL result;

  [[_controlsWindow contentView] addSubview: view];
  operation = [NSPrintOperation printOperationWithView: view printInfo: [self portraitA4PrintInfo]];
  [operation setShowsProgressPanel: NO];
  original = method_setImplementation (method, (IMP)QuirkProbeCountingPrintPanelRun);
  result = [operation runOperation];
  method_setImplementation (method, original);
  [self printCheck: @"print-dialog-no-portal"
              that: (result == NO && QuirkProbeGNUstepPrintPanelRuns == 1
                     && [NSStringFromClass ([[operation printPanel] class]) isEqualToString: @"GnomeThemePrintPanel"])
            detail: [NSString stringWithFormat: @"result %d, GNUstep's panel run %lu times, panel %@", result,
                              (unsigned long)QuirkProbeGNUstepPrintPanelRuns, [[operation printPanel] class]]];
  [view removeFromSuperview];
  [self finish];
}

- (void) checkPrintDialog
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSWindow *parent = _controlsWindow;
  NSString *parentTitle = AUTORELEASE (RETAIN ([parent title]));
  NSString *expectedParent;
  QuirkProbePagedView *view;
  NSPrintOperation *operation;
  NSPrintInfo *info;
  NSPrintPanel *panel = [NSPrintPanel printPanel];
  NSDictionary *request;
  NSDictionary *settings;
  NSDictionary *setup;
  NSArray *requests;
  NSUInteger before;
  NSDictionary *document;
  NSDictionary *dict;
  QuirkProbePrintRunDelegate *runDelegate;
  BOOL result;

  if ([defaults boolForKey: @"ProbePrintNoPortal"])
    {
      [self checkPrintDialogWithoutPortal];
      return;
    }

  [self printCheck: @"print-dialog-class"
              that: [NSStringFromClass ([panel class]) isEqualToString: @"GnomeThemePrintPanel"]
            detail: [NSString stringWithFormat: @"%@", [panel class]]];

  view = AUTORELEASE ([[QuirkProbePagedView alloc] initWithFrame: NSMakeRect (0, 0, 200, 400)]);
  [[parent contentView] addSubview: view];
  [parent setTitle: @"Probe document"];
  [parent makeKeyAndOrderFront: nil];
  expectedParent = [NSString stringWithFormat: @"x11:%lx", (unsigned long)[parent windowRef]];

  /* Printed through the dialog: A4 landscape, 2 copies, pages 2-3. */
  operation = [NSPrintOperation printOperationWithView: view printInfo: [self portraitA4PrintInfo]];
  /* The operation works on a copy of the print info it was given. */
  info = [operation printInfo];
  [operation setShowsProgressPanel: NO];
  result = [operation runOperation];
  requests = [self printRequests];
  request = ([requests count] >= 1) ? [requests objectAtIndex: 0] : nil;
  settings = [request objectForKey: @"settings"];
  setup = [request objectForKey: @"page_setup"];
  [self printCheck: @"print-dialog-prepare"
              that: ([[request objectForKey: @"method"] isEqualToString: @"PreparePrint"]
                     && [[request objectForKey: @"parent"] isEqualToString: expectedParent]
                     && [[request objectForKey: @"title"] isEqualToString: @"Probe document"]
                     && [[[request objectForKey: @"options"] objectForKey: @"modal"] boolValue])
            detail: [NSString stringWithFormat: @"%@ (parent expected %@)", request, expectedParent]];
  [self printCheck: @"print-dialog-settings-out"
              that: ([[settings objectForKey: @"orientation"] isEqualToString: @"portrait"]
                     && [[settings objectForKey: @"n-copies"] isEqualToString: @"1"]
                     && [[settings objectForKey: @"print-pages"] isEqualToString: @"all"]
                     && [[settings objectForKey: @"paper-format"] isEqualToString: @"iso_a4"]
                     && [[settings objectForKey: @"scale"] isEqualToString: @"100"]
                     && fabs ([[setup objectForKey: @"Width"] doubleValue] - 209.9) < 0.5
                     && fabs ([[setup objectForKey: @"Height"] doubleValue] - 297.0) < 0.5
                     && [[setup objectForKey: @"Name"] isEqualToString: @"iso_a4"])
            detail: [NSString stringWithFormat: @"settings %@, page setup %@", settings, setup]];

  dict = [info dictionary];
  [self printCheck: @"print-dialog-settings-in"
              that: ([info orientation] == NSLandscapeOrientation
                     && fabs ([info paperSize].width - 841.9) < 1 && fabs ([info paperSize].height - 595.3) < 1
                     && [[info paperName] isEqualToString: @"A4"]
                     && [[dict objectForKey: NSPrintCopies] intValue] == 2
                     && [[dict objectForKey: NSPrintAllPages] boolValue] == NO
                     && [[dict objectForKey: NSPrintFirstPage] intValue] == 2
                     && [[dict objectForKey: NSPrintLastPage] intValue] == 3
                     && fabs ([info topMargin] - 28.35) < 0.1)
            detail: [NSString stringWithFormat: @"orientation %d, paper %@ %@, copies %@, all %@, pages %@-%@, top %.2f",
                              (int)[info orientation], [info paperName], NSStringFromSize ([info paperSize]),
                              [dict objectForKey: NSPrintCopies], [dict objectForKey: NSPrintAllPages],
                              [dict objectForKey: NSPrintFirstPage], [dict objectForKey: NSPrintLastPage],
                              [info topMargin]]];

  /* Pages 2-3 only, as landscape A4 pages, as GTK hands the portal a
     landscape job (the stand-in reads them with pdfinfo). */
  request = ([requests count] >= 2) ? [requests objectAtIndex: 1] : nil;
  document = [request objectForKey: @"document"];
  [self printCheck: @"print-dialog-job"
              that: (result == YES
                     && [[request objectForKey: @"method"] isEqualToString: @"Print"]
                     && [[[request objectForKey: @"options"] objectForKey: @"token"] intValue] == 42
                     && [[request objectForKey: @"parent"] isEqualToString: expectedParent]
                     && [[document objectForKey: @"type"] isEqualToString: @"pdf"]
                     && [[document objectForKey: @"pages"] intValue] == 2
                     && [[document objectForKey: @"page_size"] isEqualToString: @"842 x 595"]
                     && [[document objectForKey: @"rotation"] intValue] == 0)
            detail: [NSString stringWithFormat: @"result %d, %@", result, request]];
  [self printCheck: @"print-dialog-job-restored"
              that: ([[info jobDisposition] isEqualToString: NSPrintSpoolJob]
                     && [dict objectForKey: NSPrintSavePath] == nil
                     && [dict objectForKey: @"GnomeThemePrintPortalToken"] == nil
                     && [[[NSFileManager defaultManager] directoryContentsAtPath: NSTemporaryDirectory ()]
                          indexOfObjectPassingTest: ^BOOL (id name, NSUInteger i, BOOL *stop) {
                            return [name hasPrefix: @"GNUstep-print-"];
                          }] == NSNotFound)
            detail: [NSString stringWithFormat: @"job %@, save path %@", [info jobDisposition],
                              [dict objectForKey: NSPrintSavePath]]];

  /* Cancelled: no job, the print info untouched. */
  [parent setTitle: @"Cancel me"];
  before = [[self printRequests] count];
  operation = [NSPrintOperation printOperationWithView: view printInfo: [self portraitA4PrintInfo]];
  info = [operation printInfo];
  [operation setShowsProgressPanel: NO];
  result = [operation runOperation];
  requests = [self printRequests];
  [self printCheck: @"print-dialog-cancel"
              that: (result == NO && [requests count] == before + 1
                     && [info orientation] == NSPortraitOrientation
                     && [[[info dictionary] objectForKey: NSPrintCopies] intValue] == 1
                     && [[info jobDisposition] isEqualToString: NSPrintSpoolJob])
            detail: [NSString stringWithFormat: @"result %d, %lu new requests, orientation %d",
                              result, (unsigned long)([requests count] - before), (int)[info orientation]]];
  [self printCheck: @"print-dialog-cancel-panel"
              that: ([[NSPrintPanel printPanel] runModalWithPrintInfo: [self portraitA4PrintInfo]] == NSCancelButton)
            detail: @"-runModalWithPrintInfo: didn't return NSCancelButton"];

  /* As a sheet: the delegate hears of the job. */
  [parent setTitle: @"Probe document"];
  runDelegate = AUTORELEASE ([QuirkProbePrintRunDelegate new]);
  before = [[self printRequests] count];
  operation = [NSPrintOperation printOperationWithView: view printInfo: [self portraitA4PrintInfo]];
  [operation setShowsProgressPanel: NO];
  [operation runOperationModalForWindow: parent
                               delegate: runDelegate
                         didRunSelector: @selector(printOperationDidRun:success:contextInfo:)
                            contextInfo: NULL];
  requests = [self printRequests];
  [self printCheck: @"print-dialog-sheet"
              that: (runDelegate->called && runDelegate->success && [requests count] == before + 2
                     && [[[requests lastObject] objectForKey: @"method"] isEqualToString: @"Print"])
            detail: [NSString stringWithFormat: @"called %d, success %d, %lu new requests", runDelegate->called,
                              runDelegate->success, (unsigned long)([requests count] - before)]];

  /* GnomeThemeNativePrintDialog NO (for this process only, in the
     argument domain), and an accessory view: GNUstep's panel. */
  {
    NSDictionary *arguments = RETAIN ([defaults volatileDomainForName: NSArgumentDomain]);
    NSMutableDictionary *changed = AUTORELEASE ([arguments mutableCopy]);
    BOOL off;

    if (changed == nil)
      {
        changed = [NSMutableDictionary dictionary];
      }
    [changed setObject: @"NO" forKey: @"GnomeThemeNativePrintDialog"];
    [defaults removeVolatileDomainForName: NSArgumentDomain];
    [defaults setVolatileDomain: changed forName: NSArgumentDomain];
    off = [panel gnomeThemeUsesPrintDialog];
    [defaults removeVolatileDomainForName: NSArgumentDomain];
    if (arguments != nil)
      {
        [defaults setVolatileDomain: arguments forName: NSArgumentDomain];
      }
    RELEASE (arguments);
    [panel setAccessoryView: AUTORELEASE ([[NSView alloc] initWithFrame: NSMakeRect (0, 0, 10, 10)])];
    [self printCheck: @"print-dialog-fallbacks"
                that: (off == NO && [panel gnomeThemeUsesPrintDialog] == NO)
              detail: [NSString stringWithFormat: @"with the setting NO %d, with an accessory %d", off,
                                [panel gnomeThemeUsesPrintDialog]]];
    [panel setAccessoryView: nil];
  }
  [view removeFromSuperview];
  [parent setTitle: parentTitle];
  [self finish];
}

@end
