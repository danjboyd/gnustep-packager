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

/* libadwaita's lists (#66), against libadwaita 1.7's stylesheet and
   Reference/DropDownList:

   - drop-down-list: a combo box's list is GtkDropDown's popover: rows 9pt
     above and below the text, the list 6pt from the popover's top and
     bottom, as wide as its longest item needs (or the field), a popover
     window with the header bar, the chosen row unfilled with a checkmark
     after its text, and a grey pill (6pt in from the sides) under the
     pointer;
   - source-list: a table with NSTableViewSelectionHighlightStyleSourceList
     is a navigation-sidebar list: no background or grid, a 10% pill 6pt in
     from the sides with 2pt below it on the selected row, 7% under the
     pointer, none on a group row, and cells 14pt in from the ends.

   The popover's rounded corners and shadow need a compositor (alpha) and
   are checked on screen by the screenshots, not here. */

#import "QuirkProbe.h"

#import <GNUstepGUI/GSTheme.h>
#import <dlfcn.h>

@interface QuirkProbe (ListsResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) saveWindow: (NSWindow *)window named: (NSString *)name;
- (NSWindow *) windowWithFrame: (NSRect)frame title: (NSString *)title;
@end

@interface NSComboBoxCell (QuirkProbeListsPrivate)
- (void) _didClickWithinButton: (id)sender;
- (id) _popUp;
@end

static NSBitmapImageRep *
QuirkProbeListsRender(NSView *view)
{
  NSRect bounds = [view bounds];
  NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: bounds];

  [view cacheDisplayInRect: bounds toBitmapImageRep: rep];
  return rep;
}

/* r, g, b (0-255) at a pixel, from the top left. */
static void
QuirkProbeListsPixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y, long rgb[3])
{
  NSInteger bits = [rep bitsPerSample];
  NSUInteger maxValue = (bits >= 16) ? 65535 : ((1u << bits) - 1);
  NSInteger start = ([rep hasAlpha] && ([rep bitmapFormat] & NSAlphaFirstBitmapFormat)) ? 1 : 0;
  NSUInteger pixel[5];
  int i;

  [rep getPixel: pixel atX: x y: y];
  for (i = 0; i < 3; i++)
    {
      rgb[i] = (long)(pixel[start + i] * 255 / maxValue);
    }
}

/* `color` (calibrated) as 0-255 components. */
static void
QuirkProbeListsComponents(NSColor *color, long rgb[3])
{
  NSColor *c = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  rgb[0] = lround ([c redComponent] * 255.0);
  rgb[1] = lround ([c greenComponent] * 255.0);
  rgb[2] = lround ([c blueComponent] * 255.0);
}

/* `fraction` of `over` composited on `under`. */
static void
QuirkProbeListsMix(const long under[3], const long over[3], double fraction, long out[3])
{
  int i;

  for (i = 0; i < 3; i++)
    {
      out[i] = lround (under[i] + (over[i] - under[i]) * fraction);
    }
}

static BOOL
QuirkProbeListsNear(const long a[3], const long b[3], long tolerance)
{
  return labs (a[0] - b[0]) <= tolerance && labs (a[1] - b[1]) <= tolerance
    && labs (a[2] - b[2]) <= tolerance;
}

static NSString *
QuirkProbeListsHex(const long rgb[3])
{
  return [NSString stringWithFormat: @"#%02lx%02lx%02lx", rgb[0], rgb[1], rgb[2]];
}

/* Whether any pixel in an area (top-left origin) is further than `limit`
   (the sum of the components' differences) from `background`. */
static BOOL
QuirkProbeListsHasInk(NSBitmapImageRep *rep, NSInteger x0, NSInteger x1, NSInteger y0, NSInteger y1,
                      const long background[3], long limit)
{
  NSInteger x, y;
  long rgb[3];

  for (y = MAX (y0, 0); y < MIN (y1, [rep pixelsHigh]); y++)
    {
      for (x = MAX (x0, 0); x < MIN (x1, [rep pixelsWide]); x++)
        {
          QuirkProbeListsPixel (rep, x, y, rgb);
          if (labs (rgb[0] - background[0]) + labs (rgb[1] - background[1])
            + labs (rgb[2] - background[2]) > limit)
            {
              return YES;
            }
        }
    }
  return NO;
}

/* The theme makes popovers only with its header bar: its own answer. */
static BOOL
QuirkProbeListsWantsPopover(void)
{
  typedef BOOL (*UsesHeaderBarFunction)(void);
  UsesHeaderBarFunction usesHeaderBar = (UsesHeaderBarFunction)dlsym (RTLD_DEFAULT, "GnomeThemeUsesHeaderBar");

  return usesHeaderBar != NULL && usesHeaderBar ();
}

/* Sends `table` a pointer move to `point` (in the table). */
static void
QuirkProbeListsMoveTo(NSTableView *table, NSPoint point)
{
  NSPoint inWindow = [table convertPoint: point toView: nil];
  NSEvent *event = [NSEvent mouseEventWithType: NSMouseMoved
                                      location: inWindow
                                 modifierFlags: 0
                                     timestamp: 0
                                  windowNumber: [[table window] windowNumber]
                                       context: nil
                                   eventNumber: 0
                                    clickCount: 0
                                      pressure: 0.0];

  [table mouseMoved: event];
}

/* Measures the combo box's list while it is open (its own event loop runs
   timers), then closes it with Escape. */
@interface QuirkProbeDropDownWatcher : NSObject
{
@public
  NSComboBox *combo;
  NSString *detail;
  BOOL ok;
  NSBitmapImageRep *openRep;
  NSBitmapImageRep *hoverRep;
}
@end

@implementation QuirkProbeDropDownWatcher

- (void) dealloc
{
  RELEASE (detail);
  RELEASE (openRep);
  RELEASE (hoverRep);
  [super dealloc];
}

- (void) look: (NSTimer *)timer
{
  NSComboBoxCell *cell = [combo cell];
  NSWindow *popup = [cell _popUp];
  NSView *content = [popup contentView];
  NSScrollView *scrollView = nil;
  NSTableView *table = nil;
  NSUInteger i;
  NSFont *font = [cell font];
  CGFloat textHeight = ceil ([font ascender] - [font descender]);
  CGFloat rowHeight;
  NSInteger rows = [cell numberOfItems];
  NSDictionary *attributes = [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName];
  CGFloat widest = 0.0, wantWidth;
  NSRect frame = [popup frame];
  NSRect fieldOnScreen;
  BOOL popover = QuirkProbeListsWantsPopover ();

  (void)timer;
  for (i = 0; i < [[content subviews] count]; i++)
    {
      if ([[[content subviews] objectAtIndex: i] isKindOfClass: [NSScrollView class]])
        {
          scrollView = [[content subviews] objectAtIndex: i];
        }
    }
  table = [scrollView documentView];
  rowHeight = [table rowHeight];
  for (i = 0; (NSInteger)i < rows; i++)
    {
      widest = MAX (widest, [[combo itemObjectValueAtIndex: i] sizeWithAttributes: attributes].width);
    }
  wantWidth = MAX (MAX (ceil (widest) + 58.0, 120.0), NSWidth ([combo frame]));
  {
    NSRect inWindow = [combo convertRect: [combo bounds] toView: nil];

    fieldOnScreen.origin = [[combo window] convertBaseToScreen: inWindow.origin];
    fieldOnScreen.size = inWindow.size;
  }

  ASSIGN (openRep, QuirkProbeListsRender (content));
  /* The pointer over the first row: its pill. */
  QuirkProbeListsMoveTo (table, NSMakePoint (NSMidX ([table rectOfRow: 0]), NSMidY ([table rectOfRow: 0])));
  [content display];
  ASSIGN (hoverRep, QuirkProbeListsRender (content));

  {
    long bg[3], text[3], want10[3], openPill[3], hoverPill[3], hoverEdge[3], chosen[3];
    NSInteger chosenRow = [cell indexOfSelectedItem];
    NSRect chosenRect = [table convertRect: [table rectOfRow: chosenRow] toView: content];
    NSRect firstRect = [table convertRect: [table rectOfRow: 0] toView: content];
    /* Top-left pixel rows (the content view is not flipped). */
    NSInteger height = (NSInteger)NSHeight ([content bounds]);
    NSInteger chosenY = height - (NSInteger)NSMidY (chosenRect);
    NSInteger firstY = height - (NSInteger)NSMidY (firstRect);
    NSString *chosenText = [combo itemObjectValueAtIndex: chosenRow];
    CGFloat chosenWidth = [chosenText sizeWithAttributes: attributes].width;
    /* The checkmark: 6pt after the text (which starts 18pt in), 16pt wide. */
    NSInteger checkX = 18 + (NSInteger)ceil (chosenWidth) + 6;
    BOOL check, nothingAfterCheck;
    BOOL sized, placed, inset, colours, isPopover;

    QuirkProbeListsPixel (openRep, 4, height / 2, bg);
    check = QuirkProbeListsHasInk (openRep, checkX, checkX + 16, chosenY - 6, chosenY + 6, bg, 150);
    nothingAfterCheck = QuirkProbeListsHasInk (openRep, checkX + 20, (NSInteger)NSWidth ([content bounds]) - 2,
                                               chosenY - 6, chosenY + 6, bg, 150) == NO;
    QuirkProbeListsComponents ([NSColor controlTextColor], text);
    QuirkProbeListsMix (bg, text, 0.10, want10);
    QuirkProbeListsPixel (openRep, 9, chosenY, chosen);
    QuirkProbeListsPixel (openRep, 9, firstY, openPill);
    QuirkProbeListsPixel (hoverRep, 9, firstY, hoverPill);
    QuirkProbeListsPixel (hoverRep, 3, firstY, hoverEdge);

    sized = fabs (rowHeight - (textHeight + 18.0)) < 0.5
      && fabs (NSHeight ([content frame]) - (12.0 + MIN (rows, [cell numberOfVisibleItems]) * rowHeight)) < 1.0
      && fabs (NSMinY ([scrollView frame]) - 6.0) < 0.5
      && fabs (NSWidth (frame) - wantWidth) < 1.0;
    placed = fabs (NSMinX (frame) - NSMinX (fieldOnScreen)) < 1.0
      && fabs (NSMaxY (frame) - (NSMinY (fieldOnScreen) - 2.0)) < 1.0;
    inset = NSMinX ([table frameOfCellAtColumn: 0 row: 0]) == 18.0;
    colours = QuirkProbeListsNear (chosen, bg, 3) && QuirkProbeListsNear (openPill, bg, 3)
      && QuirkProbeListsNear (hoverPill, want10, 3) && QuirkProbeListsNear (hoverEdge, bg, 3);
    isPopover = (([popup styleMask] & NSUtilityWindowMask) != 0) == popover;

    ok = sized && placed && inset && colours && check && nothingAfterCheck && isPopover;
    ASSIGN (detail, ([NSString stringWithFormat:
      @"rows %g (text %g + 18), list %gx%g (want width %g, height 12 + %ld rows), scroll view at y %g; "
      @"%g,%g below the field at %g,%g (%@); cell x %g (want 18); "
      @"chosen row %@ and others %@ unfilled (popover %@), hovered pill %@ (want %@), outside it %@; "
      @"checkmark after the text %@, nothing after it %@; popover window %@ (want %@)",
      rowHeight, textHeight, NSWidth (frame), NSHeight (frame), wantWidth,
      (long)MIN (rows, [cell numberOfVisibleItems]), NSMinY ([scrollView frame]),
      NSMinX (frame), NSMaxY (frame), NSMinX (fieldOnScreen), NSMinY (fieldOnScreen), placed ? @"2pt gap" : @"wrong",
      NSMinX ([table frameOfCellAtColumn: 0 row: 0]),
      QuirkProbeListsHex (chosen), QuirkProbeListsHex (openPill), QuirkProbeListsHex (bg),
      QuirkProbeListsHex (hoverPill), QuirkProbeListsHex (want10), QuirkProbeListsHex (hoverEdge),
      check ? @"yes" : @"no", nothingAfterCheck ? @"yes" : @"no",
      ([popup styleMask] & NSUtilityWindowMask) ? @"yes" : @"no", popover ? @"yes" : @"no"]));
  }

  [NSApp postEvent: [NSEvent keyEventWithType: NSKeyDown
                                     location: NSZeroPoint
                                modifierFlags: 0
                                    timestamp: 0
                                 windowNumber: [popup windowNumber]
                                      context: nil
                                   characters: @"\e"
                  charactersIgnoringModifiers: @"\e"
                                    isARepeat: NO
                                      keyCode: 9]
           atStart: NO];
}

@end

/* Closes a combo box's list if it opened, noting that it did (#76). */
@interface QuirkProbeEmptyListWatcher : NSObject
{
@public
  NSComboBox *combo;
  BOOL opened;
  BOOL fill;
}
@end

@implementation QuirkProbeEmptyListWatcher
- (void) look: (NSTimer *)timer
{
  NSWindow *popup = [[combo cell] _popUp];

  (void)timer;
  opened = [popup isVisible];
  if (opened)
    {
      [NSApp postEvent: [NSEvent keyEventWithType: NSKeyDown
                                         location: NSZeroPoint
                                    modifierFlags: 0
                                        timestamp: 0
                                     windowNumber: [popup windowNumber]
                                          context: nil
                                       characters: @"\e"
                      charactersIgnoringModifiers: @"\e"
                                        isARepeat: NO
                                          keyCode: 9]
               atStart: NO];
    }
}
- (void) willPopUp: (NSNotification *)notification
{
  (void)notification;
  if (fill)
    {
      [combo addItemsWithObjectValues: [NSArray arrayWithObjects: @"Recent", @"Older", nil]];
    }
}
@end

/* A source-list table's data: five rows, the first a group row. */
@interface QuirkProbeSourceListData : NSObject
@end

@implementation QuirkProbeSourceListData
- (NSInteger) numberOfRowsInTableView: (NSTableView *)tableView
{
  (void)tableView;
  return 5;
}

- (id) tableView: (NSTableView *)tableView objectValueForTableColumn: (NSTableColumn *)column row: (NSInteger)row
{
  NSArray *titles = [NSArray arrayWithObjects: @"FONTS", @"Recent", @"Favourites", @"Sans Serif", @"Serif", nil];

  (void)tableView;
  (void)column;
  return [titles objectAtIndex: row];
}

- (BOOL) tableView: (NSTableView *)tableView isGroupRow: (NSInteger)row
{
  (void)tableView;
  return row == 0;
}
@end

@interface QuirkProbe (ListsSave)
- (void) saveRep: (NSBitmapImageRep *)rep named: (NSString *)name;
@end

@implementation QuirkProbe (Lists)

- (void) checkDropDownList
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 400, 320, 120) title: @"Probe Drop-Down"];
  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 60, 140, 34)]);
  QuirkProbeDropDownWatcher *watcher = AUTORELEASE ([QuirkProbeDropDownWatcher new]);

  [combo addItemsWithObjectValues: [NSArray arrayWithObjects: @"Cantarell", @"DejaVu Sans",
    @"DejaVu Serif", @"Liberation Mono Bold Italic", @"Noto Sans", nil]];
  [combo selectItemAtIndex: 2];
  [[window contentView] addSubview: combo];
  [window makeKeyAndOrderFront: nil];
  [window display];
  /* Let the window settle: a move reported while the list is open closes
     it. */
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
  watcher->combo = combo;
  [NSTimer scheduledTimerWithTimeInterval: 0.3
                                   target: watcher
                                 selector: @selector(look:)
                                 userInfo: nil
                                  repeats: NO];
  /* As a click would: the cell knows its control while it tracks. */
  [[combo cell] setControlView: combo];
  [[combo cell] _didClickWithinButton: nil];
  if (watcher->openRep != nil)
    {
      [self saveRep: watcher->hoverRep named: @"drop-down-list"];
    }
  [window orderOut: nil];
  if (watcher->ok)
    {
      [self pass: @"drop-down-list" detail: watcher->detail];
    }
  else
    {
      [self fail: @"drop-down-list" detail: watcher->detail != nil ? watcher->detail : @"the list didn't open"];
    }
}

- (void) saveRep: (NSBitmapImageRep *)rep named: (NSString *)name
{
  NSString *directory = _outputDirectory;

  if (directory == nil || rep == nil)
    {
      return;
    }
  [[rep representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]]
    writeToFile: [directory stringByAppendingPathComponent: [name stringByAppendingPathExtension: @"png"]]
     atomically: YES];
}

- (void) checkSourceList
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 270) title: @"Probe Source List"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (20, 20, 220, 230)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 220, 190)]);
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"c"]);
  QuirkProbeSourceListData *data = AUTORELEASE ([QuirkProbeSourceListData new]);
  NSBitmapImageRep *rep;
  long win[3], text[3], want7[3], want10[3], selected[3], selectedEdge[3], gap[3], corner[3];
  long hover[3], group[3], empty[3], grid[3];
  NSInteger height;
  NSRect selectedRow, hoverRow, groupRow;
  NSString *detail;
  BOOL ok;

  [column setWidth: 220];
  [table addTableColumn: column];
  [table setHeaderView: nil];
  [table setRowHeight: 38];
  [table setIntercellSpacing: NSMakeSize (0, 0)];
  [table setGridStyleMask: NSTableViewSolidHorizontalGridLineMask];
  [table setDataSource: (id)data];
  [table setDelegate: (id)data];
  [table setSelectionHighlightStyle: NSTableViewSelectionHighlightStyleSourceList];
  [scrollView setDocumentView: table];
  [scrollView setHasVerticalScroller: NO];
  [scrollView setBorderType: NSNoBorder];
  [[window contentView] addSubview: scrollView];
  [window makeKeyAndOrderFront: nil];
  [table reloadData];
  [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 2] byExtendingSelection: NO];
  [window display];

  /* The pointer over the group row draws nothing; over row 3, a pill. */
  QuirkProbeListsMoveTo (table, NSMakePoint (100, NSMidY ([table rectOfRow: 0])));
  [window display];
  rep = QuirkProbeListsRender ([window contentView]);
  height = (NSInteger)NSHeight ([[window contentView] bounds]);
  selectedRow = [table convertRect: [table rectOfRow: 2] toView: [window contentView]];
  groupRow = [table convertRect: [table rectOfRow: 0] toView: [window contentView]];
  QuirkProbeListsPixel (rep, 20 + 9, height - (NSInteger)NSMidY (groupRow), group);
  QuirkProbeListsMoveTo (table, NSMakePoint (100, NSMidY ([table rectOfRow: 3])));
  [window display];
  rep = QuirkProbeListsRender ([window contentView]);
  hoverRow = [table convertRect: [table rectOfRow: 3] toView: [window contentView]];

  QuirkProbeListsPixel (rep, 10, height / 2, win);
  QuirkProbeListsComponents ([NSColor controlTextColor], text);
  QuirkProbeListsMix (win, text, 0.07, want7);
  QuirkProbeListsMix (win, text, 0.10, want10);
  /* Rows: inside the pill before the text, outside it at the side, the
     2pt below it, its rounded corner; the hovered row; the empty table
     below the rows; a grid line's place between rows 3 and 4. */
  QuirkProbeListsPixel (rep, 20 + 9, height - (NSInteger)NSMidY (selectedRow), selected);
  QuirkProbeListsPixel (rep, 20 + 3, height - (NSInteger)NSMidY (selectedRow), selectedEdge);
  QuirkProbeListsPixel (rep, 20 + 100, height - (NSInteger)NSMinY (selectedRow) - 1, gap);
  QuirkProbeListsPixel (rep, 20 + 6, height - (NSInteger)NSMaxY (selectedRow), corner);
  QuirkProbeListsPixel (rep, 20 + 9, height - (NSInteger)NSMidY (hoverRow), hover);
  QuirkProbeListsPixel (rep, 20 + 100, height - 25, empty);
  QuirkProbeListsPixel (rep, 20 + 3, height - (NSInteger)NSMinY (hoverRow) - 1, grid);
  [self saveWindow: window named: @"source-list"];
  [window orderOut: nil];

  ok = QuirkProbeListsNear (selected, want10, 3) && QuirkProbeListsNear (selectedEdge, win, 2)
    && QuirkProbeListsNear (gap, win, 2) && QuirkProbeListsNear (corner, win, 3)
    && QuirkProbeListsNear (hover, want7, 3) && QuirkProbeListsNear (group, win, 2)
    && QuirkProbeListsNear (empty, win, 2) && QuirkProbeListsNear (grid, win, 2)
    && [table isOpaque] == NO && [scrollView drawsBackground] == NO
    && NSMinX ([table frameOfCellAtColumn: 0 row: 1]) == 14.0
    && NSMaxX ([table frameOfCellAtColumn: 0 row: 1]) == 220.0 - 14.0;
  detail = [NSString stringWithFormat:
    @"window %@; selected pill %@ (want %@), beside it %@, below it %@, its corner %@; hovered %@ (want %@); "
    @"hovered group row %@; empty table %@; grid %@; opaque %@, scroll view background %@; cell %g to %g (want 14 to 206)",
    QuirkProbeListsHex (win), QuirkProbeListsHex (selected), QuirkProbeListsHex (want10),
    QuirkProbeListsHex (selectedEdge), QuirkProbeListsHex (gap), QuirkProbeListsHex (corner),
    QuirkProbeListsHex (hover), QuirkProbeListsHex (want7), QuirkProbeListsHex (group),
    QuirkProbeListsHex (empty), QuirkProbeListsHex (grid),
    [table isOpaque] ? @"yes" : @"no", [scrollView drawsBackground] ? @"yes" : @"no",
    NSMinX ([table frameOfCellAtColumn: 0 row: 1]), NSMaxX ([table frameOfCellAtColumn: 0 row: 1])];
  if (ok)
    {
      [self pass: @"source-list" detail: detail];
    }
  else
    {
      [self fail: @"source-list" detail: detail];
    }
}

/* A combo box with no items opens no list (it was an empty white box);
   one the app fills when told it will pop up opens as usual (#76). */
- (void) checkDropDownEmpty
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 400, 320, 120) title: @"Probe Empty Drop-Down"];
  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 60, 140, 34)]);
  QuirkProbeEmptyListWatcher *watcher = AUTORELEASE ([QuirkProbeEmptyListWatcher new]);
  BOOL emptyOpened, filledOpened;
  NSString *detail;

  [[window contentView] addSubview: combo];
  [window makeKeyAndOrderFront: nil];
  [window display];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
  watcher->combo = combo;
  [[NSNotificationCenter defaultCenter] addObserver: watcher
                                           selector: @selector(willPopUp:)
                                               name: NSComboBoxWillPopUpNotification
                                             object: combo];
  [[combo cell] setControlView: combo];

  [NSTimer scheduledTimerWithTimeInterval: 0.3 target: watcher selector: @selector(look:)
                                 userInfo: nil repeats: NO];
  [[combo cell] _didClickWithinButton: nil];
  /* The watcher looks once the click has returned. */
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
  emptyOpened = watcher->opened;

  watcher->fill = YES;
  watcher->opened = NO;
  [NSTimer scheduledTimerWithTimeInterval: 0.3 target: watcher selector: @selector(look:)
                                 userInfo: nil repeats: NO];
  [[combo cell] _didClickWithinButton: nil];
  filledOpened = watcher->opened;

  [[NSNotificationCenter defaultCenter] removeObserver: watcher];
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"no items: list %@ (want not); filled for NSComboBoxWillPopUpNotification: list %@ (want opened)",
                     emptyOpened ? @"opened" : @"not opened", filledOpened ? @"opened" : @"not opened"];
  if (emptyOpened == NO && filledOpened)
    {
      [self pass: @"drop-down-empty" detail: detail];
    }
  else
    {
      [self fail: @"drop-down-empty" detail: detail];
    }
}

/* -ProbeOnly lists-demo: a window like Reference/DropDownList's, its
   combo box's list left open, for screenshots beside GTK's. */
- (void) showListsDemo
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 300, 500, 380)
                                                 styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (24, 276, 150, 34)]);
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (24, 322, 150, 34)
                                                                pullsDown: NO]);
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (256, 24, 220, 332)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 220, 332)]);
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"c"]);
  QuirkProbeSourceListData *data = [QuirkProbeSourceListData new];
  NSArray *items = [NSArray arrayWithObjects: @"Cantarell", @"DejaVu Sans", @"DejaVu Serif",
    @"Liberation Mono", @"Noto Sans", @"Noto Serif", @"Source Code Pro", @"Ubuntu", nil];

  NSEnumerator *others = [[NSApp windows] objectEnumerator];
  NSWindow *other;

  /* The demo window alone. */
  while ((other = [others nextObject]) != nil)
    {
      if ([other isVisible] && [other canBecomeMainWindow])
        {
          [other orderOut: nil];
        }
    }
  [window setTitle: @"DropDown list"];
  [window setReleasedWhenClosed: NO];
  [combo setEditable: NO];
  [combo addItemsWithObjectValues: items];
  [combo selectItemAtIndex: 2];
  [combo setStringValue: [items objectAtIndex: 2]];
  [popUp addItemsWithTitles: items];
  [popUp selectItemAtIndex: 2];
  [column setWidth: 220];
  [table addTableColumn: column];
  [table setHeaderView: nil];
  [table setRowHeight: 38];
  [table setDataSource: (id)data];
  [table setDelegate: (id)data];
  [table setSelectionHighlightStyle: NSTableViewSelectionHighlightStyleSourceList];
  [scrollView setDocumentView: table];
  [scrollView setBorderType: NSNoBorder];
  [[window contentView] addSubview: combo];
  [[window contentView] addSubview: popUp];
  [[window contentView] addSubview: scrollView];
  [table reloadData];
  [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 3] byExtendingSelection: NO];
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: nil];
  [[combo cell] setControlView: combo];
  [[combo cell] performSelector: @selector(_didClickWithinButton:) withObject: nil afterDelay: 3.0];
}

@end
