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

#import "QuirkProbe.h"
#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSDragView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <math.h>

/* Apple's tabbing API and the tab bar, from the tabbing code the theme
   builds in (#63); this libs-gui doesn't declare them. */
@interface NSWindow (QuirkProbeTabbing)
- (void) setTabbingIdentifier: (NSString *)identifier;
- (void) addTabbedWindow: (NSWindow *)window ordered: (NSWindowOrderingMode)ordered;
- (id) tabGroup;
@end

@interface NSObject (QuirkProbeTabBar)
- (NSRect) rectForTabAtIndex: (NSUInteger)index;
- (NSRect) closeButtonRectForTabAtIndex: (NSUInteger)index;
- (NSUInteger) numberOfTabs;
- (void) setSelectedWindow: (NSWindow *)window;
- (CGFloat) windowTabBarScrollFadeWidthForWindow: (NSWindow *)window;
- (void) drawWindowTabBarScrollFadeInRect: (NSRect)rect
                                     edge: (NSRectEdge)edge
                                   window: (NSWindow *)window;
@end

/* From the theme (GnomeThemeMenusAndData.m): a narrow menu bar's overflow
   button and the menu it shows. */
@interface NSMenuView (QuirkProbeMenuBarOverflow)
- (NSRect) gnomeThemeOverflowRect;
- (NSMenu *) gnomeThemeOverflowMenu;
@end

static NSString *QuirkProbeImageItem = @"ImageItem";
static NSString *QuirkProbeViewItem = @"ViewItem";
static NSString *QuirkProbePath =
  @"/home/user/OneDrive/Documents/AVeryLongFolderNameWithoutAnySpaces/file.txt";

/* Seconds to let windows lay out and draw before measuring. */
static const NSTimeInterval QuirkProbeSettleDelay = 0.8;

/* Stands in for libs-gui's coming -[NSButton(Cell) hasDestructiveAction]
   (Docs/design/destructive-button-api.md): a cell that says YES. */
@interface QuirkProbeDestructiveCell : NSButtonCell
@end

@implementation QuirkProbeDestructiveCell
- (BOOL) hasDestructiveAction
{
  return YES;
}
@end

/* Whether the run has GNOME's primary menu: -GnomeThemeMenuStyle primary,
   or no menu style at all with -ProbeMenuDefault YES (the theme's
   default). */
static BOOL
QuirkProbeUsesPrimaryMenu(void)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *style = [defaults stringForKey: @"GnomeThemeMenuStyle"];

  if (style == nil)
    {
      return [defaults boolForKey: @"ProbeMenuDefault"];
    }
  return [style isEqualToString: @"primary"];
}

/* A scroll view that says it has a vertical scroller even when its autohiding
   scroller is out of the view tree, as some libs-gui versions do. */
@interface QuirkProbeDetachedScrollerScrollView : NSScrollView
@end

@implementation QuirkProbeDetachedScrollerScrollView
- (BOOL) hasVerticalScroller
{
  return YES;
}
@end

/* Ink extent of the pixels a test accepts, in pixels. */
typedef struct
{
  NSInteger minX;
  NSInteger width;
  NSInteger height;
  NSUInteger count;
  NSUInteger darkest;   /* lowest red + green + blue among accepted pixels */
  NSInteger minY;
  NSUInteger lightest;  /* highest red + green + blue among accepted pixels */
} QuirkProbeInk;

typedef BOOL (*QuirkProbePixelTest)(NSUInteger red, NSUInteger green, NSUInteger blue);

/* Dark text on a light control: well below the Adwaita borders and fills,
   and below the accent blue, which only focus rings use here. */
static BOOL
QuirkProbeIsTextInk (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return (red + green + blue) < 306;
}

/* Anything visibly darker than a white background: dim text, grid lines,
   borders. */
static BOOL
QuirkProbeIsNotWhite (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return (red + green + blue) < 705;
}

/* White, or nearly: a text background rather than an Adwaita entry. */
static BOOL
QuirkProbeIsWhite (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return (red + green + blue) > 750;
}

/* Ink on the background whose red + green + blue is
   QuirkProbeInkBackground, whether the ink is darker or lighter: text and
   icons in any palette. */
static NSUInteger QuirkProbeInkBackground = 750;

static BOOL
QuirkProbeIsInk (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  NSInteger difference = (NSInteger)(red + green + blue) - (NSInteger)QuirkProbeInkBackground;

  return difference > 150 || difference < -150;
}

/* How far the ink in `area` is from the background, at most. */
static NSUInteger
QuirkProbeContrast (QuirkProbeInk ink, NSUInteger background)
{
  if (ink.count == 0)
    {
      return 0;
    }
  return MAX (ink.lightest > background ? ink.lightest - background : 0,
              background > ink.darkest ? background - ink.darkest : 0);
}

/* Every pixel: for finding the darkest in an area. */
static BOOL
QuirkProbeIsAnyPixel (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return YES;
}

/* The toolbar test image is magenta, a colour the theme never draws. */
static BOOL
QuirkProbeIsMagenta (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return red > 200 && green < 80 && blue > 200;
}

/* The focus ring: the accent blue blended toward the window background. */
static BOOL
QuirkProbeIsFocusBlue (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return blue > 200 && blue > red + 30;
}

/* Strong red, in no palette: the About panel probe's icon. */
static BOOL
QuirkProbeIsProbeRed (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return red > 200 && green < 60 && blue < 60;
}

/* Strong green, in no palette: the About panel probe's large bitmap. */
static BOOL
QuirkProbeIsProbeGreen (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return green > 200 && red < 60 && blue < 60;
}

/* An opaque square `pixels` wide in one colour (RGBA bytes). */
static NSBitmapImageRep *
QuirkProbeSquareBitmap (NSInteger pixels, unsigned char red, unsigned char green)
{
  NSBitmapImageRep *bitmap = AUTORELEASE ([[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
    pixelsWide: pixels pixelsHigh: pixels bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
    colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0]);
  unsigned char *bytes = [bitmap bitmapData];
  NSInteger i;

  for (i = 0; i < pixels * pixels; i++)
    {
      bytes[4 * i] = red;
      bytes[4 * i + 1] = green;
      bytes[4 * i + 2] = 0;
      bytes[4 * i + 3] = 255;
    }
  return bitmap;
}

/* The accent in any palette: bluer than it is red or green. */
static BOOL
QuirkProbeIsAccentBlue (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return blue > red + 30 && blue > green + 10;
}

/* A libs-gui with Cocoa's -cacheDisplayInRect: draws only the view, over
   what the bitmap holds, where the older one's result included the window's
   background. The checks measure against that background, so give it to
   both. */
void
QuirkProbeFillWithBackground (NSBitmapImageRep *rep, NSView *view)
{
  NSColor *background = [[view window] backgroundColor];
  unsigned char *data = [rep bitmapData];
  NSInteger samples = [rep samplesPerPixel];
  NSInteger perRow = [rep bytesPerRow];
  NSInteger x, y;

  if (background == nil)
    {
      background = [NSColor windowBackgroundColor];
    }
  background = [background colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  if (background == nil)
    {
      return;
    }
  for (y = 0; y < [rep pixelsHigh]; y++)
    {
      for (x = 0; x < [rep pixelsWide]; x++)
        {
          unsigned char *pixel = data + y * perRow + x * samples;

          pixel[0] = (unsigned char)lround ([background redComponent] * 255.0);
          pixel[1] = (unsigned char)lround ([background greenComponent] * 255.0);
          pixel[2] = (unsigned char)lround ([background blueComponent] * 255.0);
          if (samples > 3)
            {
              pixel[3] = 255;
            }
        }
    }
}

static NSBitmapImageRep *
QuirkProbeRender (NSView *view)
{
  NSRect bounds = [view bounds];
  NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: bounds];

  QuirkProbeFillWithBackground (rep, view);
  [view cacheDisplayInRect: bounds toBitmapImageRep: rep];
  return rep;
}

/* Measures the accepted pixels in `area` (in pixels, top-left origin), or
   in the whole image when `area` is empty. */
static QuirkProbeInk
QuirkProbeMeasureIn (NSBitmapImageRep *rep, QuirkProbePixelTest test, NSRect area)
{
  QuirkProbeInk ink = { 0, 0, 0, 0, NSUIntegerMax, 0, 0 };
  NSInteger samples = [rep samplesPerPixel];
  NSInteger bits = [rep bitsPerSample];
  NSUInteger maxValue = (bits >= 16) ? 65535 : ((1u << bits) - 1);
  BOOL hasAlpha = [rep hasAlpha];
  BOOL alphaFirst = ([rep bitmapFormat] & NSAlphaFirstBitmapFormat) != 0;
  NSInteger colorStart = (hasAlpha && alphaFirst) ? 1 : 0;
  NSInteger alphaIndex = hasAlpha ? (alphaFirst ? 0 : samples - 1) : -1;
  NSInteger minX = NSIntegerMax, minY = NSIntegerMax, maxX = -1, maxY = -1;
  NSUInteger pixel[5];
  NSInteger x, y;
  NSInteger startX = 0, startY = 0;
  NSInteger endX = [rep pixelsWide], endY = [rep pixelsHigh];

  if (samples < 3 || samples > 5)
    {
      return ink;
    }
  if (NSIsEmptyRect (area) == NO)
    {
      startX = MAX (0, (NSInteger)NSMinX (area));
      startY = MAX (0, (NSInteger)NSMinY (area));
      endX = MIN (endX, (NSInteger)NSMaxX (area));
      endY = MIN (endY, (NSInteger)NSMaxY (area));
    }
  for (y = startY; y < endY; y++)
    {
      for (x = startX; x < endX; x++)
        {
          NSUInteger red, green, blue;

          [rep getPixel: pixel atX: x y: y];
          /* Skip transparent pixels: their colour samples are meaningless. */
          if (alphaIndex >= 0 && pixel[alphaIndex] * 2 < maxValue)
            {
              continue;
            }
          red = pixel[colorStart] * 255 / maxValue;
          green = pixel[colorStart + 1] * 255 / maxValue;
          blue = pixel[colorStart + 2] * 255 / maxValue;
          if (test (red, green, blue))
            {
              ink.count++;
              ink.darkest = MIN (ink.darkest, red + green + blue);
              ink.lightest = MAX (ink.lightest, red + green + blue);
              minX = MIN (minX, x);
              maxX = MAX (maxX, x);
              minY = MIN (minY, y);
              maxY = MAX (maxY, y);
            }
        }
    }
  if (ink.count > 0)
    {
      ink.minX = minX;
      ink.width = maxX - minX + 1;
      ink.height = maxY - minY + 1;
      ink.minY = minY;
    }
  return ink;
}

static QuirkProbeInk
QuirkProbeMeasure (NSBitmapImageRep *rep, QuirkProbePixelTest test)
{
  return QuirkProbeMeasureIn (rep, test, NSZeroRect);
}

static QuirkProbeInk
QuirkProbeTextInk (NSView *view)
{
  return QuirkProbeMeasure (QuirkProbeRender (view), QuirkProbeIsTextInk);
}

static NSView *
QuirkProbeFindViewOfClass (NSView *view, Class viewClass)
{
  NSEnumerator *enumerator;
  NSView *subview;

  if (viewClass == Nil || [view isKindOfClass: viewClass])
    {
      return (viewClass == Nil) ? nil : view;
    }
  enumerator = [[view subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      NSView *found = QuirkProbeFindViewOfClass (subview, viewClass);

      if (found != nil)
        {
          return found;
        }
    }
  return nil;
}

/* Sends the window a mouse-moved event at `point` (window coordinates), as
   the pointer would; tracking rects fire from these. */
static void
QuirkProbeMoveMouse (NSWindow *window, NSPoint point)
{
  NSEvent *event = [NSEvent mouseEventWithType: NSMouseMoved
                                      location: point
                                 modifierFlags: 0
                                     timestamp: 0
                                  windowNumber: [window windowNumber]
                                       context: nil
                                   eventNumber: 0
                                    clickCount: 0
                                      pressure: 0.0];

  [window sendEvent: event];
  /* Renders come from the window's backing store: draw what the event
     invalidated first. */
  [window displayIfNeeded];
}

/* Moves the pointer as QuirkProbeMoveMouse does, then delivers the cursor
   updates that entering or leaving cursor rects posts to the queue, so
   [NSCursor currentCursor] shows the result. */
static void
QuirkProbeMoveMouseForCursor (NSWindow *window, NSPoint point)
{
  NSEvent *update;

  QuirkProbeMoveMouse (window, point);
  while ((update = [NSApp nextEventMatchingMask: NSCursorUpdateMask
                                      untilDate: [NSDate distantPast]
                                         inMode: NSDefaultRunLoopMode
                                        dequeue: YES]) != nil)
    {
      [NSApp sendEvent: update];
    }
}

/* Sends an event through NSApp, as a real key or pointer press arrives. */
static void
QuirkProbeSendApplicationEvent (NSWindow *window, NSEventType type)
{
  NSEvent *event;

  if (type == NSKeyDown)
    {
      /* F13: no control or key binding uses it. */
      NSString *key = [NSString stringWithFormat: @"%C", (unichar)NSF13FunctionKey];

      event = [NSEvent keyEventWithType: NSKeyDown
                               location: NSZeroPoint
                          modifierFlags: 0
                              timestamp: 0
                           windowNumber: [window windowNumber]
                                context: nil
                             characters: key
            charactersIgnoringModifiers: key
                              isARepeat: NO
                                keyCode: 0];
    }
  else
    {
      /* On the window background, clear of any control. */
      event = [NSEvent mouseEventWithType: type
                                 location: NSMakePoint (5, 5)
                            modifierFlags: 0
                                timestamp: 0
                             windowNumber: [window windowNumber]
                                  context: nil
                              eventNumber: 0
                               clickCount: 1
                                 pressure: 1.0];
    }
  [NSApp sendEvent: event];
  [window displayIfNeeded];
}

/* YES when GNUstep draws the window decorations (-GSX11HandlesWindowDecorations
   NO), so the theme draws its header bar. */
static BOOL
QuirkProbeDrawsDecorations (void)
{
  return [GSCurrentServer () handlesWindowDecorations] == NO;
}

/* How far below the top of `view` a subview's `frame` starts. */
static CGFloat
QuirkProbeTopGap (NSView *view, NSRect frame)
{
  return [view isFlipped] ? NSMinY (frame) : NSMaxY ([view bounds]) - NSMaxY (frame);
}

/* The header bar's window buttons, left to right. */
static NSArray *
QuirkProbeWindowButtons (NSView *frameView)
{
  NSMutableArray *buttons = [NSMutableArray array];
  NSEnumerator *enumerator = [[frameView subviews] objectEnumerator];
  NSView *subview;
  NSUInteger i, j;

  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview isKindOfClass: NSClassFromString (@"GnomeThemeWindowButton")] && [subview isHidden] == NO)
        {
          [buttons addObject: subview];
        }
    }
  for (i = 1; i < [buttons count]; i++)
    {
      for (j = i; j > 0 && NSMinX ([[buttons objectAtIndex: j] frame]) < NSMinX ([[buttons objectAtIndex: j - 1] frame]); j--)
        {
          [buttons exchangeObjectAtIndex: j withObjectAtIndex: j - 1];
        }
    }
  return buttons;
}

/* A click in `window` at `point` (window coordinates), sent through NSApp. */
static void
QuirkProbeClick (NSWindow *window, NSPoint point, NSInteger clickCount)
{
  NSEvent *event = [NSEvent mouseEventWithType: NSLeftMouseDown
                                      location: point
                                 modifierFlags: 0
                                     timestamp: 0
                                  windowNumber: [window windowNumber]
                                       context: nil
                                   eventNumber: 0
                                    clickCount: clickCount
                                      pressure: 1.0];

  [NSApp sendEvent: event];
  [window displayIfNeeded];
}

static NSView *
QuirkProbeFindText (NSView *view, NSString *text)
{
  NSEnumerator *enumerator;
  NSView *subview;

  if ([view isKindOfClass: [NSTextField class]]
    && [[(NSTextField *)view stringValue] isEqualToString: text])
    {
      return view;
    }
  if ([view isKindOfClass: [NSTextView class]]
    && [[(NSTextView *)view string] isEqualToString: text])
    {
      return view;
    }
  enumerator = [[view subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      NSView *found = QuirkProbeFindText (subview, text);

      if (found != nil)
        {
          return found;
        }
    }
  return nil;
}

@interface NSCell (QuirkProbeEditing)
- (BOOL) _inEditing;
@end

/* Records what a text field's -stringValue says in
   controlTextDidChange: (#73). */
@interface QuirkProbeTextChangeDelegate : NSObject
{
@public
  NSMutableArray *seen;
  NSString *cellState;
}
@end

@implementation QuirkProbeTextChangeDelegate
- (void) controlTextDidChange: (NSNotification *)notification
{
  NSTextField *field = [notification object];
  NSCell *cell = [field cell];

  [seen addObject: [field stringValue]];
  ASSIGN (cellState, ([NSString stringWithFormat: @"editing %@, control view %@",
                        [cell _inEditing] ? @"yes" : @"no",
                        [cell controlView] == field ? @"the field"
                          : [[cell controlView] description]]));
}
@end

/* Counts how deeply -tile nests (#75). */
@interface QuirkProbeTileCountingScrollView : NSScrollView
@end

static NSUInteger QuirkProbeTileDepth = 0;
static NSUInteger QuirkProbeTileMaxDepth = 0;

@implementation QuirkProbeTileCountingScrollView
- (void) tile
{
  QuirkProbeTileDepth++;
  QuirkProbeTileMaxDepth = MAX (QuirkProbeTileMaxDepth, QuirkProbeTileDepth);
  [super tile];
  QuirkProbeTileDepth--;
}
@end

/* A content view as an AppKit app draws one: filled with
   controlBackgroundColor (LinDirStat's empty treemap pane, #94). */
@interface QuirkProbeContentFillView : NSView
@end

@implementation QuirkProbeContentFillView
- (void) drawRect: (NSRect)rect
{
  [[NSColor controlBackgroundColor] set];
  NSRectFill (rect);
}
@end

/* A toolbar delegate whose items select a view, like Gorm's document
   toolbar. */
@interface QuirkProbeSwitcherDelegate : NSObject
@end

@implementation QuirkProbeSwitcherDelegate
- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);

  [item setLabel: identifier];
  return item;
}
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Objects", @"Classes", nil];
}
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}
- (NSArray *) toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}
@end

/* Ink per row, top to bottom, over the rows that have any: the text's
   vertical profile. */
static NSArray *
QuirkProbeInkRows (NSBitmapImageRep *rep, NSRect area)
{
  NSMutableArray *rows = [NSMutableArray array];
  NSInteger y;

  for (y = (NSInteger)NSMinY (area); y < (NSInteger)NSMaxY (area) && y < [rep pixelsHigh]; y++)
    {
      QuirkProbeInk row = QuirkProbeMeasureIn (rep, QuirkProbeIsTextInk,
                                               NSMakeRect (NSMinX (area), y, NSWidth (area), 1));

      if (row.count > 0 || [rows count] > 0)
        {
          [rows addObject: [NSNumber numberWithUnsignedInteger: row.count]];
        }
    }
  while ([rows count] > 0 && [[rows lastObject] unsignedIntegerValue] == 0)
    {
      [rows removeLastObject];
    }
  return rows;
}

/* How far apart two profiles are, the second read top down or (reversed)
   bottom up. */
static NSUInteger
QuirkProbeProfileDistance (NSArray *a, NSArray *b, BOOL reversed)
{
  NSUInteger count = MIN ([a count], [b count]);
  NSUInteger i, distance = 0;

  for (i = 0; i < count; i++)
    {
      NSInteger x = [[a objectAtIndex: i] integerValue];
      NSInteger y = [[b objectAtIndex: reversed ? [b count] - 1 - i : i] integerValue];

      distance += (NSUInteger)labs (x - y);
    }
  return distance + (MAX ([a count], [b count]) - count) * 10;
}

/* Two columns of three rows, titled "Folder" and "Items". */
@interface QuirkProbeBrowserDelegate : NSObject
@end

@implementation QuirkProbeBrowserDelegate
- (NSInteger) browser: (NSBrowser *)browser numberOfRowsInColumn: (NSInteger)column
{
  return 3;
}

- (void) browser: (NSBrowser *)browser
 willDisplayCell: (id)cell
           atRow: (NSInteger)row
          column: (NSInteger)column
{
  [cell setStringValue: [NSString stringWithFormat: @"Row %ld", (long)row]];
  [cell setLeaf: column > 0];
}

- (NSString *) browser: (NSBrowser *)browser titleOfColumn: (NSInteger)column
{
  return column == 0 ? @"Folder" : @"Items";
}
@end

@interface QuirkProbe ()
- (void) after: (NSTimeInterval)delay perform: (SEL)selector;
- (NSTimer *) after: (NSTimeInterval)delay perform: (SEL)selector mode: (NSString *)mode;
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) known: (NSString *)ident detail: (NSString *)detail;
- (void) skip: (NSString *)ident detail: (NSString *)detail;
- (void) saveWindow: (NSWindow *)window named: (NSString *)name;
- (NSWindow *) windowWithFrame: (NSRect)frame title: (NSString *)title;
- (NSTextField *) labelWithText: (NSString *)text frame: (NSRect)frame;
- (NSImage *) magentaImage;
- (void) checkPrimaryMenuInMenuBar;
- (void) checkPrimaryMenuInHeaderBar;
@end

/* An icon-only toolbar as a GNOME-style app makes it: an image item and a
   34pt button (libadwaita's size) as a view item. */
@interface QuirkProbeRowToolbarDelegate : NSObject
{
@public
  BOOL _emptyLabels;
}
@end

@implementation QuirkProbeRowToolbarDelegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);

  [item setLabel: _emptyLabels ? @"" : identifier];
  if ([identifier isEqualToString: @"Image"])
    {
      NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (16, 16)]);

      [image lockFocus];
      [[NSColor blackColor] set];
      NSRectFill (NSMakeRect (0, 0, 16, 16));
      [image unlockFocus];
      [item setImage: image];
      [item setTarget: self];
      [item setAction: @selector(description)];
    }
  else
    {
      NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (0, 0, 34, 34)]);

      [button setTitle: @"B"];
      [item setView: button];
      [item setMinSize: NSMakeSize (34, 34)];
      [item setMaxSize: NSMakeSize (34, 34)];
    }
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Image", NSToolbarSeparatorItemIdentifier, @"Button",
                   NSToolbarFlexibleSpaceItemIdentifier, nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

@end

/* The theme's, from Source/Rendering/GnomeThemeWindowTypes.m and
   GnomeThemeHeaderBar.m. */
@interface NSObject (QuirkProbeGnomeTheme)
+ (NSString *) windowTypeForWindow: (NSWindow *)window;
+ (NSString *) windowManagerCloseStateForWindow: (NSWindow *)window;
- (BOOL) holdsToolbarInBar;
- (void) titleLimitsWithToolbar: (CGFloat *)minX : (CGFloat *)maxX;
- (NSString *) view: (NSView *)view stringForToolTip: (NSToolTipTag)tag point: (NSPoint)point
           userData: (void *)data;
@end

@interface NSToolbar (QuirkProbePrivate)
- (NSView *) _toolbarView;
@end

@interface NSToolbarItem (QuirkProbePrivate)
- (NSView *) _backView;
@end

/* A toolbar as a GNOME app packs its header bar: two icons at the start, a
   flexible space, a text button and an icon at the end. */
@interface QuirkProbeHeaderToolbarDelegate : NSObject
@end

@implementation QuirkProbeHeaderToolbarDelegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);

  [item setLabel: identifier];
  [item setTarget: self];
  [item setAction: @selector(description)];
  if ([identifier hasPrefix: @"Icon"])
    {
      NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (16, 16)]);

      [image lockFocus];
      [[NSColor blackColor] set];
      NSRectFill (NSMakeRect (4, 4, 8, 8));
      [image unlockFocus];
      [item setImage: image];
    }
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"IconA", @"IconB", NSToolbarFlexibleSpaceItemIdentifier, @"Share", @"IconC", nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

@end

/* A header-bar toolbar holding a segmented control as its item's view,
   as ScreenshotTool's tool switcher. */
@interface QuirkProbeSegmentToolbarDelegate : NSObject
{
@public
  NSSegmentedControl *control;
}
@end

@implementation QuirkProbeSegmentToolbarDelegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);

  [item setLabel: identifier];
  if ([identifier isEqualToString: @"Tools"])
    {
      [item setView: control];
      [item setMinSize: [control frame].size];
      [item setMaxSize: [control frame].size];
    }
  else
    {
      NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (16, 16)]);

      [image lockFocus];
      [[NSColor blackColor] set];
      NSRectFill (NSMakeRect (4, 4, 8, 8));
      [image unlockFocus];
      [item setImage: image];
      [item setTarget: self];
      [item setAction: @selector(description)];
    }
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Tools", NSToolbarFlexibleSpaceItemIdentifier, @"Copy", nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

@end

/* A toolbar item's view that acts on the release only, as ScreenshotTool's
   Copy and zoom items did (plugins-themes-Adwaita#33). */
@interface QuirkProbeReleaseView : NSView
{
@public
  int releases;
}
@end

@implementation QuirkProbeReleaseView

- (void) mouseUp: (NSEvent *)event
{
  releases++;
}

- (void) drawRect: (NSRect)rect
{
  [[NSColor grayColor] set];
  NSRectFill ([self bounds]);
}

@end

@interface QuirkProbeReleaseToolbarDelegate : NSObject
{
@public
  QuirkProbeReleaseView *view;
}
@end

@implementation QuirkProbeReleaseToolbarDelegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);

  [item setLabel: identifier];
  if ([identifier isEqualToString: @"Release"])
    {
      view = AUTORELEASE ([[QuirkProbeReleaseView alloc] initWithFrame: NSMakeRect (0, 0, 32, 28)]);
      [item setView: view];
      [item setMinSize: NSMakeSize (32, 28)];
      [item setMaxSize: NSMakeSize (32, 28)];
    }
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Release", NSToolbarFlexibleSpaceItemIdentifier, nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

@end

/* A toolbar with an item that is only a container (a plain view, as
   MarkdownViewer's status area) and one that is a label
   (plugins-themes-Adwaita#36). */
@interface QuirkProbeDragToolbarDelegate : NSObject
{
@public
  NSView *box;
  NSTextField *label;
}
@end

@implementation QuirkProbeDragToolbarDelegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);

  [item setLabel: identifier];
  if ([identifier isEqualToString: @"Box"])
    {
      box = AUTORELEASE ([[NSView alloc] initWithFrame: NSMakeRect (0, 0, 80, 28)]);
      [item setView: box];
      [item setMinSize: NSMakeSize (80, 28)];
      [item setMaxSize: NSMakeSize (80, 28)];
    }
  else if ([identifier isEqualToString: @"Label"])
    {
      label = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (0, 0, 80, 20)]);
      [label setStringValue: @"Status"];
      [label setEditable: NO];
      [label setSelectable: NO];
      [label setBezeled: NO];
      [label setDrawsBackground: NO];
      [item setView: label];
      [item setMinSize: NSMakeSize (80, 20)];
      [item setMaxSize: NSMakeSize (80, 20)];
    }
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Box", @"Label", NSToolbarFlexibleSpaceItemIdentifier, nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

@end

/* An icon-only toolbar of plain views with fixed sizes (minSize = maxSize =
   the view's frame) around a flexible space, as ScreenshotTool makes it. */
@interface QuirkProbeViewItemToolbarDelegate : NSObject
@end

@implementation QuirkProbeViewItemToolbarDelegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);
  NSView *view = AUTORELEASE ([[NSView alloc] initWithFrame:
    NSMakeRect (0, 0, [identifier isEqualToString: @"Wide"] ? 104 : 40, 32)]);

  [item setLabel: identifier];
  [item setView: view];
  [item setMinSize: [view frame].size];
  [item setMaxSize: [view frame].size];
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Narrow", NSToolbarFlexibleSpaceItemIdentifier, @"Wide", nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

@end

@implementation QuirkProbe

- (id) init
{
  self = [super init];
  if (self != nil)
    {
      _windows = [NSMutableArray new];
      _sizedButtons = [NSMutableArray new];
      _fixedButtons = [NSMutableArray new];
      _alertText = RETAIN (@"The files stay on this computer and in OneDrive. "
        @"OneDriveServiceManager stops syncing this folder, removes its service, "
        @"and forgets its settings. You can add the library again later.");
    }
  return self;
}

- (void) dealloc
{
  RELEASE (_outputDirectory);
  RELEASE (_windows);
  RELEASE (_sizedButtons);
  RELEASE (_fixedButtons);
  RELEASE (_toolbarViewButton);
  RELEASE (_alertText);
  [super dealloc];
}

#pragma mark Results

- (void) report: (NSString *)status ident: (NSString *)ident detail: (NSString *)detail
{
  if ([detail length] > 0)
    {
      printf ("%-5s %s: %s\n", [status UTF8String], [ident UTF8String], [detail UTF8String]);
    }
  else
    {
      printf ("%-5s %s\n", [status UTF8String], [ident UTF8String]);
    }
  fflush (stdout);
}

- (void) pass: (NSString *)ident detail: (NSString *)detail
{
  _passed++;
  [self report: @"PASS" ident: ident detail: detail];
}

- (void) fail: (NSString *)ident detail: (NSString *)detail
{
  _failed++;
  [self report: @"FAIL" ident: ident detail: detail];
}

- (void) known: (NSString *)ident detail: (NSString *)detail
{
  _known++;
  [self report: @"KNOWN" ident: ident detail: detail];
}

- (void) skip: (NSString *)ident detail: (NSString *)detail
{
  _skipped++;
  [self report: @"SKIP" ident: ident detail: detail];
}

#pragma mark Helpers

/* A timer in one run loop mode. (A timer added to two modes can fire in
   both.) */
- (NSTimer *) after: (NSTimeInterval)delay perform: (SEL)selector mode: (NSString *)mode
{
  NSTimer *timer = [NSTimer timerWithTimeInterval: delay
                                           target: self
                                         selector: selector
                                         userInfo: nil
                                          repeats: NO];

  [[NSRunLoop currentRunLoop] addTimer: timer forMode: mode];
  return timer;
}

- (void) after: (NSTimeInterval)delay perform: (SEL)selector
{
  [self after: delay perform: selector mode: NSDefaultRunLoopMode];
}

- (void) saveWindow: (NSWindow *)window named: (NSString *)name
{
  NSView *frameView = [[window contentView] superview];
  NSData *png;
  NSString *path;

  if (_outputDirectory == nil || frameView == nil)
    {
      return;
    }
  png = [QuirkProbeRender (frameView) representationUsingType: NSPNGFileType
                                                  properties: [NSDictionary dictionary]];
  path = [_outputDirectory stringByAppendingPathComponent:
    [name stringByAppendingPathExtension: @"png"]];
  [png writeToFile: path atomically: YES];
}

- (NSWindow *) windowWithFrame: (NSRect)frame title: (NSString *)title
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                 styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];

  [window setTitle: title];
  [window setReleasedWhenClosed: NO];
  [_windows addObject: window];
  RELEASE (window);
  return window;
}

- (NSTextField *) labelWithText: (NSString *)text frame: (NSRect)frame
{
  NSTextField *label = [[NSTextField alloc] initWithFrame: frame];

  [label setStringValue: text];
  [label setBezeled: NO];
  [label setBordered: NO];
  [label setEditable: NO];
  [label setSelectable: NO];
  [label setDrawsBackground: YES];
  [label setBackgroundColor: [NSColor whiteColor]];
  return AUTORELEASE (label);
}

- (NSImage *) magentaImage
{
  NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize (24, 24)];

  [image lockFocus];
  [[NSColor colorWithCalibratedRed: 1.0 green: 0.0 blue: 1.0 alpha: 1.0] set];
  NSRectFill (NSMakeRect (2, 2, 20, 20));
  [image unlockFocus];
  return AUTORELEASE (image);
}

#pragma mark Toolbar delegate

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: identifier];

  [item setLabel: identifier];
  if ([identifier isEqualToString: QuirkProbeImageItem])
    {
      [item setImage: [self magentaImage]];
      /* Enabled, so the image draws at full colour. */
      [item setTarget: self];
      [item setAction: @selector(toolbarItemClicked:)];
    }
  else
    {
      NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect (0, 0, 36, 32)];

      [button setImage: [self magentaImage]];
      [button setImagePosition: NSImageOnly];
      [button setBordered: NO];
      [item setView: button];
      [item setMinSize: NSMakeSize (36, 32)];
      [item setMaxSize: NSMakeSize (36, 32)];
      ASSIGN (_toolbarViewButton, button);
      RELEASE (button);
    }
  return AUTORELEASE (item);
}

- (void) toolbarItemClicked: (id)sender
{
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: QuirkProbeImageItem, QuirkProbeViewItem, nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

#pragma mark Table data source

- (NSInteger) numberOfRowsInTableView: (NSTableView *)tableView
{
  return 4;
}

- (id) tableView: (NSTableView *)tableView
objectValueForTableColumn: (NSTableColumn *)column
             row: (NSInteger)row
{
  return [NSString stringWithFormat: @"Library %ld", (long)row + 1];
}

#pragma mark Windows

- (NSTableView *) addTableAt: (NSRect)frame inView: (NSView *)view
{
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame: frame];
  NSTableView *tableView = [[NSTableView alloc] initWithFrame:
    NSMakeRect (0, 0, NSWidth (frame), NSHeight (frame))];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"name"];

  [[column headerCell] setStringValue: @"Name"];
  [column setWidth: NSWidth (frame) - 10];
  [tableView addTableColumn: column];
  [tableView setDataSource: self];
  [scrollView setDocumentView: tableView];
  [scrollView setBorderType: NSBezelBorder];
  [scrollView setHasVerticalScroller: NO];
  [scrollView setHasHorizontalScroller: NO];
  [view addSubview: scrollView];
  [tableView reloadData];
  RELEASE (column);
  RELEASE (scrollView);
  return AUTORELEASE (tableView);
}

- (void) addButtonTitled: (NSString *)title
                    type: (NSButtonType)type
                      at: (NSPoint)origin
                  inView: (NSView *)view
{
  NSButton *sized = [[NSButton alloc] initWithFrame: NSMakeRect (origin.x, origin.y, 10, 10)];
  NSButton *wide = [[NSButton alloc] initWithFrame: NSZeroRect];
  NSEnumerator *enumerator = [[NSArray arrayWithObjects: sized, wide, nil] objectEnumerator];
  NSButton *button;

  while ((button = [enumerator nextObject]) != nil)
    {
      [button setButtonType: type];
      if (type == NSMomentaryPushInButton)
        {
          [button setBezelStyle: NSRoundedBezelStyle];
        }
      [button setTitle: title];
    }
  [sized sizeToFit];
  /* The same button with room to spare: its title is the reference. The
     references get a column of their own, one per row: renders come from the
     window's backing store, so views must not overlap. */
  [wide setFrame: NSMakeRect (480, 420 - 45 * [_sizedButtons count],
                              NSWidth ([sized frame]) + 100, NSHeight ([sized frame]))];
  [view addSubview: sized];
  [view addSubview: wide];
  [_sizedButtons addObject: [NSArray arrayWithObjects: sized, wide, nil]];
  RELEASE (sized);
  RELEASE (wide);
}

/* A push button of a size the app chose, too small for the theme's full
   padding but with room for its title, beside a wide copy as the reference
   (in a column of their own at x 700). */
- (void) addFixedButtonTitled: (NSString *)title
                        frame: (NSRect)frame
                       inView: (NSView *)view
{
  NSButton *fixed = [[NSButton alloc] initWithFrame: frame];
  NSButton *wide = [[NSButton alloc] initWithFrame: NSMakeRect (700, 140 - 40 * [_fixedButtons count],
                                                               180, NSHeight (frame))];
  NSEnumerator *enumerator = [[NSArray arrayWithObjects: fixed, wide, nil] objectEnumerator];
  NSButton *button;

  while ((button = [enumerator nextObject]) != nil)
    {
      [button setButtonType: NSMomentaryPushInButton];
      [button setBezelStyle: NSRoundedBezelStyle];
      [button setTitle: title];
      [view addSubview: button];
    }
  [_fixedButtons addObject: [NSArray arrayWithObjects: fixed, wide, nil]];
  RELEASE (fixed);
  RELEASE (wide);
}

- (NSStepper *) stepperWithFrame: (NSRect)frame value: (double)value inView: (NSView *)view
{
  NSStepper *stepper = [[NSStepper alloc] initWithFrame: frame];

  [stepper setMinValue: 0];
  [stepper setMaxValue: 10];
  [stepper setDoubleValue: value];
  [view addSubview: stepper];
  return AUTORELEASE (stepper);
}

- (void) buildWindows
{
  NSView *view;
  NSToolbar *toolbar;
  NSTextField *label;

  _controlsWindow = [self windowWithFrame: NSMakeRect (40, 40, 900, 470) title: @"QuirkProbe Controls"];
  view = [_controlsWindow contentView];

  [self addButtonTitled: @"Sign In" type: NSMomentaryPushInButton at: NSMakePoint (10, 410) inView: view];
  [self addButtonTitled: @"Resync Now" type: NSMomentaryPushInButton at: NSMakePoint (130, 410) inView: view];
  [self addButtonTitled: @"OK" type: NSMomentaryPushInButton at: NSMakePoint (290, 410) inView: view];
  [self addButtonTitled: @"Errors only" type: NSSwitchButton at: NSMakePoint (10, 370) inView: view];
  [self addButtonTitled: @"Start at login" type: NSSwitchButton at: NSMakePoint (150, 370) inView: view];
  [self addButtonTitled: @"Download everything" type: NSRadioButton at: NSMakePoint (10, 335) inView: view];
  /* ScreenshotTool's quick-width buttons (plugins-themes-Adwaita#3). */
  [self addFixedButtonTitled: @"12" frame: NSMakeRect (250, 130, 64, 28) inView: view];
  [self addFixedButtonTitled: @"20" frame: NSMakeRect (330, 130, 44, 28) inView: view];
  [self addFixedButtonTitled: @"Apply" frame: NSMakeRect (250, 90, 64, 28) inView: view];
  /* Steppers: Cocoa's size, the same at its maximum, and a wide one
     (plugins-themes-Adwaita#6). */
  _tallStepper = [self stepperWithFrame: NSMakeRect (400, 100, 18, 24) value: 5 inView: view];
  _maxedStepper = [self stepperWithFrame: NSMakeRect (430, 100, 18, 24) value: 10 inView: view];
  [_maxedStepper setValueWraps: NO];
  _wideStepper = [self stepperWithFrame: NSMakeRect (400, 60, 48, 24) value: 5 inView: view];
  /* A colour well (plugins-themes-Adwaita#2). */
  _colorWell = AUTORELEASE ([[NSColorWell alloc] initWithFrame: NSMakeRect (480, 140, 52, 30)]);
  [_colorWell setColor: [NSColor colorWithCalibratedRed: 0.9 green: 0.1 blue: 0.1 alpha: 1.0]];
  [view addSubview: _colorWell];

  _wrappingLabel = [self labelWithText: @"This note is long enough that it needs to wrap onto a second line in this label."
                                 frame: NSMakeRect (10, 220, 220, 80)];
  [view addSubview: _wrappingLabel];
  _newlineLabel = [self labelWithText: @"First line\nSecond line (explicit newline)"
                                frame: NSMakeRect (240, 220, 220, 80)];
  [view addSubview: _newlineLabel];
  /* One line of the labels' font, for comparing heights. */
  label = [self labelWithText: @"Thgy(" frame: NSMakeRect (10, 130, 100, 30)];
  [label setTag: 1];
  [view addSubview: label];

  _pathLabel = [self labelWithText: QuirkProbePath frame: NSMakeRect (10, 180, 220, 20)];
  [view addSubview: _pathLabel];
  _truncatedPathLabel = [self labelWithText: QuirkProbePath frame: NSMakeRect (240, 180, 220, 20)];
  [[_truncatedPathLabel cell] setLineBreakMode: NSLineBreakByTruncatingMiddle];
  [view addSubview: _truncatedPathLabel];

  _popUpButton = [[NSPopUpButton alloc] initWithFrame: NSMakeRect (10, 60, 220, 30) pullsDown: NO];
  [_popUpButton addItemsWithTitles: [NSArray arrayWithObjects: @"Personal account", @"Work or school", nil]];
  [view addSubview: _popUpButton];
  RELEASE (_popUpButton);

  [_controlsWindow makeKeyAndOrderFront: nil];

  /* A preferences window that exists when the menu is first attached
     (plugins-themes-Adwaita#4), resizable as a main window. */
  _launchPrefsWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect (960, 420, 260, 100)
                                                   styleMask: (NSTitledWindowMask | NSClosableWindowMask
                                                               | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
  [_launchPrefsWindow setTitle: @"Preferences"];
  [_launchPrefsWindow setReleasedWhenClosed: NO];
  [_windows addObject: _launchPrefsWindow];
  RELEASE (_launchPrefsWindow);
  [_launchPrefsWindow orderFront: nil];

  _toolbarWindow = [self windowWithFrame: NSMakeRect (40, 560, 400, 120) title: @"QuirkProbe Toolbar"];
  toolbar = [[NSToolbar alloc] initWithIdentifier: @"QuirkProbe"];
  [toolbar setDelegate: self];
  [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
  [_toolbarWindow setToolbar: toolbar];
  RELEASE (toolbar);
  [_toolbarWindow orderFront: nil];

  /* Two tables: one left at GNUstep's default grid setting, one whose app
     asked for horizontal grid lines. */
  _tableWindow = [self windowWithFrame: NSMakeRect (960, 40, 300, 330) title: @"QuirkProbe Tables"];
  view = [_tableWindow contentView];
  _defaultGridTable = [self addTableAt: NSMakeRect (20, 170, 260, 140) inView: view];
  _explicitGridTable = [self addTableAt: NSMakeRect (20, 10, 260, 140) inView: view];
  [_explicitGridTable setGridStyleMask: NSTableViewSolidHorizontalGridLineMask];
  [_tableWindow orderFront: nil];

  /* A window with every window button, for the header bar checks. */
  if (QuirkProbeDrawsDecorations ())
    {
      _headerWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect (480, 200, 420, 160)
                                                  styleMask: (NSTitledWindowMask | NSClosableWindowMask
                                                              | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
      [_headerWindow setTitle: @"QuirkProbe Header Bar"];
      [_headerWindow setReleasedWhenClosed: NO];
      [_windows addObject: _headerWindow];
      RELEASE (_headerWindow);
      [_headerWindow orderFront: nil];
    }
}

#pragma mark Checks

/* The theme's GSThemeDomain (interface styles, backend defaults) reached
   the app: it was in the bundle's Info-gnustep.plist, which a clean build
   once replaced with gnustep-make's generated one (#45). */
- (void) checkThemeDomain
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *domain = [defaults volatileDomainForName: @"GSThemeDomain"];
  BOOL searched = [[defaults searchList] containsObject: @"GSThemeDomain"];
  NSString *style = [domain objectForKey: @"NSMenuInterfaceStyle"];
  NSString *detail = [NSString stringWithFormat: @"in search list %d, %lu keys, NSMenuInterfaceStyle %@",
    searched, (unsigned long)[domain count], style];

  if (searched && [style isEqualToString: @"NSWindows95InterfaceStyle"]
    && [domain objectForKey: @"GSBackHandlesWindowDecorations"] != nil)
    {
      [self pass: @"theme-domain" detail: detail];
    }
  else
    {
      [self fail: @"theme-domain" detail: detail];
    }
}

/* Text about as wide as GTK 4's at GNOME's font (#23): the widths GTK 4.18
   gives these strings at Cantarell 11 with GNOME's settings (unhinted
   metrics), measured on 2026-10-07 with a GtkLabel's Pango layout. GNUstep
   measures them with -sizeWithAttributes: and an NSLayoutManager, both of
   which use screen fonts. Before #23 a screen font was a whole pixel size
   up (15 for 14.67) and the strings came out 3.1% and 2.7% wider (296 and
   423). The theme keeps libs-back's hinted metrics, whole-pixel advances,
   which come to 283 and 407: 1.4% and 1.1% narrower than GTK's. */
- (void) checkTextWidth
{
  NSFont *font = [NSFont systemFontOfSize: 0];
  NSString *strings[2] = {
    @"The quick brown fox jumps over the lazy dog",
    @"Are you sure you want to discard the changes to this document?" };
  CGFloat gtk[2] = { 287.094, 411.679 };
  NSMutableString *detail = [NSMutableString string];
  BOOL ok = YES;
  int i;

  if (font == nil || [[font familyName] isEqualToString: @"Cantarell"] == NO
    || fabs ([font pointSize] - 11.0 * 96.0 / 72.0) > 0.01)
    {
      [self skip: @"text-width" detail: [NSString stringWithFormat:
        @"needs Cantarell at 14.667 (have %@ %.3f)", [font fontName], [font pointSize]]];
      return;
    }
  for (i = 0; i < 2; i++)
    {
      NSDictionary *attrs = [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName];
      NSTextStorage *storage = [[NSTextStorage alloc] initWithString: strings[i] attributes: attrs];
      NSLayoutManager *layout = [NSLayoutManager new];
      NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize: NSMakeSize (10000, 1000)];
      CGFloat drawn = [strings[i] sizeWithAttributes: attrs].width;
      CGFloat laidOut;

      [container setLineFragmentPadding: 0];
      [layout addTextContainer: container];
      [storage addLayoutManager: layout];
      [layout glyphRangeForTextContainer: container];
      laidOut = NSWidth ([layout usedRectForTextContainer: container]);
      /* Within 2%: hinted advances, but not the screen font's larger size. */
      if (fabs (drawn / gtk[i] - 1.0) > 0.02 || fabs (laidOut / gtk[i] - 1.0) > 0.02)
        {
          ok = NO;
        }
      [detail appendFormat: @"%s%.3f and %.3f for GTK's %.3f", i ? "; " : "", drawn, laidOut, gtk[i]];
      [container release];
      [layout release];
      [storage release];
    }
  if (ok)
    {
      [self pass: @"text-width" detail: detail];
    }
  else
    {
      [self fail: @"text-width" detail: detail];
    }
}

/* GNOME's text-scaling-factor (Large Text; -ProbeTextScale is what the run
   set in the probe's GSettings): the interface and monospace fonts are
   Cantarell 11 and Noto Sans Mono 11 at 96 dpi times the factor, the menu
   rows follow the larger text, and compact metrics (windows laid out at
   GNUstep's sizes) keep GNUstep's 12pt (#53). */
- (void) checkTextScaling
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  CGFloat factor = [defaults floatForKey: @"ProbeTextScale"];
  CGFloat expected;
  NSFont *font = [NSFont systemFontOfSize: 0];
  NSFont *fixed = [NSFont userFixedPitchFontOfSize: 0];
  CGFloat menuItem = [defaults floatForKey: @"GSMenuItemHeight"];
  CGFloat compactSize = -1.0;
  id theme = [GSTheme theme];
  id settings = nil;
  NSString *detail;
  BOOL ok;

  if (factor <= 0.0)
    {
      factor = 1.0;
    }
  expected = 11.0 * 96.0 / 72.0 * factor;
  if ([theme respondsToSelector: @selector(settings)])
    {
      settings = [theme performSelector: @selector(settings)];
    }
  if ([settings respondsToSelector: @selector(compactInterfaceFontSize)])
    {
      CGFloat (*sizeIMP)(id, SEL) = (CGFloat (*)(id, SEL))[settings methodForSelector: @selector(compactInterfaceFontSize)];

      compactSize = sizeIMP (settings, @selector(compactInterfaceFontSize));
    }
  if (font == nil || [[font familyName] isEqualToString: @"Cantarell"] == NO)
    {
      [self skip: @"text-scaling" detail: [NSString stringWithFormat:
        @"needs Cantarell (have %@)", [font fontName]]];
      return;
    }
  ok = (fabs ([font pointSize] - expected) < 0.01
    && fixed != nil && fabs ([fixed pointSize] - expected) < 0.01
    && fabs (menuItem - ceil (MAX (32.0, expected + 19.0))) < 0.5
    && fabs (compactSize - 12.0) < 0.01);
  detail = [NSString stringWithFormat:
    @"factor %.2f: interface %.3f, monospace %@ %.3f (want %.3f); menu item %.0f (want %.0f); compact %.3f (want 12)",
    factor, [font pointSize], [fixed familyName], [fixed pointSize], expected,
    menuItem, ceil (MAX (32.0, expected + 19.0)), compactSize];
  if (ok)
    {
      [self pass: @"text-scaling" detail: detail];
    }
  else
    {
      [self fail: @"text-scaling" detail: detail];
    }
}

/* +imageNamed: calls for the images the theme classifies buttons by,
   counted while -checkImageFreeButton runs (#50). */
static IMP QuirkProbeImageNamedIMP = NULL;
static NSUInteger QuirkProbeClassifyLookups = 0;

static id
QuirkProbeCountingImageNamed (id receiver, SEL selector, NSString *name)
{
  static NSSet *names = nil;

  if (names == nil)
    {
      names = [[NSSet alloc] initWithObjects: @"NSSwitch", @"NSHighlightedSwitch",
        @"NSRadioButton", @"NSHighlightedRadioButton", @"common_ret",
        @"common_retH", @"GSSearch", @"GSStop", nil];
    }
  if ([names containsObject: name])
    {
      QuirkProbeClassifyLookups++;
    }
  return ((id (*)(id, SEL, NSString *))QuirkProbeImageNamedIMP) (receiver, selector, name);
}

/* A button with a title and no image is sized and drawn without the theme
   looking up the checkbox, radio, return-key, search or stop images: the
   first lookup of each loads it, and they cost about 120ms on the first
   button an app drew (#50). */
- (void) checkImageFreeButton
{
  Method method = class_getClassMethod ([NSImage class], @selector(imageNamed:));
  NSWindow *window = [self windowWithFrame: NSMakeRect (0, 0, 200, 60) title: @"Image-free button"];
  NSButton *button;
  NSUInteger lookups;

  QuirkProbeClassifyLookups = 0;
  QuirkProbeImageNamedIMP = method_setImplementation (method, (IMP)QuirkProbeCountingImageNamed);
  button = [[NSButton alloc] initWithFrame: NSMakeRect (20, 13, 120, 34)];
  [button setTitle: @"Plain"];
  [[window contentView] addSubview: button];
  [[button cell] cellSize];
  QuirkProbeRender (button);
  method_setImplementation (method, QuirkProbeImageNamedIMP);
  lookups = QuirkProbeClassifyLookups;
  [button release];
  [window orderOut: nil];

  if (lookups == 0)
    {
      [self pass: @"image-free-button" detail: @"sized and drawn with no classification image looked up"];
    }
  else
    {
      [self fail: @"image-free-button" detail: [NSString stringWithFormat:
        @"%lu lookups of classification images", (unsigned long)lookups]];
    }
}

- (void) checkSizedButtons
{
  NSEnumerator *enumerator = [_sizedButtons objectEnumerator];
  NSArray *pair;

  while ((pair = [enumerator nextObject]) != nil)
    {
      NSButton *sized = [pair objectAtIndex: 0];
      QuirkProbeInk sizedInk = QuirkProbeTextInk (sized);
      QuirkProbeInk wideInk = QuirkProbeTextInk ([pair objectAtIndex: 1]);
      NSString *ident = [NSString stringWithFormat: @"sizeToFit-title \"%@\"", [sized title]];
      NSString *detail = [NSString stringWithFormat: @"title ink %ldx%ld at %gpt wide, %ldx%ld with room to spare",
        (long)sizedInk.width, (long)sizedInk.height, NSWidth ([sized frame]),
        (long)wideInk.width, (long)wideInk.height];

      if (wideInk.count == 0)
        {
          [self fail: ident detail: @"reference button drew no title"];
        }
      else if (sizedInk.width + 1 >= wideInk.width
        && ABS (sizedInk.height - wideInk.height) <= 1)
        {
          [self pass: ident detail: detail];
        }
      else
        {
          [self fail: ident detail: [detail stringByAppendingString: @" (clipped or wrapped)"]];
        }
    }
}

/* A button narrower than the theme's padding wants still draws its whole
   title when there's room for it. */
- (void) checkFixedButtons
{
  NSEnumerator *enumerator = [_fixedButtons objectEnumerator];
  NSArray *pair;

  while ((pair = [enumerator nextObject]) != nil)
    {
      NSButton *fixed = [pair objectAtIndex: 0];
      QuirkProbeInk fixedInk = QuirkProbeTextInk (fixed);
      QuirkProbeInk wideInk = QuirkProbeTextInk ([pair objectAtIndex: 1]);
      NSString *ident = [NSString stringWithFormat: @"fixed-width-title \"%@\"", [fixed title]];
      NSString *detail = [NSString stringWithFormat: @"title ink %ldx%ld in %gx%gpt, %ldx%ld with room to spare",
        (long)fixedInk.width, (long)fixedInk.height, NSWidth ([fixed frame]), NSHeight ([fixed frame]),
        (long)wideInk.width, (long)wideInk.height];

      if (wideInk.count == 0)
        {
          [self fail: ident detail: @"reference button drew no title"];
        }
      else if (fixedInk.width + 1 >= wideInk.width
        && ABS (fixedInk.height - wideInk.height) <= 1)
        {
          [self pass: ident detail: detail];
        }
      else
        {
          [self fail: ident detail: [detail stringByAppendingString: @" (clipped)"]];
        }
    }
}

static BOOL
QuirkProbeIsRed (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return red > 180 && green < 80 && blue < 80;
}

/* A glyph's antialiased strokes on a control's fill. */
static BOOL
QuirkProbeIsGlyphInk (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return (red + green + blue) < 600;
}

/* Glyph ink in each half of a stepper, from the theme's own button rects
   (as NSStepperCell hit-tests them), in the render's top-left pixels. */
- (void) measureStepper: (NSStepper *)stepper up: (QuirkProbeInk *)up down: (QuirkProbeInk *)down
{
  GSTheme *theme = [GSTheme theme];
  NSRect bounds = [stepper bounds];
  NSBitmapImageRep *rep = QuirkProbeRender (stepper);
  NSRect upRect = [theme stepperUpButtonRectWithFrame: bounds];
  NSRect downRect = [theme stepperDownButtonRectWithFrame: bounds];

  if ([stepper isFlipped] == NO)
    {
      upRect.origin.y = NSHeight (bounds) - NSMaxY (upRect);
      downRect.origin.y = NSHeight (bounds) - NSMaxY (downRect);
    }
  *up = QuirkProbeMeasureIn (rep, QuirkProbeIsGlyphInk, upRect);
  *down = QuirkProbeMeasureIn (rep, QuirkProbeIsGlyphInk, downRect);
}

- (void) checkSteppers
{
  GSTheme *theme = [GSTheme theme];
  NSRect bounds = [_tallStepper bounds];
  NSRect upRect = [theme stepperUpButtonRectWithFrame: bounds];
  NSRect downRect = [theme stepperDownButtonRectWithFrame: bounds];
  QuirkProbeInk up, down;
  NSString *detail;
  CGFloat middle = NSWidth (bounds) / 2.0;

  /* A Cocoa-sized stepper: an up half above a down half, each with a glyph
     in the middle. */
  [self measureStepper: _tallStepper up: &up down: &down];
  detail = [NSString stringWithFormat: @"%gx%g: up half %@ (ink %ldx%ld at x %ld), down half %@ (ink %ldx%ld at x %ld)",
    NSWidth (bounds), NSHeight (bounds), NSStringFromRect (upRect),
    (long)up.width, (long)up.height, (long)up.minX, NSStringFromRect (downRect),
    (long)down.width, (long)down.height, (long)down.minX];
  if (NSMinY (upRect) >= NSMaxY (downRect) && NSWidth (upRect) == NSWidth (bounds)
    && up.count > 0 && down.count > 0
    && ABS (up.minX + up.width / 2.0 - middle) <= 1.5
    && ABS (down.minX + down.width / 2.0 - middle) <= 1.5)
    {
      [self pass: @"stepper-vertical" detail: detail];
    }
  else
    {
      [self fail: @"stepper-vertical" detail: detail];
    }

  /* The halves' glyphs are libadwaita's vertical spin button's: + above −,
     not chevrons. A + is as tall as it is wide; a − is a 2px stroke. */
  detail = [NSString stringWithFormat: @"up glyph %ldx%ld, down glyph %ldx%ld",
    (long)up.width, (long)up.height, (long)down.width, (long)down.height];
  if (up.count > 0 && down.count > 0 && up.height >= 6 && labs ((long)up.height - (long)up.width) <= 1
    && down.height <= 2 && down.width >= 6)
    {
      [self pass: @"stepper-plus-minus" detail: detail];
    }
  else
    {
      [self fail: @"stepper-plus-minus" detail: detail];
    }

  /* At its maximum, the up half is dimmed, as GTK's spin button. */
  [self measureStepper: _maxedStepper up: &up down: &down];
  detail = [NSString stringWithFormat: @"at the maximum: darkest up glyph pixel %lu, down %lu (r+g+b)",
    (unsigned long)up.darkest, (unsigned long)down.darkest];
  if (down.count > 0 && (up.count == 0 || up.darkest > down.darkest + 100))
    {
      [self pass: @"stepper-dims-at-limit" detail: detail];
    }
  else
    {
      [self fail: @"stepper-dims-at-limit" detail: detail];
    }

  /* A wide stepper keeps − and + side by side. */
  bounds = [_wideStepper bounds];
  upRect = [theme stepperUpButtonRectWithFrame: bounds];
  downRect = [theme stepperDownButtonRectWithFrame: bounds];
  [self measureStepper: _wideStepper up: &up down: &down];
  detail = [NSString stringWithFormat: @"%gx%g: up %@ (ink %ldx%ld), down %@ (ink %ldx%ld)",
    NSWidth (bounds), NSHeight (bounds), NSStringFromRect (upRect), (long)up.width, (long)up.height,
    NSStringFromRect (downRect), (long)down.width, (long)down.height];
  if (NSMinX (upRect) >= NSMaxX (downRect) && up.count > 0 && down.count > 0
    && up.height > down.height)
    {
      [self pass: @"stepper-wide-horizontal" detail: detail];
    }
  else
    {
      [self fail: @"stepper-wide-horizontal" detail: detail];
    }
}

/* A colour well as GTK's colour button: the colour in a rounded swatch inset
   in a flat button, not NeXT's dark bevel. */
- (void) checkColorWell
{
  NSBitmapImageRep *rep = QuirkProbeRender (_colorWell);
  NSRect bounds = [_colorWell bounds];
  QuirkProbeInk swatch = QuirkProbeMeasure (rep, QuirkProbeIsRed);
  QuirkProbeInk corner, edge;
  NSString *detail;

  if (swatch.count == 0)
    {
      [self fail: @"colorwell-adwaita" detail: @"no swatch drawn"];
      return;
    }
  corner = QuirkProbeMeasureIn (rep, QuirkProbeIsRed, NSMakeRect (swatch.minX, swatch.minY, 2, 2));
  edge = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (0, 0, swatch.minX, NSHeight (bounds)));
  detail = [NSString stringWithFormat: @"swatch %ldx%ld at %ld,%ld in %gx%g; %lu red pixels in its corner; "
    @"darkest pixel left of it %lu",
    (long)swatch.width, (long)swatch.height, (long)swatch.minX, (long)swatch.minY,
    NSWidth (bounds), NSHeight (bounds), (unsigned long)corner.count, (unsigned long)edge.darkest];
  if (swatch.minX >= 4 && swatch.minY >= 3 && corner.count < 4 && edge.darkest > 450)
    {
      [self pass: @"colorwell-adwaita" detail: detail];
    }
  else
    {
      [self fail: @"colorwell-adwaita" detail: detail];
    }
}

/* The swatch's edge as libadwaita's: no ring round a dark colour (the
   pixel just outside a red swatch is the button's), and a faint one, the
   foreground at 10%, inside a light one (white: 5-40 below the white). */
- (void) checkColorWellEdge
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 200, 70) title: @"Probe Swatch Edge"];
  NSColorWell *red = AUTORELEASE ([[NSColorWell alloc] initWithFrame: NSMakeRect (10, 20, 64, 34)]);
  NSColorWell *white = AUTORELEASE ([[NSColorWell alloc] initWithFrame: NSMakeRect (100, 20, 64, 34)]);
  NSBitmapImageRep *rep;
  QuirkProbeInk swatch;
  NSUInteger outside[3], button[3], ring[3], inside[3];
  NSInteger midY;
  long redStep, whiteStep;
  NSString *detail;

  [red setColor: [NSColor colorWithCalibratedRed: 0.9 green: 0.1 blue: 0.1 alpha: 1.0]];
  [white setColor: [NSColor colorWithCalibratedWhite: 1.0 alpha: 1.0]];
  [[window contentView] addSubview: red];
  [[window contentView] addSubview: white];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (red);
  midY = [rep pixelsHigh] / 2;
  swatch = QuirkProbeMeasure (rep, QuirkProbeIsRed);
  QuirkProbePixelAt (rep, MAX (0, swatch.minX - 1), midY, outside);
  QuirkProbePixelAt (rep, MAX (0, swatch.minX - 3), midY, button);
  redStep = labs ((long)outside[0] - (long)button[0]);
  /* The white swatch, the same shape: its first column (where the red
     ink starts, with no ring round the red), against its middle. */
  rep = QuirkProbeRender (white);
  QuirkProbePixelAt (rep, swatch.minX, midY, ring);
  QuirkProbePixelAt (rep, swatch.minX + swatch.width / 2, midY, inside);
  whiteStep = (long)inside[0] - (long)ring[0];
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"red: %@ just outside, button %@; white: %@ at its edge, %@ inside",
    QuirkProbeHex (outside), QuirkProbeHex (button), QuirkProbeHex (ring), QuirkProbeHex (inside)];
  if (swatch.count > 0 && redStep <= 6 && whiteStep >= 5 && whiteStep <= 40)
    {
      [self pass: @"colorwell-swatch-edge" detail: detail];
    }
  else
    {
      [self fail: @"colorwell-swatch-edge" detail: detail];
    }
}

/* A toolbar's row as libadwaita's: 46pt for icons or labels alone, sized
   to the content for icons with labels, keeping a 34pt button view, with
   spaces and separators not setting the height (plugins-themes-Adwaita#8). */
- (NSString *) measureToolbarRowMode: (NSToolbarDisplayMode)mode
                                size: (NSToolbarSizeMode)sizeMode
                         emptyLabels: (BOOL)emptyLabels
                              height: (CGFloat *)height
                                  ok: (BOOL *)ok
{
  /* Toolbars don't retain their delegate; the windows live on. */
  QuirkProbeRowToolbarDelegate *delegate = [QuirkProbeRowToolbarDelegate new];
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 300, 360, 120) title: @"QuirkProbe Toolbar Row"];
  NSString *identifier = [NSString stringWithFormat: @"QuirkProbeRow%d%d%d", (int)mode, (int)sizeMode, (int)emptyLabels];
  NSToolbar *toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: identifier]);
  NSView *frameView, *toolbarView, *buttonView;
  NSRect toolbarFrame, contentFrame;
  NSSize imageSize;
  BOOL viewShown;

  delegate->_emptyLabels = emptyLabels;
  [toolbar setDelegate: delegate];
  [toolbar setDisplayMode: mode];
  [toolbar setSizeMode: sizeMode];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  toolbarView = QuirkProbeFindViewOfClass (frameView, NSClassFromString (@"GSToolbarView"));
  buttonView = [[[toolbar items] objectAtIndex: 2] view];
  imageSize = [[[[toolbar items] objectAtIndex: 0] image] size];
  toolbarFrame = [frameView convertRect: [toolbarView bounds] fromView: toolbarView];
  contentFrame = [frameView convertRect: [[window contentView] bounds] fromView: [window contentView]];
  viewShown = ([buttonView window] == window);
  *height = NSHeight (toolbarFrame);
  *ok = (toolbarView != nil && NSMaxY (contentFrame) <= NSMinY (toolbarFrame) + 0.5
    && (viewShown || mode == NSToolbarDisplayModeLabelOnly)
    && imageSize.width <= (sizeMode == NSToolbarSizeModeSmall ? 16 : 24));
  [window orderOut: nil];
  return [NSString stringWithFormat: @"%gpt%@, image %gx%g", NSHeight (toolbarFrame),
    viewShown ? @"" : @" (no button view)", imageSize.width, imageSize.height];
}

- (void) checkToolbarRowHeight
{
  CGFloat iconOnly, emptyLabels, labelOnly, small, labelled;
  BOOL ok1, ok2, ok3, ok4, ok5;
  NSString *detail = [NSString stringWithFormat: @"icon only %@; icon and label, empty labels %@; label only %@; "
    @"small icon only %@; icon and label %@",
    [self measureToolbarRowMode: NSToolbarDisplayModeIconOnly size: NSToolbarSizeModeRegular emptyLabels: NO
                         height: &iconOnly ok: &ok1],
    [self measureToolbarRowMode: NSToolbarDisplayModeIconAndLabel size: NSToolbarSizeModeRegular emptyLabels: YES
                         height: &emptyLabels ok: &ok2],
    [self measureToolbarRowMode: NSToolbarDisplayModeLabelOnly size: NSToolbarSizeModeRegular emptyLabels: NO
                         height: &labelOnly ok: &ok3],
    [self measureToolbarRowMode: NSToolbarDisplayModeIconOnly size: NSToolbarSizeModeSmall emptyLabels: NO
                         height: &small ok: &ok4],
    [self measureToolbarRowMode: NSToolbarDisplayModeIconAndLabel size: NSToolbarSizeModeRegular emptyLabels: NO
                         height: &labelled ok: &ok5]];

  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"GnomeThemeMetrics"] isEqualToString: @"compact"])
    {
      [self skip: @"toolbar-row-height" detail: @"compact metrics keep libs-gui's toolbar layout"];
    }
  else if (ok1 && ok2 && ok3 && ok4 && ok5
    && iconOnly >= 46 && iconOnly <= 48 && emptyLabels >= 46 && emptyLabels <= 48
    && labelOnly >= 46 && labelOnly <= 48 && small >= 46 && small <= 48
    && labelled > 48 && labelled < 62)
    {
      [self pass: @"toolbar-row-height" detail: detail];
    }
  else
    {
      [self fail: @"toolbar-row-height" detail: detail];
    }
}

/* A view item keeps its fixed width through layouts: libs-gui sets each
   view to its slot less 10pt insets, and with the theme's narrower slots
   views lost 14pt a layout down to nothing (plugins-themes-Adwaita#9). */
- (void) checkToolbarViewItemWidth
{
  /* Toolbars don't retain their delegate; the windows live on. */
  QuirkProbeViewItemToolbarDelegate *delegate = [QuirkProbeViewItemToolbarDelegate new];
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 300, 400, 120) title: @"QuirkProbe Toolbar Views"];
  NSToolbar *toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeViewItems"]);
  NSMutableString *detail = [NSMutableString string];
  BOOL ok = YES;
  NSEnumerator *enumerator;
  NSToolbarItem *item;
  int i;

  [toolbar setDelegate: delegate];
  [toolbar setDisplayMode: NSToolbarDisplayModeIconOnly];
  [toolbar setSizeMode: NSToolbarSizeModeRegular];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  /* Each resize lays the toolbar out again. */
  for (i = 0; i < 4; i++)
    {
      NSRect frame = [window frame];

      frame.size.width += (i % 2) ? -20 : 20;
      [window setFrame: frame display: YES];
    }
  enumerator = [[toolbar items] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      NSView *view = [item view];
      NSView *slot = [view superview];

      if (view == nil)
        {
          continue;
        }
      [detail appendFormat: @"%@%@ %gpt in a %gpt slot", [detail length] ? @"; " : @"", [item itemIdentifier],
        NSWidth ([view frame]), NSWidth ([slot frame])];
      ok = ok && slot != nil && NSWidth ([view frame]) == [item minSize].width
        && NSWidth ([slot frame]) >= [item minSize].width;
    }
  [window orderOut: nil];
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"GnomeThemeMetrics"] isEqualToString: @"compact"])
    {
      [self skip: @"toolbar-view-item-width" detail: @"compact metrics keep libs-gui's toolbar layout"];
    }
  else if (ok)
    {
      [self pass: @"toolbar-view-item-width" detail: detail];
    }
  else
    {
      [self fail: @"toolbar-view-item-width" detail: detail];
    }
}

/* A vertical menu as libadwaita's popover menus: a separator is one
   hairline at 15% of the text colour (plugins-themes-Adwaita#11: two rows
   of mid grey), and shortcuts end 12pt inside the row, 16pt from the
   cell's edge (the row is inset 4pt), with submenu arrows' boxes (#10:
   flush against the edge). */
/* An inline button row (#42): three items declared as one group share a
   row, side by side, and a click in each lands on it; the menu is three
   rows high, not five. */
- (void) checkInlineMenuRow
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"View"]);
  NSArray *titles = [NSArray arrayWithObjects: @"Before", @"Zoom Out", @"110%", @"Zoom In", @"After", nil];
  NSWindow *window;
  NSMenuView *menuView;
  NSRect rects[5];
  NSMutableArray *problems = [NSMutableArray array];
  NSInteger i;
  CGFloat rowHeight;
  QuirkProbeInk ink;

  for (i = 0; i < 5; i++)
    {
      NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle: [titles objectAtIndex: i]
                                                       action: @selector(description)
                                                keyEquivalent: @""];

      [item setTarget: self];
      if (i >= 1 && i <= 3)
        {
          [item setRepresentedObject: @"GnomeThemeInlineGroup:zoom"];
        }
    }
  menuView = AUTORELEASE ([[NSMenuView alloc] initWithFrame: NSMakeRect (0, 0, 200, 100)]);
  [menuView setMenu: menu];
  [menuView sizeToFit];
  window = [self windowWithFrame: NSMakeRect (40, 200, NSWidth ([menuView frame]) + 40, NSHeight ([menuView frame]) + 40)
                           title: @"QuirkProbe Inline Row"];
  [menuView setFrameOrigin: NSMakePoint (20, 20)];
  [[window contentView] addSubview: menuView];
  [window orderFront: nil];
  [window display];
  for (i = 0; i < 5; i++)
    {
      rects[i] = [menuView rectOfItemAtIndex: i];
    }
  rowHeight = NSHeight (rects[0]);
  for (i = 1; i <= 3; i++)
    {
      NSPoint middle = NSMakePoint (NSMidX (rects[i]), NSMidY (rects[i]));

      if (NSMinY (rects[i]) != NSMinY (rects[1]) || NSHeight (rects[i]) != rowHeight)
        {
          [problems addObject: [NSString stringWithFormat: @"item %ld not on the row: %@", (long)i,
                                         NSStringFromRect (rects[i])]];
        }
      if (i > 1 && NSMinX (rects[i]) < NSMaxX (rects[i - 1]))
        {
          [problems addObject: [NSString stringWithFormat: @"items %ld and %ld overlap", (long)(i - 1), (long)i]];
        }
      if ([menuView indexOfItemAtPoint: middle] != i)
        {
          [problems addObject: [NSString stringWithFormat: @"a click on item %ld finds %ld", (long)i,
                                         (long)[menuView indexOfItemAtPoint: middle]]];
        }
    }
  /* Three rows and the menu's padding, under four rows. */
  if (NSHeight ([menuView frame]) >= 4 * rowHeight)
    {
      [problems addObject: [NSString stringWithFormat: @"menu %g high for rows of %g",
                                     NSHeight ([menuView frame]), rowHeight]];
    }
  /* The middle item's title is drawn in its own segment. */
  {
    NSBitmapImageRep *rep = QuirkProbeRender (menuView);
    NSRect area = rects[2];

    if ([menuView isFlipped] == NO)
      {
        area.origin.y = NSHeight ([menuView bounds]) - NSMaxY (area);
      }
    ink = QuirkProbeMeasureIn (rep, QuirkProbeIsTextInk, area);
    if (ink.count < 20)
      {
        [problems addObject: [NSString stringWithFormat: @"no title in the middle segment %@", NSStringFromRect (area)]];
      }
  }
  [window orderOut: nil];
  if ([problems count] == 0)
    {
      [self pass: @"menu-inline-row"
          detail: [NSString stringWithFormat: @"%@ | %@ | %@", NSStringFromRect (rects[1]), NSStringFromRect (rects[2]),
                            NSStringFromRect (rects[3])]];
    }
  else
    {
      [self fail: @"menu-inline-row" detail: [problems componentsJoinedByString: @"; "]];
    }
}

/* A text field whose background the app chose (Gorm's CustomView palette
   item: dark gray, white bold text, not editable) fills with that colour;
   a plain read-only field keeps the theme's (#27). */
static BOOL
QuirkProbeIsDarkFill (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return red + green + blue < 330;
}

static BOOL
QuirkProbeIsWhiteText (NSUInteger red, NSUInteger green, NSUInteger blue)
{
  return red + green + blue > 720;
}

- (void) checkCustomBackgroundField
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 500, 280, 80) title: @"QuirkProbe Fields"];
  NSView *view = [window contentView];
  NSTextField *custom = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (10, 20, 120, 40)]);
  NSTextField *plain = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (150, 20, 120, 40)]);
  NSBitmapImageRep *rep;
  NSRect middle;
  QuirkProbeInk dark, white, plainDark;
  NSString *detail;

  [custom setBackgroundColor: [NSColor darkGrayColor]];
  [custom setTextColor: [NSColor whiteColor]];
  [custom setDrawsBackground: YES];
  [custom setAlignment: NSCenterTextAlignment];
  [custom setFont: [NSFont boldSystemFontOfSize: 0]];
  [custom setEditable: NO];
  [custom setSelectable: NO];
  [custom setStringValue: @"CustomView"];
  [plain setEditable: NO];
  [plain setSelectable: NO];
  [plain setStringValue: @"Plain"];
  [view addSubview: custom];
  [view addSubview: plain];
  [window orderFront: nil];
  [window display];

  rep = QuirkProbeRender (custom);
  middle = NSMakeRect (10, 6, [rep pixelsWide] - 20, [rep pixelsHigh] - 12);
  dark = QuirkProbeMeasureIn (rep, QuirkProbeIsDarkFill, middle);
  white = QuirkProbeMeasureIn (rep, QuirkProbeIsWhiteText, middle);
  rep = QuirkProbeRender (plain);
  plainDark = QuirkProbeMeasureIn (rep, QuirkProbeIsDarkFill,
                                   NSMakeRect (10, 6, [rep pixelsWide] - 20, [rep pixelsHigh] - 12));
  detail = [NSString stringWithFormat: @"custom: %lu dark and %lu white pixels of %ld; plain: %lu dark",
                     (unsigned long)dark.count, (unsigned long)white.count,
                     (long)(NSWidth (middle) * NSHeight (middle)), (unsigned long)plainDark.count];
  if (dark.count > NSWidth (middle) * NSHeight (middle) / 2 && white.count > 20
    && plainDark.count < NSWidth (middle) * NSHeight (middle) / 4)
    {
      [self pass: @"text-field-custom-background" detail: detail];
    }
  else
    {
      [self fail: @"text-field-custom-background" detail: detail];
    }
  [window orderOut: nil];
}

/* A field on a half pixel (an app's layout put it at y = 100.5) keeps its
   text on whole pixels while typing. The field editor's clip view offsets
   its bounds half a pixel to put the text on the pixel grid; a scroll while
   typing passed through -[NSClipView constrainScrollPoint:], which rounds
   in the clip view's current coordinates and so swapped that offset for
   the other half pixel: the text moved up and down a row as it was typed. */
- (void) checkFieldEditorOnPixels
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 500, 320, 80) title: @"QuirkProbe Field Editor"];
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (10, 20.5, 300, 28)]);
  NSString *typed = @"Tyly gjpq";
  NSMutableString *offsets = [NSMutableString string];
  NSUInteger i, offGrid = 0;
  NSText *editor;
  NSString *detail;

  [field setEditable: YES];
  [field setFont: [NSFont systemFontOfSize: 14]];
  [[window contentView] addSubview: field];
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: field];
  [window display];
  editor = [field currentEditor];
  for (i = 0; editor != nil && i < [typed length]; i++)
    {
      NSView *document = editor;
      NSPoint origin;
      CGFloat fraction;

      [editor insertText: [typed substringWithRange: NSMakeRange (i, 1)]];
      [window display];
      /* Where the text view's top edge lands in the window. */
      origin = [document convertPoint: NSMakePoint (0, 0) toView: nil];
      fraction = origin.y - floor (origin.y);
      [offsets appendFormat: @"%@%g", i ? @" " : @"", fraction];
      if (fraction != 0.0)
        {
          offGrid++;
        }
    }
  detail = [NSString stringWithFormat: @"text view's fraction of a pixel after each of %lu keys: %@",
                     (unsigned long)[typed length], offsets];
  if (editor != nil && offGrid == 0)
    {
      [self pass: @"field-editor-on-pixels" detail: detail];
    }
  else
    {
      [self fail: @"field-editor-on-pixels"
          detail: editor ? detail : @"the field didn't start editing"];
    }
  [window makeFirstResponder: nil];
  [window orderOut: nil];
}

/* A secure field's dots as GTK's: ● (GtkText's invisible character), at
   rest and while typing; libs-gui's • is about half as tall. */
- (void) checkSecureBullets
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 400, 320, 80) title: @"QuirkProbe Secure Field"];
  NSSecureTextField *field = AUTORELEASE ([[NSSecureTextField alloc] initWithFrame: NSMakeRect (10, 20, 300, 34)]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  QuirkProbeInk rest, typing;
  NSText *editor;
  NSString *detail;

  [field setEditable: YES];
  [field setStringValue: @"secret"];
  [[window contentView] addSubview: field];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (field);
  QuirkProbePixelAt (rep, 200, 17, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  rest = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (4, 4, 150, 26));
  /* The first dot alone: past the last one, the caret. */
  rest = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (rest.minX, 4, 5, 26));
  [field setStringValue: @""];
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: field];
  editor = [field currentEditor];
  [editor insertText: @"secret"];
  [window display];
  rep = QuirkProbeRender (field);
  typing = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (4, 4, 150, 26));
  typing = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (typing.minX, 4, 5, 26));
  QuirkProbeInkBackground = 750;
  [window makeFirstResponder: nil];
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"first dot %ld high at rest, %ld while typing%@",
    (long)rest.height, (long)typing.height,
    editor ? @"" : @" (the field didn't start editing)"];
  if (editor != nil && rest.height >= 6 && typing.height >= 6)
    {
      [self pass: @"secure-bullets" detail: detail];
    }
  else
    {
      [self fail: @"secure-bullets" detail: detail];
    }
}

/* Shortcut labels as GTK writes them (gtk_accelerator_get_label): Shift,
   Ctrl, Alt, then the key; an uppercase key equivalent means Shift (#41). */
- (void) checkShortcutLabels
{
  NSArray *cases = [NSArray arrayWithObjects:
    [NSArray arrayWithObjects: @"o", [NSNumber numberWithUnsignedInteger: NSCommandKeyMask], @"Ctrl+O", nil],
    [NSArray arrayWithObjects: @"O", [NSNumber numberWithUnsignedInteger: NSCommandKeyMask], @"Shift+Ctrl+O", nil],
    [NSArray arrayWithObjects: @"s", [NSNumber numberWithUnsignedInteger: NSCommandKeyMask | NSShiftKeyMask],
              @"Shift+Ctrl+S", nil],
    [NSArray arrayWithObjects: @"s",
              [NSNumber numberWithUnsignedInteger: NSCommandKeyMask | NSShiftKeyMask | NSAlternateKeyMask],
              @"Shift+Ctrl+Alt+S", nil],
    [NSArray arrayWithObjects: @"1", [NSNumber numberWithUnsignedInteger: NSCommandKeyMask], @"Ctrl+1", nil],
    [NSArray arrayWithObjects: @"?", [NSNumber numberWithUnsignedInteger: NSCommandKeyMask], @"Ctrl+?", nil],
    nil];
  NSMutableArray *wrong = [NSMutableArray array];
  NSEnumerator *e = [cases objectEnumerator];
  NSArray *c;

  while ((c = [e nextObject]) != nil)
    {
      NSMenuItem *item = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Item" action: NULL
                                                          keyEquivalent: [c objectAtIndex: 0]]);
      NSString *label;

      [item setKeyEquivalentModifierMask: [[c objectAtIndex: 1] unsignedIntegerValue]];
      label = [item respondsToSelector: @selector(gnomeThemeShortcutLabel)]
        ? [item performSelector: @selector(gnomeThemeShortcutLabel)] : nil;
      if ([label isEqualToString: [c objectAtIndex: 2]] == NO)
        {
          [wrong addObject: [NSString stringWithFormat: @"\"%@\" mask %@: %@, want %@", [c objectAtIndex: 0],
                                      [c objectAtIndex: 1], label, [c objectAtIndex: 2]]];
        }
    }
  if ([wrong count] == 0)
    {
      [self pass: @"menu-shortcut-labels" detail: nil];
    }
  else
    {
      [self fail: @"menu-shortcut-labels" detail: [wrong componentsJoinedByString: @"; "]];
    }
}

- (void) checkMenuSeparatorAndShortcut
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Probe"]);
  NSMenu *submenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"More"]);
  NSWindow *window;
  NSMenuView *menuView;
  NSBitmapImageRep *rep;
  NSRect bounds, rects[4];
  NSInteger i, rows = 0, top;
  NSUInteger background, line = 0;
  CGFloat shortcutGap, chevronGap;
  QuirkProbeInk ink;
  NSString *detail;
  BOOL highContrast;
  long contrast;

  [[menu addItemWithTitle: @"Alpha" action: @selector(description) keyEquivalent: @"1"] setTarget: self];
  [menu addItem: [NSMenuItem separatorItem]];
  [[menu addItemWithTitle: @"Quit" action: @selector(description) keyEquivalent: @"q"] setTarget: self];
  [menu setSubmenu: submenu forItem: [menu addItemWithTitle: @"More" action: NULL keyEquivalent: @""]];
  [submenu addItemWithTitle: @"Inner" action: NULL keyEquivalent: @""];
  menuView = AUTORELEASE ([[NSMenuView alloc] initWithFrame: NSMakeRect (0, 0, 200, 100)]);
  [menuView setMenu: menu];
  [menuView sizeToFit];
  window = [self windowWithFrame: NSMakeRect (40, 200, NSWidth ([menuView frame]) + 40, NSHeight ([menuView frame]) + 40)
                           title: @"QuirkProbe Menu"];
  [menuView setFrameOrigin: NSMakePoint (20, 20)];
  [[window contentView] addSubview: menuView];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (menuView);
  bounds = [menuView bounds];
  for (i = 0; i < 4; i++)
    {
      rects[i] = [menuView rectOfItemAtIndex: i];
      if ([menuView isFlipped] == NO)
        {
          rects[i].origin.y = NSHeight (bounds) - NSMaxY (rects[i]);
        }
    }
  /* The separator: the rows in the middle of its cell that differ from
     the menu's background. */
  background = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel,
                                    NSMakeRect (NSMidX (rects[1]), NSMinY (rects[1]), 1, 1)).darkest;
  for (top = (NSInteger)NSMinY (rects[1]); top < (NSInteger)NSMaxY (rects[1]); top++)
    {
      NSUInteger value = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel,
                                              NSMakeRect (NSMidX (rects[1]), top, 1, 1)).darkest;

      if (labs ((long)value - (long)background) > 6)
        {
          rows++;
          if (labs ((long)value - (long)background) > labs ((long)line - (long)background) || line == 0)
            {
              line = value;
            }
        }
    }
  QuirkProbeInkBackground = background;
  /* In the middle of the rows, clear of the menu's rounded corners. */
  ink = QuirkProbeMeasureIn (rep, QuirkProbeIsInk,
                             NSMakeRect (NSMidX (bounds), NSMinY (rects[0]) + NSHeight (rects[0]) / 4.0,
                                         NSMaxX (rects[0]) - 2.0 - NSMidX (bounds), NSHeight (rects[0]) / 2.0));
  shortcutGap = NSMaxX (rects[0]) - (ink.minX + ink.width);
  {
    /* The chevron is drawn at 30%: anything clearly off the background. */
    NSInteger x, y, maxX = -1;
    NSUInteger pixel[5];

    for (y = (NSInteger)(NSMinY (rects[3]) + NSHeight (rects[3]) / 4.0);
         y < (NSInteger)(NSMaxY (rects[3]) - NSHeight (rects[3]) / 4.0); y++)
      {
        for (x = (NSInteger)NSMidX (bounds); x < (NSInteger)NSMaxX (rects[3]) - 2; x++)
          {
            NSUInteger sum;

            [rep getPixel: pixel atX: x y: y];
            sum = pixel[0] + pixel[1] + pixel[2];
            if (labs ((long)sum - (long)background) > 60)
              {
                maxX = MAX (maxX, x);
              }
          }
      }
    chevronGap = NSMaxX (rects[3]) - (maxX + 1);
  }
  [self saveWindow: window named: @"menu"];
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"separator %ld row(s), r+g+b %lu on %lu; shortcut ends %gpt, chevron %gpt "
    @"from the row's right edge (row %@)", (long)rows, (unsigned long)line, (unsigned long)background,
    shortcutGap, chevronGap, NSStringFromRect (rects[0])];
  /* Light: libadwaita's #e0e0e1 on white is 93 below it (15%). High
     contrast is 50%: half the text's contrast with the menu (about 380 in
     the light palette, 290 in the dark). The shortcut's box ends 16pt
     in, its ink a side bearing further; the arrow's 16pt box ends there
     too, its glyph centred in it. */
  highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  contrast = labs ((long)line - (long)background);
  if (rows == 1 && (highContrast ? (contrast >= 260 && contrast <= 460) : (contrast >= 50 && contrast <= 140))
    && shortcutGap >= 16 && shortcutGap <= 20 && chevronGap >= 18 && chevronGap <= 26)
    {
      [self pass: @"menu-separator-and-shortcut" detail: detail];
    }
  else
    {
      [self fail: @"menu-separator-and-shortcut" detail: detail];
    }
}

/* With GnomeThemeHeaderBarToolbar a window's toolbar is in its header bar
   row, as a GNOME app packs its buttons there: no row of its own (the
   content keeps its size), the title in the flexible space, presses on the
   bar's empty parts the bar's, icons without labels and an item without an
   icon a text button. */
/* The theme's answer: the toolbar view's superview holds it in the bar. */
static BOOL
GnomeThemeProbeToolbarInBar(NSToolbar *toolbar)
{
  NSView *superview = [[toolbar _toolbarView] superview];

  return [superview respondsToSelector: @selector(holdsToolbarInBar)]
    && [superview holdsToolbarInBar];
}

/* The header bar toolbar setting applies to open windows: turned off, the
   toolbar moves to a row of its own, and back into the bar when turned on,
   the window keeping its frame (plugins-themes-Adwaita#30). */
- (void) checkHeaderBarToolbarLive
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  QuirkProbeHeaderToolbarDelegate *delegate;
  NSWindow *window;
  NSToolbar *toolbar;
  NSView *frameView;
  NSRect frame, rowFrame, barFrame;
  BOOL inBar, inRow, backInBar;
  NSString *detail;

  if (QuirkProbeDrawsDecorations () == NO
    || [[defaults searchList] containsObject: @"QuirkProbeHeaderBarToolbar"] == NO)
    {
      [self skip: @"header-bar-toolbar-live" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  delegate = AUTORELEASE ([QuirkProbeHeaderToolbarDelegate new]);
  window = [self windowWithFrame: NSMakeRect (40, 200, 600, 200) title: @"Probe Toolbar Live"];
  toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeLiveToolbar"]);
  [toolbar setDelegate: delegate];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  frameView = [[window contentView] superview];
  frame = [window frame];
  inBar = GnomeThemeProbeToolbarInBar (toolbar);

  [defaults removeVolatileDomainForName: @"QuirkProbeHeaderBarToolbar"];
  [defaults setVolatileDomain: [NSDictionary dictionaryWithObject: @"NO" forKey: @"GnomeThemeHeaderBarToolbar"]
                      forName: @"QuirkProbeHeaderBarToolbar"];
  [[NSNotificationCenter defaultCenter] postNotificationName: NSUserDefaultsDidChangeNotification object: defaults];
  rowFrame = [window frame];
  inRow = GnomeThemeProbeToolbarInBar (toolbar) == NO && [[toolbar _toolbarView] superview] == frameView;

  [defaults removeVolatileDomainForName: @"QuirkProbeHeaderBarToolbar"];
  [defaults setVolatileDomain: [NSDictionary dictionaryWithObject: @"YES" forKey: @"GnomeThemeHeaderBarToolbar"]
                      forName: @"QuirkProbeHeaderBarToolbar"];
  [[NSNotificationCenter defaultCenter] postNotificationName: NSUserDefaultsDidChangeNotification object: defaults];
  barFrame = [window frame];
  backInBar = GnomeThemeProbeToolbarInBar (toolbar);
  [window orderOut: nil];
  [window setToolbar: nil];
  /* Toolbars don't retain their delegates. */
  [toolbar setDelegate: nil];

  detail = [NSString stringWithFormat: @"%@; turned off: %@, frame %@; turned on: %@, frame %@ (was %@)",
    inBar ? @"in the bar" : @"not in the bar", inRow ? @"a row of its own" : @"not moved",
    NSStringFromRect (rowFrame), backInBar ? @"in the bar" : @"not moved", NSStringFromRect (barFrame),
    NSStringFromRect (frame)];
  if (inBar && inRow && backInBar && NSEqualRects (rowFrame, frame) && NSEqualRects (barFrame, frame))
    {
      [self pass: @"header-bar-toolbar-live" detail: detail];
    }
  else
    {
      [self fail: @"header-bar-toolbar-live" detail: detail];
    }
}

/* The title ink in a header bar window, between the bar's left border
   and its buttons. */
static QuirkProbeInk
QuirkProbeHeaderTitleInk(NSWindow *window)
{
  NSView *frameView = [[window contentView] superview];
  NSBitmapImageRep *rep;

  [window display];
  rep = QuirkProbeRender (frameView);
  QuirkProbeInkBackground = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (20, 4, 4, 4)).darkest;
  return QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (1, 1, NSWidth ([frameView bounds]) - 130, 44));
}

/* A document window's header bar shows the file's name, not GNUstep's
   "name  --  ~/folder", with the folder on hover, as GNOME's
   AdwWindowTitle (plugins-themes-Adwaita#31), and a dot before it while
   the document has unsaved changes (#39). */
- (void) checkHeaderBarDocumentTitle
{
  NSWindow *window;
  NSView *frameView;
  QuirkProbeInk document, plain, edited, saved;
  NSString *folder = nil;
  NSString *detail;

  if (QuirkProbeDrawsDecorations () == NO)
    {
      [self skip: @"header-bar-document-title" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  window = [self windowWithFrame: NSMakeRect (60, 300, 500, 150) title: @"Probe Document"];
  [window setTitleWithRepresentedFilename: @"/tmp/Probe Folder/white.png"];
  [window makeKeyAndOrderFront: nil];
  frameView = [[window contentView] superview];
  document = QuirkProbeHeaderTitleInk (window);
  if ([frameView respondsToSelector: @selector(view:stringForToolTip:point:userData:)])
    {
      /* A copy: retitling the window below lets the bar's go. */
      folder = AUTORELEASE ([[(id)frameView view: frameView stringForToolTip: 0 point: NSZeroPoint userData: NULL]
                              copy]);
    }
  [window setTitle: @"white.png"];
  plain = QuirkProbeHeaderTitleInk (window);
  /* Unsaved changes: a dot before the title, gone once saved
     (plugins-themes-Adwaita#39). */
  [window setDocumentEdited: YES];
  edited = QuirkProbeHeaderTitleInk (window);
  [window setDocumentEdited: NO];
  saved = QuirkProbeHeaderTitleInk (window);
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"title \"%@\" drawn %ldpx wide (\"white.png\" alone %ldpx); "
    @"folder on hover \"%@\"; edited %ldpx, saved again %ldpx", @"white.png  --  /tmp/Probe Folder",
    (long)document.width, (long)plain.width, folder ?: @"(none)", (long)edited.width, (long)saved.width];
  if (document.count > 0 && labs ((long)document.width - (long)plain.width) <= 1
    && [folder isEqualToString: @"/tmp/Probe Folder"]
    && edited.width >= plain.width + 6 && labs ((long)saved.width - (long)plain.width) <= 1)
    {
      [self pass: @"header-bar-document-title" detail: detail];
    }
  else
    {
      [self fail: @"header-bar-document-title" detail: detail];
    }
}

/* With the toolbar in the header bar, a press on an item's empty part (a
   container) or a label drags the window, as a GTK header bar's does: only
   controls keep their presses (plugins-themes-Adwaita#36). */
- (void) checkHeaderBarToolbarItemDrag
{
  QuirkProbeDragToolbarDelegate *delegate;
  NSWindow *window;
  NSToolbar *toolbar;
  NSView *frameView, *labelHit;
  NSRect boxFrame, labelFrame, before, after;
  NSPoint start;
  NSString *detail;
  int i;

  if (QuirkProbeDrawsDecorations () == NO
    || [[[NSUserDefaults standardUserDefaults] searchList] containsObject: @"QuirkProbeHeaderBarToolbar"] == NO)
    {
      [self skip: @"header-bar-toolbar-item-drag" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  delegate = AUTORELEASE ([QuirkProbeDragToolbarDelegate new]);
  window = [self windowWithFrame: NSMakeRect (200, 200, 500, 200) title: @"Probe Toolbar Drag"];
  toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeDragToolbar"]);
  [toolbar setDelegate: delegate];
  [window setToolbar: toolbar];
  [window makeKeyAndOrderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  labelFrame = [delegate->label convertRect: [delegate->label bounds] toView: nil];
  labelHit = [frameView hitTest: NSMakePoint (NSMidX (labelFrame), NSMidY (labelFrame))];

  /* A press on the box, dragged 40px right, released. (The bar's own
     move, with no window manager to hand it to, follows the real pointer,
     so the window can move further: a move is what's checked.) */
  boxFrame = [delegate->box convertRect: [delegate->box bounds] toView: nil];
  start = NSMakePoint (NSMidX (boxFrame), NSMidY (boxFrame));
  before = [window frame];
  for (i = 1; i <= 4; i++)
    {
      [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseDragged
                                           location: NSMakePoint (start.x + 10 * i, start.y)
                                      modifierFlags: 0 timestamp: 0 windowNumber: [window windowNumber]
                                            context: nil eventNumber: 0 clickCount: 1 pressure: 1.0]
               atStart: NO];
    }
  [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseUp location: NSMakePoint (start.x + 40, start.y)
                                  modifierFlags: 0 timestamp: 0 windowNumber: [window windowNumber]
                                        context: nil eventNumber: 0 clickCount: 1 pressure: 0.0]
           atStart: NO];
  [window sendEvent: [NSEvent mouseEventWithType: NSLeftMouseDown location: start modifierFlags: 0
                                        timestamp: 0 windowNumber: [window windowNumber] context: nil
                                      eventNumber: 0 clickCount: 1 pressure: 1.0]];
  after = [window frame];
  [window orderOut: nil];
  [window setToolbar: nil];
  [toolbar setDelegate: nil];

  detail = [NSString stringWithFormat: @"a press on the label goes to %@; a drag from the box moved the window %@ -> %@",
    NSStringFromClass ([labelHit class]), NSStringFromPoint (before.origin), NSStringFromPoint (after.origin)];
  if (labelHit == frameView && NSMinX (after) - NSMinX (before) >= 20)
    {
      [self pass: @"header-bar-toolbar-item-drag" detail: detail];
    }
  else
    {
      [self fail: @"header-bar-toolbar-item-drag" detail: detail];
    }
}

/* With the toolbar in the header bar, a click on an item's view that
   handles only the release reaches it: the press it passes on isn't the
   bar's to drag, and the bar leaves the release alone
   (plugins-themes-Adwaita#33). */
- (void) checkHeaderBarToolbarItemClick
{
  QuirkProbeReleaseToolbarDelegate *delegate;
  NSWindow *window;
  NSToolbar *toolbar;
  NSRect frame;
  NSPoint point;
  NSEvent *down, *up, *pending;
  NSView *hit;
  NSString *detail;
  BOOL inBar;

  if (QuirkProbeDrawsDecorations () == NO)
    {
      [self skip: @"header-bar-toolbar-item-click" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  /* The app opting in (as -checkHeaderBarToolbar does). */
  if ([[[NSUserDefaults standardUserDefaults] searchList] containsObject: @"QuirkProbeHeaderBarToolbar"] == NO)
    {
      NSMutableArray *searchList = AUTORELEASE ([[[NSUserDefaults standardUserDefaults] searchList] mutableCopy]);

      [[NSUserDefaults standardUserDefaults]
        setVolatileDomain: [NSDictionary dictionaryWithObject: @"YES" forKey: @"GnomeThemeHeaderBarToolbar"]
                  forName: @"QuirkProbeHeaderBarToolbar"];
      [searchList insertObject: @"QuirkProbeHeaderBarToolbar" atIndex: 0];
      [[NSUserDefaults standardUserDefaults] setSearchList: searchList];
    }
  delegate = AUTORELEASE ([QuirkProbeReleaseToolbarDelegate new]);
  window = [self windowWithFrame: NSMakeRect (40, 200, 500, 200) title: @"Probe Toolbar Click"];
  toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeReleaseToolbar"]);
  [toolbar setDelegate: delegate];
  [window setToolbar: toolbar];
  /* Key, as the window being used: a first click on another window only
     activates it. */
  [window makeKeyAndOrderFront: nil];
  [window display];
  inBar = [[[toolbar _toolbarView] superview] isEqual: [[window contentView] superview]];
  frame = [delegate->view convertRect: [delegate->view bounds] toView: nil];
  point = NSMakePoint (NSMidX (frame), NSMidY (frame));
  hit = [[[window contentView] superview] hitTest: point];
  if (hit != delegate->view)
    {
      [self fail: @"header-bar-toolbar-item-click"
          detail: [NSString stringWithFormat: @"the item's view at %@ in the window; a press there goes to %@",
                            NSStringFromRect (frame), NSStringFromClass ([hit class])]];
      [window orderOut: nil];
      [window setToolbar: nil];
      [toolbar setDelegate: nil];
      return;
    }
  down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                           timestamp: 0 windowNumber: [window windowNumber] context: nil
                         eventNumber: 0 clickCount: 1 pressure: 1.0];
  up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                         timestamp: 0 windowNumber: [window windowNumber] context: nil
                       eventNumber: 0 clickCount: 1 pressure: 0.0];
  /* Queued first: a bar that reads up to the release finds it, rather
     than waiting for it. */
  [NSApp postEvent: up atStart: NO];
  [window sendEvent: down];
  pending = [NSApp nextEventMatchingMask: NSLeftMouseUpMask untilDate: [NSDate distantPast]
                                  inMode: NSDefaultRunLoopMode dequeue: YES];
  if (pending != nil)
    {
      [window sendEvent: pending];
    }
  detail = [NSString stringWithFormat: @"toolbar %@ the bar; the item's view saw %d release(s) "
    @"(the release was %@)", inBar ? @"in" : @"not in", delegate->view->releases,
    pending != nil ? @"left for it" : @"taken by the bar"];
  if (inBar && delegate->view->releases == 1)
    {
      [self pass: @"header-bar-toolbar-item-click" detail: detail];
    }
  else
    {
      [self fail: @"header-bar-toolbar-item-click" detail: detail];
    }
  [window orderOut: nil];
  [window setToolbar: nil];
  /* Toolbars don't retain their delegates. */
  [toolbar setDelegate: nil];
}

- (void) checkHeaderBarToolbar
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *searchList;
  QuirkProbeHeaderToolbarDelegate *delegate;
  NSWindow *window;
  NSToolbar *toolbar;
  NSView *frameView, *toolbarView, *hitGap = nil, *hitIcon = nil;
  NSSize before, after;
  NSRect bounds, gap = NSZeroRect, iconFrame = NSZeroRect;
  NSBitmapImageRep *rep;
  QuirkProbeInk title;
  NSMutableArray *positions = [NSMutableArray array];
  NSEnumerator *enumerator;
  NSToolbarItem *item;
  BOOL labelsOk = YES;
  NSString *detail;

  if (QuirkProbeDrawsDecorations () == NO)
    {
      [self skip: @"header-bar-toolbar" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  /* The app opting in, in a domain of its own: nothing saved. */
  [defaults setVolatileDomain: [NSDictionary dictionaryWithObject: @"YES" forKey: @"GnomeThemeHeaderBarToolbar"]
                      forName: @"QuirkProbeHeaderBarToolbar"];
  searchList = AUTORELEASE ([[defaults searchList] mutableCopy]);
  [searchList insertObject: @"QuirkProbeHeaderBarToolbar" atIndex: 0];
  [defaults setSearchList: searchList];

  delegate = [QuirkProbeHeaderToolbarDelegate new];
  window = [self windowWithFrame: NSMakeRect (40, 200, 700, 260) title: @"Probe Toolbar Bar"];
  before = [[window contentView] frame].size;
  toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeHeaderToolbar"]);
  [toolbar setDelegate: delegate];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  [window display];
  after = [[window contentView] frame].size;
  frameView = [[window contentView] superview];
  bounds = [frameView bounds];
  toolbarView = [toolbar _toolbarView];

  enumerator = [[toolbar items] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      NSView *backView = [item _backView];
      NSRect frame = [frameView convertRect: [backView bounds] fromView: backView];

      [positions addObject: [NSString stringWithFormat: @"%@ %g-%g", [item itemIdentifier], NSMinX (frame), NSMaxX (frame)]];
      if ([[item itemIdentifier] isEqualToString: NSToolbarFlexibleSpaceItemIdentifier])
        {
          gap = frame;
        }
      else if ([backView isKindOfClass: [NSButton class]])
        {
          NSCellImagePosition position = [(NSButton *)backView imagePosition];

          labelsOk = labelsOk && position == ([item image] != nil ? NSImageOnly : NSNoImage);
          if ([[item itemIdentifier] isEqualToString: @"IconA"])
            {
              iconFrame = frame;
            }
        }
    }
  if (NSIsEmptyRect (gap) == NO)
    {
      hitGap = [frameView hitTest: NSMakePoint (NSMidX (gap) - 1, NSMidY (gap))];
    }
  if (NSIsEmptyRect (iconFrame) == NO)
    {
      hitIcon = [frameView hitTest: NSMakePoint (NSMidX (iconFrame), NSMidY (iconFrame))];
    }
  rep = QuirkProbeRender (frameView);
  /* The title's ink in the bar, in pixels from the top left, below the
     window's border: anything clearly off the bar's background, in any
     palette (dimmed: the probe's window isn't the key window; nothing
     else is in the gap). */
  QuirkProbeInkBackground = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel,
                                                 NSMakeRect (NSMinX (gap) + 2, 4, 1, 1)).darkest;
  title = QuirkProbeMeasureIn (rep, QuirkProbeIsInk,
                               NSMakeRect (NSMinX (gap), 2, NSWidth (gap), 42));
  [self saveWindow: window named: @"header-bar-toolbar"];
  [window orderOut: nil];

  /* Too narrow for the toolbar: the items that don't fit go into libs-gui's
     » menu, a button inside the bar at the end of the toolbar. */
  {
    NSWindow *narrow = [self windowWithFrame: NSMakeRect (40, 200, 150, 200) title: @"Probe Toolbar Narrow"];
    NSToolbar *narrowToolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeHeaderToolbarNarrow"]);
    NSView *narrowFrame, *narrowToolbarView, *mark = nil;
    NSRect markFrame = NSZeroRect;
    NSString *narrowDetail;

    [narrowToolbar setDelegate: delegate];
    [narrow setToolbar: narrowToolbar];
    [narrow orderFront: nil];
    [narrow display];
    narrowFrame = [[narrow contentView] superview];
    narrowToolbarView = [narrowToolbar _toolbarView];
    enumerator = [[narrowToolbarView subviews] objectEnumerator];
    while ((mark = [enumerator nextObject]) != nil)
      {
        if ([mark isKindOfClass: [NSButton class]])
          {
            markFrame = [narrowFrame convertRect: [mark bounds] fromView: mark];
            break;
          }
      }
    [narrow orderOut: nil];
    narrowDetail = [NSString stringWithFormat: @"toolbar %@, » %@ in %@",
      NSStringFromRect ([narrowToolbarView frame]), NSStringFromRect (markFrame),
      NSStringFromRect ([narrowFrame bounds])];
    if (mark != nil && NSMinY (markFrame) >= NSMaxY ([narrowFrame bounds]) - 46.5
      && NSMaxY (markFrame) <= NSMaxY ([narrowFrame bounds]) + 0.5
      && NSMaxX (markFrame) <= NSMaxX ([narrowToolbarView frame]) + 0.5)
      {
        [self pass: @"header-bar-toolbar-overflow" detail: narrowDetail];
      }
    else
      {
        [self fail: @"header-bar-toolbar-overflow" detail: narrowDetail];
      }
  }

  /* The title keeps 100pt of the toolbar's flexible space as the window
     narrows: the items after it go into the » menu first, and the space
     isn't squeezed to nothing (ScreenshotTool at 860pt). */
  {
    NSMutableArray *failures = [NSMutableArray array];
    NSString *roomDetail;
    int widths = 0;
    CGFloat w;

    for (w = 200.0; w <= 700.0; w += 20.0)
      {
        NSWindow *sized = [self windowWithFrame: NSMakeRect (40, 200, w, 200) title: @"Probe Toolbar Title Room"];
        NSString *identifier = [NSString stringWithFormat: @"QuirkProbeHeaderToolbarRoom%g", w];
        NSToolbar *sizedToolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: identifier]);
        NSView *sizedToolbarView;
        NSRect space = NSZeroRect;
        CGFloat startEnd = 0.0;
        BOOL beforeSpace = YES;

        [sizedToolbar setDelegate: delegate];
        [sized setToolbar: sizedToolbar];
        [sized orderFront: nil];
        [sized display];
        sizedToolbarView = [sizedToolbar _toolbarView];
        enumerator = [[sizedToolbar items] objectEnumerator];
        while ((item = [enumerator nextObject]) != nil)
          {
            NSView *backView = [item _backView];

            if ([[item itemIdentifier] isEqualToString: NSToolbarFlexibleSpaceItemIdentifier])
              {
                space = [sizedToolbarView convertRect: [backView bounds] fromView: backView];
                beforeSpace = NO;
              }
            else if (beforeSpace)
              {
                startEnd = NSMaxX ([sizedToolbarView convertRect: [backView bounds] fromView: backView]);
              }
          }
        /* Room for the start items, the title and the » at least. */
        if (NSWidth ([sizedToolbarView frame]) >= startEnd + 100.0 + 28.0)
          {
            widths++;
            if (NSWidth (space) < 99.5 || NSMaxX (space) > NSWidth ([sizedToolbarView frame]) + 0.5)
              {
                [failures addObject: [NSString stringWithFormat: @"%g: space %g-%g in %g", w,
                  NSMinX (space), NSMaxX (space), NSWidth ([sizedToolbarView frame])]];
              }
          }
        [sized orderOut: nil];
      }
    roomDetail = [NSString stringWithFormat: @"%d window widths with room, %lu with less than 100pt for the title%@%@",
      widths, (unsigned long)[failures count], [failures count] ? @": " : @"",
      [failures componentsJoinedByString: @"; "]];
    if (widths > 0 && [failures count] == 0)
      {
        [self pass: @"header-bar-toolbar-title-room" detail: roomDetail];
      }
    else
      {
        [self fail: @"header-bar-toolbar-title-room" detail: roomDetail];
      }
  }

  /* Narrower still, the title's space goes into the » menu with the items
     after it: the title is drawn between the items and the », never under
     the » (alpha13 drew it in the clipped space's frame). */
  {
    NSMutableArray *failures = [NSMutableArray array];
    NSString *overflowDetail;
    int clipped = 0;
    CGFloat w;

    for (w = 200.0; w <= 700.0; w += 20.0)
      {
        NSWindow *sized = [self windowWithFrame: NSMakeRect (40, 200, w, 200) title: @"Probe Toolbar Title Before Overflow"];
        NSString *identifier = [NSString stringWithFormat: @"QuirkProbeHeaderToolbarBeforeOverflow%g", w];
        NSToolbar *sizedToolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: identifier]);
        NSView *sizedFrame, *sizedToolbarView, *subview;
        NSRect mark = NSZeroRect;
        CGFloat minX, maxX;

        [sizedToolbar setDelegate: delegate];
        [sized setToolbar: sizedToolbar];
        [sized orderFront: nil];
        [sized display];
        sizedFrame = [[sized contentView] superview];
        sizedToolbarView = [sizedToolbar _toolbarView];
        enumerator = [[sizedToolbarView subviews] objectEnumerator];
        while ((subview = [enumerator nextObject]) != nil)
          {
            if ([subview isKindOfClass: [NSButton class]])
              {
                mark = [sizedFrame convertRect: [subview bounds] fromView: subview];
              }
          }
        if (NSWidth (mark) > 0.0 && [sizedFrame respondsToSelector: @selector(titleLimitsWithToolbar::)])
          {
            clipped++;
            minX = 0.0;
            maxX = NSWidth ([sizedFrame bounds]);
            [sizedFrame titleLimitsWithToolbar: &minX : &maxX];
            if (maxX > NSMinX (mark) + 0.5 && maxX > minX)
              {
                [failures addObject: [NSString stringWithFormat: @"%g: title %g-%g, » %g-%g", w,
                  minX, maxX, NSMinX (mark), NSMaxX (mark)]];
              }
          }
        [sized orderOut: nil];
      }
    overflowDetail = [NSString stringWithFormat: @"%d window widths with », %lu with the title under it%@%@",
      clipped, (unsigned long)[failures count], [failures count] ? @": " : @"",
      [failures componentsJoinedByString: @"; "]];
    if (clipped > 0 && [failures count] == 0)
      {
        [self pass: @"header-bar-toolbar-title-before-overflow" detail: overflowDetail];
      }
    else
      {
        [self fail: @"header-bar-toolbar-title-before-overflow" detail: overflowDetail];
      }
  }

  /* Right to left, as GTK mirrors its header bar: the first item at the
     right end, the items after the flexible space at the left. */
  {
    NSWindow *mirrored;
    NSToolbar *mirroredToolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeHeaderToolbarRTL"]);
    NSRect first = NSZeroRect, last = NSZeroRect, space = NSZeroRect;
    NSView *mirroredFrame;
    NSString *mirroredDetail;

    [defaults removeVolatileDomainForName: @"QuirkProbeHeaderBarToolbar"];
    [defaults setVolatileDomain: [NSDictionary dictionaryWithObjectsAndKeys:
                                                 @"YES", @"GnomeThemeHeaderBarToolbar",
                                                 @"YES", @"NSForceRightToLeftWritingDirection", nil]
                        forName: @"QuirkProbeHeaderBarToolbar"];
    mirrored = [self windowWithFrame: NSMakeRect (40, 200, 700, 200) title: @"Probe Toolbar RTL"];
    [mirroredToolbar setDelegate: delegate];
    [mirrored setToolbar: mirroredToolbar];
    [mirrored orderFront: nil];
    [mirrored display];
    mirroredFrame = [[mirrored contentView] superview];
    enumerator = [[mirroredToolbar items] objectEnumerator];
    while ((item = [enumerator nextObject]) != nil)
      {
        NSView *backView = [item _backView];
        NSRect frame = [mirroredFrame convertRect: [backView bounds] fromView: backView];

        if ([[item itemIdentifier] isEqualToString: @"IconA"])
          first = frame;
        else if ([[item itemIdentifier] isEqualToString: @"IconC"])
          last = frame;
        else if ([[item itemIdentifier] isEqualToString: NSToolbarFlexibleSpaceItemIdentifier])
          space = frame;
      }
    [mirrored orderOut: nil];
    mirroredDetail = [NSString stringWithFormat: @"IconA %g-%g, flexible space %g-%g, IconC %g-%g in %g",
      NSMinX (first), NSMaxX (first), NSMinX (space), NSMaxX (space), NSMinX (last), NSMaxX (last),
      NSWidth ([mirroredFrame bounds])];
    if (NSMinX (first) > NSMaxX (space) && NSMaxX (last) < NSMinX (space)
      && NSMaxX (first) > NSWidth ([mirroredFrame bounds]) - 60)
      {
        [self pass: @"header-bar-toolbar-rtl" detail: mirroredDetail];
      }
    else
      {
        [self fail: @"header-bar-toolbar-rtl" detail: mirroredDetail];
      }
  }

  [searchList removeObject: @"QuirkProbeHeaderBarToolbar"];
  [defaults setSearchList: searchList];
  [defaults removeVolatileDomainForName: @"QuirkProbeHeaderBarToolbar"];

  detail = [NSString stringWithFormat: @"content %@ -> %@; toolbar %@ in %@; items %@; title ink x %ld-%ld in the gap; "
    @"a press in the gap goes to %@, on an icon to %@; labels %@",
    NSStringFromSize (before), NSStringFromSize (after), NSStringFromRect ([toolbarView frame]),
    NSStringFromRect (bounds), [positions componentsJoinedByString: @", "],
    (long)title.minX, (long)(title.minX + title.width), NSStringFromClass ([hitGap class]),
    NSStringFromClass ([hitIcon class]), labelsOk ? @"as expected" : @"wrong"];
  if (NSEqualSizes (before, after) && [toolbarView superview] == frameView
    && NSMinY ([toolbarView frame]) >= NSMaxY (bounds) - 46.5 && NSHeight ([toolbarView frame]) == 46
    && title.count > 0 && title.minX > NSMinX (gap) && title.minX + title.width < NSMaxX (gap)
    && hitGap == frameView && [hitIcon respondsToSelector: @selector(toolbarItem)] && labelsOk)
    {
      [self pass: @"header-bar-toolbar" detail: detail];
    }
  else
    {
      [self fail: @"header-bar-toolbar" detail: detail];
    }
}

/* A selected segment stands out from the others, further from the window's
   background, in any palette (plugins-themes-Adwaita#7: in the dark one it
   was 2/255 darker than the others). Runs with the dark and high contrast
   header bar runs too. */
- (void) checkSegmentedSelection
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 200, 300, 80) title: @"QuirkProbe Segments"];
  NSSegmentedControl *control = AUTORELEASE ([[NSSegmentedControl alloc] initWithFrame: NSMakeRect (20, 20, 240, 34)]);
  NSBitmapImageRep *rep, *windowRep;
  NSUInteger fills[2], background;
  NSInteger i;
  NSString *detail;

  [control setSegmentCount: 3];
  for (i = 0; i < 3; i++)
    {
      [control setLabel: [NSString stringWithFormat: @"Item %ld", (long)i + 1] forSegment: i];
      [control setWidth: 80 forSegment: i];
    }
  [control setSelectedSegment: 1];
  [[window contentView] addSubview: control];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (control);
  windowRep = QuirkProbeRender ([window contentView]);
  /* Inside each segment, near its top edge, clear of the label. */
  for (i = 0; i < 2; i++)
    {
      fills[i] = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (40 + 80 * i, 4, 2, 2)).darkest;
    }
  background = QuirkProbeMeasureIn (windowRep, QuirkProbeIsAnyPixel, NSMakeRect (2, 2, 2, 2)).darkest;
  [self saveWindow: window named: @"segments"];
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"r+g+b: window %lu, unselected segment %lu, selected %lu",
    (unsigned long)background, (unsigned long)fills[0], (unsigned long)fills[1]];
  if (labs ((long)fills[1] - (long)fills[0]) >= 60
    && labs ((long)fills[1] - (long)background) > labs ((long)fills[0] - (long)background))
    {
      [self pass: @"segment-selected-visible" detail: detail];
    }
  else
    {
      [self fail: @"segment-selected-visible" detail: detail];
    }
}

/* Between two unselected segments, libadwaita's linked buttons overlap
   by 1px, and their translucent fills over each other read as a
   separator: one column, the fill taken 10-30 (of 255) further from the
   window (darker in the light palette, lighter in the dark). High
   contrast's is the outline, the foreground at 50%: further still. */
- (void) checkSegmentSeparator
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 200, 300, 80) title: @"QuirkProbe Segment Separator"];
  NSSegmentedControl *control = AUTORELEASE ([[NSSegmentedControl alloc] initWithFrame: NSMakeRect (20, 20, 240, 34)]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3], windowRGB[3];
  NSInteger i, x, columns = 0, step = 0;
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  NSString *detail;

  [control setSegmentCount: 3];
  for (i = 0; i < 3; i++)
    {
      [control setLabel: [NSString stringWithFormat: @"Item %ld", (long)i + 1] forSegment: i];
      [control setWidth: 80 forSegment: i];
    }
  [control setSelectedSegment: 0];
  [[window contentView] addSubview: control];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (control);
  QuirkProbePixelAt (QuirkProbeRender ([window contentView]), 2, 2, windowRGB);
  /* Near the top edge, clear of the labels: the third segment's fill,
     and the columns around the second and third segments' edge. */
  QuirkProbePixelAt (rep, 200, 6, fill);
  for (x = 150; x < 170; x++)
    {
      NSUInteger px[3];
      long d;

      QuirkProbePixelAt (rep, x, 6, px);
      d = (long)px[0] - (long)fill[0];
      if (labs (d) > 4)
        {
          columns++;
          /* Positive: away from the window. */
          step = ((long)fill[0] < (long)windowRGB[0]) ? -d : d;
        }
    }
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"fill %@, %ld column(s) apart at the edge, %ld further from the window",
    QuirkProbeHex (fill), (long)columns, (long)step];
  if (columns == 1 && step >= 10 && (highContrast || step <= 30))
    {
      [self pass: @"segment-separator" detail: detail];
    }
  else
    {
      [self fail: @"segment-separator" detail: detail];
    }
}

/* Boxes as libadwaita's: a separator box is GtkSeparator, a line from the
   window towards the text by 10 to 40 (high contrast: at least 40); an
   untitled line-border box is a card, filled lighter than the window with
   rounded corners; a titled box is a GtkFrame with the title at its left,
   not centred. */
- (void) checkBoxes
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 200, 260, 220) title: @"QuirkProbe Boxes"];
  NSBox *separator = AUTORELEASE ([[NSBox alloc] initWithFrame: NSMakeRect (10, 200, 240, 1)]);
  NSBox *card = AUTORELEASE ([[NSBox alloc] initWithFrame: NSMakeRect (10, 120, 240, 60)]);
  NSBox *frame = AUTORELEASE ([[NSBox alloc] initWithFrame: NSMakeRect (10, 10, 240, 90)]);
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], line[3], centre[3], corner[3];
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  BOOL dark;
  long step, lift, cornerStep;
  NSInteger x, y, titleX = -1;
  NSString *detail;

  [separator setBoxType: NSBoxSeparator];
  [card setTitlePosition: NSNoTitle];
  [card setBorderType: NSLineBorder];
  [card setContentViewMargins: NSZeroSize];
  [frame setTitle: @"Options"];
  [[window contentView] addSubview: separator];
  [[window contentView] addSubview: card];
  [[window contentView] addSubview: frame];
  [window orderFront: nil];
  [window display];
  QuirkProbePixelAt (QuirkProbeRender ([window contentView]), 2, 2, windowRGB);
  dark = (windowRGB[0] < 128);

  QuirkProbePixelAt (QuirkProbeRender (separator), 120, 0, line);
  /* Positive: towards the text colour. */
  step = dark ? (long)line[0] - (long)windowRGB[0] : (long)windowRGB[0] - (long)line[0];
  detail = [NSString stringWithFormat: @"window %@, line %@, %ld towards the text", QuirkProbeHex (windowRGB),
    QuirkProbeHex (line), step];
  if (step >= 10 && (highContrast ? YES : step <= 40))
    {
      [self pass: @"box-separator" detail: detail];
    }
  else
    {
      [self fail: @"box-separator" detail: detail];
    }

  rep = QuirkProbeRender (card);
  QuirkProbePixelAt (rep, 120, 30, centre);
  QuirkProbePixelAt (rep, 1, 1, corner);
  lift = ((long)centre[0] + (long)centre[1] + (long)centre[2])
    - ((long)windowRGB[0] + (long)windowRGB[1] + (long)windowRGB[2]);
  cornerStep = labs ((long)corner[0] - (long)windowRGB[0]);
  detail = [NSString stringWithFormat: @"window %@, centre %@ (%+ld), corner %@", QuirkProbeHex (windowRGB),
    QuirkProbeHex (centre), lift, QuirkProbeHex (corner)];
  if (lift >= 8 && cornerStep <= 6)
    {
      [self pass: @"box-card" detail: detail];
    }
  else
    {
      [self fail: @"box-card" detail: detail];
    }

  /* The title's first column of ink, below the frame's top edge and right
     of its corner. */
  rep = QuirkProbeRender (frame);
  for (x = 4; x < [rep pixelsWide] && titleX < 0; x++)
    {
      for (y = 6; y < 24; y++)
        {
          NSUInteger px[3];

          QuirkProbePixelAt (rep, x, y, px);
          if (labs ((long)(px[0] + px[1] + px[2]) - (long)(windowRGB[0] + windowRGB[1] + windowRGB[2])) > 240)
            {
              titleX = x;
              break;
            }
        }
    }
  QuirkProbePixelAt (rep, 1, 1, corner);
  cornerStep = labs ((long)corner[0] - (long)windowRGB[0]);
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"title ink from x %ld of %ld, corner %@", (long)titleX,
    (long)[rep pixelsWide], QuirkProbeHex (corner)];
  if (titleX >= 4 && titleX <= 20 && cornerStep <= 6)
    {
      [self pass: @"box-frame-title" detail: detail];
    }
  else
    {
      [self fail: @"box-frame-title" detail: detail];
    }

  /* The title is in the interface font, as a GtkFrame's label, not the
     small system font. */
  detail = [NSString stringWithFormat: @"title font %@ %g, system font %g",
    [[frame titleFont] fontName], [[frame titleFont] pointSize], [[NSFont systemFontOfSize: 0.0] pointSize]];
  if (fabs ([[frame titleFont] pointSize] - [[NSFont systemFontOfSize: 0.0] pointSize]) < 0.01)
    {
      [self pass: @"box-title-font" detail: detail];
    }
  else
    {
      [self fail: @"box-title-font" detail: detail];
    }
}

/* A destructive button: in a window, libadwaita's .destructive-action
   (destructive_bg_color, white text); in an alert, AdwAlertDialog's
   destructive response (destructive_color at 15% over the dialog, the
   text in it). Sampled at the fill's left edge and by the text's ink. */
- (NSString *) destructiveSampleOf: (NSButton *)button fill: (NSUInteger *)fill ink: (NSUInteger *)ink
{
  NSBitmapImageRep *rep = QuirkProbeRender (button);
  NSInteger x, y, best = -1;

  QuirkProbePixelAt (rep, 6, [rep pixelsHigh] / 2, fill);
  ink[0] = fill[0]; ink[1] = fill[1]; ink[2] = fill[2];
  for (y = 0; y < [rep pixelsHigh]; y++)
    {
      for (x = 12; x < [rep pixelsWide] - 12; x++)
        {
          NSUInteger px[3];
          NSInteger d;

          QuirkProbePixelAt (rep, x, y, px);
          d = labs ((long)px[0] - (long)fill[0]) + labs ((long)px[1] - (long)fill[1]) + labs ((long)px[2] - (long)fill[2]);
          if (d > best)
            {
              best = d;
              ink[0] = px[0]; ink[1] = px[1]; ink[2] = px[2];
            }
        }
    }
  return [NSString stringWithFormat: @"fill %@, text %@", QuirkProbeHex (fill), QuirkProbeHex (ink)];
}

/* With a libs-gui that has -[NSButton setHasDestructiveAction:]: the flag
   itself, on a window's button and through NSAlert to its panel's button.
   Skipped on one without it, where only the stand-in below can be checked. */
/* -abortModal only marks the run: an event lets it notice. */
- (void) endRealDestructiveAlert
{
  [NSApp abortModal];
  [NSApp postEvent: [NSEvent otherEventWithType: NSApplicationDefined
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                      timestamp: 0
                                   windowNumber: 0
                                        context: nil
                                        subtype: 0
                                          data1: 0
                                          data2: 0]
           atStart: NO];
}

- (void) sampleRealDestructiveAlert: (NSTimer *)timer
{
  static BOOL sampled = NO;
  NSWindow *panel = [NSApp modalWindow];

  /* The timer repeats until the run has ended. */
  if (sampled)
    {
      [self endRealDestructiveAlert];
      return;
    }
  sampled = YES;
  {
  NSEnumerator *enumerator = [[[panel contentView] subviews] objectEnumerator];
  NSView *view;

  while ((view = [enumerator nextObject]) != nil)
    {
      if ([view isKindOfClass: [NSButton class]] && [[(NSButton *)view title] isEqualToString: @"Delete"])
        {
          NSUInteger fill[3], ink[3], windowRGB[3];
          NSString *detail;
          BOOL dark;

          [panel display];
          QuirkProbePixelAt (QuirkProbeRender ([panel contentView]), 2, 2, windowRGB);
          dark = (windowRGB[0] < 128);
          detail = [self destructiveSampleOf: (NSButton *)view fill: fill ink: ink];
          if ((dark ? (ink[0] > 0xf0 && labs ((long)ink[1] - 0x93) <= 12) : (labs ((long)ink[0] - 0xc3) <= 12 && ink[1] < 0x30))
            && fill[0] > fill[2] + 8 && fill[0] > fill[1] + 8)
            {
              [self pass: @"destructive-real-alert" detail: detail];
            }
          else
            {
              [self fail: @"destructive-real-alert" detail: detail];
            }
          [self endRealDestructiveAlert];
          return;
        }
    }
  [self fail: @"destructive-real-alert" detail: @"no Delete button in the running alert"];
  [self endRealDestructiveAlert];
  }
}

- (void) checkRealDestructiveFlag
{
  NSWindow *window;
  NSButton *button;
  NSAlert *alert;
  NSButton *delete;
  NSUInteger fill[3], ink[3], windowRGB[3];
  NSString *detail;
  BOOL dark;
  void (*setFlag)(id, SEL, BOOL);
  NSTimer *timer;

  if ([NSButton instancesRespondToSelector: @selector(setHasDestructiveAction:)] == NO)
    {
      [self skip: @"destructive-real-button" detail: @"this libs-gui has no -setHasDestructiveAction:"];
      [self skip: @"destructive-real-alert" detail: @"this libs-gui has no -setHasDestructiveAction:"];
      return;
    }
  window = [self windowWithFrame: NSMakeRect (60, 60, 220, 80) title: @"QuirkProbe Destructive flag"];
  button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20, 20, 140, 34)]);
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setTitle: @"Delete"];
  setFlag = (void (*)(id, SEL, BOOL))[button methodForSelector: @selector(setHasDestructiveAction:)];
  setFlag (button, @selector(setHasDestructiveAction:), YES);
  [[window contentView] addSubview: button];
  [window orderFront: nil];
  [window display];
  QuirkProbePixelAt (QuirkProbeRender ([window contentView]), 2, 2, windowRGB);
  dark = (windowRGB[0] < 128);
  detail = [self destructiveSampleOf: button fill: fill ink: ink];
  [window orderOut: nil];
  if (labs ((long)fill[0] - (dark ? 0xc0 : 0xe0)) <= 6 && fill[1] < 0x30 && fill[2] < 0x40
    && ink[0] > 235 && ink[1] > 235 && ink[2] > 235)
    {
      [self pass: @"destructive-real-button" detail: detail];
    }
  else
    {
      [self fail: @"destructive-real-button" detail: detail];
    }

  alert = AUTORELEASE ([[NSAlert alloc] init]);
  [alert setMessageText: @"Delete “Report.md”?"];
  [alert setInformativeText: @"It will be moved to the trash."];
  delete = [alert addButtonWithTitle: @"Delete"];
  [alert addButtonWithTitle: @"Cancel"];
  setFlag (delete, @selector(setHasDestructiveAction:), YES);
  timer = [NSTimer timerWithTimeInterval: 0.3
                                  target: self
                                selector: @selector(sampleRealDestructiveAlert:)
                                userInfo: nil
                                 repeats: YES];
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSModalPanelRunLoopMode];
  [alert runModal];
  [timer invalidate];
}

- (void) checkDestructiveButtons
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 220, 80) title: @"QuirkProbe Destructive"];
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20, 20, 140, 34)]);
  QuirkProbeDestructiveCell *cell = AUTORELEASE ([[QuirkProbeDestructiveCell alloc] initTextCell: @"Delete"]);
  NSPanel *alert;
  NSButton *alertButton = nil;
  NSEnumerator *enumerator;
  NSView *view;
  NSUInteger fill[3], ink[3], windowRGB[3];
  NSString *detail;
  BOOL dark;

  [cell setBezelStyle: NSRoundedBezelStyle];
  [button setCell: cell];
  [[window contentView] addSubview: button];
  [window orderFront: nil];
  [window display];
  QuirkProbePixelAt (QuirkProbeRender ([window contentView]), 2, 2, windowRGB);
  dark = (windowRGB[0] < 128);
  detail = [self destructiveSampleOf: button fill: fill ink: ink];
  [window orderOut: nil];
  /* destructive_bg_color: #e01b24 (light) or #c01c28 (dark), white text. */
  if (labs ((long)fill[0] - (dark ? 0xc0 : 0xe0)) <= 6 && fill[1] < 0x30 && fill[2] < 0x40
    && ink[0] > 235 && ink[1] > 235 && ink[2] > 235)
    {
      [self pass: @"destructive-button" detail: detail];
    }
  else
    {
      [self fail: @"destructive-button" detail: detail];
    }

  /* The alert's first button made destructive, as NSAlert will when
     libs-gui copies the flag to its panel. */
  alert = NSGetAlertPanel (@"Delete “Report.md”?", @"It will be moved to the trash.", @"Delete", @"Cancel", nil);
  enumerator = [[[alert contentView] subviews] objectEnumerator];
  while ((view = [enumerator nextObject]) != nil)
    {
      if ([view isKindOfClass: [NSButton class]] && [[(NSButton *)view title] isEqualToString: @"Delete"])
        {
          alertButton = (NSButton *)view;
        }
    }
  if (alertButton == nil)
    {
      [self fail: @"destructive-alert-button" detail: @"no Delete button in the alert panel"];
      NSReleaseAlertPanel (alert);
      return;
    }
  {
    QuirkProbeDestructiveCell *alertCell = AUTORELEASE ([[QuirkProbeDestructiveCell alloc] initTextCell: @"Delete"]);

    [alertCell setBezelStyle: [[alertButton cell] bezelStyle]];
    [alertCell setKeyEquivalent: [alertButton keyEquivalent]];
    [alertCell setFont: [alertButton font]];
    [alertButton setCell: alertCell];
  }
  [alert orderFront: nil];
  [alert display];
  detail = [self destructiveSampleOf: alertButton fill: fill ink: ink];
  [alert orderOut: nil];
  NSReleaseAlertPanel (alert);
  /* destructive_color #c30000 (light) or #ff938c (dark) for the text, at
     15% over the dialog for the fill: a red tint, not the accent blue. */
  if ((dark ? (ink[0] > 0xf0 && labs ((long)ink[1] - 0x93) <= 12) : (labs ((long)ink[0] - 0xc3) <= 12 && ink[1] < 0x30))
    && fill[0] > fill[2] + 8 && fill[0] > fill[1] + 8)
    {
      [self pass: @"destructive-alert-button" detail: detail];
    }
  else
    {
      [self fail: @"destructive-alert-button" detail: detail];
    }
}

/* The theme's GSFontHinting: hinted metrics (high nibble 2) at scale 1,
   whole-pixel advances; metrics hinting off (1) when GSScaleFactor isn't
   1, as libs-back's own default, since hinted advances at a scale run
   glyphs together ("mustalign" at 2x). */
- (void) checkHiDPIFontHinting
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  float scale = [defaults floatForKey: @"GSScaleFactor"];
  NSInteger hinting = [defaults integerForKey: @"GSFontHinting"];
  BOOL scaled = (scale != 0.0f && scale != 1.0f);
  NSInteger want = scaled ? 1 : 2;
  NSString *detail = [NSString stringWithFormat: @"GSScaleFactor %g: GSFontHinting %ld, metrics nibble %ld (want %ld)",
    scale, (long)hinting, (long)(hinting >> 4), (long)want];

  if ((hinting >> 4) == want)
    {
      [self pass: @"hidpi-font-hinting" detail: detail];
    }
  else
    {
      [self fail: @"hidpi-font-hinting" detail: detail];
    }
}

/* What a pixel shows on an X window, which ignores alpha: the colour times
   its alpha, black under what's transparent. */
static float
QuirkProbeShownRed (NSColor *color)
{
  NSColor *rgb = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  return [rgb redComponent] * [rgb alphaComponent];
}

/* A window's edge at a scale: no pixel beside the border or round the
   content is darker than the border and the background. At 1.5 the content
   area's edge falls inside a pixel, and it used to show a dark line. Needs the
   theme's own border (-GSX11HandlesWindowDecorations NO). */
- (void) checkWindowEdgeAtScale
{
  NSWindow *window = AUTORELEASE ([[NSWindow alloc] initWithContentRect: NSMakeRect (60, 200, 300, 160)
                                                              styleMask: NSTitledWindowMask
                                                                backing: NSBackingStoreBuffered
                                                                  defer: NO]);
  NSView *frameView;
  NSBitmapImageRep *rep;
  NSInteger wide, high, x, y;
  float darkest = 1.0f;
  float limit;
  NSString *where = @"none";
  NSString *detail;

  [window orderFront: nil];
  [window display];
  /* Each redraw clears and fills the edge again, as in a running app. */
  [window display];
  frameView = [[window contentView] superview];
  if (NSMinX ([[window contentView] frame]) <= 0.0)
    {
      [self skip: @"window-edge-at-scale" detail: @"no theme border on this run"];
      [window orderOut: nil];
      return;
    }
  [frameView lockFocus];
  rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: [frameView bounds]]);
  [frameView unlockFocus];
  wide = [rep pixelsWide];
  high = [rep pixelsHigh];
  /* The outermost pixels are the border, GNOME's lightest edge and the limit. */
  limit = QuirkProbeShownRed ([rep colorAtX: 0 y: high / 2]) - 0.03f;
  /* The read itself can run half a pixel past the window: not the outermost
     pixels. */
  for (x = 1; x < wide - 1; x++)
    {
      float shown = QuirkProbeShownRed ([rep colorAtX: x y: high - 4]);

      if (shown < darkest)
        {
          darkest = shown;
          where = [NSString stringWithFormat: @"x %ld of %ld", (long)x, (long)wide];
        }
    }
  for (y = 1; y < high - 1; y++)
    {
      float shown = QuirkProbeShownRed ([rep colorAtX: wide - 6 y: y]);

      if (shown < darkest)
        {
          darkest = shown;
          where = [NSString stringWithFormat: @"y %ld of %ld", (long)y, (long)high];
        }
    }
  detail = [NSString stringWithFormat: @"GSScaleFactor %g: darkest %.3f at %@, border %.3f",
    [[NSUserDefaults standardUserDefaults] floatForKey: @"GSScaleFactor"],
    darkest, where, limit + 0.03f];
  [window orderOut: nil];
  if (darkest >= limit)
    {
      [self pass: @"window-edge-at-scale" detail: detail];
    }
  else
    {
      [self fail: @"window-edge-at-scale" detail: detail];
    }
}

/* The theme's own images (Resources/ThemeImages) carry a 2x
   representation, so at GSScaleFactor 2 they're drawn from 32px, not
   scaled up from 16px: each has a bitmap with twice its point width. The
   cursors are left out: libs-back takes a cursor's hot spot in pixels. */
- (void) checkThemeImages2x
{
  NSArray *names = [NSArray arrayWithObjects: @"common_Home", @"common_Mount", @"common_Unmount",
    @"GnomeThemeStarred-symbolic", @"GnomeThemeNonStarred-symbolic", @"NSAscendingSortIndicator",
    @"NSDescendingSortIndicator", @"GnomeThemeBranch-symbolic", nil];
  NSMutableArray *missing = [NSMutableArray array];
  NSEnumerator *enumerator = [names objectEnumerator];
  NSString *name;

  while ((name = [enumerator nextObject]) != nil)
    {
      NSImage *image = [NSImage imageNamed: name];
      NSEnumerator *reps = [[image representations] objectEnumerator];
      NSImageRep *rep;
      BOOL has2x = NO;

      while ((rep = [reps nextObject]) != nil)
        {
          if ([rep pixelsWide] >= 2 * [image size].width && [image size].width > 0)
            {
              has2x = YES;
            }
        }
      if (has2x == NO)
        {
          [missing addObject: image == nil ? [name stringByAppendingString: @" (none)"] : name];
        }
    }
  if ([missing count] == 0)
    {
      [self pass: @"theme-images-2x" detail: [NSString stringWithFormat: @"%lu images with a 2x representation",
        (unsigned long)[names count]]];
    }
  else
    {
      [self fail: @"theme-images-2x" detail: [NSString stringWithFormat: @"1x only: %@",
        [missing componentsJoinedByString: @", "]]];
    }
}

/* A dimmed label is libadwaita's --dim-opacity over the window: 55%, or
   90% in high contrast. */
- (void) checkDimLabelOpacity
{
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  NSColor *window = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSColor *dim = [[NSColor secondaryLabelColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  CGFloat span = [text redComponent] - [window redComponent];
  CGFloat fraction = (span != 0.0) ? ([dim redComponent] - [window redComponent]) / span : 0.0;
  CGFloat want = highContrast ? 0.9 : 0.55;
  NSString *detail = [NSString stringWithFormat: @"secondaryLabelColor %.0f%% from the window to the text (want %.0f%%)",
    fraction * 100.0, want * 100.0];

  if (fabs (fraction - want) <= 0.02)
    {
      [self pass: @"dim-label-opacity" detail: detail];
    }
  else
    {
      [self fail: @"dim-label-opacity" detail: detail];
    }
}

/* Column headers as libadwaita's: the foreground at 40% over the list (60%
   in high contrast), and
   no sorted state, so a highlighted column's title is as dim as another's. */
- (void) checkColumnHeaderColours
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 140) title: @"Probe Header Colours"];
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 120)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 300, 120)]);
  NSTableColumn *name = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"name"]);
  NSTableColumn *size = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"size"]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3], px[3];
  long sortedInk = 0, plainInk = 0, want, background;
  NSInteger x, y;
  NSString *detail;
  BOOL dark, highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];

  [[name headerCell] setStringValue: @"Name"];
  [[size headerCell] setStringValue: @"Size"];
  [name setWidth: 150];
  [size setWidth: 150];
  [table addTableColumn: name];
  [table addTableColumn: size];
  [scroll setHasVerticalScroller: YES];
  [scroll setDocumentView: table];
  [[window contentView] addSubview: scroll];
  [table setHighlightedTableColumn: name];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender ([table headerView]);
  QuirkProbePixelAt (rep, 120, [rep pixelsHigh] / 2, fill);
  background = (long)fill[0];
  dark = (background < 128);
  /* The strongest ink in each column's title. */
  for (y = 0; y < [rep pixelsHigh]; y++)
    {
      for (x = 0; x < 100; x++)
        {
          long a, b;

          QuirkProbePixelAt (rep, x, y, px);
          a = labs ((long)px[0] - background);
          QuirkProbePixelAt (rep, x + 150, y, px);
          b = labs ((long)px[0] - background);
          sortedInk = MAX (sortedInk, a);
          plainInk = MAX (plainInk, b);
        }
    }
  [window orderOut: nil];
  /* #adadaf on #ffffff; #777779 on #1d1d20; at 60% in high contrast. */
  want = dark ? (highContrast ? 136 : 0x77 - 0x1d) : (highContrast ? 123 : 0xff - 0xad);
  detail = [NSString stringWithFormat: @"on %@: sorted title %ld from the fill, another %ld, want %ld",
    QuirkProbeHex (fill), sortedInk, plainInk, want];
  if (labs (sortedInk - plainInk) <= 6 && labs (plainInk - want) <= 8)
    {
      [self pass: @"column-header-colours" detail: detail];
    }
  else
    {
      [self fail: @"column-header-colours" detail: detail];
    }
}

static NSImage *QuirkProbeRedImage(NSString *name);

/* How far a segment's label stands out from its fill (r+g+b), whichever
   way the palette goes, and the fill near its top edge. */
static long
QuirkProbeSegmentContrast(NSBitmapImageRep *rep, NSInteger segment, NSUInteger *fill)
{
  QuirkProbeInk ink = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (80 * segment + 12, 9, 56, 16));

  *fill = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (80 * segment + 40, 4, 2, 2)).darkest;
  return MAX ((long)*fill - (long)ink.darkest, (long)ink.lightest - (long)*fill);
}

/* A disabled segmented control, or segment, at libadwaita's insensitive
   half opacity: the fill halfway to the window, the label dimmed, the
   selected segment still told apart (ScreenshotTool's tool switcher with
   no image open, which stayed at full strength). */
- (void) checkSegmentedDisabled
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 200, 300, 80) title: @"QuirkProbe Disabled Segments"];
  NSSegmentedControl *control = AUTORELEASE ([[NSSegmentedControl alloc] initWithFrame: NSMakeRect (20, 20, 240, 34)]);
  NSBitmapImageRep *rep, *windowRep;
  NSUInteger fill[3][2], background;
  long contrast[3][2];
  NSInteger i, pass;
  NSString *detail;
  BOOL ok;

  [control setSegmentCount: 3];
  for (i = 0; i < 3; i++)
    {
      [control setLabel: [NSString stringWithFormat: @"Item %ld", (long)i + 1] forSegment: i];
      [control setWidth: 80 forSegment: i];
    }
  [control setSelectedSegment: 1];
  [[window contentView] addSubview: control];
  [window orderFront: nil];
  windowRep = QuirkProbeRender ([window contentView]);
  background = QuirkProbeMeasureIn (windowRep, QuirkProbeIsAnyPixel, NSMakeRect (2, 2, 2, 2)).darkest;
  /* Enabled; then segment 0 alone disabled; then the whole control, as
     ScreenshotTool does it. */
  for (pass = 0; pass < 3; pass++)
    {
      if (pass == 1)
        {
          [control setEnabled: NO forSegment: 0];
        }
      else if (pass == 2)
        {
          [control setEnabled: NO];
          for (i = 0; i < 3; i++)
            {
              [control setEnabled: NO forSegment: i];
            }
        }
      [window display];
      rep = QuirkProbeRender (control);
      for (i = 0; i < 2; i++)
        {
          contrast[pass][i] = QuirkProbeSegmentContrast (rep, i, &fill[pass][i]);
        }
    }
  [window orderOut: nil];

  /* Dimmed: the label at most two thirds as far from its fill (the
     theme's disabled text colour; libadwaita's half opacity gives half),
     and the fill at
     least a third closer to the window (both segments, the selected one
     too); the selected one still apart from the others. */
#define QUIRK_PROBE_CLOSER(now, was) (labs ((long)(now) - (long)background) * 3 <= labs ((long)(was) - (long)background) * 2 + 3)
  ok = contrast[1][0] * 3 <= contrast[0][0] * 2 && contrast[1][1] * 10 > contrast[0][1] * 8
    && QUIRK_PROBE_CLOSER (fill[1][0], fill[0][0])
    && contrast[2][0] * 3 <= contrast[0][0] * 2 && contrast[2][1] * 3 <= contrast[0][1] * 2
    && QUIRK_PROBE_CLOSER (fill[2][0], fill[0][0]) && QUIRK_PROBE_CLOSER (fill[2][1], fill[0][1])
    && fill[2][0] != fill[2][1];
#undef QUIRK_PROBE_CLOSER
  detail = [NSString stringWithFormat: @"r+g+b window %lu; label contrast / fill of segment 1, selected segment 2: "
    @"enabled %ld/%lu, %ld/%lu; segment 1 disabled %ld/%lu, %ld/%lu; control disabled %ld/%lu, %ld/%lu",
    (unsigned long)background,
    contrast[0][0], (unsigned long)fill[0][0], contrast[0][1], (unsigned long)fill[0][1],
    contrast[1][0], (unsigned long)fill[1][0], contrast[1][1], (unsigned long)fill[1][1],
    contrast[2][0], (unsigned long)fill[2][0], contrast[2][1], (unsigned long)fill[2][1]];
  if (ok)
    {
      [self pass: @"segment-disabled" detail: detail];
    }
  else
    {
      [self fail: @"segment-disabled" detail: detail];
    }
}

/* The same in the header bar, as ScreenshotTool's tool switcher: a
   toolbar item's view with symbolic images and no labels, disabled with
   its segments, after the toolbar validates its items. The images' colour
   moves at least a third of the way to the fill. */
- (void) checkHeaderBarSegmentedDisabled
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *searchList;
  QuirkProbeSegmentToolbarDelegate *delegate;
  NSWindow *window;
  NSToolbar *toolbar;
  NSSegmentedControl *control = AUTORELEASE ([[NSSegmentedControl alloc] initWithFrame: NSMakeRect (0, 0, 120, 34)]);
  NSBitmapImageRep *rep;
  long contrast[2][2];
  NSUInteger fill[2][2];
  NSInteger i, pass;
  NSString *detail;

  if (QuirkProbeDrawsDecorations () == NO)
    {
      [self skip: @"header-bar-segment-disabled" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  [defaults setVolatileDomain: [NSDictionary dictionaryWithObject: @"YES" forKey: @"GnomeThemeHeaderBarToolbar"]
                      forName: @"QuirkProbeHeaderBarSegments"];
  searchList = AUTORELEASE ([[defaults searchList] mutableCopy]);
  [searchList insertObject: @"QuirkProbeHeaderBarSegments" atIndex: 0];
  [defaults setSearchList: searchList];

  [control setSegmentCount: 3];
  [[control cell] setTrackingMode: NSSegmentSwitchTrackingSelectOne];
  for (i = 0; i < 3; i++)
    {
      [control setWidth: 40 forSegment: i];
      [control setLabel: @"" forSegment: i];
      [control setImage: QuirkProbeRedImage ([NSString stringWithFormat: @"quirk-probe-tool-%ld-symbolic", (long)i])
             forSegment: i];
    }
  [control setSelectedSegment: 1];
  delegate = AUTORELEASE ([QuirkProbeSegmentToolbarDelegate new]);
  delegate->control = control;
  window = [self windowWithFrame: NSMakeRect (40, 200, 500, 200) title: @"Probe Segments Bar"];
  toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeHeaderSegments"]);
  [toolbar setDelegate: delegate];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  for (pass = 0; pass < 2; pass++)
    {
      if (pass == 1)
        {
          [control setEnabled: NO];
          for (i = 0; i < 3; i++)
            {
              [control setEnabled: NO forSegment: i];
            }
        }
      [toolbar validateVisibleItems];
      [window display];
      rep = QuirkProbeRender (control);
      for (i = 0; i < 2; i++)
        {
          NSUInteger centre = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (40 * i + 19, 16, 2, 2)).darkest;

          fill[pass][i] = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (40 * i + 4, 4, 2, 2)).darkest;
          contrast[pass][i] = labs ((long)centre - (long)fill[pass][i]);
        }
    }
  [window orderOut: nil];

  /* With an item that has a view (the segmented control), the last item
     stays in the bar while there's room, at its end, and nothing goes into
     the » menu (alpha12 put ScreenshotTool's Copy there at any width). */
  {
    NSMutableArray *failures = [NSMutableArray array];
    CGFloat widths[3] = { 400.0, 800.0, 1100.0 };
    int w;

    for (w = 0; w < 3; w++)
      {
        NSWindow *sized = [self windowWithFrame: NSMakeRect (40, 200, widths[w], 200) title: @"Probe Last Item"];
        NSString *identifier = [NSString stringWithFormat: @"QuirkProbeHeaderLastItem%d", w];
        NSToolbar *sizedToolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: identifier]);
        NSView *toolbarView, *copyView = nil, *subview;
        NSEnumerator *enumerator;
        NSToolbarItem *item;
        NSRect copyFrame = NSZeroRect;
        BOOL overflow = NO;

        [sizedToolbar setDelegate: delegate];
        [sized setToolbar: sizedToolbar];
        [sized orderFront: nil];
        [sized display];
        toolbarView = [sizedToolbar _toolbarView];
        enumerator = [[sizedToolbar items] objectEnumerator];
        while ((item = [enumerator nextObject]) != nil)
          {
            if ([[item itemIdentifier] isEqualToString: @"Copy"])
              {
                copyView = [item _backView];
                copyFrame = [toolbarView convertRect: [copyView bounds] fromView: copyView];
              }
          }
        enumerator = [[toolbarView subviews] objectEnumerator];
        while ((subview = [enumerator nextObject]) != nil)
          {
            overflow = overflow || ([subview isKindOfClass: [NSButton class]] && [subview superview] == toolbarView);
          }
        if (copyView == nil || overflow || NSMaxX (copyFrame) > NSWidth ([toolbarView frame]) + 0.5
            || NSMaxX (copyFrame) < NSWidth ([toolbarView frame]) - 1.5)
          {
            [failures addObject: [NSString stringWithFormat: @"%g: Copy %g-%g in %g%@", widths[w],
              NSMinX (copyFrame), NSMaxX (copyFrame), NSWidth ([toolbarView frame]), overflow ? @", » shown" : @""]];
          }
        [sized orderOut: nil];
      }
    if ([failures count] == 0)
      {
        [self pass: @"header-bar-toolbar-last-item" detail: @"at 400, 800 and 1100pt the last item is at the toolbar's end, no »"];
      }
    else
      {
        [self fail: @"header-bar-toolbar-last-item" detail: [failures componentsJoinedByString: @"; "]];
      }
  }
  [defaults removeVolatileDomainForName: @"QuirkProbeHeaderBarSegments"];
  [searchList removeObject: @"QuirkProbeHeaderBarSegments"];
  [defaults setSearchList: searchList];

  detail = [NSString stringWithFormat: @"image contrast / fill (r+g+b), segment 1 and selected segment 2: "
    @"enabled %ld/%lu, %ld/%lu; disabled %ld/%lu, %ld/%lu (control enabled %d)",
    contrast[0][0], (unsigned long)fill[0][0], contrast[0][1], (unsigned long)fill[0][1],
    contrast[1][0], (unsigned long)fill[1][0], contrast[1][1], (unsigned long)fill[1][1], (int)[control isEnabled]];
  if (contrast[0][0] > 60 && contrast[1][0] * 3 <= contrast[0][0] * 2 && contrast[1][1] * 3 <= contrast[0][1] * 2
    && fill[1][0] != fill[1][1])
    {
      [self pass: @"header-bar-segment-disabled" detail: detail];
    }
  else
    {
      [self fail: @"header-bar-segment-disabled" detail: detail];
    }
}

- (void) checkLabel: (NSView *)label ident: (NSString *)ident lineHeight: (NSInteger)lineHeight
{
  QuirkProbeInk ink = QuirkProbeTextInk (label);
  NSString *detail = [NSString stringWithFormat: @"text ink %ldpt high, one line %ldpt",
    (long)ink.height, (long)lineHeight];

  if (lineHeight > 0 && ink.height * 2 >= lineHeight * 3)
    {
      [self pass: ident detail: detail];
    }
  else
    {
      [self fail: ident detail: [detail stringByAppendingString: @" (one line only)"]];
    }
}

- (NSInteger) lineHeight
{
  return QuirkProbeTextInk ([[_controlsWindow contentView] viewWithTag: 1]).height;
}

- (void) checkLabels
{
  NSInteger lineHeight = [self lineHeight];
  NSEnumerator *enumerator;
  NSTextField *label;

  [self checkLabel: _wrappingLabel ident: @"label-wraps" lineHeight: lineHeight];
  [self checkLabel: _newlineLabel ident: @"label-newline" lineHeight: lineHeight];

  enumerator = [[NSArray arrayWithObjects: _pathLabel, _truncatedPathLabel, nil] objectEnumerator];
  while ((label = [enumerator nextObject]) != nil)
    {
      QuirkProbeInk ink = QuirkProbeTextInk (label);
      NSString *ident = (label == _pathLabel) ? @"long-path-label" : @"long-path-label-truncated";
      NSString *detail = [NSString stringWithFormat: @"text ink %ldpt wide in a %gpt label",
        (long)ink.width, NSWidth ([label frame])];

      if (ink.width * 2 >= NSWidth ([label frame]))
        {
          [self pass: ident detail: detail];
        }
      else
        {
          [self fail: ident detail: [detail stringByAppendingString: @" (drew little or nothing)"]];
        }
    }
}

- (void) checkToolbar
{
  NSView *frameView = [[_toolbarWindow contentView] superview];
  QuirkProbeInk magenta = QuirkProbeMeasure (QuirkProbeRender (frameView), QuirkProbeIsMagenta);
  NSString *detail;

  /* Only the image-only item can draw magenta: the view item's image is lost
     (checked below). */
  detail = [NSString stringWithFormat: @"%lu image pixels drawn", (unsigned long)magenta.count];
  if (magenta.count >= 100)
    {
      [self pass: @"toolbar-image-item-draws" detail: detail];
    }
  else
    {
      [self fail: @"toolbar-image-item-draws" detail: detail];
    }

  if ([_toolbarViewButton image] == nil)
    {
      [self known: @"toolbar-view-item-image"
             detail: @"libs-gui: -[NSToolbarItem _layout] sets the view's image to nil "
                     @"(Docs/upstream-issues/1-libs-gui-toolbar-view-item-image.md)"];
    }
  else
    {
      [self pass: @"toolbar-view-item-image"
            detail: @"the view kept its image: fixed upstream? Update IMPROVEMENTS.md"];
    }
}

/* Pixels on the boundary lines between rows 0-1, 1-2 and 2-3 that are
   darker than the white row background, in the right half of the table
   (clear of the rows' text and its descenders). */
- (NSUInteger) gridPixelsInTable: (NSTableView *)tableView
{
  NSBitmapImageRep *rep = QuirkProbeRender (tableView);
  NSUInteger count = 0;
  NSInteger row;

  for (row = 0; row < 3; row++)
    {
      NSInteger y = (NSInteger)NSMaxY ([tableView rectOfRow: row]) - 1;

      count += QuirkProbeMeasureIn (rep, QuirkProbeIsNotWhite,
                                    NSMakeRect ([rep pixelsWide] / 2, y, [rep pixelsWide] / 2, 1)).count;
    }
  return count;
}

- (void) checkTables
{
  NSUInteger defaultGrid = [self gridPixelsInTable: _defaultGridTable];
  NSUInteger explicitGrid = [self gridPixelsInTable: _explicitGridTable];
  NSInteger width = (NSInteger)NSWidth ([_defaultGridTable bounds]);
  NSScrollView *scrollView = [_defaultGridTable enclosingScrollView];
  NSBitmapImageRep *scrollRep = QuirkProbeRender (scrollView);
  NSInteger scrollWidth = [scrollRep pixelsWide];
  NSInteger scrollHeight = [scrollRep pixelsHigh];
  NSUInteger framePixels = 0;
  NSTableHeaderView *headerView = [_defaultGridTable headerView];
  QuirkProbeInk headerInk = QuirkProbeMeasure (QuirkProbeRender (headerView), QuirkProbeIsNotWhite);
  QuirkProbeInk rowInk = QuirkProbeMeasure (QuirkProbeRender (_defaultGridTable), QuirkProbeIsNotWhite);
  NSString *detail;

  detail = [NSString stringWithFormat: @"%lu grid pixels on 3 half-row boundaries",
    (unsigned long)defaultGrid];
  if (defaultGrid == 0)
    {
      [self pass: @"table-grid-default" detail: detail];
    }
  else
    {
      [self fail: @"table-grid-default"
          detail: [detail stringByAppendingString: @" (GNUstep's default grid should draw none)"]];
    }

  detail = [NSString stringWithFormat: @"%lu grid pixels on 3 half-row boundaries of %ldpt",
    (unsigned long)explicitGrid, (long)width / 2];
  if (explicitGrid >= (NSUInteger)width * 3 / 4)
    {
      [self pass: @"table-grid-explicit" detail: detail];
    }
  else
    {
      [self fail: @"table-grid-explicit"
          detail: [detail stringByAppendingString: @" (asked-for grid lines missing)"]];
    }

  /* The scroll view's outermost ring of pixels. */
  framePixels += QuirkProbeMeasureIn (scrollRep, QuirkProbeIsNotWhite, NSMakeRect (0, 0, scrollWidth, 1)).count;
  framePixels += QuirkProbeMeasureIn (scrollRep, QuirkProbeIsNotWhite, NSMakeRect (0, scrollHeight - 1, scrollWidth, 1)).count;
  framePixels += QuirkProbeMeasureIn (scrollRep, QuirkProbeIsNotWhite, NSMakeRect (0, 0, 1, scrollHeight)).count;
  framePixels += QuirkProbeMeasureIn (scrollRep, QuirkProbeIsNotWhite, NSMakeRect (scrollWidth - 1, 0, 1, scrollHeight)).count;
  detail = [NSString stringWithFormat: @"%lu frame pixels around a bezel-bordered table", (unsigned long)framePixels];
  if (framePixels == 0)
    {
      [self pass: @"table-no-frame" detail: detail];
    }
  else
    {
      [self fail: @"table-no-frame" detail: detail];
    }

  detail = [NSString stringWithFormat: @"header text starts at %ldpt, rows at %ldpt; darkest header %lu, rows %lu",
    (long)headerInk.minX, (long)rowInk.minX,
    (unsigned long)headerInk.darkest, (unsigned long)rowInk.darkest];
  if (headerInk.count > 0 && rowInk.count > 0
    && ABS (headerInk.minX - rowInk.minX) <= 2
    && headerInk.darkest >= rowInk.darkest + 120)
    {
      [self pass: @"table-header" detail: detail];
    }
  else
    {
      [self fail: @"table-header"
          detail: [detail stringByAppendingString: @" (want left-aligned with the rows, and dimmer)"]];
    }
}

/* GNOME apps have no menu named after the app; an empty one (this probe's:
   its only menu is File) should be gone. */
- (void) checkMenuBar
{
  NSMenu *mainMenu = [NSApp mainMenu];
  NSString *first = ([mainMenu numberOfItems] > 0) ? [[mainMenu itemAtIndex: 0] title] : @"";
  NSString *detail = [NSString stringWithFormat: @"first menu bar item \"%@\"", first];

  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      [self skip: @"menubar-no-empty-app-item" detail: @"needs -NSMenuInterfaceStyle NSWindows95InterfaceStyle"];
    }
  else if ([first isEqualToString: [[NSProcessInfo processInfo] processName]])
    {
      [self fail: @"menubar-no-empty-app-item" detail: [detail stringByAppendingString: @" (empty app menu shown)"]];
    }
  else
    {
      [self pass: @"menubar-no-empty-app-item" detail: detail];
    }
}

/* No dark line across the menu bar and toolbar (GSTheme's fallback toolbar
   border is dark grey). */
- (void) checkToolbarEdges
{
  NSView *frameView = [[_toolbarWindow contentView] superview];
  NSView *toolbarView = QuirkProbeFindViewOfClass (frameView, NSClassFromString (@"GSToolbarView"));
  NSBitmapImageRep *rep = QuirkProbeRender (frameView);
  NSInteger bottom = 120;
  QuirkProbeInk dark;
  NSString *detail;

  if (toolbarView != nil)
    {
      NSRect frame = [toolbarView convertRect: [toolbarView bounds] toView: frameView];

      bottom = (NSInteger)([frameView isFlipped] ? NSMaxY (frame) : NSHeight ([frameView bounds]) - NSMinY (frame)) + 2;
    }
  /* A column clear of the toolbar items, from the top to just below the
     toolbar. */
  dark = QuirkProbeMeasureIn (rep, QuirkProbeIsTextInk,
                              NSMakeRect ([rep pixelsWide] - 5, 0, 1, bottom));
  detail = [NSString stringWithFormat: @"%lu dark pixels in the top %ldpt of the right edge",
    (unsigned long)dark.count, (long)bottom];
  if (dark.count == 0)
    {
      [self pass: @"toolbar-edges-light" detail: detail];
    }
  else
    {
      [self fail: @"toolbar-edges-light" detail: detail];
    }
}

/* Moving the pointer over an image toolbar button shows the hover
   background. */
- (void) checkToolbarHover
{
  NSView *frameView = [[_toolbarWindow contentView] superview];
  NSView *button = QuirkProbeFindViewOfClass (frameView, NSClassFromString (@"GSToolbarButton"));
  NSRect inWindow;
  NSUInteger before, after;
  NSRect edge;

  if (button == nil)
    {
      [self fail: @"toolbar-hover" detail: @"no toolbar button found"];
      return;
    }
  /* A strip along the left edge, clear of the icon and label. */
  edge = NSMakeRect (3, NSHeight ([button bounds]) / 2 - 5, 4, 10);
  inWindow = [button convertRect: [button bounds] toView: nil];
  QuirkProbeMoveMouse (_toolbarWindow, NSMakePoint (NSMaxX (inWindow) + 150, NSMinY (inWindow) - 30));
  before = QuirkProbeMeasureIn (QuirkProbeRender (button), QuirkProbeIsAnyPixel, edge).darkest;
  QuirkProbeMoveMouse (_toolbarWindow, NSMakePoint (NSMidX (inWindow), NSMidY (inWindow)));
  after = QuirkProbeMeasureIn (QuirkProbeRender (button), QuirkProbeIsAnyPixel, edge).darkest;
  QuirkProbeMoveMouse (_toolbarWindow, NSMakePoint (NSMaxX (inWindow) + 150, NSMinY (inWindow) - 30));

  if (after + 20 <= before)
    {
      [self pass: @"toolbar-hover"
          detail: [NSString stringWithFormat: @"background %lu away from the pointer, %lu under it",
                     (unsigned long)before, (unsigned long)after]];
    }
  else
    {
      [self fail: @"toolbar-hover"
          detail: [NSString stringWithFormat: @"background %lu away from the pointer, %lu under it (no hover)",
                     (unsigned long)before, (unsigned long)after]];
    }
}

/* A pop-up button's title starts near its left edge (the originals of the
   theme's NSMenuItemCell overrides would put it about 50pt in). */
- (void) checkPopUpButton
{
  QuirkProbeInk ink = QuirkProbeTextInk (_popUpButton);
  NSString *detail = [NSString stringWithFormat: @"title starts %ldpt from the left edge", (long)ink.minX];

  if (ink.count > 0 && ink.minX <= 24)
    {
      [self pass: @"popup-title-position" detail: detail];
    }
  else
    {
      [self fail: @"popup-title-position" detail: detail];
    }
}

/* A pop-up button's chevron is libadwaita's pan-down: about 10x7 with a
   2px stroke, in the text colour, and nothing else at that end (GNUstep's
   was 6x4 and faint, after a divider; plugins-themes-Adwaita#59). */
- (void) checkPopUpChevron
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 70) title: @"Probe Chevron"];
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 18, 200, 34)
                                                                pullsDown: NO]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  QuirkProbeInk ink;
  NSInteger width;
  NSString *detail;

  [popUp addItemWithTitle: @"x"];
  [[window contentView] addSubview: popUp];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (popUp);
  width = [rep pixelsWide];
  QuirkProbePixelAt (rep, width - 6, [rep pixelsHigh] / 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  /* Inside the bezel: in high contrast its 1px outline (#61) runs along the
     top, bottom and right edges and isn't the chevron. */
  ink = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (width - 40, 4, 32, [rep pixelsHigh] - 8));
  QuirkProbeInkBackground = 750;
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"ink %ldx%ld at the right end (want about 10x7)", (long)ink.width, (long)ink.height];
  if (ink.count > 0 && ink.width >= 9 && ink.width <= 11 && ink.height >= 5 && ink.height <= 8)
    {
      [self pass: @"popup-chevron" detail: detail];
    }
  else
    {
      [self fail: @"popup-chevron" detail: detail];
    }
}

/* Focus-visible is a window's own, as in GTK: a key press in one window
   (LinDirStat's Ctrl+, in its main window) doesn't ring the first key view
   of the dialog it opens; a key press in the dialog does (#85). */
- (void) checkFocusVisiblePerWindow
{
  NSWindow *main = [self windowWithFrame: NSMakeRect (480, 600, 200, 60) title: @"QuirkProbe Focus Main"];
  NSWindow *dialog = [self windowWithFrame: NSMakeRect (480, 700, 260, 60) title: @"QuirkProbe Focus Dialog"];
  NSButton *checkbox = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20, 18, 220, 24)]);
  QuirkProbeInk opened, afterKey;
  NSString *detail;

  [checkbox setButtonType: NSSwitchButton];
  [checkbox setTitle: @"Show sizes"];
  [[dialog contentView] addSubview: checkbox];
  [main makeKeyAndOrderFront: nil];
  QuirkProbeSendApplicationEvent (main, NSKeyDown);
  [dialog makeKeyAndOrderFront: nil];
  [dialog makeFirstResponder: checkbox];
  [dialog display];
  opened = QuirkProbeMeasure (QuirkProbeRender (checkbox), QuirkProbeIsFocusBlue);
  QuirkProbeSendApplicationEvent (dialog, NSKeyDown);
  [dialog display];
  afterKey = QuirkProbeMeasure (QuirkProbeRender (checkbox), QuirkProbeIsFocusBlue);
  [self saveWindow: dialog named: @"focus-visible-per-window"];
  /* Leave focus-visible off for later checks. */
  QuirkProbeSendApplicationEvent (dialog, NSLeftMouseDown);
  QuirkProbeSendApplicationEvent (dialog, NSLeftMouseUp);
  QuirkProbeSendApplicationEvent (main, NSLeftMouseDown);
  QuirkProbeSendApplicationEvent (main, NSLeftMouseUp);
  [dialog orderOut: nil];
  [main orderOut: nil];

  detail = [NSString stringWithFormat: @"checkbox ring pixels: %lu when the dialog opens after a key "
    @"in another window (want 0), %lu after a key in the dialog", (unsigned long)opened.count,
    (unsigned long)afterKey.count];
  if (opened.count == 0 && afterKey.count > 20)
    {
      [self pass: @"focus-visible-per-window" detail: detail];
    }
  else
    {
      [self fail: @"focus-visible-per-window" detail: detail];
    }
}

/* The rows of `rect` (pixels, top-left origin) in which some pixel is
   more than 6 apart from the background at its top-left corner, from the
   first such row to the last. */
static NSInteger
QuirkProbeRowsUnlikeBackground (NSBitmapImageRep *rep, NSRect rect)
{
  NSUInteger back[3], pixel[3];
  NSInteger x, y, first = -1, last = -1;

  QuirkProbePixelAt (rep, (NSInteger)NSMinX (rect), (NSInteger)NSMinY (rect), back);
  for (y = (NSInteger)NSMinY (rect); y < (NSInteger)NSMaxY (rect) && y < [rep pixelsHigh]; y++)
    {
      for (x = (NSInteger)NSMinX (rect); x < (NSInteger)NSMaxX (rect) && x < [rep pixelsWide]; x++)
        {
          QuirkProbePixelAt (rep, x, y, pixel);
          if (labs ((long)pixel[0] - (long)back[0]) + labs ((long)pixel[1] - (long)back[1])
              + labs ((long)pixel[2] - (long)back[2]) > 6)
            {
              first = first < 0 ? y : first;
              last = y;
              break;
            }
        }
    }
  return first < 0 ? 0 : last - first + 1;
}

/* Sized to fit, a combo box and a pop-up button are as tall as a push
   button: GTK's entry and GtkDropDown are 34px, as its buttons are
   (LinDirStat's folder combo box was 25pt beside a 34pt Browse…, #86).
   The combo box's field fills its frame, as LinDirStat builds it: sized
   to fit while empty, placed, filled, and its window's first key view.
   A bezeled text field is as tall (GtkEntry); a label isn't. */
- (void) checkControlHeights
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 420, 70) title: @"Probe Control Heights"];
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (10, 10, 100, 20)]);
  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (0, 0, 200, 34)]);
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (280, 10, 120, 20)
                                                                pullsDown: NO]);
  NSTextField *field34 = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (0, 0, 40, 20)]);
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (0, 0, 40, 20)]);
  CGFloat buttonHeight, comboHeight, placedHeight, popUpHeight;
  NSInteger field, editedField;
  NSString *detail;
  NSRect strip;

  [button setTitle: @"Browse…"];
  [button setBezelStyle: NSRoundedBezelStyle];
  [popUp addItemWithTitle: @"System Default"];
  [combo setEditable: YES];
  [combo setCompletes: NO];
  [combo setUsesDataSource: NO];
  [combo setNumberOfVisibleItems: 10];
  [field34 setStringValue: @"0"];
  [label setStringValue: @"Minimum"];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];
  [label setEditable: NO];
  [field34 sizeToFit];
  [label sizeToFit];
  [button sizeToFit];
  [combo sizeToFit];
  [popUp sizeToFit];
  comboHeight = NSHeight ([combo frame]);
  [combo setFrame: NSMakeRect (120, 10, 150, comboHeight)];
  placedHeight = NSHeight ([combo frame]);
  [[window contentView] addSubview: button];
  [[window contentView] addSubview: combo];
  [[window contentView] addSubview: popUp];
  [combo addItemsWithObjectValues: [NSArray arrayWithObject: @"/usr/share/doc"]];
  [combo setStringValue: @"/usr/share/doc"];
  [window setInitialFirstResponder: combo];
  [window makeKeyAndOrderFront: nil];
  [window display];
  /* A strip of the combo box's field between its text and its chevron,
     clear of the rounded corners, with the window's background above and
     below. */
  strip = NSMakeRect (NSMinX ([combo frame]) + 105, 0, 3, NSHeight ([[window contentView] frame]));
  editedField = QuirkProbeRowsUnlikeBackground (QuirkProbeRender ([window contentView]), strip);
  [window makeFirstResponder: nil];
  [window display];
  field = QuirkProbeRowsUnlikeBackground (QuirkProbeRender ([window contentView]), strip);
  [self saveWindow: window named: @"control-heights"];
  [window orderOut: nil];
  buttonHeight = NSHeight ([button frame]);
  popUpHeight = NSHeight ([popUp frame]);

  detail = [NSString stringWithFormat: @"sized to fit: button %g, combo box %g, pop-up %g high "
    @"(want 34 or more, within 1 of the button); the combo box %g high after -setFrame:, its field "
    @"drawn %ld high, %ld as the first key view (want within 2 of its frame); a text field %g high, "
    @"a label %g", buttonHeight, comboHeight,
    popUpHeight, placedHeight, (long)field, (long)editedField, NSHeight ([field34 frame]), NSHeight ([label frame])];
  if (comboHeight >= 34.0 && popUpHeight >= 34.0
    && fabs (comboHeight - buttonHeight) <= 1.0 && fabs (popUpHeight - buttonHeight) <= 1.0
    && fabs (NSHeight ([field34 frame]) - buttonHeight) <= 1.0 && NSHeight ([label frame]) < 30.0
    && placedHeight == comboHeight && field >= comboHeight - 2.0 && editedField >= comboHeight - 2.0)
    {
      [self pass: @"control-heights" detail: detail];
    }
  else
    {
      [self fail: @"control-heights" detail: detail];
    }
}

/* A focused push button, as in OneDriveServiceManager's Resync panel, where
   Cancel is the first key view. As in GTK, the ring shows only after a key
   press. It runs along the button's edge: not around the title (where NSCell
   put a second ring) and not in the corners outside the rounded fill (all
   that showed of a ring drawn outside the frame). */
- (void) checkButtonFocusRing
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (480, 700, 200, 60) title: @"QuirkProbe Focus"];
  NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect (40, 15, 120, 30)];
  NSRect bounds;
  NSRect inner;
  QuirkProbeInk afterClick, afterKey, title, corner;
  NSString *detail;

  [button setTitle: @"Cancel"];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setKeyEquivalent: @"\e"];
  [[window contentView] addSubview: button];
  RELEASE (button);
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: button];
  bounds = [button bounds];
  inner = NSInsetRect (bounds, 5, 5);

  QuirkProbeSendApplicationEvent (window, NSLeftMouseDown);
  QuirkProbeSendApplicationEvent (window, NSLeftMouseUp);
  afterClick = QuirkProbeMeasure (QuirkProbeRender (button), QuirkProbeIsFocusBlue);
  QuirkProbeSendApplicationEvent (window, NSKeyDown);
  afterKey = QuirkProbeMeasure (QuirkProbeRender (button), QuirkProbeIsFocusBlue);
  title = QuirkProbeMeasureIn (QuirkProbeRender (button), QuirkProbeIsFocusBlue, inner);
  corner = QuirkProbeMeasureIn (QuirkProbeRender (button), QuirkProbeIsFocusBlue, NSMakeRect (0, 0, 2, 2));
  [self saveWindow: window named: @"button-focus"];
  /* Leave focus-visible off for later checks. */
  QuirkProbeSendApplicationEvent (window, NSLeftMouseDown);
  QuirkProbeSendApplicationEvent (window, NSLeftMouseUp);
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"ring pixels: %lu after a click, %lu after a key "
    @"(%ldx%ld of %gx%g), %lu around the title, %lu in the corner",
    (unsigned long)afterClick.count, (unsigned long)afterKey.count,
    (long)afterKey.width, (long)afterKey.height, NSWidth (bounds), NSHeight (bounds),
    (unsigned long)title.count, (unsigned long)corner.count];
  if (afterClick.count == 0 && afterKey.count > 0
    && afterKey.width + 4 >= NSWidth (bounds) && afterKey.height + 4 >= NSHeight (bounds)
    && title.count == 0 && corner.count == 0)
    {
      [self pass: @"button-focus-ring" detail: detail];
    }
  else
    {
      [self fail: @"button-focus-ring" detail: detail];
    }
}

/* The label starts about 5px after a checkbox's indicator, as in GTK. */
- (void) checkCheckboxGap
{
  NSEnumerator *enumerator = [_sizedButtons objectEnumerator];
  NSArray *pair;

  while ((pair = [enumerator nextObject]) != nil)
    {
      NSButton *button = [pair objectAtIndex: 0];
      NSBitmapImageRep *rep;
      QuirkProbeInk text, indicator;
      NSInteger gap;
      NSString *detail;

      if ([[button title] isEqualToString: @"Errors only"] == NO)
        {
          continue;
        }
      rep = QuirkProbeRender (button);
      text = QuirkProbeMeasure (rep, QuirkProbeIsTextInk);
      indicator = QuirkProbeMeasureIn (rep, QuirkProbeIsNotWhite,
                                       NSMakeRect (0, 0, text.minX - 1, [rep pixelsHigh]));
      gap = text.minX - (indicator.minX + indicator.width);
      detail = [NSString stringWithFormat: @"indicator %ldpx wide, label %ldpx after it",
        (long)indicator.width, (long)gap];
      if (text.count > 0 && indicator.count > 0 && gap >= 3 && gap <= 7)
        {
          [self pass: @"checkbox-label-gap" detail: detail];
        }
      else
        {
          [self fail: @"checkbox-label-gap" detail: detail];
        }
      return;
    }
  [self fail: @"checkbox-label-gap" detail: @"checkbox not found"];
}

/* A table built in code gets GTK's list density; one the app sized keeps
   its rows. */
- (void) checkTableDensity
{
  NSTableView *plain = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 100, 100)]);
  NSTableView *sized = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 100, 100)]);
  NSString *detail;

  [sized setRowHeight: 22.0];
  detail = [NSString stringWithFormat: @"default rows %gpt, spacing %@; app-sized rows %gpt",
    [plain rowHeight], NSStringFromSize ([plain intercellSpacing]), [sized rowHeight]];
  if ([plain rowHeight] >= 34.0 && NSEqualSizes ([plain intercellSpacing], NSZeroSize)
    && [sized rowHeight] == 22.0)
    {
      [self pass: @"table-row-density" detail: detail];
    }
  else
    {
      [self fail: @"table-row-density" detail: detail];
    }
}

/* Top tabs are flat, GtkNotebook style: only the selected tab is marked, by
   a 4px accent underline at the bottom of the tab strip. */
- (void) checkTabView
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (700, 700, 360, 120) title: @"QuirkProbe Tabs"];
  NSTabView *tabView = [[NSTabView alloc] initWithFrame: NSMakeRect (10, 10, 340, 100)];
  NSArray *labels = [NSArray arrayWithObjects: @"Overview", @"Activity", @"Settings", nil];
  NSEnumerator *enumerator = [labels objectEnumerator];
  NSString *label;
  NSBitmapImageRep *rep;
  CGFloat tabHeight = [[GSTheme theme] tabHeightForType: NSTopTabsBezelBorder];
  QuirkProbeInk accent, text;
  NSString *detail;

  while ((label = [enumerator nextObject]) != nil)
    {
      NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier: label];

      [item setLabel: label];
      [tabView addTabViewItem: item];
      RELEASE (item);
    }
  [[window contentView] addSubview: tabView];
  RELEASE (tabView);
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (tabView);
  [self saveWindow: window named: @"tabs"];
  [window orderOut: nil];

  accent = QuirkProbeMeasureIn (rep, QuirkProbeIsFocusBlue, NSMakeRect (0, 0, [rep pixelsWide], tabHeight));
  text = QuirkProbeMeasureIn (rep, QuirkProbeIsTextInk, NSMakeRect (0, 0, [rep pixelsWide], tabHeight));
  detail = [NSString stringWithFormat: @"accent %ldx%ld at x %ld in a %gpt strip; labels from x %ld",
    (long)accent.width, (long)accent.height, (long)accent.minX, tabHeight, (long)text.minX];
  /* One underline, 4px high, under the first tab only (it starts left of
     the first label and is far narrower than the strip). */
  if (accent.count > 0 && accent.height == 4 && accent.minX < text.minX
    && accent.width < [rep pixelsWide] / 2 && accent.count == (NSUInteger)(accent.width * accent.height))
    {
      [self pass: @"tab-view-flat" detail: detail];
    }
  else
    {
      [self fail: @"tab-view-flat" detail: detail];
    }
}

/* A toolbar the app gives no display mode starts icon-only, as GNOME header
   bars are; one the app sets keeps its mode, and a toolbar with the same
   identifier copies it. */
- (void) checkToolbarDisplayMode
{
  NSToolbar *fresh = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeFresh"]);
  NSToolbar *chosen = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeChosen"]);
  NSToolbar *sibling;
  NSString *detail;

  [chosen setDisplayMode: NSToolbarDisplayModeIconAndLabel];
  sibling = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeChosen"]);
  detail = [NSString stringWithFormat: @"default %d, app's choice %d, same identifier %d (icon-only %d, icon and label %d)",
    (int)[fresh displayMode], (int)[chosen displayMode], (int)[sibling displayMode],
    (int)NSToolbarDisplayModeIconOnly, (int)NSToolbarDisplayModeIconAndLabel];
  if ([fresh displayMode] == NSToolbarDisplayModeIconOnly
    && [chosen displayMode] == NSToolbarDisplayModeIconAndLabel
    && [sibling displayMode] == NSToolbarDisplayModeIconAndLabel)
    {
      [self pass: @"toolbar-default-icon-only" detail: detail];
    }
  else
    {
      [self fail: @"toolbar-default-icon-only" detail: detail];
    }
}

/* With an application menu (the app has loose items such as Info), its ☰
   sits at the right end of the menu bar, and clicks there reach it. */
- (void) checkApplicationMenuPosition
{
  NSMenu *mainMenu = [NSApp mainMenu];
  NSMenu *appMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: [[NSProcessInfo processInfo] processName]]);
  NSMenuItem *appItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: [[NSProcessInfo processInfo] processName]
                                                                  action: NULL
                                                           keyEquivalent: @""]);
  NSMenuView *menuView;
  NSRect appRect, fileRect;
  NSInteger hit;
  CGFloat submenuRight, itemRight;
  NSString *detail;

  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      [self skip: @"menubar-app-menu-at-end" detail: @"needs -NSMenuInterfaceStyle NSWindows95InterfaceStyle"];
      return;
    }
  [appMenu addItemWithTitle: @"Info" action: NULL keyEquivalent: @""];
  [appItem setSubmenu: appMenu];
  [mainMenu insertItem: appItem atIndex: 0];
  menuView = (NSMenuView *)QuirkProbeFindViewOfClass ([[_controlsWindow contentView] superview],
                                                      [NSMenuView class]);
  [menuView sizeToFit];
  appRect = [menuView rectOfItemAtIndex: 0];
  fileRect = [menuView rectOfItemAtIndex: 1];
  hit = [menuView indexOfItemAtPoint: NSMakePoint (NSMidX (appRect), NSMidY (appRect))];
  /* Its menu opens with right edges aligned. */
  submenuRight = [menuView locationForSubmenu: appMenu].x
    + NSWidth ([[[appMenu menuRepresentation] window] frame]);
  itemRight = [_controlsWindow convertBaseToScreen:
                 [menuView convertPoint: NSMakePoint (NSMaxX (appRect), 0) toView: nil]].x;
  [mainMenu removeItem: appItem];
  [menuView sizeToFit];

  detail = [NSString stringWithFormat: @"app menu at x %g-%g of %g, File at x %g, a click on the app menu hits item %ld, "
    @"its menu ends at screen x %g (the item at %g)",
    NSMinX (appRect), NSMaxX (appRect), NSWidth ([menuView bounds]), NSMinX (fileRect), (long)hit,
    submenuRight, itemRight];
  if (menuView == nil)
    {
      [self fail: @"menubar-app-menu-at-end" detail: @"no menu view in the window"];
    }
  else if (NSMaxX (appRect) > NSWidth ([menuView bounds]) - 20 && NSMinX (fileRect) < 20 && hit == 0
    && fabs (submenuRight - itemRight) < 1.0)
    {
      [self pass: @"menubar-app-menu-at-end" detail: detail];
    }
  else
    {
      [self fail: @"menubar-app-menu-at-end" detail: detail];
    }
}

/* The menu bar overflow check: actions run by a folded menu's key
   equivalent, and the items of the menu the overflow button showed. */
static NSUInteger QuirkProbeOverflowActions = 0;
static NSString *QuirkProbeOverflowShown = nil;

- (void) overflowAction: (id)sender
{
  QuirkProbeOverflowActions++;
}

/* Fires while the overflow button's menu tracks: note its items, then
   click elsewhere to close it. */
- (void) inspectOverflowMenu: (NSTimer *)timer
{
  NSEnumerator *enumerator = [[NSApp windows] objectEnumerator];
  NSWindow *window;

  ASSIGN (QuirkProbeOverflowShown, @"");
  while ((window = [enumerator nextObject]) != nil)
    {
      NSMenuView *menuView = (NSMenuView *)QuirkProbeFindViewOfClass ([window contentView], [NSMenuView class]);

      if ([window isVisible] && menuView != nil && [menuView isHorizontal] == NO)
        {
          NSMutableArray *titles = [NSMutableArray array];
          NSEnumerator *items = [[[menuView menu] itemArray] objectEnumerator];
          NSMenuItem *item;

          while ((item = [items nextObject]) != nil)
            {
              [titles addObject: [item title]];
            }
          ASSIGN (QuirkProbeOverflowShown, [titles componentsJoinedByString: @", "]);
        }
    }
  [GSCurrentServer () setMouseLocation: [_controlsWindow convertBaseToScreen: NSMakePoint (850, 20)]
                              onScreen: [[_controlsWindow screen] screenNumber]];
  [self after: 0.2 perform: @selector(clickOffMenuBar:) mode: NSEventTrackingRunLoopMode];
}

/* A window too narrow for its menu bar (#25): the titles that don't fit
   fold into an overflow button at the bar's end, ☰ stays first, a click on
   the button shows the folded menus, and their key equivalents still
   work. Widened again, the bar is as it was. */
- (void) checkMenuBarOverflow
{
  NSMenu *mainMenu = [NSApp mainMenu];
  NSString *name = [[NSProcessInfo processInfo] processName];
  NSMenu *appMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: name]);
  NSMenuItem *appItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: name action: NULL keyEquivalent: @""]);
  NSArray *titles = [NSArray arrayWithObjects: @"Edit", @"View", @"Navigate", @"Window", @"Overflow Tools", nil];
  NSMutableArray *added = [NSMutableArray array];
  NSMutableArray *wideRects = [NSMutableArray array];
  NSMutableArray *folded = [NSMutableArray array];
  NSMutableArray *shownTitles = [NSMutableArray array];
  NSWindow *window;
  NSMenuView *menuView;
  NSRect frame = NSMakeRect (60, 60, 720, 120);
  NSRect overflow, wideOverflow, bounds, wideFrame;
  NSMenu *overflowMenu;
  NSEvent *key;
  NSUInteger i, count;
  NSUInteger actionsBefore = QuirkProbeOverflowActions;
  BOOL keyHandled;
  BOOL layoutOK = YES;
  BOOL submenusOK = YES;
  BOOL restored = YES;
  NSInteger hit;
  QuirkProbeInk ink;
  NSString *narrowDetail, *widenDetail;

  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle
    || QuirkProbeUsesPrimaryMenu ())
    {
      [self skip: @"menubar-overflow" detail: @"needs the menu bar (NSWindows95InterfaceStyle, not primary)"];
      [self skip: @"menubar-overflow-widens-back" detail: @"needs the menu bar (NSWindows95InterfaceStyle, not primary)"];
      [self skip: @"menubar-overflow-click" detail: @"needs the menu bar (NSWindows95InterfaceStyle, not primary)"];
      return;
    }
  if ([NSMenuView instancesRespondToSelector: @selector(gnomeThemeOverflowRect)] == NO)
    {
      [self fail: @"menubar-overflow" detail: @"the theme has no menu bar overflow"];
      return;
    }

  [appMenu addItemWithTitle: @"Info" action: NULL keyEquivalent: @""];
  [appItem setSubmenu: appMenu];
  [mainMenu insertItem: appItem atIndex: 0];
  for (i = 0; i < [titles count]; i++)
    {
      NSMenu *submenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: [titles objectAtIndex: i]]);
      NSMenuItem *item = (NSMenuItem *)[mainMenu addItemWithTitle: [titles objectAtIndex: i]
                                                           action: NULL
                                                    keyEquivalent: @""];

      if (i == [titles count] - 1)
        {
          [[submenu addItemWithTitle: @"Overflow Action" action: @selector(overflowAction:) keyEquivalent: @"j"]
            setTarget: self];
        }
      else
        {
          [submenu addItemWithTitle: @"Item" action: NULL keyEquivalent: @""];
        }
      [mainMenu setSubmenu: submenu forItem: item];
      [added addObject: item];
    }

  window = [self windowWithFrame: frame title: @"Menu Bar Overflow"];
  if ([window menu] == nil)
    {
      [[GSTheme theme] setMenu: mainMenu forWindow: window];
    }
  [window orderFront: nil];
  menuView = (NSMenuView *)QuirkProbeFindViewOfClass ([[window contentView] superview], [NSMenuView class]);
  if (menuView == nil || [menuView isHorizontal] == NO)
    {
      [self fail: @"menubar-overflow" detail: @"no menu bar in the window"];
      [window orderOut: nil];
      [mainMenu removeItem: appItem];
      for (i = 0; i < [added count]; i++)
        {
          [mainMenu removeItem: [added objectAtIndex: i]];
        }
      return;
    }
  [menuView sizeToFit];
  [window display];
  count = [mainMenu numberOfItems];
  for (i = 0; i < count; i++)
    {
      [wideRects addObject: NSStringFromRect ([menuView rectOfItemAtIndex: i])];
    }
  wideOverflow = [menuView gnomeThemeOverflowRect];
  wideFrame = [window frame];
  [self saveWindow: window named: @"menubar-overflow-wide"];

  /* Narrow: ☰, then the titles that fit, then the button. */
  [window setFrame: NSMakeRect (NSMinX ([window frame]), NSMinY ([window frame]), 240, NSHeight ([window frame]))
           display: YES];
  bounds = [menuView bounds];
  overflow = [menuView gnomeThemeOverflowRect];
  for (i = 0; i < count; i++)
    {
      NSRect rect = [menuView rectOfItemAtIndex: i];

      if (NSWidth (rect) == 0.0)
        {
          [folded addObject: [[mainMenu itemAtIndex: i] title]];
        }
      else if ([folded count] > 0 || NSMaxX (rect) > NSMinX (overflow) || NSMinX (rect) < NSMinX (bounds))
        {
          /* A shown title after a folded one, or one reaching the button. */
          layoutOK = NO;
        }
    }
  overflowMenu = [menuView gnomeThemeOverflowMenu];
  for (i = 0; i < (NSUInteger)[overflowMenu numberOfItems]; i++)
    {
      NSMenuItem *item = (NSMenuItem *)[overflowMenu itemAtIndex: i];

      [shownTitles addObject: [item title]];
      if ([item hasSubmenu] == NO || [[item submenu] numberOfItems] == 0)
        {
          submenusOK = NO;
        }
    }
  hit = [menuView indexOfItemAtPoint: NSMakePoint (NSMidX (overflow), NSMidY (overflow))];
  [window display];
  {
    NSBitmapImageRep *rep = QuirkProbeRender (menuView);
    CGFloat scale = [rep pixelsWide] / NSWidth (bounds);
    NSRect area = NSMakeRect (NSMinX (overflow) * scale,
                              ([menuView isFlipped] ? NSMinY (overflow) : NSHeight (bounds) - NSMaxY (overflow)) * scale,
                              NSWidth (overflow) * scale, NSHeight (overflow) * scale);

    ink = QuirkProbeMeasureIn (rep, QuirkProbeIsTextInk, area);
  }
  key = [NSEvent keyEventWithType: NSKeyDown
                         location: NSZeroPoint
                    modifierFlags: NSCommandKeyMask
                        timestamp: 0
                     windowNumber: [window windowNumber]
                          context: nil
                       characters: @"j"
      charactersIgnoringModifiers: @"j"
                        isARepeat: NO
                          keyCode: 0];
  keyHandled = [mainMenu performKeyEquivalent: key];
  [self saveWindow: window named: @"menubar-overflow-narrow"];

  narrowDetail = [NSString stringWithFormat: @"bar %gpt wide: ☰ at x %g, overflow button at x %g-%g (ink %lu px), "
    @"folded: %@, its menu: %@, a click on it hits item %ld, the folded Overflow Tools' Cmd-J %@ (%lu action)",
    NSWidth (bounds), NSMinX ([menuView rectOfItemAtIndex: 0]), NSMinX (overflow), NSMaxX (overflow),
    (unsigned long)ink.count, [folded componentsJoinedByString: @", "], [shownTitles componentsJoinedByString: @", "],
    (long)hit, keyHandled ? @"handled" : @"not handled",
    (unsigned long)(QuirkProbeOverflowActions - actionsBefore)];
  if (NSIsEmptyRect (wideOverflow) && NSIsEmptyRect (overflow) == NO && NSMaxX (overflow) <= NSMaxX (bounds)
    && layoutOK && submenusOK && [folded count] > 0 && [folded isEqualToArray: shownTitles]
    && [folded containsObject: name] == NO && NSMinX ([menuView rectOfItemAtIndex: 0]) < 20
    && hit == -1 && ink.count > 0 && keyHandled && QuirkProbeOverflowActions == actionsBefore + 1)
    {
      [self pass: @"menubar-overflow" detail: narrowDetail];
    }
  else
    {
      [self fail: @"menubar-overflow" detail: narrowDetail];
    }

  /* A click on the button shows the folded menus; a click elsewhere
     closes them. Moves the pointer, so only on the probe's own display. */
  if ([[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeOwnsDisplay"] == NO)
    {
      [self skip: @"menubar-overflow-click" detail: @"moves the pointer: only on the probe's own Xvfb"];
    }
  else
    {
      NSRect button = [menuView convertRect: overflow toView: nil];
      NSPoint point = NSMakePoint (NSMidX (button), NSMidY (button));
      NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                        timestamp: 0 windowNumber: [window windowNumber] context: nil
                                      eventNumber: 0 clickCount: 1 pressure: 1];
      NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                                      timestamp: 0 windowNumber: [window windowNumber] context: nil
                                    eventNumber: 0 clickCount: 1 pressure: 0];
      NSString *afterClose;
      NSString *expected = [shownTitles componentsJoinedByString: @", "];
      NSString *detail;

      ASSIGN (QuirkProbeOverflowShown, @"");
      [GSCurrentServer () setMouseLocation: [window convertBaseToScreen: point]
                                  onScreen: [[window screen] screenNumber]];
      [self after: 0.3 perform: @selector(inspectOverflowMenu:) mode: NSEventTrackingRunLoopMode];
      [NSApp postEvent: up atStart: NO];
      [menuView mouseDown: down];
      afterClose = QuirkProbeVisibleMenus ();
      detail = [NSString stringWithFormat: @"0.3s after a click on the overflow button: showing \"%@\"; "
        @"after a click elsewhere: \"%@\"", QuirkProbeOverflowShown, afterClose];
      if ([expected length] > 0 && [QuirkProbeOverflowShown isEqualToString: expected] && [afterClose length] == 0)
        {
          [self pass: @"menubar-overflow-click" detail: detail];
        }
      else
        {
          [self fail: @"menubar-overflow-click" detail: detail];
        }
    }

  /* Wide again: the bar as it was, ☰ back at the end. */
  [window setFrame: wideFrame display: YES];
  for (i = 0; i < count; i++)
    {
      if ([[wideRects objectAtIndex: i] isEqualToString: NSStringFromRect ([menuView rectOfItemAtIndex: i])] == NO)
        {
          restored = NO;
        }
    }
  widenDetail = [NSString stringWithFormat: @"widened back to %g: rects %@, ☰ at x %g of %g, overflow button %@",
    NSWidth ([menuView bounds]), restored ? @"as before" : @"changed",
    NSMinX ([menuView rectOfItemAtIndex: 0]), NSWidth ([menuView bounds]),
    NSIsEmptyRect ([menuView gnomeThemeOverflowRect]) ? @"gone" : @"still there"];
  if (restored && NSIsEmptyRect ([menuView gnomeThemeOverflowRect])
    && NSMaxX ([menuView rectOfItemAtIndex: 0]) > NSWidth ([menuView bounds]) - 20)
    {
      [self pass: @"menubar-overflow-widens-back" detail: widenDetail];
    }
  else
    {
      [self fail: @"menubar-overflow-widens-back" detail: widenDetail];
    }

  [window orderOut: nil];
  [mainMenu removeItem: appItem];
  for (i = 0; i < [added count]; i++)
    {
      [mainMenu removeItem: [added objectAtIndex: i]];
    }
}

/* A Cocoa-style main menu: an untitled first item holding the application
   menu. The theme names it after the app (so it becomes the ☰ menu instead
   of a blank item) and leaves out Hide, Hide Others and Show All. */
- (void) checkCocoaApplicationMenu
{
  NSMenu *original = RETAIN ([NSApp mainMenu]);
  NSMenu *cocoa = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Main"]);
  NSMenu *appMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Apple"]);
  NSMenu *fileMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"File"]);
  NSString *name = [[NSProcessInfo processInfo] processName];
  NSMenuItem *first;
  NSMutableArray *titles = [NSMutableArray array];
  NSEnumerator *enumerator;
  NSMenuItem *item;
  BOOL hasHide = NO, hasAbout = NO;
  NSString *detail;

  [appMenu addItemWithTitle: @"About QuirkProbe" action: @selector(orderFrontStandardAboutPanel:) keyEquivalent: @""];
  [appMenu addItem: [NSMenuItem separatorItem]];
  [appMenu addItemWithTitle: @"Hide QuirkProbe" action: @selector(hide:) keyEquivalent: @"h"];
  [appMenu addItemWithTitle: @"Hide Others" action: @selector(hideOtherApplications:) keyEquivalent: @""];
  [appMenu addItemWithTitle: @"Show All" action: @selector(unhideAllApplications:) keyEquivalent: @""];
  [appMenu addItem: [NSMenuItem separatorItem]];
  [appMenu addItemWithTitle: @"Quit QuirkProbe" action: @selector(terminate:) keyEquivalent: @"q"];
  [fileMenu addItemWithTitle: @"Open" action: NULL keyEquivalent: @""];
  [cocoa setSubmenu: appMenu forItem: [cocoa addItemWithTitle: @"" action: NULL keyEquivalent: @""]];
  [cocoa setSubmenu: fileMenu forItem: [cocoa addItemWithTitle: @"File" action: NULL keyEquivalent: @""]];
  [NSApp setMainMenu: cocoa];

  enumerator = [[cocoa itemArray] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      [titles addObject: [NSString stringWithFormat: @"\"%@\"", [item title]]];
    }
  first = (NSMenuItem *)[cocoa itemAtIndex: 0];
  enumerator = [[[first submenu] itemArray] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      hasHide |= sel_isEqual ([item action], @selector(hide:));
      hasAbout |= sel_isEqual ([item action], @selector(orderFrontStandardAboutPanel:));
    }
  [NSApp setMainMenu: original];
  RELEASE (original);

  detail = [NSString stringWithFormat: @"menu bar %@; app menu %@ About, %@ Hide",
    [titles componentsJoinedByString: @" "], hasAbout ? @"has" : @"lacks", hasHide ? @"has" : @"no"];
  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      [self skip: @"menubar-cocoa-app-menu" detail: @"needs -NSMenuInterfaceStyle NSWindows95InterfaceStyle"];
    }
  else if ([titles count] == 2 && [[first title] isEqualToString: name] && hasAbout && hasHide == NO)
    {
      [self pass: @"menubar-cocoa-app-menu" detail: detail];
    }
  else
    {
      [self fail: @"menubar-cocoa-app-menu" detail: detail];
    }
}

/* Checks from putting Gorm through its paces: its inspectors use switches
   with the box to the right of the title, boxes whose title cell is an
   NSTextFieldCell, NSForms, grooved boxes, and a view-switcher toolbar. */
- (void) checkGormControls
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (700, 500, 420, 120) title: @"QuirkProbe Gorm"];
  NSView *view = [window contentView];
  NSButton *trailing = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (10, 80, 140, 24)]);
  NSBox *box = AUTORELEASE ([[NSBox alloc] initWithFrame: NSMakeRect (160, 50, 120, 60)]);
  NSTextFieldCell *titleCell = AUTORELEASE ([[NSTextFieldCell alloc] initTextCell: @"Fy"]);
  NSTextField *reference = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (300, 80, 100, 24)]);
  NSForm *form = AUTORELEASE ([[NSForm alloc] initWithFrame: NSMakeRect (10, 10, 260, 24)]);
  NSToolbar *switcher = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: @"QuirkProbeSwitcher"]);
  QuirkProbeSwitcherDelegate *switcherDelegate = AUTORELEASE ([QuirkProbeSwitcherDelegate new]);
  NSColor *highlight = [[NSColor controlHighlightColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSBitmapImageRep *rep;
  QuirkProbeInk text, indicator;
  NSArray *boxRows, *referenceRows;
  NSUInteger upright, flipped;
  NSRect entry;
  NSUInteger white;
  NSString *detail;

  [trailing setButtonType: NSSwitchButton];
  [trailing setTitle: @"Command"];
  [trailing setImagePosition: NSImageRight];
  [trailing setAlignment: NSRightTextAlignment];
  [view addSubview: trailing];

  [titleCell setFont: [NSFont systemFontOfSize: 12]];
  object_setIvar (box, class_getInstanceVariable ([NSBox class], "_cell"), RETAIN (titleCell));
  [box setBorderType: NSGrooveBorder];
  [box setTitlePosition: NSAtTop];
  [view addSubview: box];
  [reference setStringValue: @"Fy"];
  [reference setFont: [NSFont systemFontOfSize: 12]];
  [reference setBezeled: NO];
  [reference setDrawsBackground: NO];
  [view addSubview: reference];

  /* libs-gui after 0.32 doesn't autosize a matrix by default, as AppKit's
     doesn't, so the form's cell keeps its default size without this. */
  [form setCellSize: NSMakeSize (260, 24)];
  [form addEntry: @"Title:"];
  [form setBezeled: YES];
  [view addSubview: form];
  [window orderFront: nil];
  [window display];
  [self saveWindow: window named: @"gorm-controls"];

  /* Switch with its box on the right. */
  rep = QuirkProbeRender (trailing);
  text = QuirkProbeMeasure (rep, QuirkProbeIsTextInk);
  indicator = QuirkProbeMeasureIn (rep, QuirkProbeIsNotWhite,
                                   NSMakeRect (text.minX + text.width + 1, 0, [rep pixelsWide], [rep pixelsHigh]));
  detail = [NSString stringWithFormat: @"title ink x %ld-%ld, box from x %ld",
    (long)text.minX, (long)(text.minX + text.width), (long)indicator.minX];
  if (text.count > 0 && indicator.count > 0 && indicator.minX > text.minX + text.width)
    [self pass: @"switch-box-on-right" detail: detail];
  else
    [self fail: @"switch-box-on-right" detail: detail];

  /* Box title upright: its ink profile matches a label's, not the label's
     turned upside down. */
  rep = QuirkProbeRender (box);
  boxRows = QuirkProbeInkRows (rep, NSMakeRect (0, 0, [rep pixelsWide], 20));
  rep = QuirkProbeRender (reference);
  referenceRows = QuirkProbeInkRows (rep, NSMakeRect (0, 0, [rep pixelsWide], [rep pixelsHigh]));
  upright = QuirkProbeProfileDistance (boxRows, referenceRows, NO);
  flipped = QuirkProbeProfileDistance (boxRows, referenceRows, YES);
  detail = [NSString stringWithFormat: @"%lu rows of ink; differs from a label by %lu upright, %lu upside down",
    (unsigned long)[boxRows count], (unsigned long)upright, (unsigned long)flipped];
  if ([boxRows count] > 0 && upright < flipped)
    [self pass: @"box-title-upright" detail: detail];
  else
    [self fail: @"box-title-upright" detail: detail];

  /* Bevel highlights are neutral, not the accent colour. */
  detail = [NSString stringWithFormat: @"controlHighlightColor %.2f %.2f %.2f",
    [highlight redComponent], [highlight greenComponent], [highlight blueComponent]];
  if (fabs ([highlight blueComponent] - [highlight redComponent]) < 0.1)
    [self pass: @"bevel-highlight-neutral" detail: detail];
  else
    [self fail: @"bevel-highlight-neutral" detail: detail];

  /* A form's entry is an Adwaita entry, not a white box. */
  rep = QuirkProbeRender (form);
  entry = NSMakeRect ([[form cellAtIndex: 0] titleWidth] + 10, 8, 60, 8);
  white = QuirkProbeMeasureIn (rep, QuirkProbeIsWhite, entry).count;
  detail = [NSString stringWithFormat: @"%lu of %lu entry pixels white",
    (unsigned long)white, (unsigned long)QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, entry).count];
  if (white == 0)
    [self pass: @"form-entry-adwaita" detail: detail];
  else
    [self fail: @"form-entry-adwaita" detail: detail];
  [window orderOut: nil];

  /* A view switcher keeps its labels. */
  [switcher setDelegate: switcherDelegate];
  detail = [NSString stringWithFormat: @"display mode %d (icon and label %d)",
    (int)[switcher displayMode], (int)NSToolbarDisplayModeIconAndLabel];
  if ([switcher displayMode] == NSToolbarDisplayModeIconAndLabel)
    [self pass: @"toolbar-view-switcher-labels" detail: detail];
  else
    [self fail: @"toolbar-view-switcher-labels" detail: detail];
  [switcher setDelegate: nil];
}

/* An app built in code (no main nib) gets GNOME's metrics: the interface
   font at GNOME's size, not GNUstep's 12pt, and bold button titles. Apps
   with a main Gorm or nib file get GNUstep's metrics instead (compact),
   and -GnomeThemeMetrics compact|gnome overrides either way. */
- (void) checkMetricsMode
{
  NSString *choice = [[NSUserDefaults standardUserDefaults] stringForKey: @"GnomeThemeMetrics"];
  CGFloat size = [[NSFont systemFontOfSize: 0] pointSize];
  BOOL compact = [choice isEqualToString: @"compact"];
  NSString *detail = [NSString stringWithFormat: @"system font %gpt (%@)",
    size, choice != nil ? choice : @"automatic, no main nib"];

  if ((compact && fabs (size - 12.0) < 0.5) || (compact == NO && size > 13.0))
    {
      [self pass: @"metrics-mode" detail: detail];
    }
  else
    {
      [self fail: @"metrics-mode" detail: detail];
    }
}

/* What the primary menu showed, seen from inside its tracking loop. */
static NSMutableArray *QuirkProbePrimaryTitles = nil;
/* Set when the Escape check had to close the menu with a click. */
static BOOL QuirkProbeEscapeNeededClick = NO;
/* Set when the Escape check's timer pressed Escape before the check's click
   returned. It isn't when something else had already closed the menu: the
   check then proves nothing about Escape. */
static BOOL QuirkProbeEscapePressed = NO;
static NSRect QuirkProbePrimaryFrame;
/* The menus a menu bar click showed, seen from inside its tracking loop. */
static NSString *QuirkProbeMenuBarOpen = nil;
static BOOL QuirkProbeMenuBarItemPicked = NO;
static NSWindow *QuirkProbeMenuBarItemWindow = nil;
static NSValue *QuirkProbeMenuBarItemPoint = nil;

static NSView *
QuirkProbePrimaryButtonIn (NSView *view)
{
  return QuirkProbeFindViewOfClass (view, NSClassFromString (@"GnomeThemePrimaryMenuButton"));
}

/* Drops an Escape that found no menu: left queued, it closes the next popup
   that tracks (a combo box's list). */
static void
QuirkProbeDropStaleKeys (void)
{
  NSEvent *event;

  while ((event = [NSApp nextEventMatchingMask: NSKeyDownMask | NSKeyUpMask
                                     untilDate: [NSDate distantPast]
                                        inMode: NSDefaultRunLoopMode
                                       dequeue: YES]) != nil)
    {
    }
}

/* Fires while the ☰'s menu is tracking: presses Escape. */
- (void) pressEscape: (NSTimer *)timer
{
  NSString *escape = [NSString stringWithFormat: @"%C", (unichar)0x1b];

  QuirkProbeEscapePressed = YES;

  [NSApp postEvent: [NSEvent keyEventWithType: NSKeyDown
                                     location: NSZeroPoint
                                modifierFlags: 0
                                    timestamp: 0
                                 windowNumber: [_controlsWindow windowNumber]
                                      context: nil
                                   characters: escape
                  charactersIgnoringModifiers: escape
                                    isARepeat: NO
                                      keyCode: 9]
           atStart: NO];
}

/* Fires if Escape didn't close the menu: close it with a click. */
- (void) closeMenuAfterEscape: (NSTimer *)timer
{
  NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: NSMakePoint (-50, -50) modifierFlags: 0
                                  timestamp: 0 windowNumber: 0 context: nil eventNumber: 0 clickCount: 1 pressure: 0];

  QuirkProbeEscapeNeededClick = YES;
  [NSApp postEvent: up atStart: NO];
}

/* The titles of the vertical menus showing, as "File: New, Open | ...". */
static NSString *
QuirkProbeVisibleMenus (void)
{
  NSEnumerator *enumerator = [[NSApp windows] objectEnumerator];
  NSMutableArray *menus = [NSMutableArray array];
  NSWindow *window;

  while ((window = [enumerator nextObject]) != nil)
    {
      NSMenuView *menuView = (NSMenuView *)QuirkProbeFindViewOfClass ([window contentView], [NSMenuView class]);

      if ([window isVisible] && menuView != nil && [menuView isHorizontal] == NO)
        {
          [menus addObject: [[menuView menu] title]];
        }
    }
  return [menus componentsJoinedByString: @", "];
}

/* Fires while a menu bar menu is tracking: note what's showing, move the
   pointer off the bar, then click there. */
- (void) inspectMenuBarMenu: (NSTimer *)timer
{
  ASSIGN (QuirkProbeMenuBarOpen, QuirkProbeVisibleMenus ());
  [GSCurrentServer () setMouseLocation: [_controlsWindow convertBaseToScreen: NSMakePoint (850, 20)]
                              onScreen: [[_controlsWindow screen] screenNumber]];
  [self after: 0.2 perform: @selector(clickOffMenuBar:) mode: NSEventTrackingRunLoopMode];
}

- (void) clickOffMenuBar: (NSTimer *)timer
{
  NSPoint point = NSMakePoint (850, 20);
  NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                    timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                  eventNumber: 0 clickCount: 1 pressure: 1];
  NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                                  timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                eventNumber: 0 clickCount: 1 pressure: 0];

  [NSApp postEvent: down atStart: NO];
  [NSApp postEvent: up atStart: NO];
}

/* Fires while a pop-up button's menu is tracking: note whether it's
   showing, then click elsewhere to close it. */
- (void) inspectPopUpMenu: (NSTimer *)timer
{
  NSWindow *menuWindow = [[[_popUpButton menu] menuRepresentation] window];

  ASSIGN (QuirkProbeMenuBarOpen, (menuWindow != nil && [menuWindow isVisible]) ? @"menu" : @"");
  [GSCurrentServer () setMouseLocation: [_controlsWindow convertBaseToScreen: NSMakePoint (850, 20)]
                              onScreen: [[_controlsWindow screen] screenNumber]];
  [self after: 0.2 perform: @selector(clickOffMenuBar:) mode: NSEventTrackingRunLoopMode];
}

/* A click on a pop-up button opens its menu and the menu stays open: its
   menu opens on the press, and the release (here already queued) used to
   end the tracking, picking the current item and closing the menu at once
   (when the release came before the tracking, as while the menu's window
   was first made, the menu stayed open: so only from the second click on).
   A click elsewhere closes it and changes nothing. */
- (void) checkPopUpClick
{
  NSRect frame = [_popUpButton convertRect: [_popUpButton bounds] toView: nil];
  NSPoint point = NSMakePoint (NSMidX (frame), NSMidY (frame));
  NSString *before = [_popUpButton titleOfSelectedItem];
  NSMutableArray *opened = [NSMutableArray array];
  NSWindow *menuWindow;
  NSString *detail;
  int i;

  if ([[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeOwnsDisplay"] == NO)
    {
      [self skip: @"popup-click-stays-open" detail: @"moves the pointer: only on the probe's own Xvfb"];
      return;
    }
  for (i = 0; i < 3; i++)
    {
      NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                        timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                      eventNumber: 0 clickCount: 1 pressure: 1];
      NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                                      timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                    eventNumber: 0 clickCount: 1 pressure: 0];

      ASSIGN (QuirkProbeMenuBarOpen, @"");
      [GSCurrentServer () setMouseLocation: [_controlsWindow convertBaseToScreen: point]
                                  onScreen: [[_controlsWindow screen] screenNumber]];
      [self after: 0.3 perform: @selector(inspectPopUpMenu:) mode: NSEventTrackingRunLoopMode];
      [NSApp postEvent: up atStart: NO];
      [_popUpButton mouseDown: down];
      [opened addObject: [QuirkProbeMenuBarOpen length] > 0 ? @"open" : @"closed"];
    }
  menuWindow = [[[_popUpButton menu] menuRepresentation] window];
  detail = [NSString stringWithFormat: @"0.3s after each of 3 clicks: %@; after a click elsewhere: %@, selection %@ -> %@",
    [opened componentsJoinedByString: @", "],
    [menuWindow isVisible] ? @"showing" : @"closed", before, [_popUpButton titleOfSelectedItem]];
  if ([opened containsObject: @"closed"] == NO && [menuWindow isVisible] == NO
    && [before isEqualToString: [_popUpButton titleOfSelectedItem]])
    {
      [self pass: @"popup-click-stays-open" detail: detail];
    }
  else
    {
      [self fail: @"popup-click-stays-open" detail: detail];
    }
}

/* The pop-up list's window sizes while popUpListKeepsSize runs, each
   marked when the list was on screen. */
static NSMutableArray *QuirkProbePopUpListSizes = nil;

- (void) popUpListDidResize: (NSNotification *)notification
{
  NSWindow *window = [notification object];

  [QuirkProbePopUpListSizes addObject: [NSString stringWithFormat: @"%.0fx%.0f%@",
    NSWidth ([window frame]), NSHeight ([window frame]), [window isVisible] ? @" on screen" : @""]];
}

/* Picks an item in the pop-up button's open list and says how the list
   was resized; YES in `resized` when it was resized while on screen. */
- (NSString *) pickInPopUpList: (BOOL *)resized
{
  NSPopUpButtonCell *cell = [_popUpButton cell];
  NSInteger before = [_popUpButton indexOfSelectedItem];
  NSWindow *menuWindow;
  NSString *opened;
  NSString *detail;

  [cell attachPopUpWithFrame: [_popUpButton bounds] inView: _popUpButton];
  menuWindow = [[[_popUpButton menu] menuRepresentation] window];
  opened = [NSString stringWithFormat: @"%.0fx%.0f", NSWidth ([menuWindow frame]), NSHeight ([menuWindow frame])];
  QuirkProbePopUpListSizes = [NSMutableArray array];
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(popUpListDidResize:)
                                               name: NSWindowDidResizeNotification
                                             object: menuWindow];
  [[_popUpButton menu] performActionForItemAtIndex: (before == 0) ? 1 : 0];
  [[_popUpButton menu] update];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSWindowDidResizeNotification
                                                object: menuWindow];
  *resized = [[QuirkProbePopUpListSizes componentsJoinedByString: @","] rangeOfString: @"on screen"].location != NSNotFound;
  detail = [NSString stringWithFormat: @"list %@; resizes during the pick: %@",
    opened, [QuirkProbePopUpListSizes count] > 0 ? [QuirkProbePopUpListSizes componentsJoinedByString: @", "] : @"none"];
  QuirkProbePopUpListSizes = nil;
  if ([menuWindow isVisible])
    {
      [cell dismissPopUp];
    }
  [_popUpButton selectItemAtIndex: before];
  return detail;
}

/* Picking an item in a pop-up button's list doesn't resize the list while
   it's on screen on Wayland. -[NSMenu update] sized it down to its own
   width (from the button's) just before it closed; under GNOME on Wayland,
   Mutter freezes an XWayland window's commits on a resize until its next
   paint, and withdrawn first the list never showed again (only its first
   opening did; GNOME/mutter#5080). Elsewhere GNUstep's resize stays, as for
   tool tips. The theme reads WAYLAND_DISPLAY when it sizes the list, so
   the check sets it for the Wayland pick. */
- (void) checkPopUpListKeepsSize
{
  const char *saved = getenv ("WAYLAND_DISPLAY");
  NSString *savedDisplay = (saved != NULL) ? [NSString stringWithUTF8String: saved] : nil;
  NSString *x11Detail;
  NSString *waylandDetail;
  NSString *detail;
  BOOL x11Resized;
  BOOL waylandResized;

  unsetenv ("WAYLAND_DISPLAY");
  x11Detail = [self pickInPopUpList: &x11Resized];
  setenv ("WAYLAND_DISPLAY", "quirk-probe", 1);
  waylandDetail = [self pickInPopUpList: &waylandResized];
  if (savedDisplay != nil)
    {
      setenv ("WAYLAND_DISPLAY", [savedDisplay UTF8String], 1);
    }
  else
    {
      unsetenv ("WAYLAND_DISPLAY");
    }

  detail = [NSString stringWithFormat: @"Wayland: %@; not Wayland: %@", waylandDetail, x11Detail];
  if (waylandResized == NO && x11Resized)
    {
      [self pass: @"popup-list-keeps-size" detail: detail];
    }
  else
    {
      [self fail: @"popup-list-keeps-size" detail: detail];
    }
}

/* Clicks a menu bar title, as a click with the pointer on it: the release
   is already queued when the press is handled. */
/* Presses a menu bar title and holds it: no release follows. */
- (void) pressMenuBar: (NSMenuView *)bar item: (NSInteger)index
{
  NSRect title = [bar convertRect: [bar rectOfItemAtIndex: index] toView: nil];
  NSPoint point = NSMakePoint (NSMidX (title), NSMidY (title));
  NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                    timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                  eventNumber: 0 clickCount: 1 pressure: 1];

  [GSCurrentServer () setMouseLocation: [_controlsWindow convertBaseToScreen: point]
                              onScreen: [[_controlsWindow screen] screenNumber]];
  [bar mouseDown: down];
}

- (void) clickMenuBar: (NSMenuView *)bar item: (NSInteger)index
{
  NSRect title = [bar convertRect: [bar rectOfItemAtIndex: index] toView: nil];
  NSPoint point = NSMakePoint (NSMidX (title), NSMidY (title));
  NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                    timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                  eventNumber: 0 clickCount: 1 pressure: 1];
  NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                                  timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil
                                eventNumber: 0 clickCount: 1 pressure: 0];

  [GSCurrentServer () setMouseLocation: [_controlsWindow convertBaseToScreen: point]
                              onScreen: [[_controlsWindow screen] screenNumber]];
  [NSApp postEvent: up atStart: NO];
  [bar mouseDown: down];
}

/* A click on a menu bar title opens its menu and the menu stays open
   (libs-gui 0.32 closed it on the release: upstream item 8,
   plugins-themes-Adwaita#5); a click elsewhere or Escape closes it. Moves
   the pointer, so only on the probe's own display. */
- (void) checkMenuBarClick
{
  NSMenuView *bar = nil;
  NSEnumerator *enumerator;
  NSView *view;
  NSInteger index;
  NSString *detail;
  NSString *afterClose;

  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle
    || QuirkProbeUsesPrimaryMenu ())
    {
      [self skip: @"menubar-click-opens" detail: @"needs the menu bar (NSWindows95InterfaceStyle, not primary)"];
      return;
    }
  if ([[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeOwnsDisplay"] == NO)
    {
      [self skip: @"menubar-click-opens" detail: @"moves the pointer: only on the probe's own Xvfb"];
      return;
    }
  enumerator = [[[[_controlsWindow contentView] superview] subviews] objectEnumerator];
  while ((view = [enumerator nextObject]) != nil && bar == nil)
    {
      NSMenuView *found = (NSMenuView *)QuirkProbeFindViewOfClass (view, [NSMenuView class]);

      if (found != nil && [found isHorizontal])
        {
          bar = found;
        }
    }
  index = [[NSApp mainMenu] indexOfItemWithTitle: @"File"];
  if (bar == nil || index < 0)
    {
      [self fail: @"menubar-click-opens" detail: @"no menu bar with a File menu"];
      return;
    }

  ASSIGN (QuirkProbeMenuBarOpen, @"");
  [self after: 0.3 perform: @selector(inspectMenuBarMenu:) mode: NSEventTrackingRunLoopMode];
  [self clickMenuBar: bar item: index];
  afterClose = QuirkProbeVisibleMenus ();
  detail = [NSString stringWithFormat: @"0.3s after a click on File: showing \"%@\"; after a click elsewhere: \"%@\"",
    QuirkProbeMenuBarOpen, afterClose];
  if ([QuirkProbeMenuBarOpen isEqualToString: @"File"] && [afterClose length] == 0)
    {
      [self pass: @"menubar-click-opens" detail: detail];
    }
  else
    {
      [self fail: @"menubar-click-opens" detail: detail];
    }

  /* A press alone opens it, as GTK's menu bar does (the theme used to
     hold the press until its release); a click elsewhere closes it. */
  ASSIGN (QuirkProbeMenuBarOpen, @"");
  [self after: 0.3 perform: @selector(inspectMenuBarMenu:) mode: NSEventTrackingRunLoopMode];
  [self pressMenuBar: bar item: index];
  afterClose = QuirkProbeVisibleMenus ();
  detail = [NSString stringWithFormat: @"0.3s into a press on File: showing \"%@\"; after a click elsewhere: \"%@\"",
    QuirkProbeMenuBarOpen, afterClose];
  if ([QuirkProbeMenuBarOpen isEqualToString: @"File"] && [afterClose length] == 0)
    {
      [self pass: @"menubar-press-opens" detail: detail];
    }
  else
    {
      [self fail: @"menubar-press-opens" detail: detail];
    }

  /* The same for the application menu, drawn as ☰ at the bar's end. */
  {
    NSString *name = [[NSProcessInfo processInfo] processName];
    NSMenu *appMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: name]);
    NSMenuItem *appItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: name action: NULL keyEquivalent: @""]);

    [appMenu addItemWithTitle: @"Info" action: NULL keyEquivalent: @""];
    [appItem setSubmenu: appMenu];
    [[NSApp mainMenu] insertItem: appItem atIndex: 0];
    [bar sizeToFit];
    ASSIGN (QuirkProbeMenuBarOpen, @"");
    [self after: 0.3 perform: @selector(inspectMenuBarMenu:) mode: NSEventTrackingRunLoopMode];
    [self clickMenuBar: bar item: 0];
    afterClose = QuirkProbeVisibleMenus ();
    detail = [NSString stringWithFormat: @"0.3s after a click on ☰ at x %g: showing \"%@\"; after a click elsewhere: \"%@\"",
      NSMinX ([bar rectOfItemAtIndex: 0]), QuirkProbeMenuBarOpen, afterClose];
    [[NSApp mainMenu] removeItem: appItem];
    [bar sizeToFit];
    if ([QuirkProbeMenuBarOpen isEqualToString: name] && [afterClose length] == 0)
      {
        [self pass: @"menubar-click-opens-app-menu" detail: detail];
      }
    else
      {
        [self fail: @"menubar-click-opens-app-menu" detail: detail];
      }
  }

  /* Escape closes it. */
  {
    NSTimer *fallback = [NSTimer timerWithTimeInterval: 1.5 target: self selector: @selector(closeMenuAfterEscape:)
                                              userInfo: nil repeats: NO];

    NSTimer *escape;

    QuirkProbeEscapeNeededClick = NO;
    QuirkProbeEscapePressed = NO;
    [[NSRunLoop currentRunLoop] addTimer: fallback forMode: NSEventTrackingRunLoopMode];
    ASSIGN (QuirkProbeMenuBarOpen, @"");
    escape = [self after: 0.3 perform: @selector(pressEscapeOnMenuBar:) mode: NSEventTrackingRunLoopMode];
    [self clickMenuBar: bar item: index];
    [fallback invalidate];
    [escape invalidate];
    QuirkProbeDropStaleKeys ();
    afterClose = QuirkProbeVisibleMenus ();
    detail = [NSString stringWithFormat: @"showing \"%@\" before Escape; after it: %@, showing \"%@\"",
      QuirkProbeMenuBarOpen,
      QuirkProbeEscapePressed == NO ? @"never pressed (tracking had ended)"
        : QuirkProbeEscapeNeededClick ? @"still tracking (closed by a click)" : @"tracking ended", afterClose];
    if ([QuirkProbeMenuBarOpen isEqualToString: @"File"] && QuirkProbeEscapePressed && QuirkProbeEscapeNeededClick == NO
      && [afterClose length] == 0)
      {
        [self pass: @"menubar-click-escape" detail: detail];
      }
    else
      {
        [self fail: @"menubar-click-escape" detail: detail];
      }
  }

  /* A click on an item of the open menu runs it. Escape's spare release
     (for libs-gui master) is still queued: dispatch it, as the main loop
     would. */
  {
    NSEvent *pending;

    while ((pending = [NSApp nextEventMatchingMask: NSAnyEventMask untilDate: [NSDate distantPast]
                                            inMode: NSDefaultRunLoopMode dequeue: YES]) != nil)
      {
        [NSApp sendEvent: pending];
      }
  }
  {
    NSMenu *fileMenu = [[[NSApp mainMenu] itemAtIndex: index] submenu];
    NSMenuItem *probeItem = [fileMenu addItemWithTitle: @"Probe Item"
                                                action: @selector(menuBarItemPicked:)
                                         keyEquivalent: @""];

    [probeItem setTarget: self];
    QuirkProbeMenuBarItemPicked = NO;
    [self after: 0.3 perform: @selector(clickProbeItem:) mode: NSEventTrackingRunLoopMode];
    [self clickMenuBar: bar item: index];
    afterClose = QuirkProbeVisibleMenus ();
    [fileMenu removeItem: probeItem];
    detail = [NSString stringWithFormat: @"a click on File, then on its item: %@; showing \"%@\" after",
      QuirkProbeMenuBarItemPicked ? @"the item ran" : @"the item didn't run", afterClose];
    if (QuirkProbeMenuBarItemPicked && [afterClose length] == 0)
      {
        [self pass: @"menubar-click-picks" detail: detail];
      }
    else
      {
        [self fail: @"menubar-click-picks" detail: detail];
      }
  }
  [GSCurrentServer () setMouseLocation: NSMakePoint (0, 0) onScreen: [[_controlsWindow screen] screenNumber]];
}

- (void) pressEscapeOnMenuBar: (NSTimer *)timer
{
  ASSIGN (QuirkProbeMenuBarOpen, QuirkProbeVisibleMenus ());
  [self pressEscape: timer];
}

- (void) menuBarItemPicked: (id)sender
{
  QuirkProbeMenuBarItemPicked = YES;
}

/* Fires while File is open from a click: point at its probe item, then
   click it. */
- (void) clickProbeItem: (NSTimer *)timer
{
  NSEnumerator *enumerator = [[NSApp windows] objectEnumerator];
  NSWindow *window;

  while ((window = [enumerator nextObject]) != nil)
    {
      NSMenuView *menuView = (NSMenuView *)QuirkProbeFindViewOfClass ([window contentView], [NSMenuView class]);
      NSInteger item = [[menuView menu] indexOfItemWithTitle: @"Probe Item"];

      if ([window isVisible] && menuView != nil && [menuView isHorizontal] == NO && item >= 0)
        {
          NSRect rect = [menuView convertRect: [menuView rectOfItemAtIndex: item] toView: nil];
          NSPoint point = NSMakePoint (NSMidX (rect), NSMidY (rect));

          [GSCurrentServer () setMouseLocation: [window convertBaseToScreen: point]
                                      onScreen: [[window screen] screenNumber]];
          ASSIGN (QuirkProbeMenuBarItemWindow, window);
          ASSIGN (QuirkProbeMenuBarItemPoint, [NSValue valueWithPoint: point]);
          [self after: 0.2 perform: @selector(clickPointedItem:) mode: NSEventTrackingRunLoopMode];
          return;
        }
    }
  /* Not open: end the tracking. */
  [self clickOffMenuBar: timer];
}

- (void) clickPointedItem: (NSTimer *)timer
{
  NSPoint point = [QuirkProbeMenuBarItemPoint pointValue];
  NSInteger number = [QuirkProbeMenuBarItemWindow windowNumber];

  [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                      timestamp: 0 windowNumber: number context: nil
                                    eventNumber: 0 clickCount: 1 pressure: 1]
           atStart: NO];
  [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                                      timestamp: 0 windowNumber: number context: nil
                                    eventNumber: 0 clickCount: 1 pressure: 0]
           atStart: NO];
  DESTROY (QuirkProbeMenuBarItemWindow);
}

/* Fires while the ☰'s menu is tracking: note the vertical menu that's
   showing, then close it with a click outside. */
- (void) inspectPrimaryMenu: (NSTimer *)timer
{
  NSEnumerator *enumerator = [[NSApp windows] objectEnumerator];
  NSWindow *window;
  NSEvent *up, *down;

  while ((window = [enumerator nextObject]) != nil)
    {
      NSMenuView *menuView = (NSMenuView *)QuirkProbeFindViewOfClass ([window contentView], [NSMenuView class]);

      if ([window isVisible] && menuView != nil && [menuView isHorizontal] == NO)
        {
          NSEnumerator *items = [[[menuView menu] itemArray] objectEnumerator];
          NSMenuItem *item;

          QuirkProbePrimaryFrame = [window frame];
          [self saveWindow: window named: @"primary-menu"];
          while ((item = [items nextObject]) != nil)
            {
              [QuirkProbePrimaryTitles addObject: [item isSeparatorItem] ? @"--" : [item title]];
            }
        }
    }
  /* A click on the window, clear of the menu, as a user closes it. */
  up = [NSEvent mouseEventWithType: NSLeftMouseUp location: NSMakePoint (5, 5) modifierFlags: 0
                         timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil eventNumber: 0
                        clickCount: 1 pressure: 0];
  down = [NSEvent mouseEventWithType: NSLeftMouseDown location: NSMakePoint (5, 5) modifierFlags: 0
                           timestamp: 0 windowNumber: [_controlsWindow windowNumber] context: nil eventNumber: 0
                          clickCount: 1 pressure: 1];
  [NSApp postEvent: down atStart: NO];
  [NSApp postEvent: up atStart: NO];
}

/* With -GnomeThemeMenuStyle primary: a window without a toolbar shows a
   slim bar holding ☰; a window with one shows ☰ at the toolbar's end and no
   menu bar; clicking ☰ shows the main menu vertically under it. */
- (void) checkPrimaryMenu
{
  NSView *barButton;
  NSString *detail;
  NSRect buttonInWindow;
  NSEvent *click;

  if (QuirkProbeUsesPrimaryMenu () == NO)
    {
      [self skip: @"primary-menu" detail: @"needs -GnomeThemeMenuStyle primary or -ProbeMenuDefault YES"];
      return;
    }

  if (QuirkProbeDrawsDecorations ())
    {
      [self checkPrimaryMenuInHeaderBar];
    }
  else
    {
      [self checkPrimaryMenuInMenuBar];
    }

  /* Open it, with an application menu and an Edit menu added: the click's
     tracking loop runs until -inspectPrimaryMenu: closes the menu. */
  {
    NSMenu *mainMenu = [NSApp mainMenu];
    NSString *name = [[NSProcessInfo processInfo] processName];
    NSMenu *appMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: name]);
    NSMenu *editMenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Edit"]);
    NSMenuItem *appItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: name action: NULL keyEquivalent: @""]);
    NSMenuItem *editItem = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: @"Edit" action: NULL keyEquivalent: @""]);

    [appMenu addItemWithTitle: @"Preferences…" action: NULL keyEquivalent: @","];
    [appMenu addItemWithTitle: @"About QuirkProbe" action: @selector(orderFrontStandardAboutPanel:) keyEquivalent: @""];
    [editMenu addItemWithTitle: @"Copy" action: @selector(copy:) keyEquivalent: @"c"];
    [appItem setSubmenu: appMenu];
    [editItem setSubmenu: editMenu];
    [mainMenu insertItem: appItem atIndex: 0];
    [mainMenu addItem: editItem];
    _primaryExtraItems = [[NSArray alloc] initWithObjects: appItem, editItem, nil];
  }
  ASSIGN (QuirkProbePrimaryTitles, [NSMutableArray array]);
  /* Changing the main menu gives the window a new menu view and ☰. */
  barButton = QuirkProbePrimaryButtonIn ([[_controlsWindow contentView] superview]);
  buttonInWindow = [barButton convertRect: [barButton bounds] toView: nil];
  click = [NSEvent mouseEventWithType: NSLeftMouseDown
                             location: NSMakePoint (NSMaxX (buttonInWindow) - 23, NSMidY (buttonInWindow))
                        modifierFlags: 0
                            timestamp: 0
                         windowNumber: [_controlsWindow windowNumber]
                              context: nil
                          eventNumber: 0
                           clickCount: 1
                             pressure: 1.0];
  /* A click: the menu opens on the release and stays open. */
  [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseUp
                                       location: [click locationInWindow]
                                  modifierFlags: 0
                                      timestamp: 0
                                   windowNumber: [_controlsWindow windowNumber]
                                        context: nil
                                    eventNumber: 0
                                     clickCount: 1
                                       pressure: 0.0]
           atStart: NO];
  [self after: 0.3 perform: @selector(inspectPrimaryMenu:) mode: NSEventTrackingRunLoopMode];
  [barButton mouseDown: click];
  {
    NSEnumerator *extras = [_primaryExtraItems objectEnumerator];
    NSMenuItem *extra;

    while ((extra = [extras nextObject]) != nil)
      {
        [[NSApp mainMenu] removeItem: extra];
      }
    DESTROY (_primaryExtraItems);
  }

  detail = [NSString stringWithFormat: @"menu %@ at %@, the button's right edge at %g",
    [QuirkProbePrimaryTitles componentsJoinedByString: @" | "], NSStringFromRect (QuirkProbePrimaryFrame),
    [_controlsWindow convertBaseToScreen: NSMakePoint (NSMaxX (buttonInWindow) - 6, 0)].x];
  /* Escape closes it. */
  {
    NSTimer *fallback;
    NSTimer *escape;

    barButton = QuirkProbePrimaryButtonIn ([[_controlsWindow contentView] superview]);
    [NSApp postEvent: [NSEvent mouseEventWithType: NSLeftMouseUp
                                         location: [click locationInWindow]
                                    modifierFlags: 0
                                        timestamp: 0
                                     windowNumber: [_controlsWindow windowNumber]
                                          context: nil
                                      eventNumber: 0
                                       clickCount: 1
                                         pressure: 0.0]
             atStart: NO];
    QuirkProbeEscapeNeededClick = NO;
    QuirkProbeEscapePressed = NO;
    escape = [self after: 0.3 perform: @selector(pressEscape:) mode: NSEventTrackingRunLoopMode];
    fallback = [NSTimer timerWithTimeInterval: 1.5 target: self selector: @selector(closeMenuAfterEscape:)
                                     userInfo: nil repeats: NO];
    [[NSRunLoop currentRunLoop] addTimer: fallback forMode: NSEventTrackingRunLoopMode];
    [barButton mouseDown: click];
    [fallback invalidate];
    [escape invalidate];
    QuirkProbeDropStaleKeys ();
    if (QuirkProbeEscapePressed == NO)
      [self fail: @"primary-menu-escape" detail: @"the menu had closed before Escape (or never opened)"];
    else if (QuirkProbeEscapeNeededClick == NO)
      [self pass: @"primary-menu-escape" detail: @"Escape closed the menu"];
    else
      [self fail: @"primary-menu-escape" detail: @"the menu stayed open after Escape"];
  }

  /* The app's menus in order, then its application menu's items. */
  if ([[QuirkProbePrimaryTitles componentsJoinedByString: @" | "]
        isEqualToString: @"File | Edit | -- | Preferences… | About QuirkProbe"]
    && fabs (NSMaxX (QuirkProbePrimaryFrame) - [_controlsWindow convertBaseToScreen: NSMakePoint (NSMaxX (buttonInWindow) - 6, 0)].x) < 1.0)
    [self pass: @"primary-menu-opens" detail: detail];
  else
    [self fail: @"primary-menu-opens" detail: detail];
}

/* Without the header bar, the ☰ is in a slim bar, or at the toolbar's end
   when the window shows one. */
- (void) checkPrimaryMenuInMenuBar
{
  NSView *controlsFrame = [[_controlsWindow contentView] superview];
  NSView *toolbarFrame = [[_toolbarWindow contentView] superview];
  NSMenuView *controlsBar = (NSMenuView *)QuirkProbeFindViewOfClass (controlsFrame, [NSMenuView class]);
  NSMenuView *toolbarBar = (NSMenuView *)QuirkProbeFindViewOfClass (toolbarFrame, [NSMenuView class]);
  NSView *barButton = QuirkProbePrimaryButtonIn (controlsBar);
  NSView *toolbarView = QuirkProbeFindViewOfClass (toolbarFrame, NSClassFromString (@"GSToolbarView"));
  NSView *toolbarButton = QuirkProbePrimaryButtonIn (toolbarFrame);
  NSString *detail;

  detail = [NSString stringWithFormat: @"bar %gpt high with %@; toolbar window: bar %gpt, ☰ %@ beside a toolbar ending at %g",
    NSHeight ([controlsBar frame]), barButton != nil ? @"☰" : @"no ☰",
    NSHeight ([toolbarBar frame]), NSStringFromRect ([toolbarButton frame]), NSMaxX ([toolbarView frame])];
  if (barButton != nil && NSHeight ([controlsBar frame]) >= 34 && ([toolbarBar superview] == nil || NSHeight ([toolbarBar frame]) == 0)
    && toolbarButton != nil && NSMinX ([toolbarButton frame]) == NSMaxX ([toolbarView frame])
    && NSMaxX ([toolbarButton frame]) == NSMaxX ([toolbarFrame bounds]))
    [self pass: @"primary-menu-placement" detail: detail];
  else
    [self fail: @"primary-menu-placement" detail: detail];

  /* Hiding the toolbar moves ☰ to a bar; showing it again moves it back.
     The content view keeps meeting the bar or toolbar with no gap. */
  {
    NSToolbar *toolbar = [_toolbarWindow toolbar];
    NSView *content = [_toolbarWindow contentView];
    NSMenuView *bar;
    CGFloat hiddenBar, hiddenGap, shownGap;

    [toolbar setVisible: NO];
    bar = (NSMenuView *)QuirkProbeFindViewOfClass (toolbarFrame, [NSMenuView class]);
    hiddenBar = NSHeight ([bar frame]);
    hiddenGap = NSMinY ([bar frame]) - NSMaxY ([content frame]);
    [toolbar setVisible: YES];
    toolbarView = QuirkProbeFindViewOfClass (toolbarFrame, NSClassFromString (@"GSToolbarView"));
    toolbarButton = QuirkProbePrimaryButtonIn (toolbarFrame);
    shownGap = NSMinY ([toolbarView frame]) - NSMaxY ([content frame]);
    detail = [NSString stringWithFormat: @"toolbar hidden: bar %gpt, %gpt above the content; shown: toolbar %gpt above it, ☰ %@",
      hiddenBar, hiddenGap, shownGap, NSStringFromRect ([toolbarButton frame])];
    if (hiddenBar >= 34 && QuirkProbePrimaryButtonIn (bar) != nil && fabs (hiddenGap) <= 1 && fabs (shownGap) <= 1
      && [toolbarButton window] == _toolbarWindow && NSMinX ([toolbarButton frame]) == NSMaxX ([toolbarView frame]))
      [self pass: @"primary-menu-toolbar-toggle" detail: detail];
    else
      [self fail: @"primary-menu-toolbar-toggle" detail: detail];
  }
}

/* With the header bar, the ☰ is in it: at the bar's end, or 6pt before the
   window buttons (the ☰ view keeps that margin at its right). There's no
   menu bar row, and the toolbar isn't narrowed for it. */
- (void) checkPrimaryMenuInHeaderBar
{
  NSView *controlsFrame = [[_controlsWindow contentView] superview];
  NSView *headerFrame = [[_headerWindow contentView] superview];
  NSView *toolbarFrame = [[_toolbarWindow contentView] superview];
  NSView *controlsButton = QuirkProbePrimaryButtonIn (controlsFrame);
  NSView *headerButton = QuirkProbePrimaryButtonIn (headerFrame);
  NSView *toolbarButton = QuirkProbePrimaryButtonIn (toolbarFrame);
  NSArray *windowButtons = QuirkProbeWindowButtons (headerFrame);
  NSMenuView *bar = (NSMenuView *)QuirkProbeFindViewOfClass (controlsFrame, [NSMenuView class]);
  NSView *toolbarView = QuirkProbeFindViewOfClass (toolbarFrame, NSClassFromString (@"GSToolbarView"));
  NSView *content = [_toolbarWindow contentView];
  NSToolbar *toolbar = [_toolbarWindow toolbar];
  CGFloat hiddenGap, shownGap;
  NSString *detail;

  detail = [NSString stringWithFormat: @"☰ %@ in a %gpt-wide frame, %gpt from the top; ☰ %@ before buttons from %g; menu bar %gpt; toolbar to %g, content to %g",
    NSStringFromRect ([controlsButton frame]), NSWidth ([controlsFrame bounds]),
    QuirkProbeTopGap (controlsFrame, [controlsButton frame]), NSStringFromRect ([headerButton frame]),
    [windowButtons count] > 0 ? NSMinX ([[windowButtons objectAtIndex: 0] frame]) : -1.0,
    NSHeight ([bar frame]), NSMaxX ([toolbarView frame]), NSMaxX ([content frame])];
  if ([controlsButton superview] == controlsFrame && NSMaxX ([controlsButton frame]) == NSMaxX ([controlsFrame bounds])
    && QuirkProbeTopGap (controlsFrame, [controlsButton frame]) == 0 && NSHeight ([controlsButton frame]) == 46
    && [headerButton superview] == headerFrame && [windowButtons count] > 0
    && NSMaxX ([headerButton frame]) == NSMinX ([[windowButtons objectAtIndex: 0] frame])
    && (bar == nil || [bar superview] == nil || NSHeight ([bar frame]) == 0)
    && [toolbarButton superview] == toolbarFrame && NSMaxX ([toolbarView frame]) == NSMaxX ([content frame]))
    [self pass: @"primary-menu-placement" detail: detail];
  else
    [self fail: @"primary-menu-placement" detail: detail];

  /* Hiding the toolbar leaves no bar: the content meets the header bar. */
  [toolbar setVisible: NO];
  hiddenGap = QuirkProbeTopGap (toolbarFrame, [content frame]);
  [toolbar setVisible: YES];
  toolbarView = QuirkProbeFindViewOfClass (toolbarFrame, NSClassFromString (@"GSToolbarView"));
  shownGap = QuirkProbeTopGap (toolbarFrame, [toolbarView frame]);
  detail = [NSString stringWithFormat: @"toolbar hidden: content %gpt from the top; shown: toolbar %gpt from the top, %gpt above the content",
    hiddenGap, shownGap, NSMinY ([toolbarView frame]) - NSMaxY ([content frame])];
  if (hiddenGap == 46 && shownGap == 46 && fabs (NSMinY ([toolbarView frame]) - NSMaxY ([content frame])) <= 1
    && [QuirkProbePrimaryButtonIn (toolbarFrame) superview] == toolbarFrame)
    [self pass: @"primary-menu-toolbar-toggle" detail: detail];
  else
    [self fail: @"primary-menu-toolbar-toggle" detail: detail];
}

/* The header bar the theme draws when GNUstep draws the decorations,
   measured against libadwaita 1.7 (Reference/HeaderBar). */
- (void) checkHeaderBar
{
  NSView *frameView = [[_headerWindow contentView] superview];
  NSRect bounds = [frameView bounds];
  NSArray *buttons = QuirkProbeWindowButtons (frameView);
  NSButton *closeButton = [buttons lastObject];
  NSString *detail;
  NSRect titleInk = NSZeroRect;
  NSUInteger barBackground = 750;
  /* Set by run-quirk-probe.sh for QUIRK_PROBE_STYLE=high-contrast. */
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];

  if (QuirkProbeDrawsDecorations () == NO)
    {
      [self skip: @"header-bar" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }

  /* A 46pt bar; 34pt buttons 6pt from the top and the end, 3pt apart, in
     button-layout's order (appmenu:minimize,maximize,close here). */
  {
    NSMutableArray *parts = [NSMutableArray array];
    NSEnumerator *enumerator = [[frameView subviews] objectEnumerator];
    NSView *subview;
    CGFloat below = NSHeight (bounds);
    BOOL ok = [frameView isKindOfClass: NSClassFromString (@"GnomeThemeHeaderBarDecorationView")] && [buttons count] == 3;
    NSUInteger i;

    while ((subview = [enumerator nextObject]) != nil)
      {
        if ([buttons containsObject: subview] == NO && subview != QuirkProbePrimaryButtonIn (frameView))
          {
            below = MIN (below, QuirkProbeTopGap (frameView, [subview frame]));
          }
      }
    for (i = 0; i < [buttons count]; i++)
      {
        NSButton *button = [buttons objectAtIndex: i];
        NSRect frame = [button frame];
        NSInteger expected[] = { NSWindowMiniaturizeButton, NSWindowZoomButton, NSWindowCloseButton };

        [parts addObject: [NSString stringWithFormat: @"%ld at %@", (long)[button tag], NSStringFromRect (frame)]];
        ok = ok && i < 3 && [button tag] == expected[i] && NSWidth (frame) == 34 && NSHeight (frame) == 34
          && QuirkProbeTopGap (frameView, frame) == 6
          && (i == 0 || NSMinX (frame) - NSMaxX ([[buttons objectAtIndex: i - 1] frame]) == 3);
      }
    ok = ok && NSMaxX ([closeButton frame]) == NSMaxX (bounds) - 6 && below == 46;
    detail = [NSString stringWithFormat: @"%@ in %@; content %gpt from the top; buttons %@",
      NSStringFromClass ([frameView class]), NSStringFromRect (bounds), below,
      [parts componentsJoinedByString: @", "]];
    if (ok)
      [self pass: @"header-bar-layout" detail: detail];
    else
      [self fail: @"header-bar-layout" detail: detail];
  }

  /* Rendered: the bold title centred on the window (or, when that would
     reach them, 6pt clear of the controls at the end, as GTK's centre box
     shifts it) with its ink 17px from the top (as libadwaita's), and a
     circle 10% of the text colour behind the buttons. */
  {
    NSBitmapImageRep *rep;
    QuirkProbeInk title, circle, background, ring;
    NSRect closeFrame = [closeButton frame];
    NSView *menuButton = QuirkProbePrimaryButtonIn (frameView);
    CGFloat circleY = QuirkProbeTopGap (frameView, closeFrame) + 17;
    CGFloat centre, expected, end;
    long circleContrast, ringContrast;

    /* Renders come from the backing store: draw the focus change first. */
    [_headerWindow makeKeyWindow];
    [_headerWindow displayIfNeeded];
    rep = QuirkProbeRender (frameView);
    barBackground = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (20, 4, 4, 4)).darkest;
    QuirkProbeInkBackground = barBackground;
    /* Inside the border, up to the buttons, or the ☰ before them in the
       primary menu's run. */
    title = QuirkProbeMeasureIn (rep, QuirkProbeIsInk,
                                 NSMakeRect (1, 1, NSMinX (menuButton != nil ? [menuButton frame]
                                                           : [[buttons objectAtIndex: 0] frame]) - 1, 44));
    titleInk = NSMakeRect (title.minX, title.minY, title.width, title.height);
    centre = title.minX + title.width / 2.0;
    end = NSMinX (menuButton != nil ? [menuButton frame] : [[buttons objectAtIndex: 0] frame]) - 6;
    expected = MIN (NSWidth (bounds) / 2.0, end - title.width / 2.0);
    circle = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (NSMinX (closeFrame) + 6, circleY - 1, 2, 3));
    background = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (NSMinX (closeFrame) - 2, circleY - 1, 1, 3));
    /* The circle's left edge: its ring in high contrast. */
    ring = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (NSMinX (closeFrame) + 5, circleY - 1, 1, 3));
    circleContrast = labs ((long)circle.darkest - (long)background.darkest);
    ringContrast = labs ((long)ring.darkest - (long)background.darkest);
    detail = [NSString stringWithFormat: @"title ink %ldx%ld at (%ld, %ld), centre %g (expected %g); circle %lu, its edge %lu, on %lu%@",
      (long)title.width, (long)title.height, (long)title.minX, (long)title.minY, centre, expected,
      (unsigned long)circle.darkest, (unsigned long)ring.darkest, (unsigned long)background.darkest,
      highContrast ? @" (high contrast: a ring)" : @""];
    if (title.count > 0 && fabs (centre - expected) <= 3 && title.minY >= 16 && title.minY <= 18
      && title.height >= 10 && title.height <= 14
      && circleContrast > 30 && circleContrast < 110
      && (highContrast == NO || ringContrast > circleContrast + 60))
      [self pass: @"header-bar-render" detail: detail];
    else
      [self fail: @"header-bar-render" detail: detail];
  }

  /* Another window key: the title dims, as GTK's backdrop state. */
  {
    NSUInteger focused = QuirkProbeContrast (QuirkProbeMeasureIn (QuirkProbeRender (frameView), QuirkProbeIsAnyPixel, titleInk),
                                             barBackground);
    NSUInteger dimmed;

    [_controlsWindow makeKeyWindow];
    [_headerWindow displayIfNeeded];
    dimmed = QuirkProbeContrast (QuirkProbeMeasureIn (QuirkProbeRender (frameView), QuirkProbeIsAnyPixel, titleInk),
                                 barBackground);
    detail = [NSString stringWithFormat: @"title's contrast with the bar %lu focused, %lu not", (unsigned long)focused, (unsigned long)dimmed];
    if (focused >= 450 && dimmed + 150 <= focused)
      [self pass: @"header-bar-backdrop" detail: detail];
    else
      [self fail: @"header-bar-backdrop" detail: detail];
  }

  /* Edges resize: the frame view takes clicks there, over the content.
     A window that can't be resized leaves them to the content. */
  {
    NSView *controlsFrame = [[_controlsWindow contentView] superview];
    CGFloat midY = NSMidY (bounds) - 20;
    BOOL edges = [frameView hitTest: NSMakePoint (2, midY)] == frameView
      && [frameView hitTest: NSMakePoint (NSMaxX (bounds) - 2, midY)] == frameView
      && [frameView hitTest: NSMakePoint (NSMidX (bounds), 2)] == frameView
      && [frameView hitTest: NSMakePoint (3, 3)] == frameView;
    NSView *inside = [frameView hitTest: NSMakePoint (12, midY)];
    NSView *fixed = [controlsFrame hitTest: NSMakePoint (2, 100)];

    NSCursor *leftCursor, *cornerCursor, *insideCursor;

    /* The cursor shows the resize direction. */
    [_headerWindow makeKeyWindow];
    [_headerWindow resetCursorRects];
    QuirkProbeMoveMouseForCursor (_headerWindow, NSMakePoint (NSMidX (bounds), NSMidY (bounds) - 20));
    QuirkProbeMoveMouseForCursor (_headerWindow, NSMakePoint (2, midY));
    leftCursor = [NSCursor currentCursor];
    QuirkProbeMoveMouseForCursor (_headerWindow, NSMakePoint (3, 3));
    cornerCursor = [NSCursor currentCursor];
    QuirkProbeMoveMouseForCursor (_headerWindow, NSMakePoint (NSMidX (bounds), NSMidY (bounds) - 20));
    insideCursor = [NSCursor currentCursor];
    [_controlsWindow makeKeyWindow];

    detail = [NSString stringWithFormat: @"edges %@; 12pt in: %@; unresizable window's edge: %@; cursors: left edge %@, corner %@, inside %@",
      edges ? @"taken" : @"not taken", NSStringFromClass ([inside class]), NSStringFromClass ([fixed class]),
      leftCursor == [NSCursor resizeLeftRightCursor] ? @"left-right" : @"other",
      (cornerCursor != leftCursor && cornerCursor != [NSCursor resizeUpDownCursor] && cornerCursor != insideCursor) ? @"diagonal" : @"other",
      insideCursor == [NSCursor arrowCursor] ? @"arrow" : @"other"];
    if (edges && inside != frameView && fixed != controlsFrame
      && leftCursor == [NSCursor resizeLeftRightCursor] && cornerCursor != leftCursor
      && cornerCursor != insideCursor && insideCursor != leftCursor)
      [self pass: @"header-bar-resize-edges" detail: detail];
    else
      [self fail: @"header-bar-resize-edges" detail: detail];
  }

  /* Double-clicking the bar maximises (GNOME's default action); again
     goes back to the frame before. */
  {
    NSRect before = [_headerWindow frame];
    NSRect maximised;
    BOOL zoomed;

    QuirkProbeClick (_headerWindow, NSMakePoint (40, NSHeight ([frameView bounds]) - 20), 2);
    maximised = [_headerWindow frame];
    zoomed = [_headerWindow isZoomed];
    QuirkProbeClick (_headerWindow, NSMakePoint (40, NSHeight ([frameView bounds]) - 20), 2);
    detail = [NSString stringWithFormat: @"%@, then %@ (%@), then %@", NSStringFromRect (before),
      NSStringFromRect (maximised), zoomed ? @"zoomed" : @"not zoomed", NSStringFromRect ([_headerWindow frame])];
    if (zoomed && NSEqualRects (maximised, before) == NO && NSEqualRects ([_headerWindow frame], before))
      [self pass: @"header-bar-double-click" detail: detail];
    else
      [self fail: @"header-bar-double-click" detail: detail];
  }

  /* Right to left (as GTK in Arabic or Hebrew): the buttons at the end go
     to the left, close outermost, 6pt from the edge; the ☰ 6pt to their
     right. Switched through a volatile domain, so nothing is saved. */
  {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *searchList = AUTORELEASE ([[defaults searchList] mutableCopy]);
    NSArray *mirrored;
    NSView *menuButton;
    NSMutableArray *parts = [NSMutableArray array];
    BOOL ok;
    NSUInteger i;

    [defaults setVolatileDomain: [NSDictionary dictionaryWithObject: @"YES" forKey: @"NSForceRightToLeftWritingDirection"]
                        forName: @"QuirkProbeRightToLeft"];
    [searchList insertObject: @"QuirkProbeRightToLeft" atIndex: 0];
    [defaults setSearchList: searchList];
    [frameView performSelector: @selector(updateRects)];
    mirrored = QuirkProbeWindowButtons (frameView);
    menuButton = QuirkProbePrimaryButtonIn (frameView);
    for (i = 0; i < [mirrored count]; i++)
      {
        [parts addObject: [NSString stringWithFormat: @"%ld at %g", (long)[[mirrored objectAtIndex: i] tag],
          NSMinX ([[mirrored objectAtIndex: i] frame])]];
      }
    if (menuButton != nil)
      {
        [parts addObject: [NSString stringWithFormat: @"☰ view at %g", NSMinX ([menuButton frame])]];
      }
    ok = [mirrored count] == 3
      && [[mirrored objectAtIndex: 0] tag] == NSWindowCloseButton && NSMinX ([[mirrored objectAtIndex: 0] frame]) == 6
      && [[mirrored objectAtIndex: 1] tag] == NSWindowZoomButton && NSMinX ([[mirrored objectAtIndex: 1] frame]) == 43
      && [[mirrored objectAtIndex: 2] tag] == NSWindowMiniaturizeButton && NSMinX ([[mirrored objectAtIndex: 2] frame]) == 80
      && (menuButton == nil || NSMinX ([menuButton frame]) == 120);

    [searchList removeObject: @"QuirkProbeRightToLeft"];
    [defaults setSearchList: searchList];
    [defaults removeVolatileDomainForName: @"QuirkProbeRightToLeft"];
    [frameView performSelector: @selector(updateRects)];

    detail = [parts componentsJoinedByString: @", "];
    if (ok)
      [self pass: @"header-bar-rtl" detail: detail];
    else
      [self fail: @"header-bar-rtl" detail: detail];
  }

  /* A right-click on the bar opens the window menu (GNOME's default
     action-right-click-titlebar), which stays open after the release. */
  {
    NSPoint inBar = NSMakePoint (40, NSHeight ([frameView bounds]) - 20);
    NSString *titles;

    ASSIGN (QuirkProbePrimaryTitles, [NSMutableArray array]);
    [NSApp postEvent: [NSEvent mouseEventWithType: NSRightMouseUp location: inBar modifierFlags: 0 timestamp: 0
                                     windowNumber: [_headerWindow windowNumber] context: nil eventNumber: 0
                                       clickCount: 1 pressure: 0.0]
             atStart: NO];
    [self after: 0.3 perform: @selector(inspectPrimaryMenu:) mode: NSEventTrackingRunLoopMode];
    [NSApp sendEvent: [NSEvent mouseEventWithType: NSRightMouseDown location: inBar modifierFlags: 0 timestamp: 0
                                     windowNumber: [_headerWindow windowNumber] context: nil eventNumber: 0
                                       clickCount: 1 pressure: 1.0]];
    titles = [QuirkProbePrimaryTitles componentsJoinedByString: @" | "];
    if ([titles isEqualToString: @"Hide | Maximize | -- | Always on Top | -- | Close"])
      [self pass: @"header-bar-window-menu" detail: titles];
    else
      [self fail: @"header-bar-window-menu" detail: [titles length] > 0 ? titles : @"no menu open 0.3s after the click"];
  }

  /* Other kinds of window: where the content starts and which buttons
     show. Panels (utility ones too) get the bar, as GNOME's dialogs do;
     a window with buttons and no title gets the bar without one; without
     title or buttons only the border stays; fullscreen has neither. */
  {
    struct { const char *name; BOOL panel; NSUInteger style; CGFloat top; NSUInteger buttons; } kinds[] = {
      { "panel", YES, NSTitledWindowMask | NSClosableWindowMask, 46, 1 },
      { "utility", YES, NSTitledWindowMask | NSClosableWindowMask | NSUtilityWindowMask, 46, 1 },
      { "untitled", NO, NSClosableWindowMask | NSResizableWindowMask, 46, 2 },
      { "resizable", NO, NSResizableWindowMask, 1, 0 },
      { "borderless", NO, NSBorderlessWindowMask, 0, 0 },
      { "fullscreen", NO, NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask | NSFullScreenWindowMask, 0, 0 }
    };
    NSMutableArray *parts = [NSMutableArray array];
    BOOL ok = YES;
    NSUInteger i;

    for (i = 0; i < sizeof (kinds) / sizeof (kinds[0]); i++)
      {
        Class windowClass = kinds[i].panel ? [NSPanel class] : [NSWindow class];
        NSWindow *window = [[windowClass alloc] initWithContentRect: NSMakeRect (500, 300, 260, 100)
                                                          styleMask: kinds[i].style
                                                            backing: NSBackingStoreBuffered
                                                              defer: NO];
        NSView *kindFrame = [[window contentView] superview];
        CGFloat top = QuirkProbeTopGap (kindFrame, [[window contentView] frame]);
        NSUInteger count = [QuirkProbeWindowButtons (kindFrame) count];
        BOOL edge = [kindFrame hitTest: NSMakePoint (2, 50)] == kindFrame;
        BOOL expectEdge = (kinds[i].style & NSResizableWindowMask) && !(kinds[i].style & NSFullScreenWindowMask);

        [window setTitle: @"Kind"];
        [parts addObject: [NSString stringWithFormat: @"%s %gpt, %lu button(s)%@", kinds[i].name, top,
          (unsigned long)count, edge ? @", resize edges" : @""]];
        ok = ok && top == kinds[i].top && count == kinds[i].buttons && edge == expectEdge;
        RELEASE (window);
      }
    detail = [parts componentsJoinedByString: @"; "];
    if (ok)
      [self pass: @"header-bar-window-kinds" detail: detail];
    else
      [self fail: @"header-bar-window-kinds" detail: detail];
  }

  /* A window that can only be closed: one button, at the end, which
     closes it. */
  {
    NSWindow *closable = [[NSWindow alloc] initWithContentRect: NSMakeRect (500, 420, 240, 80)
                                                     styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
    NSView *closableFrame;
    NSArray *closableButtons;
    NSButton *button;

    [closable setReleasedWhenClosed: NO];
    [closable setTitle: @"Closable"];
    [closable orderFront: nil];
    closableFrame = [[closable contentView] superview];
    closableButtons = QuirkProbeWindowButtons (closableFrame);
    button = [closableButtons lastObject];
    detail = [NSString stringWithFormat: @"%lu button(s), the last at %@ in %@",
      (unsigned long)[closableButtons count], NSStringFromRect ([button frame]), NSStringFromRect ([closableFrame bounds])];
    [button performClick: nil];
    if ([closableButtons count] == 1 && [button tag] == NSWindowCloseButton
      && NSMaxX ([button frame]) == NSMaxX ([closableFrame bounds]) - 6 && [closable isVisible] == NO)
      [self pass: @"header-bar-close" detail: detail];
    else
      [self fail: @"header-bar-close" detail: [detail stringByAppendingString: [closable isVisible] ? @"; still open" : @""]];
    RELEASE (closable);
  }
}

- (void) checkFonts
{
  NSFont *system = [NSFont systemFontOfSize: 0];
  NSFont *bold = [NSFont boldSystemFontOfSize: 0];
  NSString *detail = [NSString stringWithFormat: @"system %@, bold %@",
    [system fontName], [bold fontName]];

  if ([[system familyName] isEqualToString: [bold familyName]]
    && ([[NSFontManager sharedFontManager] traitsOfFont: bold] & NSBoldFontMask) != 0)
    {
      [self pass: @"bold-font-family" detail: detail];
    }
  else
    {
      [self fail: @"bold-font-family" detail: detail];
    }
}

/* Tool tips and drag images are hidden by shrinking their window to
   NSZeroRect before ordering it out, which leaves them frozen under
   Mutter/Xwayland (GNOME/mutter#5080). On Wayland the theme keeps the size;
   elsewhere it leaves GNUstep's shrink alone. */
- (void) showForHiding: (NSWindow *)window
{
  [window setFrame: NSMakeRect (100, 100, 80, 24) display: NO];
  [window orderFront: nil];
}

- (void) checkHiddenWindow: (NSWindow *)window ident: (NSString *)ident
{
  BOOL wayland = (getenv ("WAYLAND_DISPLAY") != NULL);
  NSRect frame = [window frame];
  NSString *detail = [NSString stringWithFormat: @"%@ after hiding (%@), %@",
    NSStringFromSize (frame.size), wayland ? @"Wayland" : @"not Wayland",
    [window isVisible] ? @"still visible" : @"ordered out"];

  /* GNUstep clamps NSZeroRect to 1x1. */
  BOOL shrunk = (NSWidth (frame) <= 1 && NSHeight (frame) <= 1);

  if ([window isVisible] == NO && shrunk != wayland)
    {
      [self pass: ident detail: detail];
    }
  else
    {
      [self fail: ident detail: detail];
    }
}

/* A tool tip shown by GSToolTips itself: libadwaita's dark box with light
   text and its padding, no black border, in the interface font's size, and
   it stays put when it follows an unmoved pointer
   (plugins-themes-Adwaita#1). */
- (void) checkToolTip
{
  Class tipsClass = NSClassFromString (@"GSToolTips");
  NSView *anchor = [[_controlsWindow contentView] viewWithTag: 1];
  NSString *tipText = @"Zoom: Fit to Window";
  NSTimer *fake;
  id tips;
  NSWindow *panel = nil;
  NSEnumerator *enumerator;
  NSWindow *window;
  NSBitmapImageRep *rep;
  QuirkProbeInk edge, light;
  NSRect shown, followed;
  NSString *detail;

  if (tipsClass == Nil || anchor == nil)
    {
      [self skip: @"tooltip-adwaita" detail: @"GSToolTips not found"];
      return;
    }
  [anchor setToolTip: tipText];
  tips = [tipsClass performSelector: @selector(tipsForView:) withObject: anchor];
  fake = [NSTimer timerWithTimeInterval: 1000 target: self selector: @selector(finish)
                               userInfo: tipText repeats: NO];
  [tips performSelector: @selector(_timedOut:) withObject: fake];

  enumerator = [[NSApp windows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      if ([window isKindOfClass: NSClassFromString (@"GSTTPanel")] && [window isVisible])
        {
          panel = window;
        }
    }
  if (panel == nil)
    {
      [self fail: @"tooltip-adwaita" detail: @"no tool tip window shown"];
      return;
    }
  shown = [panel frame];
  [tips performSelector: @selector(mouseMoved:) withObject: nil];
  followed = [panel frame];

  rep = QuirkProbeRender ([panel contentView]);
  QuirkProbeInkBackground = 0;
  light = QuirkProbeMeasure (rep, QuirkProbeIsWhite);
  edge = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSMakeRect (0, 0, 1, [rep pixelsHigh]));
  QuirkProbeInkBackground = 750;
  detail = [NSString stringWithFormat: @"%gx%g; text ink %ldx%ld at %ld,%ld; edge r+g+b %lu-%lu; "
    @"%@ after following an unmoved pointer",
    NSWidth (shown), NSHeight (shown), (long)light.width, (long)light.height,
    (long)light.minX, (long)light.minY, (unsigned long)edge.darkest, (unsigned long)edge.lightest,
    NSEqualRects (shown, followed) ? @"same frame" : NSStringFromRect (followed)];

  if (light.count > 0 && light.minX >= 8 && light.minY >= 4
    && light.minX + light.width <= NSWidth (shown) - 8
    && light.height >= 10
    && edge.lightest < 200 && edge.lightest - edge.darkest < 30
    && NSEqualRects (shown, followed))
    {
      [self pass: @"tooltip-adwaita" detail: detail];
    }
  else
    {
      [self fail: @"tooltip-adwaita" detail: detail];
    }
  [tips performSelector: @selector(_endDisplay)];
  [anchor setToolTip: nil];
}

- (void) checkHiddenWindows
{
  Class panelClass = NSClassFromString (@"GSTTPanel");
  GSDragView *dragView = [GSDragView sharedDragView];

  if (panelClass == Nil)
    {
      [self skip: @"tooltip-hide-keeps-size" detail: @"GSTTPanel not found"];
    }
  else
    {
      NSWindow *panel = [[panelClass alloc] initWithContentRect: NSMakeRect (0, 0, 100, 25)
                                                      styleMask: NSBorderlessWindowMask
                                                        backing: NSBackingStoreRetained
                                                          defer: YES];

      /* Hidden as -[GSToolTips _endDisplay:] does it. */
      [panel setReleasedWhenClosed: NO];
      [self showForHiding: panel];
      [panel setFrame: NSZeroRect display: NO];
      [panel orderOut: nil];
      [self checkHiddenWindow: panel ident: @"tooltip-hide-keeps-size"];
      RELEASE (panel);
    }

  [self showForHiding: [dragView window]];
  [dragView performSelector: @selector(_clearupWindow)];
  [self checkHiddenWindow: [dragView window] ident: @"drag-image-hide-keeps-size"];
}

/* A red square, named `name`. */
static NSImage *
QuirkProbeRedImage(NSString *name)
{
  NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (16, 16)]);

  [image lockFocus];
  [[NSColor colorWithCalibratedRed: 1.0 green: 0.0 blue: 0.0 alpha: 1.0] set];
  NSRectFill (NSMakeRect (0, 0, 16, 16));
  [image unlockFocus];
  [image setName: name];
  return image;
}

/* The colour at a button's centre, where its image is. */
static NSColor *
QuirkProbeButtonImageColor(NSButton *button)
{
  NSBitmapImageRep *rep = QuirkProbeRender (button);
  NSInteger bits = [rep bitsPerSample];
  CGFloat maxValue = (bits >= 16) ? 65535.0 : (CGFloat)((1u << bits) - 1);
  BOOL alphaFirst = [rep hasAlpha] && ([rep bitmapFormat] & NSAlphaFirstBitmapFormat) != 0;
  NSInteger start = alphaFirst ? 1 : 0;
  NSUInteger pixel[5];

  if ([rep samplesPerPixel] < 3 || [rep samplesPerPixel] > 5)
    {
      return [NSColor clearColor];
    }
  [rep getPixel: pixel atX: [rep pixelsWide] / 2 y: [rep pixelsHigh] / 2];
  return [NSColor colorWithCalibratedRed: pixel[start] / maxValue green: pixel[start + 1] / maxValue
                                    blue: pixel[start + 2] / maxValue alpha: 1.0];
}

/* Template (symbolic) images are tinted with the text colour: red ones
   named "...Template" or "...-symbolic" come out neutral (dark in the
   light palette, light in the dark one), and in the title colour on a
   suggested button; an image that isn't a template keeps its colours
   (plugins-themes-Adwaita#32). */
- (void) checkTemplateImages
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 300, 80) title: @"Probe Templates"];
  /* Image names are unique: -setName: refuses one already in use. */
  NSString *names[4] = { @"QuirkProbeIconTemplate", @"quirk-probe-icon-symbolic", @"QuirkProbeIcon",
                         @"QuirkProbeDefaultIconTemplate" };
  NSColor *colors[4];
  NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSColor *suggested = [[NSColor selectedControlTextColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL darkText = text == nil || [text brightnessComponent] < 0.5;
  BOOL darkSuggested = suggested != nil && [suggested brightnessComponent] < 0.5;
  BOOL ok = YES;
  NSMutableArray *parts = [NSMutableArray array];
  int i;

  for (i = 0; i < 4; i++)
    {
      NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (10 + 70 * i, 20, 60, 34)]);

      [button setImage: QuirkProbeRedImage (names[i])];
      [button setImagePosition: NSImageOnly];
      [button setBezelStyle: NSRoundedBezelStyle];
      if (i == 3)
        {
          [button setKeyEquivalent: @"\r"];
        }
      [[window contentView] addSubview: button];
    }
  [window orderFront: nil];
  [window display];
  for (i = 0; i < 4; i++)
    {
      colors[i] = QuirkProbeButtonImageColor ([[[window contentView] subviews] objectAtIndex: i]);
    }
  /* A segmented control's segments, one selected (plugins-themes-Adwaita#37). */
  {
    NSSegmentedControl *segments = AUTORELEASE ([[NSSegmentedControl alloc] initWithFrame: NSMakeRect (10, 0, 120, 30)]);
    NSBitmapImageRep *rep;
    NSInteger bits;
    CGFloat maxValue;
    NSInteger start;
    NSUInteger pixel[5];
    int k;

    [segments setSegmentCount: 2];
    [segments setImage: QuirkProbeRedImage (@"QuirkProbeSegmentTemplate") forSegment: 0];
    [segments setImage: QuirkProbeRedImage (@"quirk-probe-segment-symbolic") forSegment: 1];
    [segments setWidth: 60 forSegment: 0];
    [segments setWidth: 60 forSegment: 1];
    [segments setSelectedSegment: 1];
    [[window contentView] addSubview: segments];
    [window display];
    rep = QuirkProbeRender (segments);
    bits = [rep bitsPerSample];
    maxValue = (bits >= 16) ? 65535.0 : (CGFloat)((1u << bits) - 1);
    start = ([rep hasAlpha] && ([rep bitmapFormat] & NSAlphaFirstBitmapFormat)) ? 1 : 0;
    for (k = 0; k < 2; k++)
      {
        CGFloat r, g, b;

        [rep getPixel: pixel atX: (NSInteger)(([rep pixelsWide] / 4.0) * (1 + 2 * k)) y: [rep pixelsHigh] / 2];
        r = pixel[start] / maxValue; g = pixel[start + 1] / maxValue; b = pixel[start + 2] / maxValue;
        ok = ok && fabs (r - g) < 0.08 && fabs (g - b) < 0.08 && (darkText ? r < 0.5 : r > 0.5);
        [parts addObject: [NSString stringWithFormat: @"segment %d%@ %.2f/%.2f/%.2f", k,
                                   k == 1 ? @" (selected)" : @"", r, g, b]];
      }
  }
  [window orderOut: nil];

  for (i = 0; i < 4; i++)
    {
      NSColor *c = colors[i];
      CGFloat r = [c redComponent], g = [c greenComponent], b = [c blueComponent];
      BOOL neutral = fabs (r - g) < 0.08 && fabs (g - b) < 0.08;
      BOOL want;

      switch (i)
        {
          case 0: case 1: want = neutral && (darkText ? r < 0.5 : r > 0.5); break;
          case 2: want = r > 0.8 && g < 0.2 && b < 0.2; break;
          /* The default button's title colour, whatever the palette
             makes it. */
          default: want = darkSuggested ? (r < 0.3 && g < 0.3 && b < 0.3) : (neutral && r > 0.85); break;
        }
      ok = ok && want;
      [parts addObject: [NSString stringWithFormat: @"%@ %.2f/%.2f/%.2f",
                                 (i == 0 ? @"...Template" : i == 1 ? @"...-symbolic" : i == 2 ? @"not a template"
                                  : @"...Template on the default button"), r, g, b]];
    }
  if (ok)
    {
      [self pass: @"template-images" detail: [parts componentsJoinedByString: @"; "]];
    }
  else
    {
      [self fail: @"template-images" detail: [parts componentsJoinedByString: @"; "]];
    }
}

/* r, g, b (0-255) at a view's pixel, from the top left. */
static void
QuirkProbePixelAt(NSBitmapImageRep *rep, NSInteger x, NSInteger y, NSUInteger rgb[3])
{
  NSInteger bits = [rep bitsPerSample];
  NSUInteger maxValue = (bits >= 16) ? 65535 : ((1u << bits) - 1);
  NSInteger start = ([rep hasAlpha] && ([rep bitmapFormat] & NSAlphaFirstBitmapFormat)) ? 1 : 0;
  NSUInteger pixel[5];
  int i;

  [rep getPixel: pixel atX: x y: y];
  for (i = 0; i < 3; i++)
    {
      rgb[i] = pixel[start + i] * 255 / maxValue;
    }
}

/* Whether a pixel is within `tolerance` of an expected colour (0xRRGGBB),
   in every channel. */
static BOOL
QuirkProbeNear(const NSUInteger rgb[3], unsigned int expected, NSUInteger tolerance)
{
  long want[3] = { (expected >> 16) & 0xff, (expected >> 8) & 0xff, expected & 0xff };
  int i;

  for (i = 0; i < 3; i++)
    {
      if (labs ((long)rgb[i] - want[i]) > (long)tolerance)
        {
          return NO;
        }
    }
  return YES;
}

static NSString *
QuirkProbeHex(const NSUInteger rgb[3])
{
  return [NSString stringWithFormat: @"#%02lx%02lx%02lx",
    (unsigned long)rgb[0], (unsigned long)rgb[1], (unsigned long)rgb[2]];
}

/* A table in a scroll view draws on libadwaita's view colour, as a plain
   GtkColumnView does over the window (measured with
   Reference/TableCard/table_card.py, #62): #ffffff in light and #1d1d20 in
   dark, the same in high contrast. No card: no border, no rounded corners.
   The dark palette's table colours were never read (a lookup that only
   finds GSTheme's extra colours), so tables drew on #303030. */
- (void) checkTableBackground
{
  NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL dark = [windowColor redComponent] < 0.5;
  NSUInteger want[3] = { 0xff, 0xff, 0xff };
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 240, 160) title: @"Probe Table Background"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (20, 20, 200, 120)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 200, 120)]);
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"c"]);
  NSBitmapImageRep *rep;
  NSUInteger inside[3], corner[3], outside[3];
  NSString *detail;
  BOOL ok;

  if (dark)
    {
      want[0] = 0x1d; want[1] = 0x1d; want[2] = 0x20;
    }
  [column setWidth: 180];
  [[column headerCell] setStringValue: @"Column"];
  [table addTableColumn: column];
  [scrollView setDocumentView: table];
  [scrollView setHasVerticalScroller: NO];
  [scrollView setBorderType: NSNoBorder];
  [[window contentView] addSubview: scrollView];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender ([window contentView]);
  /* The middle of the empty table, its top left corner pixel (a card's
     rounded corner would show the window there) and the window beside it. */
  QuirkProbePixelAt (rep, 120, 110, inside);
  QuirkProbePixelAt (rep, 20, 160 - 20 - 120, corner);
  QuirkProbePixelAt (rep, 10, 80, outside);
  [window orderOut: nil];

  ok = labs ((long)inside[0] - (long)want[0]) <= 2 && labs ((long)inside[1] - (long)want[1]) <= 2
    && labs ((long)inside[2] - (long)want[2]) <= 2
    && labs ((long)corner[0] - (long)inside[0]) <= 2 && labs ((long)corner[2] - (long)inside[2]) <= 2;
  detail = [NSString stringWithFormat: @"%@: table #%02lx%02lx%02lx (want #%02lx%02lx%02lx), corner #%02lx%02lx%02lx, window #%02lx%02lx%02lx",
    dark ? @"dark" : @"light",
    (unsigned long)inside[0], (unsigned long)inside[1], (unsigned long)inside[2],
    (unsigned long)want[0], (unsigned long)want[1], (unsigned long)want[2],
    (unsigned long)corner[0], (unsigned long)corner[1], (unsigned long)corner[2],
    (unsigned long)outside[0], (unsigned long)outside[1], (unsigned long)outside[2]];
  if (ok)
    {
      [self pass: @"table-background" detail: detail];
    }
  else
    {
      [self fail: @"table-background" detail: detail];
    }
}

/* A view an app fills with controlBackgroundColor matches an empty table
   beside it: libadwaita's view colour, #ffffff in light and #1d1d20 in
   dark. In dark it was the card colour, #303030, a lighter pane beside the
   lists (#94). Menus keep the card colour. */
- (void) checkContentBackground
{
  NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL dark = [windowColor redComponent] < 0.5;
  unsigned int view = dark ? 0x1d1d20 : 0xffffff;
  unsigned int card = dark ? 0x303030 : 0xffffff;
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 440, 160) title: @"Probe Content Background"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (20, 20, 190, 120)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 190, 120)]);
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"c"]);
  QuirkProbeContentFillView *pane = AUTORELEASE ([[QuirkProbeContentFillView alloc]
                                                   initWithFrame: NSMakeRect (230, 20, 190, 120)]);
  NSColor *menu = [[[[GSTheme theme] colors] colorWithKey: @"menuBackgroundColor"]
                    colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSUInteger menuRGB[3] = { 0, 0, 0 };
  NSUInteger tableRGB[3], paneRGB[3];
  NSBitmapImageRep *rep;
  NSString *detail;

  [column setWidth: 170];
  [table addTableColumn: column];
  [table setHeaderView: nil];
  [scrollView setDocumentView: table];
  [scrollView setHasVerticalScroller: NO];
  [scrollView setBorderType: NSNoBorder];
  [[window contentView] addSubview: scrollView];
  [[window contentView] addSubview: pane];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender ([window contentView]);
  QuirkProbePixelAt (rep, 115, 80, tableRGB);
  QuirkProbePixelAt (rep, 325, 80, paneRGB);
  [self saveWindow: window named: @"content-background"];
  [window orderOut: nil];
  if (menu != nil)
    {
      menuRGB[0] = lround ([menu redComponent] * 255);
      menuRGB[1] = lround ([menu greenComponent] * 255);
      menuRGB[2] = lround ([menu blueComponent] * 255);
    }

  detail = [NSString stringWithFormat: @"%@: controlBackgroundColor pane %@, table %@ (want #%06x for both)",
    dark ? @"dark" : @"light", QuirkProbeHex (paneRGB), QuirkProbeHex (tableRGB), view];
  if (QuirkProbeNear (paneRGB, view, 2) && QuirkProbeNear (tableRGB, view, 2))
    {
      [self pass: @"content-background" detail: detail];
    }
  else
    {
      [self fail: @"content-background" detail: detail];
    }
  detail = [NSString stringWithFormat: @"%@: menuBackgroundColor %@ (want #%06x, the card colour)",
    dark ? @"dark" : @"light", QuirkProbeHex (menuRGB), card];
  if (menu != nil && QuirkProbeNear (menuRGB, card, 1))
    {
      [self pass: @"content-background-menus-keep-card" detail: detail];
    }
  else
    {
      [self fail: @"content-background-menus-keep-card" detail: detail];
    }
}

/* The theme's colour lookup (GnomeThemeColor(), in the bundle) reads the
   palette first: a palette-only key comes back as the palette's colour,
   not the fallback. -colorNamed:state: alone reads GSTheme's extra colour
   lists, which the theme doesn't ship, so such keys used to come back as
   the fallback (#62's dark tables, the selection below). */
/* A pop-up button's arrow image never lands on its items: NSPopUpButtonCell
   put it on each item it selected and left it on the earlier ones, so the
   open menu showed GNUstep's nibble at the right of their rows (#67). The
   items are selected in code, as ObjcMarkdown's paragraph pop-up follows
   the caret. */
- (void) checkPopUpMenuArrowImage
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 380, 70) title: @"Probe Pop-Up Items"];
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (10, 18, 160, 34)
                                                                pullsDown: NO]);
  NSPopUpButton *pullDown = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (200, 18, 160, 34)
                                                                  pullsDown: YES]);
  NSMutableArray *withImage = [NSMutableArray array];
  NSArray *buttons = [NSArray arrayWithObjects: popUp, pullDown, nil];
  NSEnumerator *enumerator = [buttons objectEnumerator];
  NSPopUpButton *button;
  NSString *detail;
  NSInteger order[4] = { 1, 2, 0, 1 };
  int i;

  [popUp addItemsWithTitles: [NSArray arrayWithObjects: @"Paragraph", @"Heading 1", @"Heading 2", nil]];
  [pullDown addItemsWithTitles: [NSArray arrayWithObjects: @"Insert", @"Table", @"Image", nil]];
  [[window contentView] addSubview: popUp];
  [[window contentView] addSubview: pullDown];
  [window orderFront: nil];
  /* Drawn after each selection, as the app's window is. */
  for (i = 0; i < 4; i++)
    {
      [popUp selectItemAtIndex: order[i]];
      [pullDown selectItemAtIndex: order[i]];
      [window display];
    }
  [window orderOut: nil];
  /* For the screenshots: the pop-up's items as its open menu shows them,
     the second hovered. */
  {
    NSMenu *copy = AUTORELEASE ([[popUp menu] copy]);
    NSMenuView *menuView = AUTORELEASE ([[NSMenuView alloc] initWithFrame: NSMakeRect (0, 0, 160, 100)]);
    NSWindow *menuWindow;

    [menuView setMenu: copy];
    [menuView sizeToFit];
    menuWindow = [self windowWithFrame: NSMakeRect (60, 200, NSWidth ([menuView frame]) + 40, NSHeight ([menuView frame]) + 40)
                                 title: @"Probe Pop-Up Menu"];
    [menuView setFrameOrigin: NSMakePoint (20, 20)];
    [[menuWindow contentView] addSubview: menuView];
    [menuWindow orderFront: nil];
    [menuView setHighlightedItemIndex: 1];
    [menuWindow display];
    [self saveWindow: menuWindow named: @"popup-menu-items"];
    [menuView setHighlightedItemIndex: -1];
    [menuWindow orderOut: nil];
  }
  while ((button = [enumerator nextObject]) != nil)
    {
      NSEnumerator *items = [[button itemArray] objectEnumerator];
      NSMenuItem *item;

      while ((item = [items nextObject]) != nil)
        {
          if ([item image] != nil)
            {
              [withImage addObject: [item title]];
            }
        }
    }
  detail = [withImage count] == 0
    ? @"no item of a pop-up or a pull-down has an image after four selections in code, each drawn"
    : [NSString stringWithFormat: @"items with the arrow image: %@", [withImage componentsJoinedByString: @", "]];
  if ([withImage count] == 0)
    {
      [self pass: @"popup-menu-no-arrow-image" detail: detail];
    }
  else
    {
      [self fail: @"popup-menu-no-arrow-image" detail: detail];
    }
}

/* A long title stops before the chevron, cut short with an ellipsis, as
   GtkDropDown's label; it ran under the chevron, whatever the cell's line
   break mode (#67). The chevron's 24pt box ends 8pt from the right edge;
   its ink starts 6pt into it. */
- (void) checkPopUpTitleTruncation
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 180, 70) title: @"Probe Pop-Up Title"];
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 18, 120, 34)
                                                                pullsDown: NO]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  QuirkProbeInk title, gap;
  NSInteger width, chevronStart;
  NSString *detail;

  [popUp addItemWithTitle: @"DejaVu Math TeX Gyre"];
  [[window contentView] addSubview: popUp];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (popUp);
  width = [rep pixelsWide];
  QuirkProbePixelAt (rep, 6, [rep pixelsHigh] / 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  chevronStart = width - 8 - 24 + 6;
  title = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (4, 6, chevronStart - 4, [rep pixelsHigh] - 12));
  gap = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (chevronStart - 5, 6, 5, [rep pixelsHigh] - 12));
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"popup-title-truncation"];
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"title ink from %ldpt to %ldpt, chevron from %ldpt; "
    @"%lu ink pixel(s) in the 5pt before the chevron",
    (long)title.minX, (long)(title.minX + title.width), (long)chevronStart, (unsigned long)gap.count];
  if (title.count > 0 && title.width >= 40 && gap.count == 0)
    {
      [self pass: @"popup-title-truncation" detail: detail];
    }
  else
    {
      [self fail: @"popup-title-truncation" detail: detail];
    }
}

/* A disabled pop-up button is libadwaita's insensitive drop-down: button and
   title at half opacity, so its fill is nearer the window's and its title
   fainter than an enabled one's. It drew exactly as enabled (#69). */
- (void) checkPopUpDisabled
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 180, 110) title: @"Probe Pop-Up Disabled"];
  NSPopUpButton *enabled = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 60, 120, 34)
                                                                  pullsDown: NO]);
  NSPopUpButton *disabled = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 14, 120, 34)
                                                                   pullsDown: NO]);
  NSBitmapImageRep *windowRep, *enabledRep, *disabledRep;
  NSUInteger windowFill[3], enabledFill[3], disabledFill[3];
  NSUInteger windowSum, enabledSum, disabledSum, enabledContrast, disabledContrast;
  NSInteger enabledDistance, disabledDistance;
  QuirkProbeInk ink;
  NSString *detail;

  [enabled addItemWithTitle: @"Mm Title"];
  [disabled addItemWithTitle: @"Mm Title"];
  [disabled setEnabled: NO];
  [[window contentView] addSubview: enabled];
  [[window contentView] addSubview: disabled];
  [window orderFront: nil];
  [window display];
  windowRep = QuirkProbeRender ([window contentView]);
  enabledRep = QuirkProbeRender (enabled);
  disabledRep = QuirkProbeRender (disabled);
  QuirkProbePixelAt (windowRep, 4, 4, windowFill);
  QuirkProbePixelAt (enabledRep, 6, [enabledRep pixelsHigh] / 2, enabledFill);
  QuirkProbePixelAt (disabledRep, 6, [disabledRep pixelsHigh] / 2, disabledFill);
  windowSum = windowFill[0] + windowFill[1] + windowFill[2];
  enabledSum = enabledFill[0] + enabledFill[1] + enabledFill[2];
  disabledSum = disabledFill[0] + disabledFill[1] + disabledFill[2];
  enabledDistance = labs ((long)enabledSum - (long)windowSum);
  disabledDistance = labs ((long)disabledSum - (long)windowSum);
  ink = QuirkProbeMeasureIn (enabledRep, QuirkProbeIsAnyPixel,
                             NSMakeRect (8, 6, 60, [enabledRep pixelsHigh] - 12));
  enabledContrast = QuirkProbeContrast (ink, enabledSum);
  ink = QuirkProbeMeasureIn (disabledRep, QuirkProbeIsAnyPixel,
                             NSMakeRect (8, 6, 60, [disabledRep pixelsHigh] - 12));
  disabledContrast = QuirkProbeContrast (ink, disabledSum);
  [self saveWindow: window named: @"popup-disabled"];
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"fill %ld from the window's enabled, %ld disabled; "
    @"title contrast %lu enabled, %lu disabled",
    (long)enabledDistance, (long)disabledDistance,
    (unsigned long)enabledContrast, (unsigned long)disabledContrast];
  if (enabledContrast > 0 && disabledContrast * 10 <= enabledContrast * 7
      && disabledDistance * 10 <= enabledDistance * 7 + 10)
    {
      [self pass: @"popup-disabled" detail: detail];
    }
  else
    {
      [self fail: @"popup-disabled" detail: detail];
    }
}

/* A submenu that doesn't fit right of its menu opens to the left, its own
   submenus go on left, and one that would leave the bottom of the screen is
   moved up into it, as GTK places submenus. GNUstep opened them right
   whatever the screen: at the right edge they ran off (#77). */
- (void) checkSubmenuAtScreenEdge
{
  NSRect visible = [[NSScreen mainScreen] visibleFrame];
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Edge"]);
  NSMenu *submenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Help"]);
  NSMenu *nested = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"More"]);
  NSMenuItem *item;
  NSWindow *menuWindow, *submenuWindow;
  NSRect menuFrame, submenuFrame, nestedFrame;
  NSPoint right, left, bottom, deeper;
  BOOL rightOK, leftOK, bottomOK, deeperOK;
  NSString *detail;

  [nested addItemWithTitle: @"Report a Bug in Something Long" action: NULL keyEquivalent: @""];
  [submenu addItemWithTitle: @"Check for Updates Now" action: NULL keyEquivalent: @""];
  [submenu addItemWithTitle: @"Documentation" action: NULL keyEquivalent: @""];
  [submenu addItemWithTitle: @"Keyboard Shortcuts" action: NULL keyEquivalent: @""];
  [submenu addItemWithTitle: @"Release Notes" action: NULL keyEquivalent: @""];
  item = [submenu addItemWithTitle: @"More" action: NULL keyEquivalent: @""];
  [submenu setSubmenu: nested forItem: item];
  [menu addItemWithTitle: @"Preferences" action: NULL keyEquivalent: @""];
  item = [menu addItemWithTitle: @"Help" action: NULL keyEquivalent: @""];
  [menu setSubmenu: submenu forItem: item];
  [menu sizeToFit];
  [submenu sizeToFit];
  [nested sizeToFit];
  menuWindow = [[menu menuRepresentation] window];
  submenuWindow = [[submenu menuRepresentation] window];
  menuFrame = [menuWindow frame];
  submenuFrame = [submenuWindow frame];
  nestedFrame = [[[nested menuRepresentation] window] frame];

  /* At the left: opens to the right, as before. */
  [menuWindow setFrameOrigin: NSMakePoint (NSMinX (visible) + 20, NSMaxY (visible) - NSHeight (menuFrame) - 20)];
  menuFrame = [menuWindow frame];
  left = [[menu menuRepresentation] locationForSubmenu: submenu];
  leftOK = left.x >= NSMaxX (menuFrame) - 10;

  /* 10pt from the right edge: opens to the left, on the screen. */
  [menuWindow setFrameOrigin: NSMakePoint (NSMaxX (visible) - NSWidth (menuFrame) - 10, NSMaxY (visible) - NSHeight (menuFrame) - 20)];
  menuFrame = [menuWindow frame];
  right = [[menu menuRepresentation] locationForSubmenu: submenu];
  rightOK = right.x >= NSMinX (visible) && right.x + NSWidth (submenuFrame) <= NSMinX (menuFrame) + 10;

  /* Its submenu goes on left, though there's room to the right of it. */
  [submenuWindow setFrameOrigin: right];
  deeper = [[submenu menuRepresentation] locationForSubmenu: nested];
  deeperOK = deeper.x + NSWidth (nestedFrame) <= right.x + 10;

  /* At the bottom: moved up onto the screen. */
  [menuWindow setFrameOrigin: NSMakePoint (NSMinX (visible) + 20, NSMinY (visible))];
  bottom = [[menu menuRepresentation] locationForSubmenu: submenu];
  bottomOK = bottom.y >= NSMinY (visible);

  detail = [NSString stringWithFormat: @"left of screen: submenu at x %.0f (menu ends %.0f); "
    @"right edge: x %.0f to %.0f (menu starts %.0f, screen ends %.0f); nested ends %.0f; bottom: y %.0f (screen from %.0f)",
    left.x, NSMaxX ([menuWindow frame]), right.x, right.x + NSWidth (submenuFrame),
    NSMaxX (visible) - NSWidth (menuFrame) - 10, NSMaxX (visible),
    deeper.x + NSWidth (nestedFrame), bottom.y, NSMinY (visible)];
  if (leftOK && rightOK && deeperOK && bottomOK)
    {
      [self pass: @"submenu-screen-edge" detail: detail];
    }
  else
    {
      [self fail: @"submenu-screen-edge" detail: detail];
    }
}

/* A submenu's first item is level with the item that opens it, as GTK
   places a submenu, in a menu that doesn't hang from a horizontal bar (a
   pop-up's menu, the main menu's); libs-gui lined the submenu's top up
   with the menu's top instead. */
- (void) checkSubmenuLinesUpWithItem
{
  NSRect visible = [[NSScreen mainScreen] visibleFrame];
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Share"]);
  NSMenu *submenu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Email as"]);
  NSMenuView *menuView, *submenuView;
  NSMenuItem *item;
  NSWindow *menuWindow;
  NSRect itemRect, firstRect;
  NSPoint location;
  CGFloat itemTop, firstTop;
  NSString *detail;

  [submenu addItemWithTitle: @"Markdown" action: NULL keyEquivalent: @""];
  [submenu addItemWithTitle: @"HTML" action: NULL keyEquivalent: @""];
  [submenu addItemWithTitle: @"PDF" action: NULL keyEquivalent: @""];
  [menu addItemWithTitle: @"Copy Link" action: NULL keyEquivalent: @""];
  [menu addItemWithTitle: @"Copy as HTML" action: NULL keyEquivalent: @""];
  [menu addItemWithTitle: @"Save a Copy" action: NULL keyEquivalent: @""];
  item = [menu addItemWithTitle: @"Email as" action: NULL keyEquivalent: @""];
  [menu setSubmenu: submenu forItem: item];
  [menu sizeToFit];
  [submenu sizeToFit];
  menuView = (NSMenuView *)[menu menuRepresentation];
  submenuView = (NSMenuView *)[submenu menuRepresentation];
  menuWindow = [menuView window];
  [menuWindow setFrameOrigin: NSMakePoint (NSMinX (visible) + 20, NSMaxY (visible) - NSHeight ([menuWindow frame]) - 20)];

  location = [menuView locationForSubmenu: submenu];
  itemRect = [menuView convertRect: [menuView rectOfItemAtIndex: 3] toView: nil];
  itemTop = [menuWindow convertBaseToScreen: NSMakePoint (0.0, NSMaxY (itemRect))].y;
  firstRect = [submenuView convertRect: [submenuView rectOfItemAtIndex: 0] toView: nil];
  firstTop = location.y + NSMaxY (firstRect);

  detail = [NSString stringWithFormat: @"item \"Email as\" top %.0f, submenu's first item top %.0f (menu top %.0f)",
    itemTop, firstTop, NSMaxY ([menuWindow frame])];
  if (fabs (firstTop - itemTop) <= 1.0)
    {
      [self pass: @"submenu-lines-up-with-item" detail: detail];
    }
  else
    {
      [self fail: @"submenu-lines-up-with-item" detail: detail];
    }
}

/* The named sort indicators an app sets on a column are GTK 4's: pan-up
   ascending, pan-down descending, about 10x6, 6pt after the title in a
   16pt box. GNUstep has no NSAscendingSortIndicator or
   NSDescendingSortIndicator, so they were nil and nothing showed (#71). */
- (BOOL) sortIndicatorIn: (NSTableHeaderView *)header
               ascending: (BOOL)ascending
                  detail: (NSMutableString *)detail
{
  NSBitmapImageRep *rep = QuirkProbeRender (header);
  NSInteger height = [rep pixelsHigh];
  NSUInteger fill[3];
  QuirkProbeInk all, title, arrow, middle, side;
  NSInteger gap;
  BOOL pointsUp, ok;

  QuirkProbePixelAt (rep, 150, height / 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  /* Lighter ink than the tests' usual threshold: header text is dim. */
  all = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (0, 0, 140, height));
  title = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (0, 0, all.minX + 30, height));
  arrow = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (all.minX + 34, 0, 140 - all.minX - 34, height));
  middle = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (arrow.minX + arrow.width / 2 - 1, 0, 2, height));
  side = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (arrow.minX, 0, 2, height));
  QuirkProbeInkBackground = 750;
  gap = arrow.minX - (title.minX + title.width);
  pointsUp = middle.minY < side.minY;
  [detail appendFormat: @"%@: title ink %ld to %ld, arrow %ldx%ld from %ld (gap %ld), points %@; ",
    ascending ? @"ascending" : @"descending",
    (long)title.minX, (long)(title.minX + title.width), (long)arrow.width, (long)arrow.height,
    (long)arrow.minX, (long)gap, pointsUp ? @"up" : @"down"];
  ok = arrow.count > 0 && arrow.width >= 8 && arrow.width <= 12 && arrow.height >= 4 && arrow.height <= 8
    && gap >= 6 && gap <= 13 && pointsUp == ascending;
  return ok;
}

- (void) checkSortIndicator
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 140) title: @"Probe Sort Indicator"];
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 120)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 300, 120)]);
  NSTableColumn *name = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"name"]);
  NSTableColumn *size = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"size"]);
  NSImage *up = [NSImage imageNamed: @"NSAscendingSortIndicator"];
  NSImage *down = [NSImage imageNamed: @"NSDescendingSortIndicator"];
  NSMutableString *detail = [NSMutableString string];
  BOOL ok;

  [[name headerCell] setStringValue: @"Name"];
  [[size headerCell] setStringValue: @"Size"];
  [name setWidth: 150];
  [size setWidth: 150];
  [table addTableColumn: name];
  [table addTableColumn: size];
  [scroll setHasVerticalScroller: YES];
  [scroll setDocumentView: table];
  [[window contentView] addSubview: scroll];
  [window orderFront: nil];

  [detail appendFormat: @"named images %@ and %@; ", up != nil ? @"found" : @"missing", down != nil ? @"found" : @"missing"];
  [table setIndicatorImage: up inTableColumn: name];
  [window display];
  ok = [self sortIndicatorIn: [table headerView] ascending: YES detail: detail];
  [self saveWindow: window named: @"sort-indicator"];
  [table setIndicatorImage: down inTableColumn: name];
  [window display];
  ok = [self sortIndicatorIn: [table headerView] ascending: NO detail: detail] && ok;

  /* No image set: the indicator follows the sort descriptors, as in Cocoa. */
  [table setIndicatorImage: nil inTableColumn: name];
  [name setSortDescriptorPrototype: AUTORELEASE ([[NSSortDescriptor alloc] initWithKey: @"name" ascending: YES])];
  [size setSortDescriptorPrototype: AUTORELEASE ([[NSSortDescriptor alloc] initWithKey: @"size" ascending: YES])];
  [detail appendString: @"from descriptors, "];
  [table setSortDescriptors: [NSArray arrayWithObject: [name sortDescriptorPrototype]]];
  [window display];
  ok = [self sortIndicatorIn: [table headerView] ascending: YES detail: detail] && ok;
  [detail appendString: @"from descriptors, "];
  [table setSortDescriptors: [NSArray arrayWithObject: [[name sortDescriptorPrototype] reversedSortDescriptor]]];
  [window display];
  ok = [self sortIndicatorIn: [table headerView] ascending: NO detail: detail] && ok;
  [window orderOut: nil];

  if (ok && up != nil && down != nil)
    {
      [self pass: @"sort-indicator" detail: detail];
    }
  else
    {
      [self fail: @"sort-indicator" detail: detail];
    }
}

/* The runs of ink across a header column `columnRect` (in pixels):
   columns with ink, apart where 3 or more have none. */
static NSArray *
QuirkProbeHeaderInkRuns (NSBitmapImageRep *rep, NSRect columnRect)
{
  NSMutableArray *runs = [NSMutableArray array];
  NSInteger x, start = -1, end = -1, height = [rep pixelsHigh];

  for (x = (NSInteger)NSMinX (columnRect) + 2; x < (NSInteger)NSMaxX (columnRect) - 2; x++)
    {
      if (QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (x, 2, 1, height - 4)).count == 0)
        {
          continue;
        }
      if (start >= 0 && x - end > 3)
        {
          [runs addObject: [NSValue valueWithRange: NSMakeRange (start, end - start + 1)]];
          start = -1;
        }
      if (start < 0)
        {
          start = x;
        }
      end = x;
    }
  if (start >= 0)
    {
      [runs addObject: [NSValue valueWithRange: NSMakeRange (start, end - start + 1)]];
    }
  return runs;
}

/* A column too narrow for its title and its sort indicator: the title is
   ellipsized and keeps clear of the indicator, before a right-aligned
   title (LinDirStat's 90pt Percentage, at GNOME's metrics, read
   "ercentage" under the ▾; 76pt at the compact ones) and
   after a left-aligned one (#84). */
- (void) checkSortIndicatorNarrow
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 140) title: @"Probe Sort Indicator Narrow"];
  NSScrollView *scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 120)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 300, 120)]);
  NSTableColumn *first = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"first"]);
  NSTableColumn *narrow = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"narrow"]);
  NSTableColumn *last = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"last"]);
  NSImage *down = [NSImage imageNamed: @"NSDescendingSortIndicator"];
  NSMutableString *detail = [NSMutableString string];
  BOOL ok = YES;
  int pass;

  [[first headerCell] setStringValue: @"Name"];
  [[narrow headerCell] setStringValue: @"Percentage"];
  [[last headerCell] setStringValue: @"Files"];
  [first setWidth: 100];
  [narrow setWidth: 76];
  [last setWidth: 90];
  [table setColumnAutoresizingStyle: NSTableViewNoColumnAutoresizing];
  [table addTableColumn: first];
  [table addTableColumn: narrow];
  [table addTableColumn: last];
  [scroll setHasVerticalScroller: YES];
  [scroll setDocumentView: table];
  [[window contentView] addSubview: scroll];
  [window orderFront: nil];
  [table setIndicatorImage: down inTableColumn: narrow];

  for (pass = 0; pass < 2; pass++)
    {
      BOOL right = (pass == 0);
      NSTableHeaderView *header = [table headerView];
      NSBitmapImageRep *rep;
      NSUInteger fill[3];
      NSArray *runs;
      NSRange arrow, title;
      NSRect column;

      [[narrow headerCell] setAlignment: right ? NSRightTextAlignment : NSLeftTextAlignment];
      [header setNeedsDisplay: YES];
      [window display];
      rep = QuirkProbeRender (header);
      column = [header headerRectOfColumn: 1];
      QuirkProbePixelAt (rep, (NSInteger)NSMinX (column) + 3, [rep pixelsHigh] / 2, fill);
      QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
      runs = QuirkProbeHeaderInkRuns (rep, column);
      QuirkProbeInkBackground = 750;
      if (right == NO)
        {
          [self saveWindow: window named: @"sort-indicator-narrow"];
        }
      if ([runs count] < 2)
        {
          [detail appendFormat: @"%@: %lu run(s) of ink, title and indicator together; ",
            right ? @"right-aligned" : @"left-aligned", (unsigned long)[runs count]];
          ok = NO;
          continue;
        }
      arrow = [[runs objectAtIndex: right ? 0 : [runs count] - 1] rangeValue];
      title = [[runs objectAtIndex: right ? 1 : 0] rangeValue];
      [detail appendFormat: @"%@ in %g to %g: indicator %lu wide at %lu, title from %lu; ",
        right ? @"right-aligned" : @"left-aligned", NSMinX (column), NSMaxX (column),
        (unsigned long)arrow.length, (unsigned long)arrow.location, (unsigned long)title.location];
      /* The indicator alone: GTK's chevron is 8 to 12 pixels wide. */
      ok = ok && arrow.length >= 8 && arrow.length <= 12;
    }
  [window orderOut: nil];
  if (ok && down != nil)
    {
      [self pass: @"sort-indicator-narrow" detail: detail];
    }
  else
    {
      [self fail: @"sort-indicator-narrow" detail: detail];
    }
}

/* A combo box that can't be edited is a GtkDropDown: focused by Tab it
   keeps its bold label, with no field editor (no cursor, no lighter strip,
   and its text didn't vanish), shows the ring after the key, and Tab moves
   on. GNUstep started the field editor (#70). */
- (void) checkDropDownComboFocus
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 120) title: @"Probe Drop-Down Focus"];
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (20, 70, 220, 34)]);
  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 20, 220, 34)]);
  NSString *tab = @"\t";
  NSEvent *tabKey;
  QuirkProbeInk before, after, ring;
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  BOOL comboFocused, noEditor, movedOn;
  NSString *detail;

  [combo addItemsWithObjectValues: [NSArray arrayWithObjects: @"Largest files", @"Duplicates", nil]];
  [combo selectItemAtIndex: 0];
  [combo setEditable: NO];
  [field setNextKeyView: combo];
  [combo setNextKeyView: field];
  [[window contentView] addSubview: field];
  [[window contentView] addSubview: combo];
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: field];
  [window display];
  rep = QuirkProbeRender (combo);
  QuirkProbePixelAt (rep, 6, [rep pixelsHigh] / 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  before = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (6, 6, 150, [rep pixelsHigh] - 12));

  tabKey = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: 0
                           timestamp: 0 windowNumber: [window windowNumber] context: nil
                          characters: tab charactersIgnoringModifiers: tab
                           isARepeat: NO keyCode: 0x17];
  [NSApp sendEvent: tabKey];
  [window display];
  comboFocused = ([window firstResponder] == combo);
  noEditor = ([combo currentEditor] == nil);
  rep = QuirkProbeRender (combo);
  after = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (6, 6, 150, [rep pixelsHigh] - 12));
  QuirkProbeInkBackground = 750;
  ring = QuirkProbeMeasure (rep, QuirkProbeIsAccentBlue);
  [self saveWindow: window named: @"dropdown-focus"];
  [NSApp sendEvent: tabKey];
  movedOn = ([window firstResponder] != combo);
  /* Leave focus-visible off for later checks. */
  QuirkProbeSendApplicationEvent (window, NSLeftMouseDown);
  QuirkProbeSendApplicationEvent (window, NSLeftMouseUp);
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"after Tab: %@ first responder, field editor %@; "
    @"label ink %ldx%ld (%lu px) closed, %ldx%ld (%lu px) focused; %lu ring pixels; next Tab %@",
    comboFocused ? @"combo box" : @"not the combo box", noEditor ? @"none" : @"up",
    (long)before.width, (long)before.height, (unsigned long)before.count,
    (long)after.width, (long)after.height, (unsigned long)after.count,
    (unsigned long)ring.count, movedOn ? @"moved on" : @"stayed"];
  if (comboFocused && noEditor && movedOn && before.count > 0
    && labs ((long)before.width - (long)after.width) <= 1
    && labs ((long)before.count - (long)after.count) * 20 <= (long)before.count
    && ring.count > 0)
    {
      [self pass: @"dropdown-combo-focus" detail: detail];
    }
  else
    {
      [self fail: @"dropdown-combo-focus" detail: detail];
    }
}

/* NSBrowser's column titles (GNUstep's own Open panel) are readable: dim
   bold header text, well apart from what's behind it. They were white on
   a light grey bezel (#72). */
- (void) checkBrowserTitles
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Browser"];
  NSBrowser *browser = AUTORELEASE ([[NSBrowser alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
  QuirkProbeBrowserDelegate *delegate = AUTORELEASE ([QuirkProbeBrowserDelegate new]);
  NSBitmapImageRep *rep;
  NSRect titleFrame;
  NSRect area;
  NSUInteger fill[3];
  QuirkProbeInk ink;
  NSUInteger contrast;
  NSString *detail;

  [browser setDelegate: delegate];
  [browser setTitled: YES];
  [browser setMaxVisibleColumns: 2];
  [[window contentView] addSubview: browser];
  [browser loadColumnZero];
  [browser selectRow: 0 inColumn: 0];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (browser);
  titleFrame = [browser titleFrameOfColumn: 0];
  /* In pixels from the top. */
  area = NSMakeRect (NSMinX (titleFrame), [browser isFlipped] ? NSMinY (titleFrame)
                     : NSHeight ([browser bounds]) - NSMaxY (titleFrame),
                     NSWidth (titleFrame), NSHeight (titleFrame));
  QuirkProbePixelAt (rep, (NSInteger)NSMinX (area) + 3, (NSInteger)NSMidY (area), fill);
  ink = QuirkProbeMeasureIn (rep, QuirkProbeIsAnyPixel, NSInsetRect (area, 3, 2));
  contrast = QuirkProbeContrast (ink, fill[0] + fill[1] + fill[2]);
  [self saveWindow: window named: @"browser-titles"];
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"title %@ background %lu, strongest ink %lu from it",
    NSStringFromRect (titleFrame), (unsigned long)(fill[0] + fill[1] + fill[2]), (unsigned long)contrast];
  if (contrast >= 200)
    {
      [self pass: @"browser-titles" detail: detail];
    }
  else
    {
      [self fail: @"browser-titles" detail: detail];
    }
}

/* A tinted template image keeps its bitmaps: with a 24pt one in 1px
   stripes and a solid 32pt one, tinted and drawn into 24pt, it shows the
   stripes in the tint, exactly. It was tinted at the image's size from the
   32pt bitmap and scaled down (#68). */
static NSBitmapImageRep *
QuirkProbeStripedBitmap (NSInteger pixels, BOOL striped)
{
  NSBitmapImageRep *rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                               pixelsWide: pixels
                                                                               pixelsHigh: pixels
                                                                            bitsPerSample: 8
                                                                          samplesPerPixel: 4
                                                                                 hasAlpha: YES
                                                                                 isPlanar: NO
                                                                           colorSpaceName: NSCalibratedRGBColorSpace
                                                                              bytesPerRow: 0
                                                                             bitsPerPixel: 0]);
  unsigned char *data = [rep bitmapData];
  NSInteger x, y;

  for (y = 0; y < pixels; y++)
    {
      for (x = 0; x < pixels; x++)
        {
          unsigned char *pixel = data + y * [rep bytesPerRow] + x * 4;

          pixel[0] = pixel[1] = pixel[2] = 0;
          pixel[3] = (striped && (x % 2) == 1) ? 0 : 255;
        }
    }
  [rep setSize: NSMakeSize (pixels, pixels)];
  return rep;
}

- (void) checkTintedImageReps
{
  typedef NSImage *(*TintFunction)(NSImage *, NSColor *);
  TintFunction tint = (TintFunction)dlsym (RTLD_DEFAULT, "GnomeThemeTintedImage");
  NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (32, 32)]);
  NSImage *canvas = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (24, 24)]);
  NSImage *tinted;
  NSBitmapImageRep *rep;
  NSInteger x, y, wrong = 0;
  NSString *detail;

  if (tint == NULL)
    {
      [self skip: @"tinted-image-reps" detail: @"GnomeThemeTintedImage not found"];
      return;
    }
  [image addRepresentation: QuirkProbeStripedBitmap (24, YES)];
  [image addRepresentation: QuirkProbeStripedBitmap (32, NO)];
  tinted = tint (image, [NSColor colorWithCalibratedRed: 1.0 green: 0.0 blue: 0.0 alpha: 1.0]);
  [canvas lockFocus];
  [[NSColor whiteColor] set];
  NSRectFill (NSMakeRect (0, 0, 24, 24));
  [tinted drawInRect: NSMakeRect (0, 0, 24, 24) fromRect: NSZeroRect
           operation: NSCompositeSourceOver fraction: 1.0];
  rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: NSMakeRect (0, 0, 24, 24)]);
  [canvas unlockFocus];

  for (y = 0; y < [rep pixelsHigh]; y++)
    {
      for (x = 0; x < [rep pixelsWide]; x++)
        {
          NSUInteger rgb[3];
          BOOL red;

          QuirkProbePixelAt (rep, x, y, rgb);
          red = rgb[0] > 230 && rgb[1] < 25 && rgb[2] < 25;
          if (red != ((x % 2) == 0) || (red == NO && (rgb[0] < 230 || rgb[1] < 230 || rgb[2] < 230)))
            {
              wrong++;
            }
        }
    }
  detail = [NSString stringWithFormat: @"%ld of %ldx%ld pixels not the 24pt bitmap's stripes in red; "
    @"tinted image has %lu representation(s)",
    (long)wrong, (long)[rep pixelsWide], (long)[rep pixelsHigh], (unsigned long)[[tinted representations] count]];
  if (wrong == 0 && [rep pixelsWide] == 24)
    {
      [self pass: @"tinted-image-reps" detail: detail];
    }
  else
    {
      [self fail: @"tinted-image-reps" detail: detail];
    }
}

/* A browser's columns are GNOME lists: rows and the space below them in
   the list colour (rows were controlColor, grey, over a white column), and
   a row with more inside ends in GtkTreeExpander's pan-end chevron (about
   6x10) in the text colour, not NeXT's 3D arrow. */
- (void) checkBrowserLists
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Browser Lists"];
  NSBrowser *browser = AUTORELEASE ([[NSBrowser alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
  QuirkProbeBrowserDelegate *delegate = AUTORELEASE ([QuirkProbeBrowserDelegate new]);
  NSMatrix *matrix;
  NSScrollView *scrollView;
  NSBitmapImageRep *rep;
  NSRect row1, visible;
  NSUInteger rowRGB[3], emptyRGB[3];
  NSInteger y;
  QuirkProbeInk chevron;
  BOOL coloursOK, chevronOK;
  NSString *detail;

  [browser setDelegate: delegate];
  [browser setTitled: NO];
  [browser setMaxVisibleColumns: 2];
  [[window contentView] addSubview: browser];
  [browser loadColumnZero];
  [browser selectRow: 0 inColumn: 0];
  [window orderFront: nil];
  [window display];
  matrix = [browser matrixInColumn: 0];
  scrollView = [matrix enclosingScrollView];
  rep = QuirkProbeRender ([scrollView contentView]);
  visible = [[scrollView contentView] bounds];
  row1 = [matrix cellFrameAtRow: 1 column: 0];
  y = (NSInteger)NSMidY ([matrix convertRect: row1 toView: [scrollView contentView]]) - (NSInteger)NSMinY (visible);
  if ([[scrollView contentView] isFlipped] == NO)
    {
      y = [rep pixelsHigh] - 1 - y;
    }
  /* The row, between its text and its chevron; the column below the
     rows. */
  QuirkProbePixelAt (rep, [rep pixelsWide] / 2, y, rowRGB);
  QuirkProbePixelAt (rep, [rep pixelsWide] / 2, [rep pixelsHigh] - 4, emptyRGB);
  QuirkProbeInkBackground = rowRGB[0] + rowRGB[1] + rowRGB[2];
  chevron = QuirkProbeMeasureIn (rep, QuirkProbeIsInk,
                                 NSMakeRect ([rep pixelsWide] - 24, y - 9, 22, 18));
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"browser-lists"];
  [window orderOut: nil];

  coloursOK = labs ((long)rowRGB[0] - (long)emptyRGB[0]) <= 2 && labs ((long)rowRGB[2] - (long)emptyRGB[2]) <= 2;
  chevronOK = chevron.count > 0 && chevron.width >= 4 && chevron.width <= 8
    && chevron.height >= 8 && chevron.height <= 12;
  detail = [NSString stringWithFormat: @"row %@, column below the rows %@; chevron ink %ldx%ld",
    QuirkProbeHex (rowRGB), QuirkProbeHex (emptyRGB), (long)chevron.width, (long)chevron.height];
  if (coloursOK && chevronOK)
    {
      [self pass: @"browser-lists" detail: detail];
    }
  else
    {
      [self fail: @"browser-lists" detail: detail];
    }
}

/* A browser's selected row is every other list's selection, not the solid
   accent: the table's selected-row colour, with the text colour unchanged
   and well apart from the fill. */
- (void) checkBrowserSelection
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Browser Selection"];
  NSBrowser *browser = AUTORELEASE ([[NSBrowser alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
  QuirkProbeBrowserDelegate *delegate = AUTORELEASE ([QuirkProbeBrowserDelegate new]);
  NSColor *want = [[NSColor colorWithCatalogName: @"System" colorName: @"highlightedTableRowBackgroundColor"]
                    colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSMatrix *matrix;
  NSScrollView *scrollView;
  NSBitmapImageRep *rep;
  NSUInteger rowRGB[3];
  NSInteger y;
  long wantRed, wantBlue;
  NSString *detail;

  [browser setDelegate: delegate];
  [browser setTitled: NO];
  [browser setMaxVisibleColumns: 2];
  [[window contentView] addSubview: browser];
  [browser loadColumnZero];
  [browser selectRow: 0 inColumn: 0];
  [window orderFront: nil];
  [window display];
  matrix = [browser matrixInColumn: 0];
  scrollView = [matrix enclosingScrollView];
  rep = QuirkProbeRender ([scrollView contentView]);
  y = (NSInteger)NSMidY ([matrix convertRect: [matrix cellFrameAtRow: 0 column: 0] toView: [scrollView contentView]])
    - (NSInteger)NSMinY ([[scrollView contentView] bounds]);
  if ([[scrollView contentView] isFlipped] == NO)
    {
      y = [rep pixelsHigh] - 1 - y;
    }
  QuirkProbePixelAt (rep, [rep pixelsWide] / 2, y, rowRGB);
  [window orderOut: nil];
  wantRed = lround ([want redComponent] * 255.0);
  wantBlue = lround ([want blueComponent] * 255.0);
  detail = [NSString stringWithFormat: @"selected row %@, want r %ld b %ld (a table's selected row)",
    QuirkProbeHex (rowRGB), wantRed, wantBlue];
  if (want != nil && labs ((long)rowRGB[0] - wantRed) <= 3 && labs ((long)rowRGB[2] - wantBlue) <= 3)
    {
      [self pass: @"browser-selection" detail: detail];
    }
  else
    {
      [self fail: @"browser-selection" detail: detail];
    }
}

/* Over a text view's overlay scroller the cursor is the arrow, not the
   text view's I-beam, whether the pointer comes from the text or straight
   from outside the window; back over the text it's the I-beam. */
- (void) checkOverlayScrollerCursor
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Scroller Cursor"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
  NSTextView *text = AUTORELEASE ([[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 300, 180)]);
  NSMutableString *lines = [NSMutableString string];
  NSScroller *scroller;
  NSPoint overScroller, overText, outside;
  NSCursor *fromText, *backOnText, *fromOutside;
  NSInteger i;
  NSString *detail;

  for (i = 0; i < 80; i++)
    {
      [lines appendFormat: @"Line %ld of text long enough to scroll\n", (long)i];
    }
  [text setString: lines];
  [scrollView setHasVerticalScroller: YES];
  [scrollView setDocumentView: text];
  [[window contentView] addSubview: scrollView];
  [window makeKeyAndOrderFront: nil];
  [window display];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: QuirkProbeSettleDelay]];
  scroller = [scrollView verticalScroller];
  if (NSWidth ([scroller frame]) <= 0.0 || NSMinX ([scroller frame]) >= NSWidth ([scrollView bounds]) - 1.0)
    {
      [window orderOut: nil];
      [self skip: @"overlay-scroller-cursor" detail: @"no scroller on screen"];
      return;
    }
  overScroller = [scroller convertPoint: NSMakePoint (NSMidX ([scroller bounds]), NSMidY ([scroller bounds])) toView: nil];
  overText = [scrollView convertPoint: NSMakePoint (100, 90) toView: nil];
  outside = NSMakePoint (-30, -30);

  QuirkProbeMoveMouseForCursor (window, overText);
  QuirkProbeMoveMouseForCursor (window, overScroller);
  fromText = [NSCursor currentCursor];
  QuirkProbeMoveMouseForCursor (window, overText);
  backOnText = [NSCursor currentCursor];
  QuirkProbeMoveMouseForCursor (window, outside);
  QuirkProbeMoveMouseForCursor (window, overScroller);
  fromOutside = [NSCursor currentCursor];
  QuirkProbeMoveMouseForCursor (window, outside);
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"over the scroller from the text: %@; back on the text: %@; over the scroller from outside: %@",
    fromText == [NSCursor arrowCursor] ? @"arrow" : (fromText == [NSCursor IBeamCursor] ? @"I-beam" : @"other"),
    backOnText == [NSCursor IBeamCursor] ? @"I-beam" : (backOnText == [NSCursor arrowCursor] ? @"arrow" : @"other"),
    fromOutside == [NSCursor arrowCursor] ? @"arrow" : (fromOutside == [NSCursor IBeamCursor] ? @"I-beam" : @"other")];
  if (fromText == [NSCursor arrowCursor] && backOnText == [NSCursor IBeamCursor] && fromOutside == [NSCursor arrowCursor])
    {
      [self pass: @"overlay-scroller-cursor" detail: detail];
    }
  else
    {
      [self fail: @"overlay-scroller-cursor" detail: detail];
    }
}

/* An autohiding scroll view takes its scroller out of the view tree while
   the text fits: the text keeps its I-beam right up to the edge. When the
   text grows and the scroller comes back, the scroller has the arrow. */
- (void) checkAutohiddenScrollerCursor
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Autohidden Scroller"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
  NSTextView *text = AUTORELEASE ([[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 300, 180)]);
  NSMutableString *lines = [NSMutableString string];
  NSScroller *scroller;
  NSPoint overText, nearEdge, overScroller, outside = NSMakePoint (-30, -30);
  NSCursor *shortMiddle, *shortEdge, *grownText = nil, *grownScroller = nil, *reportedMiddle;
  BOOL detached;
  NSInteger i;
  NSString *detail;

  [text setString: @"Short"];
  [scrollView setHasVerticalScroller: YES];
  [scrollView setAutohidesScrollers: YES];
  [scrollView setDocumentView: text];
  [[window contentView] addSubview: scrollView];
  [window makeKeyAndOrderFront: nil];
  [window display];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: QuirkProbeSettleDelay]];
  scroller = [scrollView verticalScroller];
  detached = ([scroller superview] == nil);
  overText = [scrollView convertPoint: NSMakePoint (100, 90) toView: nil];
  nearEdge = [scrollView convertPoint: NSMakePoint (292, 90) toView: nil];

  [window resetCursorRects];
  QuirkProbeMoveMouseForCursor (window, outside);
  QuirkProbeMoveMouseForCursor (window, overText);
  shortMiddle = [NSCursor currentCursor];
  QuirkProbeMoveMouseForCursor (window, nearEdge);
  shortEdge = [NSCursor currentCursor];
  QuirkProbeMoveMouseForCursor (window, outside);

  for (i = 0; i < 80; i++)
    {
      [lines appendFormat: @"Line %ld of text long enough to scroll\n", (long)i];
    }
  [text setString: lines];
  [window display];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: QuirkProbeSettleDelay]];
  if ([scroller superview] == scrollView)
    {
      overScroller = [scroller convertPoint: NSMakePoint (NSMidX ([scroller bounds]), NSMidY ([scroller bounds])) toView: nil];
      QuirkProbeMoveMouseForCursor (window, overScroller);
      grownScroller = [NSCursor currentCursor];
      QuirkProbeMoveMouseForCursor (window, overText);
      grownText = [NSCursor currentCursor];
    }
  QuirkProbeMoveMouseForCursor (window, outside);
  [scrollView removeFromSuperview];

  /* The same short text where the scroll view still says it has the
     detached scroller: the scroller's frame means nothing then. */
  {
    QuirkProbeDetachedScrollerScrollView *reporting
      = AUTORELEASE ([[QuirkProbeDetachedScrollerScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
    NSTextView *shortText = AUTORELEASE ([[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 300, 180)]);

    [shortText setString: @"Short"];
    [reporting setHasVerticalScroller: YES];
    [reporting setAutohidesScrollers: YES];
    [reporting setDocumentView: shortText];
    [[window contentView] addSubview: reporting];
    [[reporting verticalScroller] removeFromSuperview];
    [window display];
    [window resetCursorRects];
    QuirkProbeMoveMouseForCursor (window, outside);
    QuirkProbeMoveMouseForCursor (window, overText);
    reportedMiddle = [NSCursor currentCursor];
    QuirkProbeMoveMouseForCursor (window, outside);
  }
  [window orderOut: nil];

#define QPCursorName(c) ((c) == [NSCursor IBeamCursor] ? @"I-beam" : ((c) == [NSCursor arrowCursor] ? @"arrow" : @"other"))
  detail = [NSString stringWithFormat: @"scroller %@; short text: %@ in the middle, %@ near the edge; grown: %@ over the scroller, %@ on the text; detached but reported: %@",
    detached ? @"detached" : @"attached", QPCursorName (shortMiddle), QPCursorName (shortEdge),
    QPCursorName (grownScroller), QPCursorName (grownText), QPCursorName (reportedMiddle)];
#undef QPCursorName
  if (detached == NO)
    {
      [self skip: @"autohidden-scroller-cursor" detail: detail];
    }
  else if (shortMiddle == [NSCursor IBeamCursor] && shortEdge == [NSCursor IBeamCursor]
    && grownScroller == [NSCursor arrowCursor] && grownText == [NSCursor IBeamCursor]
    && reportedMiddle == [NSCursor IBeamCursor])
    {
      [self pass: @"autohidden-scroller-cursor" detail: detail];
    }
  else
    {
      [self fail: @"autohidden-scroller-cursor" detail: detail];
    }
}

/* Recessed and textured buttons are libadwaita's .flat buttons: nothing
   behind the label at rest, the foreground at 10% over the window while a
   toggle is on, 16% while pressed. A rounded button keeps its fill.
   (They were all the regular filled button.) */
- (void) checkFlatButtons
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 440, 70) title: @"Probe Flat Buttons"];
  NSView *content = [window contentView];
  NSInteger styles[3] = { NSRecessedBezelStyle, NSTexturedRoundedBezelStyle, NSTexturedSquareBezelStyle };
  NSButton *flat[3], *on, *pressed, *rounded;
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], rest[3][3], onRGB[3], pressedRGB[3], roundedRGB[3], text[1];
  NSInteger i, top = 70 - 46;
  BOOL restOK = YES, onOK, pressedOK, roundedOK;
  NSString *detail;

  for (i = 0; i < 3; i++)
    {
      flat[i] = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (10 + 70 * i, 20, 60, 26)]);
      [flat[i] setBezelStyle: styles[i]];
      [flat[i] setTitle: @"A"];
      [content addSubview: flat[i]];
    }
  on = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (220, 20, 60, 26)]);
  [on setBezelStyle: NSRecessedBezelStyle];
  [on setButtonType: NSPushOnPushOffButton];
  [on setTitle: @"A"];
  [on setState: NSOnState];
  [content addSubview: on];
  pressed = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (360, 20, 60, 26)]);
  [pressed setBezelStyle: NSRecessedBezelStyle];
  [pressed setTitle: @"A"];
  [[pressed cell] setHighlighted: YES];
  [content addSubview: pressed];
  rounded = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (290, 20, 60, 26)]);
  [rounded setBezelStyle: NSRoundedBezelStyle];
  [rounded setTitle: @"A"];
  [content addSubview: rounded];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (content);
  QuirkProbePixelAt (rep, 2, 2, windowRGB);
  /* 8pt in from each button's left edge, halfway down: clear of the label
     and the corners. */
  for (i = 0; i < 3; i++)
    {
      QuirkProbePixelAt (rep, 10 + 70 * i + 8, top + 13, rest[i]);
      restOK = restOK && labs ((long)rest[i][0] - (long)windowRGB[0]) <= 2;
    }
  QuirkProbePixelAt (rep, 220 + 8, top + 13, onRGB);
  QuirkProbePixelAt (rep, 290 + 8, top + 13, roundedRGB);
  QuirkProbePixelAt (rep, 360 + 8, top + 13, pressedRGB);
  text[0] = (NSUInteger)floor ([[[NSColor controlTextColor]
    colorUsingColorSpaceName: NSCalibratedRGBColorSpace] redComponent] * 255.0 + 0.5);
  /* 10% of the way from the window's red to the text's. */
  onOK = labs ((long)onRGB[0] - (long)(windowRGB[0] + 0.10 * ((long)text[0] - (long)windowRGB[0]))) <= 4
    && labs ((long)onRGB[0] - (long)windowRGB[0]) >= 6;
  pressedOK = labs ((long)pressedRGB[0] - (long)(windowRGB[0] + 0.16 * ((long)text[0] - (long)windowRGB[0]))) <= 4;
  roundedOK = labs ((long)roundedRGB[0] - (long)windowRGB[0]) >= 6;
  [self saveWindow: window named: @"flat-buttons"];
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"window %@; at rest: recessed %@, textured rounded %@, textured square %@; "
    @"recessed toggle on %@, pressed %@; rounded %@",
    QuirkProbeHex (windowRGB), QuirkProbeHex (rest[0]), QuirkProbeHex (rest[1]), QuirkProbeHex (rest[2]),
    QuirkProbeHex (onRGB), QuirkProbeHex (pressedRGB), QuirkProbeHex (roundedRGB)];
  if (restOK && onOK && pressedOK && roundedOK)
    {
      [self pass: @"flat-buttons" detail: detail];
    }
  else
    {
      [self fail: @"flat-buttons" detail: detail];
    }
}

/* Buttons whose style is a shape: a disclosure button is GtkExpander's
   arrow (pointing right closed, down open; GSTheme drew nothing), help and
   circular buttons are round (.circular), the help button with its "?"
   (they were rounded squares, the "?" lost). */
- (void) checkShapedButtons
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 70) title: @"Probe Shaped Buttons"];
  NSView *content = [window contentView];
  NSButton *closed = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (10, 20, 30, 30)]);
  NSButton *open = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (50, 20, 30, 30)]);
  NSButton *help = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (90, 20, 30, 30)]);
  NSButton *circle = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (130, 20, 30, 30)]);
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], corner[3], centre[3];
  QuirkProbeInk closedInk, openInk, helpInk;
  BOOL arrowsOK, helpOK, circleOK;
  NSString *detail;
  NSInteger top = 70 - 50;

  [closed setBezelStyle: NSDisclosureBezelStyle];
  [closed setButtonType: NSOnOffButton];
  [closed setTitle: @""];
  [open setBezelStyle: NSDisclosureBezelStyle];
  [open setButtonType: NSOnOffButton];
  [open setTitle: @""];
  [open setState: NSOnState];
  [help setBezelStyle: NSHelpButtonBezelStyle];
  [help setTitle: @""];
  [circle setBezelStyle: NSCircularBezelStyle];
  [circle setTitle: @""];
  [content addSubview: closed];
  [content addSubview: open];
  [content addSubview: help];
  [content addSubview: circle];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (content);
  QuirkProbePixelAt (rep, 2, 2, windowRGB);
  QuirkProbeInkBackground = windowRGB[0] + windowRGB[1] + windowRGB[2];
  /* Pixel rects from the top: the buttons are 30pt, 20pt up from the
     bottom of a 70pt view. */
  closedInk = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (10, top, 30, 30));
  openInk = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (50, top, 30, 30));
  QuirkProbePixelAt (rep, 92, top + 2, corner);
  QuirkProbePixelAt (rep, 145, top + 15, centre);
  helpOK = labs ((long)corner[0] - (long)windowRGB[0]) <= 3;
  QuirkProbePixelAt (rep, 132, top + 2, corner);
  circleOK = labs ((long)corner[0] - (long)windowRGB[0]) <= 3
    && labs ((long)centre[0] - (long)windowRGB[0]) >= 6;
  {
    NSUInteger fill[3];

    QuirkProbePixelAt (rep, 97, top + 15, fill);
    QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
    helpInk = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (99, top + 6, 12, 18));
  }
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"shaped-buttons"];
  [window orderOut: nil];

  arrowsOK = closedInk.count > 0 && openInk.count > 0
    && closedInk.height > closedInk.width && openInk.width > openInk.height
    && closedInk.height <= 12 && openInk.width <= 12;
  helpOK = helpOK && helpInk.count > 0 && helpInk.height >= 6;
  detail = [NSString stringWithFormat: @"disclosure arrow %ldx%ld closed, %ldx%ld open; help: corner %@, "
    @"\"?\" %ldx%ld; circular: corner %@",
    (long)closedInk.width, (long)closedInk.height, (long)openInk.width, (long)openInk.height,
    helpOK ? @"window" : @"not the window", (long)helpInk.width, (long)helpInk.height,
    circleOK ? @"window, filled inside" : @"not round"];
  if (arrowsOK && helpOK && circleOK)
    {
      [self pass: @"shaped-buttons" detail: detail];
    }
  else
    {
      [self fail: @"shaped-buttons" detail: detail];
    }
}

/* An editable combo box is an entry, its text in the regular weight the
   field editor types in; only a drop-down (not editable) has a button's
   bold label. Both were bold. Compares the ink of the same text. */
- (void) checkEditableComboWeight
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 110) title: @"Probe Combo Weight"];
  NSComboBox *editable = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 60, 220, 34)]);
  NSComboBox *dropDown = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 14, 220, 34)]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  QuirkProbeInk regular, bold;
  NSString *detail;

  [editable addItemWithObjectValue: @"Largest files"];
  [editable setStringValue: @"Largest files"];
  [dropDown addItemWithObjectValue: @"Largest files"];
  [dropDown setStringValue: @"Largest files"];
  [dropDown setEditable: NO];
  [[window contentView] addSubview: editable];
  [[window contentView] addSubview: dropDown];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (editable);
  QuirkProbePixelAt (rep, 6, [rep pixelsHigh] / 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  regular = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (6, 4, 150, [rep pixelsHigh] - 8));
  rep = QuirkProbeRender (dropDown);
  bold = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (6, 4, 150, [rep pixelsHigh] - 8));
  QuirkProbeInkBackground = 750;
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"text ink %lu px (%ldpt wide) editable, %lu px (%ldpt) drop-down",
    (unsigned long)regular.count, (long)regular.width, (unsigned long)bold.count, (long)bold.width];
  if (regular.count > 0 && bold.count * 10 >= regular.count * 12 && regular.width < bold.width)
    {
      [self pass: @"editable-combo-weight" detail: detail];
    }
  else
    {
      [self fail: @"editable-combo-weight" detail: detail];
    }
}

/* An editable combo box is libadwaita's entry linked to a button: one
   column where they overlap sets the button off, 6-20 (of 255) from the
   fill. A drop-down is one button, with none. */
- (void) checkComboSeparator
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 110) title: @"Probe Combo Separator"];
  NSComboBox *editable = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 60, 220, 34)]);
  NSComboBox *dropDown = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 14, 220, 34)]);
  NSInteger columns[2] = {0, 0}, step = 0, i, x;
  NSString *detail;

  [editable addItemWithObjectValue: @"Largest files"];
  [editable setStringValue: @"Largest files"];
  [dropDown addItemWithObjectValue: @"Largest files"];
  [dropDown setStringValue: @"Largest files"];
  [dropDown setEditable: NO];
  [[window contentView] addSubview: editable];
  [[window contentView] addSubview: dropDown];
  [window orderFront: nil];
  [window display];
  for (i = 0; i < 2; i++)
    {
      NSBitmapImageRep *rep = QuirkProbeRender (i == 0 ? editable : dropDown);
      NSUInteger fill[3];

      /* Row 6, above the text and the chevron, from past the text to the
         rounded end. */
      QuirkProbePixelAt (rep, 120, 6, fill);
      for (x = 140; x < 210; x++)
        {
          NSUInteger px[3];

          QuirkProbePixelAt (rep, x, 6, px);
          if (labs ((long)px[0] - (long)fill[0]) > 4)
            {
              columns[i]++;
              if (i == 0)
                {
                  step = labs ((long)px[0] - (long)fill[0]);
                }
            }
        }
    }
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"editable: %ld column(s), %ld from the fill; drop-down: %ld column(s)",
    (long)columns[0], (long)step, (long)columns[1]];
  if (columns[0] == 1 && step >= 6 && step <= 20 && columns[1] == 0)
    {
      [self pass: @"combo-separator" detail: detail];
    }
  else
    {
      [self fail: @"combo-separator" detail: detail];
    }
}

/* Level indicators and activity as libadwaita draws them (GtkLevelBar,
   GtkProgressBar pulsing, AdwSpinner): an 8pt bar in the accent (the
   warning colour past the warning value), discrete blocks 2pt apart, stars
   for a rating; a pulse a fifth of the trough long; a spinner a ring.
   GNUstep's were bevelled boxes in green, yellow and red, no rating image,
   grey stripes and NeXT's spinner images. */
- (void) checkLevelAndActivity
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Levels"];
  NSView *content = [window contentView];
  NSLevelIndicator *plain = AUTORELEASE ([[NSLevelIndicator alloc] initWithFrame: NSMakeRect (10, 170, 200, 18)]);
  NSLevelIndicator *warned = AUTORELEASE ([[NSLevelIndicator alloc] initWithFrame: NSMakeRect (10, 145, 200, 18)]);
  NSLevelIndicator *discrete = AUTORELEASE ([[NSLevelIndicator alloc] initWithFrame: NSMakeRect (10, 120, 200, 18)]);
  NSLevelIndicator *rating = AUTORELEASE ([[NSLevelIndicator alloc] initWithFrame: NSMakeRect (10, 95, 100, 18)]);
  /* Thresholds at or below 0 count: -1 is past a critical value of -2. */
  NSLevelIndicator *negative = AUTORELEASE ([[NSLevelIndicator alloc] initWithFrame: NSMakeRect (220, 170, 90, 18)]);
  NSProgressIndicator *pulse = AUTORELEASE ([[NSProgressIndicator alloc] initWithFrame: NSMakeRect (10, 60, 300, 20)]);
  NSProgressIndicator *spinner = AUTORELEASE ([[NSProgressIndicator alloc] initWithFrame: NSMakeRect (10, 10, 32, 32)]);
  NSBitmapImageRep *rep;
  NSUInteger accentRGB[3], warnRGB[3], windowRGB[3], troughEnd[3], troughInside[3], negativeRGB[3];
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  NSColor *accent = [[NSColor selectedControlColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  QuirkProbeInk plainInk, ratingInk, pulseInk, spinnerInk;
  NSInteger x, gaps = 0;
  BOOL inBlock = NO, levelsOK, ratingOK, pulseOK, spinnerOK;
  NSString *detail;

  [[plain cell] setLevelIndicatorStyle: NSContinuousCapacityLevelIndicatorStyle];
  [plain setMaxValue: 10];
  [plain setDoubleValue: 7];
  [[warned cell] setLevelIndicatorStyle: NSContinuousCapacityLevelIndicatorStyle];
  [warned setMaxValue: 10];
  [warned setWarningValue: 6];
  [warned setCriticalValue: 8];
  [warned setDoubleValue: 7];
  [[discrete cell] setLevelIndicatorStyle: NSDiscreteCapacityLevelIndicatorStyle];
  [discrete setMaxValue: 10];
  [discrete setDoubleValue: 4];
  [[rating cell] setLevelIndicatorStyle: NSRatingLevelIndicatorStyle];
  [rating setMaxValue: 5];
  [rating setDoubleValue: 3];
  [[negative cell] setLevelIndicatorStyle: NSContinuousCapacityLevelIndicatorStyle];
  [negative setMinValue: -10];
  [negative setMaxValue: 0];
  [negative setWarningValue: -5];
  [negative setCriticalValue: -2];
  [negative setDoubleValue: -1];
  [content addSubview: negative];
  [pulse setIndeterminate: YES];
  [spinner setStyle: NSProgressIndicatorSpinningStyle];
  [spinner setIndeterminate: YES];
  /* A stopped spinner is hidden unless asked, as in Cocoa. */
  [spinner setDisplayedWhenStopped: YES];
  [content addSubview: plain];
  [content addSubview: warned];
  [content addSubview: discrete];
  [content addSubview: rating];
  [content addSubview: pulse];
  [content addSubview: spinner];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (content);
  QuirkProbePixelAt (rep, 300, 5, windowRGB);
  /* Rows from the top of the 200pt view. */
  QuirkProbePixelAt (rep, 20, 200 - 179, accentRGB);
  QuirkProbePixelAt (rep, 20, 200 - 154, warnRGB);
  QuirkProbePixelAt (rep, 224, 200 - 179, negativeRGB);
  QuirkProbeInkBackground = windowRGB[0] + windowRGB[1] + windowRGB[2];
  plainInk = QuirkProbeMeasureIn (rep, QuirkProbeIsAccentBlue, NSMakeRect (10, 200 - 188, 200, 18));
  for (x = 10; x < 210; x++)
    {
      NSUInteger px[3];
      BOOL lit;

      QuirkProbePixelAt (rep, x, 200 - 129, px);
      lit = labs ((long)px[0] - (long)windowRGB[0]) > 8 || labs ((long)px[2] - (long)windowRGB[2]) > 8;
      if (inBlock && lit == NO)
        {
          gaps++;
        }
      inBlock = lit;
    }
  ratingInk = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (10, 200 - 113, 100, 18));
  pulseInk = QuirkProbeMeasureIn (rep, QuirkProbeIsAccentBlue, NSMakeRect (10, 200 - 80, 300, 20));
  spinnerInk = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (10, 200 - 42, 32, 32));
  QuirkProbeInkBackground = 750;
  /* The plain level's empty trough (the 8pt bar is rows 17 to 24 from
     the top): its top row and its middle, away from the rounded end. In
     high contrast the edge is the outline (libadwaita's base-hc.css). */
  QuirkProbePixelAt (rep, 190, 200 - 183, troughEnd);
  QuirkProbePixelAt (rep, 190, 200 - 179, troughInside);
  [self saveWindow: window named: @"levels"];
  [window orderOut: nil];

  levelsOK = plainInk.height >= 7 && plainInk.height <= 9 && plainInk.width >= 135 && plainInk.width <= 145
    && labs ((long)accentRGB[2] - (long)floor ([accent blueComponent] * 255.0 + 0.5)) <= 3
    && warnRGB[0] > warnRGB[2] + 100 && warnRGB[1] > warnRGB[2] + 60
    && gaps >= 8;
  /* The three filled stars; the empty ones are dimmer than ink. */
  ratingOK = ratingInk.count > 0 && ratingInk.width >= 48 && ratingInk.width <= 56 && ratingInk.height >= 12;
  pulseOK = pulseInk.count > 0 && pulseInk.width >= 50 && pulseInk.width <= 70;
  /* The turning quarter; the ring is dimmer than ink. */
  spinnerOK = spinnerInk.count > 0 && spinnerInk.width >= 10 && spinnerInk.height >= 10;
  /* The error colour: red well above green and blue. */
  levelsOK = levelsOK && negativeRGB[0] > negativeRGB[1] + 100 && negativeRGB[0] > negativeRGB[2] + 100;
  levelsOK = levelsOK && (highContrast
    ? labs ((long)troughEnd[0] - (long)troughInside[0]) >= 20
    : labs ((long)troughEnd[0] - (long)troughInside[0]) <= 3);
  detail = [NSString stringWithFormat: @"level %ldx%ld in %@ (accent), warned %@, negative critical %@, trough edge %@ inside %@; discrete gaps %ld; "
    @"rating ink %ldx%ld; pulse %ldpt of 298; spinner ink %ldx%ld",
    (long)plainInk.width, (long)plainInk.height, QuirkProbeHex (accentRGB), QuirkProbeHex (warnRGB),
    QuirkProbeHex (negativeRGB), QuirkProbeHex (troughEnd), QuirkProbeHex (troughInside),
    (long)gaps, (long)ratingInk.width, (long)ratingInk.height, (long)pulseInk.width,
    (long)spinnerInk.width, (long)spinnerInk.height];
  if (levelsOK && ratingOK && pulseOK && spinnerOK)
    {
      [self pass: @"level-and-activity" detail: detail];
    }
  else
    {
      [self fail: @"level-and-activity" detail: detail];
    }
}

/* A determinate bar as libadwaita's: an 8px trough in a 20pt bar (Cocoa's
   height), and the blue filling its height, as many rows as the trough
   beside it. */
- (void) checkProgressFill
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 240, 60) title: @"Probe Progress"];
  NSView *content = [window contentView];
  NSProgressIndicator *bar = AUTORELEASE ([[NSProgressIndicator alloc] initWithFrame: NSMakeRect (10, 20, 220, 20)]);
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3];
  NSInteger y, fillRows = 0, troughRows = 0;
  NSString *detail;

  [bar setIndeterminate: NO];
  [bar setMinValue: 0];
  [bar setMaxValue: 100];
  [bar setDoubleValue: 50];
  [content addSubview: bar];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (content);
  QuirkProbePixelAt (rep, 5, 5, windowRGB);
  /* Columns well inside the fill (x 60) and the empty trough (x 180),
     rows 20 to 40 from the top: the bar's frame. */
  for (y = 20; y < 40; y++)
    {
      NSUInteger fill[3], trough[3];

      QuirkProbePixelAt (rep, 60, y, fill);
      QuirkProbePixelAt (rep, 180, y, trough);
      if ((long)fill[2] > (long)fill[0] + 60)
        {
          fillRows++;
        }
      if (labs ((long)trough[0] - (long)windowRGB[0]) > 6)
        {
          troughRows++;
        }
    }
  [window orderOut: nil];
  detail = [NSString stringWithFormat: @"fill %ld rows, trough %ld rows", (long)fillRows, (long)troughRows];
  if (troughRows >= 7 && troughRows <= 9 && labs (fillRows - troughRows) <= 1)
    {
      [self pass: @"progress-fill" detail: detail];
    }
  else
    {
      [self fail: @"progress-fill" detail: detail];
    }
}

/* A slider's tick marks (libs-gui draws none) are GtkScale's: 1x6pt
   lines 6pt below the trough, one per tick across the knob's travel. */
- (void) checkSliderTickMarks
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 60) title: @"Probe Slider Ticks"];
  NSSlider *slider = AUTORELEASE ([[NSSlider alloc] initWithFrame: NSMakeRect (20, 16, 220, 28)]);
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  QuirkProbeInk marks;
  NSInteger x, columns = 0;
  BOOL inMark = NO, dimmed = NO;
  NSString *detail;

  [slider setNumberOfTickMarks: 5];
  [slider setDoubleValue: 0.0];
  [[window contentView] addSubview: slider];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (slider);
  QuirkProbePixelAt (rep, 2, 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  /* Below the trough (its middle is the slider's), clear of the knob's
     20pt. */
  marks = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (24, 14 + 4, 220 - 24, 10));
  for (x = 24; x < 220; x++)
    {
      QuirkProbeInk column = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (x, 14 + 4, 1, 10));

      if (column.count > 0 && inMark == NO)
        {
          columns++;
        }
      inMark = column.count > 0;
    }
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"slider-ticks"];
  /* Disabled, the marks are fainter. */
  {
    NSUInteger on[3], off[3];
    NSInteger markX = 24 + (220 - 22) / 2;
    NSBitmapImageRep *enabledRep = rep, *disabledRep;
    NSInteger x2;

    /* The middle mark's column (the slider is 220 wide, the knob at 0). */
    for (x2 = 110; x2 < 130; x2++)
      {
        QuirkProbePixelAt (enabledRep, x2, 14 + 10, on);
        if (labs ((long)on[0] - (long)fill[0]) > 20)
          {
            markX = x2;
            break;
          }
      }
    QuirkProbePixelAt (enabledRep, markX, 14 + 10, on);
    [slider setEnabled: NO];
    [window display];
    disabledRep = QuirkProbeRender (slider);
    QuirkProbePixelAt (disabledRep, markX, 14 + 10, off);
    dimmed = labs ((long)off[0] - (long)fill[0]) < labs ((long)on[0] - (long)fill[0]) - 10;
  }
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"%ld marks right of the knob (want 4), %ldpt high, from %ldpt below the top; "
    @"disabled %@", (long)columns, (long)marks.height, (long)marks.minY, dimmed ? @"fainter" : @"not fainter"];
  if (columns == 4 && marks.height >= 5 && marks.height <= 7 && dimmed)
    {
      [self pass: @"slider-tick-marks" detail: detail];
    }
  else
    {
      [self fail: @"slider-tick-marks" detail: detail];
    }
}

/* Split view dividers are GtkPaned's: thick (6pt), a 1pt line at each
   edge and the window between, no dimple; thin, one 1pt line. Both lines
   the separator colour (15%, 50% in high contrast). */
- (void) checkSplitViewDividers
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 140) title: @"Probe Split Views"];
  NSSplitView *thick = AUTORELEASE ([[NSSplitView alloc] initWithFrame: NSMakeRect (10, 75, 300, 60)]);
  NSSplitView *thin = AUTORELEASE ([[NSSplitView alloc] initWithFrame: NSMakeRect (10, 5, 300, 60)]);
  NSSplitView *views[2] = { thick, thin };
  NSUInteger windowRGB[3], first[3], middle[3], last[3], thinLine[3], thinNext[3];
  NSBitmapImageRep *rep;
  NSInteger x0, x1, t0;
  QuirkProbeInk dimple;
  BOOL thickOK, thinOK;
  NSString *detail;
  int i;

  for (i = 0; i < 2; i++)
    {
      [views[i] addSubview: AUTORELEASE ([[NSView alloc] initWithFrame: NSMakeRect (0, 0, 140, 60)])];
      [views[i] addSubview: AUTORELEASE ([[NSView alloc] initWithFrame: NSMakeRect (0, 0, 140, 60)])];
      [views[i] setVertical: YES];
      [[window contentView] addSubview: views[i]];
      [views[i] adjustSubviews];
    }
  [thick setDividerStyle: NSSplitViewDividerStyleThick];
  [thin setDividerStyle: NSSplitViewDividerStyleThin];
  [thick adjustSubviews];
  [thin adjustSubviews];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (thick);
  x0 = (NSInteger)NSMaxX ([[[thick subviews] objectAtIndex: 0] frame]);
  x1 = (NSInteger)NSMinX ([[[thick subviews] objectAtIndex: 1] frame]) - 1;
  QuirkProbePixelAt (rep, 20, 30, windowRGB);
  QuirkProbePixelAt (rep, x0, 30, first);
  QuirkProbePixelAt (rep, (x0 + x1) / 2, 30, middle);
  QuirkProbePixelAt (rep, x1, 30, last);
  QuirkProbeInkBackground = windowRGB[0] + windowRGB[1] + windowRGB[2];
  /* Between the edge lines (in high contrast, 50%, as dark as ink). */
  dimple = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (x0 + 1, 0, x1 - x0 - 1, 60));
  QuirkProbeInkBackground = 750;
  rep = QuirkProbeRender (thin);
  t0 = (NSInteger)NSMaxX ([[[thin subviews] objectAtIndex: 0] frame]);
  QuirkProbePixelAt (rep, t0, 30, thinLine);
  QuirkProbePixelAt (rep, t0 + 2, 30, thinNext);
  [self saveWindow: window named: @"split-views"];
  [window orderOut: nil];

  thickOK = x1 - x0 >= 4 && dimple.count == 0
    && labs ((long)first[0] - (long)windowRGB[0]) >= 8 && labs ((long)last[0] - (long)windowRGB[0]) >= 8
    && labs ((long)middle[0] - (long)windowRGB[0]) <= 2;
  thinOK = labs ((long)thinLine[0] - (long)windowRGB[0]) >= 8
    && labs ((long)thinLine[0] - (long)first[0]) <= 2
    && labs ((long)thinNext[0] - (long)windowRGB[0]) <= 2;
  detail = [NSString stringWithFormat: @"thick divider %ld to %ld: %@ %@ %@ on %@, %lu dark pixel(s); thin %@ then %@",
    (long)x0, (long)x1, QuirkProbeHex (first), QuirkProbeHex (middle), QuirkProbeHex (last), QuirkProbeHex (windowRGB),
    (unsigned long)dimple.count, QuirkProbeHex (thinLine), QuirkProbeHex (thinNext)];
  if (thickOK && thinOK)
    {
      [self pass: @"split-view-dividers" detail: detail];
    }
  else
    {
      [self fail: @"split-view-dividers" detail: detail];
    }
}

/* Bottom tabs are the top tabs' GtkNotebook row below the content, the
   selected tab's underline on the content's side, above its label
   (GNUstep's curved NeXT tabs were left). The frame is GtkNotebook's
   border, the separator colour, visible in every palette (it all but
   vanished in the dark one). */
- (void) checkBottomTabs
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 140) title: @"Probe Bottom Tabs"];
  NSTabView *tabView = AUTORELEASE ([[NSTabView alloc] initWithFrame: NSMakeRect (10, 10, 300, 120)]);
  NSTabViewItem *one = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"one"]);
  NSTabViewItem *two = AUTORELEASE ([[NSTabViewItem alloc] initWithIdentifier: @"two"]);
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], frameRGB[3];
  QuirkProbeInk accent, label;
  NSInteger height;
  BOOL ok;
  NSString *detail;

  [one setLabel: @"General"];
  [two setLabel: @"Advanced"];
  [tabView setTabViewType: NSBottomTabsBezelBorder];
  [tabView addTabViewItem: one];
  [tabView addTabViewItem: two];
  [[window contentView] addSubview: tabView];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (tabView);
  height = [rep pixelsHigh];
  QuirkProbePixelAt (rep, 150, 30, windowRGB);
  QuirkProbePixelAt (rep, 0, 30, frameRGB);
  accent = QuirkProbeMeasure (rep, QuirkProbeIsAccentBlue);
  QuirkProbeInkBackground = windowRGB[0] + windowRGB[1] + windowRGB[2];
  /* The labels, below the underline's rows. */
  label = QuirkProbeMeasureIn (rep, QuirkProbeIsInk,
                               NSMakeRect (2, accent.minY + accent.height, 296, height - 2 - accent.minY - accent.height));
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"bottom-tabs"];
  [window orderOut: nil];

  ok = accent.count > 0 && accent.height <= 4 && accent.minY > height / 2
    && label.count > 0 && label.height >= 8
    && labs ((long)frameRGB[0] - (long)windowRGB[0]) >= 8;
  detail = [NSString stringWithFormat: @"underline %ldx%ld from row %ld of %ld; label from row %ld; frame %@ on %@",
    (long)accent.width, (long)accent.height, (long)accent.minY, (long)height, (long)label.minY,
    QuirkProbeHex (frameRGB), QuirkProbeHex (windowRGB)];
  if (ok)
    {
      [self pass: @"bottom-tabs" detail: detail];
    }
  else
    {
      [self fail: @"bottom-tabs" detail: detail];
    }
}

/* A borderless pop-up button (as a table's pop-up cells are) is a flat
   drop-down: its title and chevron on what is behind it, no button fill.
   It drew a full button. A bordered one keeps its fill. */
- (void) checkBorderlessPopUp
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 100) title: @"Probe Borderless Pop-Up"];
  NSPopUpButton *flat = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 54, 200, 34) pullsDown: NO]);
  NSPopUpButton *bordered = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 10, 200, 34) pullsDown: NO]);
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], flatRGB[3], borderedRGB[3];
  QuirkProbeInk title, ring;
  BOOL ok;
  NSString *detail;

  [flat addItemWithTitle: @"High"];
  [flat setBordered: NO];
  [bordered addItemWithTitle: @"High"];
  [[window contentView] addSubview: flat];
  [[window contentView] addSubview: bordered];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender ([window contentView]);
  QuirkProbePixelAt (rep, 5, 5, windowRGB);
  /* Inside each button, left of its title. */
  QuirkProbePixelAt (rep, 24, 100 - 71, flatRGB);
  QuirkProbePixelAt (rep, 24, 100 - 27, borderedRGB);
  QuirkProbeInkBackground = windowRGB[0] + windowRGB[1] + windowRGB[2];
  title = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (20, 100 - 88, 200, 34));
  QuirkProbeInkBackground = 750;
  /* Focused after a key press, it shows the ring all the same. */
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: flat];
  QuirkProbeSendApplicationEvent (window, NSKeyDown);
  [window display];
  ring = QuirkProbeMeasure (QuirkProbeRender (flat), QuirkProbeIsAccentBlue);
  QuirkProbeSendApplicationEvent (window, NSLeftMouseDown);
  QuirkProbeSendApplicationEvent (window, NSLeftMouseUp);
  [window orderOut: nil];

  ok = labs ((long)flatRGB[0] - (long)windowRGB[0]) <= 2 && labs ((long)borderedRGB[0] - (long)windowRGB[0]) >= 6
    && title.count > 0 && ring.count > 0;
  detail = [NSString stringWithFormat: @"window %@; inside the borderless one %@, the bordered one %@; borderless title ink %lu px, "
    @"%lu focus ring pixels",
    QuirkProbeHex (windowRGB), QuirkProbeHex (flatRGB), QuirkProbeHex (borderedRGB), (unsigned long)title.count,
    (unsigned long)ring.count];
  if (ok)
    {
      [self pass: @"borderless-popup" detail: detail];
    }
  else
    {
      [self fail: @"borderless-popup" detail: detail];
    }
}

/* An image view's frame (photo, grey bezel, groove) is GtkFrame's
   border: one line in the separator colour, the inside the window's. It
   was NeXT's bevels: dark and light lines, nearly invisible in the dark
   palette. */
- (void) checkImageFrames
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 240, 80) title: @"Probe Image Frames"];
  NSImageFrameStyle styles[3] = { NSImageFramePhoto, NSImageFrameGrayBezel, NSImageFrameGroove };
  NSImageView *views[3];
  NSUInteger windowRGB[3];
  NSMutableString *detail = [NSMutableString string];
  BOOL ok = YES;
  int i;

  for (i = 0; i < 3; i++)
    {
      views[i] = AUTORELEASE ([[NSImageView alloc] initWithFrame: NSMakeRect (10 + 75 * i, 10, 60, 60)]);
      [views[i] setImageFrameStyle: styles[i]];
      [[window contentView] addSubview: views[i]];
    }
  [window orderFront: nil];
  [window display];
  QuirkProbePixelAt (QuirkProbeRender ([window contentView]), 5, 5, windowRGB);
  for (i = 0; i < 3; i++)
    {
      NSBitmapImageRep *rep = QuirkProbeRender (views[i]);
      NSUInteger left[3], right[3], top[3], bottom[3], inside[3];

      QuirkProbePixelAt (rep, 0, 30, left);
      QuirkProbePixelAt (rep, 59, 30, right);
      QuirkProbePixelAt (rep, 30, 0, top);
      QuirkProbePixelAt (rep, 30, 59, bottom);
      QuirkProbePixelAt (rep, 1, 30, inside);
      /* The same line all round, against the window; nothing inside it. */
      if (labs ((long)left[0] - (long)windowRGB[0]) < 8
        || labs ((long)left[0] - (long)right[0]) > 2 || labs ((long)left[0] - (long)top[0]) > 2
        || labs ((long)left[0] - (long)bottom[0]) > 2
        || labs ((long)inside[0] - (long)windowRGB[0]) > 2)
        {
          ok = NO;
        }
      [detail appendFormat: @"%@ left %@ right %@ top %@ bottom %@ inside %@; ",
        i == 0 ? @"photo" : (i == 1 ? @"grey bezel" : @"groove"),
        QuirkProbeHex (left), QuirkProbeHex (right), QuirkProbeHex (top), QuirkProbeHex (bottom), QuirkProbeHex (inside)];
    }
  [self saveWindow: window named: @"image-frames"];
  [window orderOut: nil];
  [detail appendFormat: @"window %@", QuirkProbeHex (windowRGB)];
  if (ok)
    {
      [self pass: @"image-frames" detail: detail];
    }
  else
    {
      [self fail: @"image-frames" detail: detail];
    }
}

/* A text view's ruler is on the window's colour, its marks in a dimmed
   text colour: lighter than the background in the dark palettes, darker in
   the light ones. libs-gui fills it with controlColor and draws its marks
   in black, all but lost in the dark palette. */
- (void) checkRulerMarks
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 420, 120) title: @"Probe Ruler"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: [[window contentView] bounds]]);
  NSTextView *textView = AUTORELEASE ([[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 400, 120)]);
  NSRulerView *ruler;
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], rulerRGB[3];
  NSColor *text = [[NSColor controlTextColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL darkPalette = [text redComponent] > 0.5;
  QuirkProbeInk marks;
  BOOL ok;
  NSString *detail;

  [scrollView setHasVerticalScroller: YES];
  [scrollView setDocumentView: textView];
  [scrollView setHasHorizontalRuler: YES];
  [scrollView setRulersVisible: YES];
  [window setContentView: scrollView];
  [window orderFront: nil];
  [window display];
  ruler = [scrollView horizontalRulerView];
  {
    NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    windowRGB[0] = (NSUInteger)floor ([windowColor redComponent] * 255.0 + 0.5);
    windowRGB[1] = (NSUInteger)floor ([windowColor greenComponent] * 255.0 + 0.5);
    windowRGB[2] = (NSUInteger)floor ([windowColor blueComponent] * 255.0 + 0.5);
  }
  if (ruler == nil)
    {
      [window orderOut: nil];
      [self fail: @"ruler-marks" detail: @"no ruler"];
      return;
    }
  /* What the window shows, not a bitmap render: the theme recolours the
     marks by reading its own pixels back, which only a screen has. */
  [ruler lockFocus];
  rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: [ruler bounds]]);
  [ruler unlockFocus];
  QuirkProbePixelAt (rep, [rep pixelsWide] - 30, 2, rulerRGB);
  QuirkProbeInkBackground = windowRGB[0] + windowRGB[1] + windowRGB[2];
  marks = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSZeroRect);
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"ruler"];
  [window orderOut: nil];

  /* The ink runs the text colour's way from the background. */
  ok = labs ((long)rulerRGB[0] - (long)windowRGB[0]) <= 2 && marks.count > 50
    && (darkPalette ? marks.lightest > windowRGB[0] + windowRGB[1] + windowRGB[2] + 150
                    : marks.darkest + 150 < windowRGB[0] + windowRGB[1] + windowRGB[2]);
  detail = [NSString stringWithFormat: @"window %@, ruler %@; %lu mark pixels, r+g+b %lu to %lu",
    QuirkProbeHex (windowRGB), QuirkProbeHex (rulerRGB), (unsigned long)marks.count,
    (unsigned long)marks.darkest, (unsigned long)marks.lightest];
  if (ok)
    {
      [self pass: @"ruler-marks" detail: detail];
    }
  else
    {
      [self fail: @"ruler-marks" detail: detail];
    }
}

/* A pop-up item carrying GNUstep's arrow image (common_Nibble), as items
   archived in a Gorm file do, shows only the theme's chevron: the Page
   Layout panel's empty Custom pop-up drew the nibble beside it. */
- (void) checkPopUpArchivedArrow
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 120) title: @"Probe Pop-Up Arrow"];
  NSPopUpButton *popUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 18, 200, 34) pullsDown: NO]);
  NSPopUpButton *iconPopUp = AUTORELEASE ([[NSPopUpButton alloc] initWithFrame: NSMakeRect (20, 70, 200, 34) pullsDown: NO]);
  NSImage *nibble = [NSImage imageNamed: @"common_Nibble"];
  QuirkProbeInk icon;
  NSBitmapImageRep *rep;
  NSUInteger fill[3];
  QuirkProbeInk ink;
  NSString *detail;

  [popUp addItemWithTitle: @""];
  [[popUp itemAtIndex: 0] setImage: nibble];
  [[window contentView] addSubview: popUp];
  /* An item whose icon is a 3D arrow (not a pull-down's arrow here) keeps
     it. */
  [iconPopUp addItemWithTitle: @""];
  [[iconPopUp itemAtIndex: 0] setImage: [NSImage imageNamed: @"common_3DArrowRight"]];
  [[window contentView] addSubview: iconPopUp];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (popUp);
  QuirkProbePixelAt (rep, 6, [rep pixelsHigh] / 2, fill);
  QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
  /* Everything before the chevron's box. */
  ink = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (4, 4, 200 - 8 - 24 - 6, [rep pixelsHigh] - 8));
  icon = QuirkProbeMeasureIn (QuirkProbeRender (iconPopUp), QuirkProbeIsInk,
                              NSMakeRect (4, 4, 200 - 8 - 24 - 6, [rep pixelsHigh] - 8));
  QuirkProbeInkBackground = 750;
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"nibble image %@; %lu ink pixel(s) before the chevron; a 3D arrow icon %lu",
    nibble != nil ? @"found" : @"missing", (unsigned long)ink.count, (unsigned long)icon.count];
  if (nibble == nil)
    {
      [self skip: @"popup-archived-arrow" detail: detail];
    }
  else if (ink.count == 0 && icon.count > 0)
    {
      [self pass: @"popup-archived-arrow" detail: detail];
    }
  else
    {
      [self fail: @"popup-archived-arrow" detail: detail];
    }
}

/* Below a browser's columns, where its horizontal scroller is, there is
   only the window: the theme's scrollers are overlay indicators (hidden
   when nothing overflows, as here), and GSTheme's grey bezel round the
   scroller is left out. */
- (void) checkBrowserScrollerBezel
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 200) title: @"Probe Browser Scroller"];
  NSBrowser *browser = AUTORELEASE ([[NSBrowser alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)]);
  QuirkProbeBrowserDelegate *delegate = AUTORELEASE ([QuirkProbeBrowserDelegate new]);
  NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSBitmapImageRep *rep;
  NSInteger top, x, y, marked = 0;
  NSInteger windowSum = (NSInteger)floor ([windowColor redComponent] * 255.0 + 0.5)
    + (NSInteger)floor ([windowColor greenComponent] * 255.0 + 0.5)
    + (NSInteger)floor ([windowColor blueComponent] * 255.0 + 0.5);
  NSString *detail;

  [browser setDelegate: delegate];
  [browser setMaxVisibleColumns: 2];
  [browser setHasHorizontalScroller: YES];
  [[window contentView] addSubview: browser];
  [browser loadColumnZero];
  [window orderFront: nil];
  [window display];
  rep = QuirkProbeRender (browser);
  /* From just below the columns (the browser isn't flipped) down. */
  top = [rep pixelsHigh] - (NSInteger)NSMinY ([browser frameOfColumn: 0]) + 2;
  for (y = top; y < [rep pixelsHigh]; y++)
    {
      for (x = 0; x < [rep pixelsWide]; x++)
        {
          NSUInteger rgb[3];

          QuirkProbePixelAt (rep, x, y, rgb);
          if (labs ((long)(rgb[0] + rgb[1] + rgb[2]) - (long)windowSum) > 12)
            {
              marked++;
            }
        }
    }
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"%ld pixel(s) other than the window's in rows %ld to %ld",
    (long)marked, (long)top, (long)[rep pixelsHigh] - 1];
  if (marked == 0)
    {
      [self pass: @"browser-scroller-bezel" detail: detail];
    }
  else
    {
      [self fail: @"browser-scroller-bezel" detail: detail];
    }
}

/* GNUstep's Open and Save panels' Home, Mount and Unmount buttons show
   GNOME's symbolic icons (user-home, drive-removable-media, media-eject),
   drawn as templates in the text colour; they were NeXT's icons. */
- (void) checkPanelIcons
{
  typedef BOOL (*TemplateFunction)(NSImage *);
  TemplateFunction isTemplate = (TemplateFunction)dlsym (RTLD_DEFAULT, "GnomeThemeImageIsTemplate");
  NSArray *names = [NSArray arrayWithObjects: @"common_Home", @"common_Mount", @"common_Unmount", nil];
  NSEnumerator *enumerator = [names objectEnumerator];
  NSMutableString *detail = [NSMutableString string];
  NSString *name;
  BOOL ok = (isTemplate != NULL);

  while ((name = [enumerator nextObject]) != nil)
    {
      NSImage *image = [NSImage imageNamed: name];
      NSSize size = [image size];
      BOOL symbolic = (image != nil && isTemplate != NULL && isTemplate (image));

      [detail appendFormat: @"%@ %gx%g%@; ", name, size.width, size.height, symbolic ? @" template" : @""];
      ok = ok && symbolic && size.width == 16 && size.height == 16;
    }
  if (ok)
    {
      [self pass: @"panel-icons" detail: detail];
    }
  else
    {
      [self fail: @"panel-icons" detail: detail];
    }
}

/* The About panel's icon, drawn, measured with `test`: the panel shown
   with `options`, then closed. */
static QuirkProbeInk
QuirkProbeAboutIconInk (NSDictionary *options, QuirkProbePixelTest test)
{
  QuirkProbeInk ink = { 0 };
  NSEnumerator *enumerator;
  NSWindow *window, *panel = nil;
  NSView *view;

  [NSApp orderFrontStandardAboutPanelWithOptions: options];
  enumerator = [[NSApp windows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      if ([window isVisible] && [window isKindOfClass: [NSPanel class]]
        && fabs (NSWidth ([[window contentView] frame]) - 350.0) < 0.5)
        {
          panel = window;
        }
    }
  enumerator = [[[panel contentView] subviews] objectEnumerator];
  while ((view = [enumerator nextObject]) != nil)
    {
      if ([view isKindOfClass: [NSImageView class]])
        {
          [panel display];
          ink = QuirkProbeMeasure (QuirkProbeRender (view), test);
        }
    }
  [panel orderOut: nil];
  return ink;
}

/* The standard About panel is the first page of AdwAboutWindow: 350pt
   wide, the icon at 128pt, the name in title-1 (bold, about 181% of the
   interface font), the version in a pill. GNUstep's had NeXT's layout.
   A description too long for one line wraps (the label was once one line
   tall, and cut it off), and the panel sits on whole points (at half a
   point, X11 drew nothing in it). A 32px bitmap icon is drawn at 32pt in
   the middle of its 128pt slot, not scaled up and jagged; an icon like an
   app's default one, 48pt with a 48px and a 192px bitmap, is drawn from
   the 192px one at 128pt (the 48px one was drawn, scaled up); the last
   line names the current theme, as GSInfoPanel's does. */
- (void) checkAboutPanel
{
  NSBitmapImageRep *bitmap = AUTORELEASE ([[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
    pixelsWide: 32 pixelsHigh: 32 bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
    colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0]);
  NSImage *smallIcon = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (32, 32)]);
  NSString *themeLine = [NSString stringWithFormat: @"Current theme: %@", [[GSTheme theme] name]];
  NSImageView *iconView = nil;
  QuirkProbeInk iconInk = { 0 }, largeInk, smallInk;
  BOOL themeShown = NO;
  unsigned char *pixels = [bitmap bitmapData];
  NSInteger i;

  NSString *description = @"A description long enough to need three lines or so in the About panel, "
    @"as an application's own description often is";
  NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
    @"Probe About", @"ApplicationName", @"0.1.0", @"ApplicationRelease",
    [NSArray arrayWithObject: @"QuirkProbe"], @"Authors", description, @"ApplicationDescription",
    smallIcon, @"ApplicationIcon", nil];
  CGFloat descriptionHeight = 0.0, lineHeight;
  NSPoint origin = NSZeroPoint;
  NSEnumerator *enumerator;
  NSWindow *window, *panel = nil;
  NSView *view;
  BOOL icon = NO, pill = NO;
  CGFloat nameSize = 0.0;
  NSString *detail;

  /* An opaque red square, unlike any palette's colours. */
  for (i = 0; i < 32 * 32 * 4; i++)
    {
      pixels[i] = (i % 4 == 0 || i % 4 == 3) ? 255 : 0;
    }
  [smallIcon addRepresentation: bitmap];
  [NSApp orderFrontStandardAboutPanelWithOptions: options];
  enumerator = [[NSApp windows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      if ([window isVisible] && [window isKindOfClass: [NSPanel class]]
        && fabs (NSWidth ([[window contentView] frame]) - 350.0) < 0.5)
        {
          panel = window;
        }
    }
  enumerator = [[[panel contentView] subviews] objectEnumerator];
  while ((view = [enumerator nextObject]) != nil)
    {
      if ([view isKindOfClass: [NSImageView class]] && NSEqualSizes ([view frame].size, NSMakeSize (128, 128)))
        {
          icon = YES;
          iconView = (NSImageView *)view;
        }
      if ([view isKindOfClass: [NSTextField class]] && [[(NSTextField *)view stringValue] isEqualToString: themeLine])
        {
          themeShown = YES;
        }
      if ([NSStringFromClass ([view class]) isEqualToString: @"GnomeThemeAboutPill"])
        {
          pill = YES;
        }
      if ([view isKindOfClass: [NSTextField class]]
        && [[(NSTextField *)view stringValue] isEqualToString: @"Probe About"])
        {
          nameSize = [[(NSTextField *)view font] pointSize];
        }
      if ([view isKindOfClass: [NSTextField class]]
        && [[(NSTextField *)view stringValue] isEqualToString: description])
        {
          descriptionHeight = NSHeight ([view frame]);
        }
    }
  if (iconView != nil)
    {
      [panel display];
      iconInk = QuirkProbeMeasure (QuirkProbeRender (iconView), QuirkProbeIsProbeRed);
    }
  origin = [panel frame].origin;
  [panel orderOut: nil];
  {
    NSImage *defaultLike = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (48, 48)]);
    NSBitmapImageRep *small = QuirkProbeSquareBitmap (48, 255, 0);
    NSBitmapImageRep *large = QuirkProbeSquareBitmap (192, 0, 255);

    [small setSize: NSMakeSize (48, 48)];
    [large setSize: NSMakeSize (48, 48)];
    [defaultLike addRepresentation: small];
    [defaultLike addRepresentation: large];
    largeInk = QuirkProbeAboutIconInk ([NSDictionary dictionaryWithObjectsAndKeys: @"Probe About",
      @"ApplicationName", defaultLike, @"ApplicationIcon", nil], QuirkProbeIsProbeGreen);
    smallInk = QuirkProbeAboutIconInk ([NSDictionary dictionaryWithObjectsAndKeys: @"Probe About",
      @"ApplicationName", defaultLike, @"ApplicationIcon", nil], QuirkProbeIsProbeRed);
  }
  lineHeight = [[NSFont systemFontOfSize: 0] defaultLineHeightForFont];

  detail = [NSString stringWithFormat: @"panel %@ at %@; icon %@, name at %gpt (interface %gpt), "
    @"version pill %@, long description %gpt tall (line %gpt); a 32px icon drawn %ldx%ld at %ld,%ld "
    @"(want 32x32 at 48,48); a 48pt icon with 48px and 192px bitmaps: the 192px one drawn %ldx%ld, "
    @"the 48px one %lu pixels (want 128x128 and none); \"%@\" %@",
    panel != nil ? @"350pt wide" : @"not found", NSStringFromPoint (origin), icon ? @"128pt" : @"missing",
    nameSize, [[NSFont systemFontOfSize: 0] pointSize], pill ? @"shown" : @"missing",
    descriptionHeight, lineHeight, (long)iconInk.width, (long)iconInk.height, (long)iconInk.minX,
    (long)iconInk.minY, (long)largeInk.width, (long)largeInk.height, (unsigned long)smallInk.count,
    themeLine, themeShown ? @"shown" : @"missing"];
  if (panel != nil && icon && pill && nameSize >= 1.7 * [[NSFont systemFontOfSize: 0] pointSize]
    && descriptionHeight >= 2.5 * lineHeight
    && origin.x == floor (origin.x) && origin.y == floor (origin.y)
    && iconInk.width == 32 && iconInk.height == 32 && iconInk.minX == 48 && iconInk.minY == 48 && themeShown
    && largeInk.width == 128 && largeInk.height == 128 && smallInk.count == 0)
    {
      [self pass: @"about-panel" detail: detail];
    }
  else
    {
      [self fail: @"about-panel" detail: detail];
    }
}

/* A hovered row of a menu (a pop-up button's too) is libadwaita's: the
   foreground at 10% over the menu, with the row's text in the text colour.
   It was the accent with white text, and in a pop-up button's menu, whose
   window isn't key, the pale inactive selection with white text (#67). */
- (void) checkMenuHoverTextColor
{
  typedef NSColor *(*LookupFunction)(GSTheme *, NSString *, NSColor *);
  LookupFunction lookup = (LookupFunction)dlsym (RTLD_DEFAULT, "GnomeThemeColor");
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @"Probe"]);
  NSMenuView *menuView;
  NSWindow *window;
  NSBitmapImageRep *rep;
  NSRect rows[2], bounds;
  NSUInteger hovered[3], plain[3];
  NSColor *foreground, *text;
  long want[3], textSum, fillSum;
  QuirkProbeInk ink;
  NSString *detail;
  BOOL fillOK, textOK;
  int i;

  if (lookup == NULL)
    {
      [self skip: @"menu-hover-text-colour" detail: @"GnomeThemeColor() not found in the loaded theme"];
      return;
    }
  foreground = [lookup ([GSTheme theme], @"GnomeThemeForegroundColor", [NSColor controlTextColor])
                 colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  text = [lookup ([GSTheme theme], @"controlTextColor", [NSColor controlTextColor])
           colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  [[menu addItemWithTitle: @"Heading 1" action: @selector(description) keyEquivalent: @""] setTarget: self];
  [[menu addItemWithTitle: @"Heading 2" action: @selector(description) keyEquivalent: @""] setTarget: self];
  menuView = AUTORELEASE ([[NSMenuView alloc] initWithFrame: NSMakeRect (0, 0, 200, 100)]);
  [menuView setMenu: menu];
  [menuView sizeToFit];
  window = [self windowWithFrame: NSMakeRect (40, 200, NSWidth ([menuView frame]) + 40, NSHeight ([menuView frame]) + 40)
                           title: @"QuirkProbe Menu Hover"];
  [menuView setFrameOrigin: NSMakePoint (20, 20)];
  [[window contentView] addSubview: menuView];
  [window orderFront: nil];
  [menuView setHighlightedItemIndex: 0];
  [window display];
  rep = QuirkProbeRender (menuView);
  bounds = [menuView bounds];
  for (i = 0; i < 2; i++)
    {
      rows[i] = [menuView rectOfItemAtIndex: i];
      if ([menuView isFlipped] == NO)
        {
          rows[i].origin.y = NSHeight (bounds) - NSMaxY (rows[i]);
        }
    }
  /* Clear of the title and of the rounded ends. */
  QuirkProbePixelAt (rep, (NSInteger)NSMaxX (rows[0]) - 16, (NSInteger)NSMidY (rows[0]), hovered);
  QuirkProbePixelAt (rep, (NSInteger)NSMaxX (rows[1]) - 16, (NSInteger)NSMidY (rows[1]), plain);
  QuirkProbeInkBackground = hovered[0] + hovered[1] + hovered[2];
  ink = QuirkProbeMeasureIn (rep, QuirkProbeIsInk,
                             NSMakeRect (NSMinX (rows[0]) + 8, NSMinY (rows[0]) + 4,
                                         NSWidth (rows[0]) / 2, NSHeight (rows[0]) - 8));
  QuirkProbeInkBackground = 750;
  [self saveWindow: window named: @"menu-hover"];
  [menuView setHighlightedItemIndex: -1];
  [window orderOut: nil];

  want[0] = lround (plain[0] * 0.9 + [foreground redComponent] * 255 * 0.1);
  want[1] = lround (plain[1] * 0.9 + [foreground greenComponent] * 255 * 0.1);
  want[2] = lround (plain[2] * 0.9 + [foreground blueComponent] * 255 * 0.1);
  fillOK = YES;
  for (i = 0; i < 3; i++)
    {
      if (labs ((long)hovered[i] - want[i]) > 3)
        {
          fillOK = NO;
        }
    }
  /* The title's ink lies on the text colour's side of the fill: dark in the
     light palette, light in the dark one (white text failed the light). */
  textSum = lround (([text redComponent] + [text greenComponent] + [text blueComponent]) * 255);
  fillSum = (long)(hovered[0] + hovered[1] + hovered[2]);
  textOK = ink.count > 0
    && ((textSum < fillSum) ? ((long)ink.darkest < fillSum - 300) : ((long)ink.lightest > fillSum + 300));
  detail = [NSString stringWithFormat: @"hovered row %@ (want #%02lx%02lx%02lx, 10%% foreground over %@); "
    @"title ink r+g+b %lu to %lu on %ld, text colour %ld",
    QuirkProbeHex (hovered), want[0], want[1], want[2], QuirkProbeHex (plain),
    (unsigned long)ink.darkest, (unsigned long)ink.lightest, fillSum, textSum];
  if (fillOK && textOK)
    {
      [self pass: @"menu-hover-text-colour" detail: detail];
    }
  else
    {
      [self fail: @"menu-hover-text-colour" detail: detail];
    }
}

/* An empty search field (and text field) shows its placeholder while it
   has focus, as GTK's entries do, and hides it once there is text (#67).
   GNUstep's cell drew it only when not editing. */
- (void) checkSearchPlaceholderFocused
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 120) title: @"Probe Placeholder"];
  NSSearchField *search = AUTORELEASE ([[NSSearchField alloc] initWithFrame: NSMakeRect (20, 66, 220, 34)]);
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (20, 20, 220, 34)]);
  NSArray *fields = [NSArray arrayWithObjects: search, field, nil];
  NSMutableString *detail = [NSMutableString string];
  NSWindow *previousKey = [NSApp keyWindow];
  BOOL ok = YES;
  NSUInteger i;

  [[search cell] setPlaceholderString: @"Search Fonts"];
  [[field cell] setPlaceholderString: @"Family Name"];
  [[window contentView] addSubview: search];
  [[window contentView] addSubview: field];
  [window makeKeyAndOrderFront: nil];
  for (i = 0; i < [fields count]; i++)
    {
      NSTextField *control = [fields objectAtIndex: i];
      NSBitmapImageRep *rep;
      NSUInteger fill[3];
      QuirkProbeInk empty, typed;
      NSRect area;

      [window makeFirstResponder: control];
      [window display];
      rep = QuirkProbeRender (control);
      /* Inside the entry, after the search icon, clear of its rounded ends. */
      area = NSMakeRect (i == 0 ? 30 : 8, 8, [rep pixelsWide] - (i == 0 ? 60 : 16), [rep pixelsHigh] - 16);
      QuirkProbePixelAt (rep, [rep pixelsWide] - 40, 6, fill);
      QuirkProbeInkBackground = fill[0] + fill[1] + fill[2];
      empty = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, area);
      [(NSTextView *)[control currentEditor] insertText: @"l"];
      [window display];
      typed = QuirkProbeMeasureIn (QuirkProbeRender (control), QuirkProbeIsInk, area);
      QuirkProbeInkBackground = 750;
      [detail appendFormat: @"%s%@ focused and empty: ink %ldpt wide, editing %@; with \"l\" typed: %ldpt",
        i ? "; " : "", i == 0 ? @"search field" : @"text field", (long)empty.width,
        [control currentEditor] != nil ? @"yes" : @"no", (long)typed.width];
      if (empty.width < 40 || typed.width > 12 || typed.count == 0)
        {
          ok = NO;
        }
    }
  [(NSTextView *)[field currentEditor] setString: @""];
  [search setStringValue: @""];
  [field setNeedsDisplay: YES];
  [window display];
  [self saveWindow: window named: @"search-placeholder"];
  [window makeFirstResponder: nil];
  [window orderOut: nil];
  [previousKey makeKeyWindow];

  if (ok)
    {
      [self pass: @"search-placeholder-focused" detail: detail];
    }
  else
    {
      [self fail: @"search-placeholder-focused" detail: detail];
    }
}

/* A delegate reading -stringValue in controlTextDidChange: gets the text
   with the key just typed, as filters-while-typing need; under the theme
   it got the text from before it (#73). */
- (void) checkStringValueWhileTyping
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 166) title: @"Probe Typing"];
  NSSearchField *search = AUTORELEASE ([[NSSearchField alloc] initWithFrame: NSMakeRect (20, 112, 220, 34)]);
  NSTextField *field = AUTORELEASE ([[NSTextField alloc] initWithFrame: NSMakeRect (20, 66, 220, 34)]);
  NSComboBox *combo = AUTORELEASE ([[NSComboBox alloc] initWithFrame: NSMakeRect (20, 20, 220, 34)]);
  NSArray *fields = [NSArray arrayWithObjects: search, field, combo, nil];
  NSArray *names = [NSArray arrayWithObjects: @"search field", @"text field", @"combo box", nil];
  QuirkProbeTextChangeDelegate *delegate = AUTORELEASE ([[QuirkProbeTextChangeDelegate alloc] init]);
  NSMutableString *detail = [NSMutableString string];
  NSWindow *previousKey = [NSApp keyWindow];
  BOOL ok = YES;
  NSUInteger i;

  delegate->seen = [NSMutableArray array];
  [[window contentView] addSubview: search];
  [[window contentView] addSubview: field];
  [combo addItemWithObjectValue: @"Cantarell"];
  [[window contentView] addSubview: combo];
  [window makeKeyAndOrderFront: nil];
  [window display];
  for (i = 0; i < [fields count]; i++)
    {
      NSTextField *control = [fields objectAtIndex: i];
      NSTextView *editor;

      [delegate->seen removeAllObjects];
      [control setDelegate: (id)delegate];
      [window makeFirstResponder: control];
      [window display];
      editor = (NSTextView *)[control currentEditor];
      [editor insertText: @"d"];
      [window display];
      [editor insertText: @"e"];
      [editor insertText: @"j"];
      [detail appendFormat: @"%s%@ typed \"dej\": delegate saw (%@), %@",
        i ? "; " : "", [names objectAtIndex: i],
        [delegate->seen componentsJoinedByString: @", "], delegate->cellState];
      if ([delegate->seen count] != 3
        || [[delegate->seen lastObject] isEqualToString: @"dej"] == NO
        || [[delegate->seen objectAtIndex: 0] isEqualToString: @"d"] == NO)
        {
          ok = NO;
        }
      [control setDelegate: nil];
    }
  [window makeFirstResponder: nil];
  [window orderOut: nil];
  [previousKey makeKeyWindow];
  DESTROY (delegate->cellState);

  if (ok)
    {
      [self pass: @"string-value-while-typing" detail: detail];
    }
  else
    {
      [self fail: @"string-value-while-typing" detail: detail];
    }
}

/* An auto-hiding scroll view whose content is near its size: libs-gui's
   -tile has the clip view reflect, and auto-hiding tiles again, which
   re-entered the theme's -tile override until the stack ran out where
   libs-gui and the overlay layout disagreed on whether a scroller was
   needed (Markdown Viewer's split view at launch). Sizes sweep both
   boundaries; the check passes by finishing, with the scrollers settled. */
- (void) checkAutohideTileSettles
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 360, 300) title: @"Probe Autohide"];
  NSScrollView *scrollView = AUTORELEASE ([[QuirkProbeTileCountingScrollView alloc] initWithFrame: NSMakeRect (10, 10, 240, 200)]);
  NSTextView *text = AUTORELEASE ([[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 240, 200)]);
  NSMutableString *words = [NSMutableString string];
  NSUInteger frames = 0;
  CGFloat w, h;
  NSString *detail;
  int i;

  for (i = 0; i < 60; i++)
    {
      [words appendString: @"lorem ipsum dolor "];
    }
  [text setString: words];
  [text setHorizontallyResizable: NO];
  [text setVerticallyResizable: YES];
  [text setAutoresizingMask: NSViewWidthSizable];
  [[text textContainer] setWidthTracksTextView: YES];
  [text setMaxSize: NSMakeSize (FLT_MAX, FLT_MAX)];
  QuirkProbeTileMaxDepth = 0;
  [scrollView setHasVerticalScroller: YES];
  [scrollView setAutohidesScrollers: YES];
  [scrollView setDocumentView: text];
  [[window contentView] addSubview: scrollView];
  [window orderFront: nil];
  /* Widths where the text wraps to one more line once a scroller's width
     is taken off, and heights round the text's. */
  for (w = 140; w <= 320; w += 1)
    {
      [scrollView setFrame: NSMakeRect (10, 10, w, 200)];
      for (h = NSHeight ([text frame]) - 20; h <= NSHeight ([text frame]) + 20; h += 1)
        {
          [scrollView setFrame: NSMakeRect (10, 10, w, h)];
          frames++;
        }
    }
  /* Both scrollers, content within a scroller's footprint of the clip
     view each way: libs-gui master's auto-hiding adds a shown scroller's
     footprint back onto the clip view, which overlay scrollers leave
     full size, so the content fits once a scroller shows and doesn't once
     it hides. */
  {
    NSScrollView *both = AUTORELEASE ([[QuirkProbeTileCountingScrollView alloc] initWithFrame: NSMakeRect (10, 10, 200, 150)]);
    NSView *document = AUTORELEASE ([[NSView alloc] initWithFrame: NSMakeRect (0, 0, 200, 150)]);
    CGFloat dw, dh;

    [both setHasVerticalScroller: YES];
    [both setHasHorizontalScroller: YES];
    [both setAutohidesScrollers: YES];
    [both setDocumentView: document];
    [[window contentView] addSubview: both];
    for (dw = -2; dw <= 20; dw += 1)
      {
        for (dh = -2; dh <= 20; dh += 1)
          {
            [document setFrameSize: NSMakeSize (200 + dw, 150 + dh)];
            [both setFrame: NSMakeRect (10, 10, 199, 150)];
            [both setFrame: NSMakeRect (10, 10, 200, 150)];
            frames += 2;
          }
      }
  }
  [window display];
  detail = [NSString stringWithFormat: @"%lu frames of auto-hiding scroll views round their content's size; "
                     @"-tile nested %lu deep (want 2 at most: the theme's layout runs libs-gui's again itself)",
                     (unsigned long)frames, (unsigned long)QuirkProbeTileMaxDepth];
  [window orderOut: nil];
  if (QuirkProbeTileMaxDepth <= 2)
    {
      [self pass: @"autohide-tile-settles" detail: detail];
    }
  else
    {
      [self fail: @"autohide-tile-settles" detail: detail];
    }
}

- (void) checkPaletteLookup
{
  typedef NSColor *(*LookupFunction)(GSTheme *, NSString *, NSColor *);
  LookupFunction lookup = (LookupFunction)dlsym (RTLD_DEFAULT, "GnomeThemeColor");
  GSTheme *theme = [GSTheme theme];
  NSColor *fallback = [NSColor colorWithCalibratedRed: 1.0 green: 0.0 blue: 0.0 alpha: 1.0];
  NSString *keys[2] = { @"sliderKnobColor", @"highlightedTableRowBackgroundColor" };
  NSMutableString *detail = [NSMutableString string];
  BOOL ok = YES;
  int i;

  if (lookup == NULL)
    {
      [self skip: @"palette-lookup" detail: @"GnomeThemeColor() not found in the loaded theme"];
      return;
    }
  for (i = 0; i < 2; i++)
    {
      NSColor *palette = [[theme colors] colorWithKey: keys[i]];
      NSColor *found = lookup (theme, keys[i], fallback);

      if (palette == nil || found != palette)
        {
          ok = NO;
        }
      [detail appendFormat: @"%s%@ %@", i ? "; " : "", keys[i],
        found == fallback ? @"came back as the fallback" : (found == palette ? @"from the palette" : @"from elsewhere")];
    }
  if (ok)
    {
      [self pass: @"palette-lookup" detail: detail];
    }
  else
    {
      [self fail: @"palette-lookup" detail: detail];
    }
}

/* A selected row in a focused table is libadwaita's (measured from its
   GtkColumnView, Reference/AdwaitaDemo's data page): the accent at 25%
   over the view colour, #cce0f8 in light and #233751 in dark, the same in
   high contrast; the row's text stays the text colour. It used to be
   alternateSelectedControlColor (#99c1f1, #4f7cb8) with white text, as
   the palette's selection keys were never read. */
- (void) checkTableSelection
{
  NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL dark = [windowColor redComponent] < 0.5;
  NSUInteger want[3] = { 0xcc, 0xe0, 0xf8 };
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 240, 160) title: @"Probe Table Selection"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (20, 20, 200, 120)]);
  NSTableView *table = AUTORELEASE ([[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 200, 120)]);
  NSTableColumn *column = AUTORELEASE ([[NSTableColumn alloc] initWithIdentifier: @"c"]);
  NSBitmapImageRep *rep;
  NSRect rowRect;
  NSUInteger selected[3], plain[3];
  NSWindow *previousKey;
  NSString *detail;
  BOOL ok;

  if (dark)
    {
      want[0] = 0x23; want[1] = 0x37; want[2] = 0x51;
    }
  [column setWidth: 180];
  [table addTableColumn: column];
  [table setHeaderView: nil];
  [table setDataSource: (id)self];
  [scrollView setDocumentView: table];
  [scrollView setHasVerticalScroller: NO];
  [scrollView setBorderType: NSNoBorder];
  [[window contentView] addSubview: scrollView];
  [table reloadData];
  [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 1] byExtendingSelection: NO];
  /* Key for the measurement only: later checks draw in windows that expect
     to stay key. */
  previousKey = [NSApp keyWindow];
  [window makeKeyAndOrderFront: nil];
  [window makeFirstResponder: table];
  [window display];
  rep = QuirkProbeRender (table);
  /* Near the right end of the selected row, clear of its text, and the
     same in the row after it. */
  rowRect = [table rectOfRow: 1];
  QuirkProbePixelAt (rep, (NSInteger)NSMaxX (rowRect) - 8, (NSInteger)NSMidY (rowRect), selected);
  rowRect = [table rectOfRow: 2];
  QuirkProbePixelAt (rep, (NSInteger)NSMaxX (rowRect) - 8, (NSInteger)NSMidY (rowRect), plain);
  [window orderOut: nil];
  [previousKey makeKeyWindow];

  ok = labs ((long)selected[0] - (long)want[0]) <= 2 && labs ((long)selected[1] - (long)want[1]) <= 2
    && labs ((long)selected[2] - (long)want[2]) <= 2;
  detail = [NSString stringWithFormat: @"%@: selected row %@ (want #%02lx%02lx%02lx), next row %@",
    dark ? @"dark" : @"light", QuirkProbeHex (selected),
    (unsigned long)want[0], (unsigned long)want[1], (unsigned long)want[2], QuirkProbeHex (plain)];
  if (ok)
    {
      [self pass: @"table-selection" detail: detail];
    }
  else
    {
      [self fail: @"table-selection" detail: detail];
    }
}

/* -setGSThemeStyle: @"accent" (ScreenshotTool's primary buttons): drawn
   as libadwaita's .suggested-action, #3584e4 with a white title, without
   becoming the window's default button. A toolbar-style (textured) one is
   filled too, as .suggested-action in a header bar; pressed, the blue
   darkened; disabled, the blue at half opacity over the window. */
- (void) checkAccentButtons
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 560, 80) title: @"Probe Accent Buttons"];
  NSButton *buttons[4];
  NSUInteger fill[4][3], titleRGB[3] = { 0, 0, 0 }, windowRGB[3];
  NSView *frameView;
  NSBitmapImageRep *rep;
  NSRect inWindow;
  NSString *detail;
  NSInteger i, x;
  BOOL ok;

  for (i = 0; i < 4; i++)
    {
      buttons[i] = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20 + i * 130, 23, 120, 34)]);
      [buttons[i] setTitle: @"Accent"];
      if ([buttons[i] respondsToSelector: @selector(setGSThemeStyle:)] == NO)
        {
          [self fail: @"accent-button" detail: @"NSButton has no -setGSThemeStyle:"];
          [window orderOut: nil];
          return;
        }
      [buttons[i] performSelector: @selector(setGSThemeStyle:) withObject: @"accent"];
      [[window contentView] addSubview: buttons[i]];
    }
  [buttons[1] setBezelStyle: NSTexturedRoundedBezelStyle];
  [[buttons[2] cell] setHighlighted: YES];
  [buttons[3] setEnabled: NO];
  [window orderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  rep = QuirkProbeRender (frameView);
#define QUIRK_PROBE_SAMPLE(view, dx, dy, rgb) \
  inWindow = [view convertRect: [view bounds] toView: nil]; \
  QuirkProbePixelAt (rep, (NSInteger)(NSMinX (inWindow) + (dx)), \
                     (NSInteger)(NSHeight ([frameView bounds]) - NSMaxY (inWindow) + (dy)), rgb)
  QUIRK_PROBE_SAMPLE (buttons[0], -6, 17, windowRGB);
  for (i = 0; i < 4; i++)
    {
      QUIRK_PROBE_SAMPLE (buttons[i], 8, 17, fill[i]);
    }
  for (x = 20; x < 100; x++)
    {
      NSUInteger rgb[3];

      QUIRK_PROBE_SAMPLE (buttons[0], x, 17, rgb);
      if (rgb[0] + rgb[1] + rgb[2] > titleRGB[0] + titleRGB[1] + titleRGB[2])
        {
          titleRGB[0] = rgb[0]; titleRGB[1] = rgb[1]; titleRGB[2] = rgb[2];
        }
    }
#undef QUIRK_PROBE_SAMPLE
  [window orderOut: nil];

  {
    unsigned int pressed = ((0x35 * 82 / 100) << 16) | ((0x84 * 82 / 100) << 8) | (0xe4 * 82 / 100);
    unsigned int disabled = (((0x35 + windowRGB[0]) / 2) << 16) | (((0x84 + windowRGB[1]) / 2) << 8)
      | ((0xe4 + windowRGB[2]) / 2);

    ok = QuirkProbeNear (fill[0], 0x3584e4, 1) && QuirkProbeNear (fill[1], 0x3584e4, 1)
      && QuirkProbeNear (fill[2], pressed, 2) && QuirkProbeNear (fill[3], disabled, 2)
      && titleRGB[0] >= 240 && titleRGB[1] >= 240 && titleRGB[2] >= 240
      && [window defaultButtonCell] == nil;
    detail = [NSString stringWithFormat: @"fill %@, toolbar style %@ (want #3584e4), pressed %@ (want #%06x), "
      @"disabled %@ (want #%06x), title's brightest pixel %@ (want white), default button %@ (want none)",
      QuirkProbeHex (fill[0]), QuirkProbeHex (fill[1]), QuirkProbeHex (fill[2]), pressed,
      QuirkProbeHex (fill[3]), disabled, QuirkProbeHex (titleRGB),
      [window defaultButtonCell] == nil ? @"none" : @"set"];
  }
  if (ok)
    {
      [self pass: @"accent-button" detail: detail];
    }
  else
    {
      [self fail: @"accent-button" detail: detail];
    }
}

/* With an accent button in the window, the default (Return) button is
   drawn as a regular button, so the accent one is the only suggested
   action (ScreenshotTool's empty state: Open... and Take Screenshot);
   hide the accent button and the default one is blue again. Return still
   belongs to the default button. */
- (void) checkAccentYields
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 300, 80) title: @"Probe Accent And Default"];
  NSButton *open = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20, 23, 120, 34)]);
  NSButton *accent = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (160, 23, 120, 34)]);
  NSUInteger openFill[2][3], accentFill[3];
  NSView *frameView;
  NSBitmapImageRep *rep;
  NSRect inWindow;
  NSString *detail;
  NSInteger pass;
  BOOL ok;

  if ([accent respondsToSelector: @selector(setGSThemeStyle:)] == NO)
    {
      [self fail: @"accent-default-yields" detail: @"NSButton has no -setGSThemeStyle:"];
      return;
    }
  [open setTitle: @"Open"];
  [open setKeyEquivalent: @"\r"];
  [accent setTitle: @"Take"];
  [accent performSelector: @selector(setGSThemeStyle:) withObject: @"accent"];
  [[window contentView] addSubview: open];
  [[window contentView] addSubview: accent];
  [window setDefaultButtonCell: [open cell]];
  [window orderFront: nil];
  for (pass = 0; pass < 2; pass++)
    {
      [accent setHidden: pass == 1];
      [window display];
      frameView = [[window contentView] superview];
      rep = QuirkProbeRender (frameView);
#define QUIRK_PROBE_SAMPLE(view, dx, dy, rgb) \
  inWindow = [view convertRect: [view bounds] toView: nil]; \
  QuirkProbePixelAt (rep, (NSInteger)(NSMinX (inWindow) + (dx)), \
                     (NSInteger)(NSHeight ([frameView bounds]) - NSMaxY (inWindow) + (dy)), rgb)
      QUIRK_PROBE_SAMPLE (open, 8, 17, openFill[pass]);
      if (pass == 0)
        {
          QUIRK_PROBE_SAMPLE (accent, 8, 17, accentFill);
        }
#undef QUIRK_PROBE_SAMPLE
    }
  [window orderOut: nil];

  ok = QuirkProbeNear (accentFill, 0x3584e4, 1) && QuirkProbeNear (openFill[0], 0x3584e4, 40) == NO
    && QuirkProbeNear (openFill[1], 0x3584e4, 1) && [window defaultButtonCell] == [open cell];
  detail = [NSString stringWithFormat: @"accent %@ (want #3584e4), default button beside it %@ (want a regular button), "
    @"default button with the accent one hidden %@ (want #3584e4), Return %@",
    QuirkProbeHex (accentFill), QuirkProbeHex (openFill[0]), QuirkProbeHex (openFill[1]),
    [window defaultButtonCell] == [open cell] ? @"still the default button's" : @"moved"];
  if (ok)
    {
      [self pass: @"accent-default-yields" detail: detail];
    }
  else
    {
      [self fail: @"accent-default-yields" detail: detail];
    }
}

/* libadwaita 1.7's control colours, measured from its reference app on the
   same display (Reference/AdwaitaDemo), in the palette the run uses (light
   or dark by the window colour, high contrast from -ProbeHighContrast):
   the window and a button (the foreground at 10% over it, #60), the
   default button's accent (#55), an unchecked radio's and check box's
   ring (#57) and a button's outline (#61). */
- (void) checkControlColors
{
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL dark = [windowColor redComponent] < 0.5;
  NSString *style = dark ? (highContrast ? @"high contrast dark" : @"dark")
                         : (highContrast ? @"high contrast" : @"light");
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 320, 120) title: @"Probe Control Colours"];
  NSButton *secondary = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20, 70, 120, 34)]);
  NSButton *defaultButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (170, 70, 120, 34)]);
  NSButton *radio = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (20, 20, 120, 24)]);
  NSButton *checkBox = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (170, 20, 120, 24)]);
  NSView *frameView;
  NSBitmapImageRep *rep;
  NSUInteger windowRGB[3], buttonRGB[3], defaultRGB[3], titleRGB[3] = { 0, 0, 0 };
  NSUInteger radioRGB[3] = { 0, 0, 0 }, checkRGB[3] = { 0, 0, 0 }, edgeRGB[3];
  long radioStep = -1, checkStep = -1;
  unsigned int ring;
  NSRect inWindow;
  NSString *detail;
  NSInteger x;

  [secondary setTitle: @""];
  [defaultButton setTitle: @"Default"];
  [defaultButton setKeyEquivalent: @"\r"];
  [radio setButtonType: NSRadioButton];
  [radio setTitle: @""];
  [checkBox setButtonType: NSSwitchButton];
  [checkBox setTitle: @""];
  [[window contentView] addSubview: secondary];
  [[window contentView] addSubview: defaultButton];
  [[window contentView] addSubview: radio];
  [[window contentView] addSubview: checkBox];
  [window orderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  rep = QuirkProbeRender (frameView);
#define QUIRK_PROBE_SAMPLE(view, dx, dy, rgb) \
  inWindow = [view convertRect: [view bounds] toView: nil]; \
  QuirkProbePixelAt (rep, (NSInteger)(NSMinX (inWindow) + (dx)), \
                     (NSInteger)(NSHeight ([frameView bounds]) - NSMaxY (inWindow) + (dy)), rgb)
  QUIRK_PROBE_SAMPLE (secondary, -10, 17, windowRGB);
  QUIRK_PROBE_SAMPLE (secondary, 60, 17, buttonRGB);
  QUIRK_PROBE_SAMPLE (secondary, 60, 0, edgeRGB);
  QUIRK_PROBE_SAMPLE (defaultButton, 8, 17, defaultRGB);
  /* The title's brightest pixel along the button's middle. */
  for (x = 20; x < 100; x++)
    {
      NSUInteger rgb[3];

      QUIRK_PROBE_SAMPLE (defaultButton, x, 17, rgb);
      if (rgb[0] + rgb[1] + rgb[2] > titleRGB[0] + titleRGB[1] + titleRGB[2])
        {
          titleRGB[0] = rgb[0]; titleRGB[1] = rgb[1]; titleRGB[2] = rgb[2];
        }
    }
  /* An unchecked indicator's ring: the pixel along its middle row that is
     furthest from the window. */
  for (x = 0; x < 30; x++)
    {
      NSUInteger rgb[3];
      long step;

      QUIRK_PROBE_SAMPLE (radio, x, 12, rgb);
      step = labs ((long)rgb[0] - (long)windowRGB[0]) + labs ((long)rgb[1] - (long)windowRGB[1])
        + labs ((long)rgb[2] - (long)windowRGB[2]);
      if (step > radioStep)
        {
          radioStep = step; radioRGB[0] = rgb[0]; radioRGB[1] = rgb[1]; radioRGB[2] = rgb[2];
        }
      QUIRK_PROBE_SAMPLE (checkBox, x, 12, rgb);
      step = labs ((long)rgb[0] - (long)windowRGB[0]) + labs ((long)rgb[1] - (long)windowRGB[1])
        + labs ((long)rgb[2] - (long)windowRGB[2]);
      if (step > checkStep)
        {
          checkStep = step; checkRGB[0] = rgb[0]; checkRGB[1] = rgb[1]; checkRGB[2] = rgb[2];
        }
    }
#undef QUIRK_PROBE_SAMPLE
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"%@: window %@ (want %s), button %@ (want %s)", style,
    QuirkProbeHex (windowRGB), dark ? "#222226" : "#fafafb",
    QuirkProbeHex (buttonRGB), dark ? "#38383b" : "#e6e6e7"];
  if (QuirkProbeNear (windowRGB, dark ? 0x222226 : 0xfafafb, 1)
    && QuirkProbeNear (buttonRGB, dark ? 0x38383b : 0xe6e6e7, 1))
    {
      [self pass: @"control-colors-window-button" detail: detail];
    }
  else
    {
      [self fail: @"control-colors-window-button" detail: detail];
    }

  /* The default button is libadwaita's suggested action in every palette:
     accent_bg_color #3584e4 with a white title (plugins-themes-Adwaita#55). */
  detail = [NSString stringWithFormat: @"%@: fill %@ (want #3584e4), title's brightest pixel %@ (want white)",
    style, QuirkProbeHex (defaultRGB), QuirkProbeHex (titleRGB)];
  if (QuirkProbeNear (defaultRGB, 0x3584e4, 1)
    && titleRGB[0] >= 240 && titleRGB[1] >= 240 && titleRGB[2] >= 240)
    {
      [self pass: @"control-colors-default-button" detail: detail];
    }
  else
    {
      [self fail: @"control-colors-default-button" detail: detail];
    }

  /* An unchecked radio and check box show libadwaita's ring: the
     foreground at 15% over the window, 50% in high contrast. In the dark
     palette they used to be the window's own colour (#57). */
  ring = dark ? (highContrast ? 0x919193 : 0x434346) : (highContrast ? 0x969699 : 0xdddddd);
  detail = [NSString stringWithFormat: @"%@: radio ring %@, check box ring %@ (want #%06x)",
    style, QuirkProbeHex (radioRGB), QuirkProbeHex (checkRGB), ring];
  if (QuirkProbeNear (radioRGB, ring, 6) && QuirkProbeNear (checkRGB, ring, 6))
    {
      [self pass: @"control-colors-unchecked-indicators" detail: detail];
    }
  else
    {
      [self fail: @"control-colors-unchecked-indicators" detail: detail];
    }

  /* A button's top edge: no outline in libadwaita's normal styles (the edge
     pixel is between the window and the fill; the light palette's used to
     be a #dfdfdf line), and in high contrast its 1px outline, the
     foreground at 50% (#61). */
  {
    unsigned int outline = dark ? 0x919193 : 0x969699;
    BOOL between = YES;
    int i;

    for (i = 0; i < 3; i++)
      {
        NSUInteger low = MIN (windowRGB[i], buttonRGB[i]);
        NSUInteger high = MAX (windowRGB[i], buttonRGB[i]);

        if (edgeRGB[i] + 1 < low || edgeRGB[i] > high + 1)
          {
            between = NO;
          }
      }
    detail = [NSString stringWithFormat: @"%@: button edge %@ (want %@)", style, QuirkProbeHex (edgeRGB),
      highContrast ? [NSString stringWithFormat: @"#%06x, the outline", outline]
                   : @"between the window and the fill"];
    if (highContrast ? QuirkProbeNear (edgeRGB, outline, 8) : between)
      {
        [self pass: @"control-colors-outline" detail: detail];
      }
    else
      {
        [self fail: @"control-colors-outline" detail: detail];
      }
  }
}

/* NSSwitch as libadwaita's switch: a 46x26 pill, the accent when on with
   the knob at the end, a neutral track when off with the knob at the start
   (plugins-themes-Adwaita#35). */
/* The slider's knob as libadwaita's: 20px with its outline and shadow,
   and lighter than the trough in any palette (the dark palette's knob
   was the window's colour and vanished; plugins-themes-Adwaita#56). */
- (void) checkSliderKnob
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 80) title: @"Probe Slider"];
  NSSlider *slider = AUTORELEASE ([[NSSlider alloc] initWithFrame: NSMakeRect (20, 20, 200, 30)]);
  NSView *frameView;
  NSBitmapImageRep *rep;
  NSRect knob;
  NSUInteger centre[3], trough[3], background[3], pixel[3];
  NSInteger x, y, top = -1, bottom = -1, backgroundSum, frameHeight;
  NSString *detail;

  [slider setMinValue: 0.0];
  [slider setMaxValue: 100.0];
  [slider setDoubleValue: 30.0];
  [[window contentView] addSubview: slider];
  [window orderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  rep = QuirkProbeRender (frameView);
  frameHeight = (NSInteger)NSHeight ([frameView bounds]);
  knob = [slider convertRect: [[slider cell] knobRectFlipped: [slider isFlipped]] toView: nil];
  x = (NSInteger)floor (NSMidX (knob));
  y = frameHeight - (NSInteger)floor (NSMidY (knob)) - 1;
  QuirkProbePixelAt (rep, x, y, centre);
  /* The trough to the right of the knob: the slider is at 30%. */
  QuirkProbePixelAt (rep, x + 60, y, trough);
  QuirkProbePixelAt (rep, x, y - 20, background);
  backgroundSum = (NSInteger)(background[0] + background[1] + background[2]);
  for (y = frameHeight - (NSInteger)floor (NSMidY (knob)) - 16; y <= frameHeight - (NSInteger)floor (NSMidY (knob)) + 16; y++)
    {
      QuirkProbePixelAt (rep, x, y, pixel);
      if (labs ((NSInteger)(pixel[0] + pixel[1] + pixel[2]) - backgroundSum) > 12)
        {
          if (top < 0)
            {
              top = y;
            }
          bottom = y;
        }
    }
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"knob %ldpx high with its outline and shadow, centre %lu/%lu/%lu, trough %lu/%lu/%lu, window %lu/%lu/%lu",
    (long)(top >= 0 ? bottom - top + 1 : 0),
    (unsigned long)centre[0], (unsigned long)centre[1], (unsigned long)centre[2],
    (unsigned long)trough[0], (unsigned long)trough[1], (unsigned long)trough[2],
    (unsigned long)background[0], (unsigned long)background[1], (unsigned long)background[2]];
  if (top >= 0 && bottom - top + 1 >= 20 && bottom - top + 1 <= 24
      && centre[0] + centre[1] + centre[2] >= trough[0] + trough[1] + trough[2] + 60)
    {
      [self pass: @"slider-knob" detail: detail];
    }
  else
    {
      [self fail: @"slider-knob" detail: detail];
    }
}

/* A text view's scroll view draws libadwaita's frame: one 1px line at its
   edge and rounded corners, where GNUstep's bezel drew two dark lines and
   square corners (plugins-themes-Adwaita#58). */
- (void) checkScrollViewFrame
{
  NSWindow *window = [self windowWithFrame: NSMakeRect (60, 60, 260, 160) title: @"Probe Frame"];
  NSScrollView *scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (20, 20, 220, 120)]);
  NSTextView *textView = AUTORELEASE ([[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, 200, 300)]);
  NSView *frameView;
  NSBitmapImageRep *rep;
  NSRect inWindow;
  NSUInteger corner[3], outside[3], inside[3], pixel[3];
  NSInteger left, top, x, y, lines = 0, insideSum;
  NSString *detail;

  [scrollView setBorderType: NSBezelBorder];
  [scrollView setHasVerticalScroller: YES];
  [scrollView setDocumentView: textView];
  [[window contentView] addSubview: scrollView];
  [window orderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  rep = QuirkProbeRender (frameView);
  inWindow = [scrollView convertRect: [scrollView bounds] toView: nil];
  left = (NSInteger)NSMinX (inWindow);
  top = (NSInteger)(NSHeight ([frameView bounds]) - NSMaxY (inWindow));
  QuirkProbePixelAt (rep, left, top, corner);
  QuirkProbePixelAt (rep, left - 3, top - 3, outside);
  x = left + (NSInteger)NSWidth (inWindow) / 3;
  QuirkProbePixelAt (rep, x, top + 8, inside);
  insideSum = (NSInteger)(inside[0] + inside[1] + inside[2]);
  /* The rows at the top edge that aren't the content's colour. */
  for (y = top; y < top + 5; y++)
    {
      QuirkProbePixelAt (rep, x, y, pixel);
      if (labs ((NSInteger)(pixel[0] + pixel[1] + pixel[2]) - insideSum) > 15)
        {
          lines++;
        }
    }
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"%ld line(s) at the top edge; corner %lu/%lu/%lu, window %lu/%lu/%lu, content %lu/%lu/%lu",
    (long)lines, (unsigned long)corner[0], (unsigned long)corner[1], (unsigned long)corner[2],
    (unsigned long)outside[0], (unsigned long)outside[1], (unsigned long)outside[2],
    (unsigned long)inside[0], (unsigned long)inside[1], (unsigned long)inside[2]];
  if (lines == 1
      && labs ((NSInteger)(corner[0] + corner[1] + corner[2]) - (NSInteger)(outside[0] + outside[1] + outside[2])) <= 12)
    {
      [self pass: @"scroll-view-frame" detail: detail];
    }
  else
    {
      [self fail: @"scroll-view-frame" detail: detail];
    }
}

- (void) checkSwitch
{
  Class switchClass = NSClassFromString (@"NSSwitch");
  NSWindow *window;
  NSControl *offSwitch, *onSwitch, *disabledSwitch;
  NSBitmapImageRep *offRep, *onRep, *disabledRep;
  NSUInteger onTrack[3], onKnob[3], offTrack[3], offKnob[3], disabledTrack[3];
  NSString *detail;
  BOOL ok;

  if (switchClass == Nil)
    {
      [self skip: @"switch-adwaita" detail: @"no NSSwitch in this libs-gui"];
      return;
    }
  window = [self windowWithFrame: NSMakeRect (60, 60, 200, 80) title: @"Probe Switch"];
  offSwitch = AUTORELEASE ([[switchClass alloc] initWithFrame: NSMakeRect (10, 20, 46, 26)]);
  onSwitch = AUTORELEASE ([[switchClass alloc] initWithFrame: NSMakeRect (80, 20, 46, 26)]);
  [(id)onSwitch setState: NSOnState];
  /* libs-gui 0.32's NSSwitch starts disabled (its _enabled isn't set). */
  [offSwitch setEnabled: YES];
  [onSwitch setEnabled: YES];
  disabledSwitch = AUTORELEASE ([[switchClass alloc] initWithFrame: NSMakeRect (140, 20, 46, 26)]);
  [(id)disabledSwitch setState: NSOnState];
  [disabledSwitch setEnabled: NO];
  [[window contentView] addSubview: offSwitch];
  [[window contentView] addSubview: onSwitch];
  [[window contentView] addSubview: disabledSwitch];
  [window orderFront: nil];
  [window display];
  offRep = QuirkProbeRender (offSwitch);
  onRep = QuirkProbeRender (onSwitch);
  /* The track's free end (6px in from it), and the knob's centre. */
  QuirkProbePixelAt (onRep, 6, [onRep pixelsHigh] / 2, onTrack);
  QuirkProbePixelAt (onRep, [onRep pixelsWide] - 13, [onRep pixelsHigh] / 2, onKnob);
  QuirkProbePixelAt (offRep, [offRep pixelsWide] - 6, [offRep pixelsHigh] / 2, offTrack);
  QuirkProbePixelAt (offRep, 13, [offRep pixelsHigh] / 2, offKnob);
  /* Rendered with the window under it: it's translucent. */
  {
    NSView *frameView = [[window contentView] superview];
    NSRect inWindow = [disabledSwitch convertRect: [disabledSwitch bounds] toView: nil];

    disabledRep = QuirkProbeRender (frameView);
    QuirkProbePixelAt (disabledRep, (NSInteger)NSMinX (inWindow) + 6,
                       (NSInteger)(NSHeight ([frameView bounds]) - NSMidY (inWindow)), disabledTrack);
  }
  [window orderOut: nil];

  detail = [NSString stringWithFormat: @"on: track %lu/%lu/%lu, knob %lu/%lu/%lu; off: track %lu/%lu/%lu, knob %lu/%lu/%lu; "
    @"disabled on: track %lu/%lu/%lu",
    (unsigned long)onTrack[0], (unsigned long)onTrack[1], (unsigned long)onTrack[2],
    (unsigned long)onKnob[0], (unsigned long)onKnob[1], (unsigned long)onKnob[2],
    (unsigned long)offTrack[0], (unsigned long)offTrack[1], (unsigned long)offTrack[2],
    (unsigned long)offKnob[0], (unsigned long)offKnob[1], (unsigned long)offKnob[2],
    (unsigned long)disabledTrack[0], (unsigned long)disabledTrack[1], (unsigned long)disabledTrack[2]];
  /* On: blue track, a white knob, in the dark palette too. Off: a grey
     track 15-30% of the way from the window to the text (darker in the
     light palette, lighter in the dark), the knob lighter than the track.
     Disabled: closer to the window than the enabled one, still blue. */
  {
    NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    long window = (long)([windowColor redComponent] * 255.0);
    long offStep = labs ((long)offTrack[0] - window);

    ok = onTrack[2] > onTrack[0] + 60 && onKnob[0] >= 250 && onKnob[1] >= 250 && onKnob[2] >= 250
      && labs ((long)offTrack[0] - (long)offTrack[2]) < 12 && offStep >= 20 && offStep <= 80
      && offKnob[0] > offTrack[0] + 15
      && disabledTrack[2] > disabledTrack[0]
      && labs ((long)disabledTrack[0] - window) < labs ((long)onTrack[0] - window);
  }
  if (ok)
    {
      [self pass: @"switch-adwaita" detail: detail];
    }
  else
    {
      [self fail: @"switch-adwaita" detail: detail];
    }
}

/* Overlay scrollbars (GNOME's overlay-scrolling): the content runs under
   the scroller, which isn't drawn and lets presses through at rest; it
   shows (and takes presses) once the content scrolls, and fades out a
   second later (plugins-themes-Adwaita#17). */
- (void) checkOverlayScrollers
{
  NSWindow *window;
  NSScrollView *scrollView;
  NSView *document;
  NSScroller *scroller;
  NSRect strip, clip;
  NSString *detail;
  NSView *hitRest, *hitShown, *hitFaded;
  NSUInteger inkRest, inkShown;
  BOOL under;

  if ([[NSUserDefaults standardUserDefaults] objectForKey: @"GnomeThemeOverlayScrollbars"] != nil
    && [[NSUserDefaults standardUserDefaults] boolForKey: @"GnomeThemeOverlayScrollbars"] == NO)
    {
      [self skip: @"overlay-scrollers" detail: @"GnomeThemeOverlayScrollbars is NO"];
      return;
    }
  window = [self windowWithFrame: NSMakeRect (60, 200, 300, 200) title: @"Probe Overlay Scrollers"];
  scrollView = AUTORELEASE ([[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 280, 180)]);
  [scrollView setHasVerticalScroller: YES];
  [scrollView setBorderType: NSBezelBorder];
  document = AUTORELEASE ([[NSView alloc] initWithFrame: NSMakeRect (0, 0, 280, 1000)]);
  [document setAutoresizingMask: NSViewWidthSizable];
  [scrollView setDocumentView: document];
  [[window contentView] addSubview: scrollView];
  [window orderFront: nil];
  [window display];
  scroller = [scrollView verticalScroller];
  strip = [scroller frame];
  clip = [[scrollView contentView] frame];
  under = NSMaxX (clip) >= NSMaxX (strip) && NSMinX (strip) >= NSMinX (clip);
  hitRest = [scrollView hitTest: [[scrollView superview] convertPoint: NSMakePoint (NSMidX (strip), NSMidY (strip))
                                                             fromView: scrollView]];
  inkRest = QuirkProbeMeasure (QuirkProbeRender (scroller), QuirkProbeIsInk).count;

  {
    /* The slider shown: pixels in the scroller's strip that change from
       the scroll view at rest. (Counting ink over the whole scroll view
       counted its bezel, plugins-themes-Adwaita#58.) */
    NSBitmapImageRep *before = QuirkProbeRender (scrollView), *after;
    NSInteger x, y;
    NSUInteger a[3], b[3];

    [document scrollPoint: NSMakePoint (0, 300)];
    [window display];
    hitShown = [scrollView hitTest: [[scrollView superview] convertPoint: NSMakePoint (NSMidX (strip), NSMidY (strip))
                                                                fromView: scrollView]];
    after = QuirkProbeRender (scrollView);
    inkShown = 0;
    for (y = (NSInteger)NSMinY (strip); y < (NSInteger)NSMaxY (strip); y++)
      {
        for (x = (NSInteger)NSMinX (strip); x < (NSInteger)NSMaxX (strip); x++)
          {
            QuirkProbePixelAt (before, x, y, a);
            QuirkProbePixelAt (after, x, y, b);
            if (labs ((NSInteger)(a[0] + a[1] + a[2]) - (NSInteger)(b[0] + b[1] + b[2])) > 30)
              {
                inkShown++;
              }
          }
      }
  }

  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.6]];
  hitFaded = [scrollView hitTest: [[scrollView superview] convertPoint: NSMakePoint (NSMidX (strip), NSMidY (strip))
                                                               fromView: scrollView]];
  [window orderOut: nil];

  /* Freed while its scroller is shown: its fade timer must stop with it
     (it messaged the freed views; plugins-themes-Adwaita#38). Run with
     NSZombieEnabled to see such messages. */
  {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSWindow *gone = [[NSWindow alloc] initWithContentRect: NSMakeRect (60, 200, 300, 200)
                                                 styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
    NSScrollView *goneView = [[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 280, 180)];
    NSView *goneDocument = [[NSView alloc] initWithFrame: NSMakeRect (0, 0, 280, 1000)];

    [goneView setHasVerticalScroller: YES];
    [goneView setDocumentView: goneDocument];
    [[gone contentView] addSubview: goneView];
    [gone orderFront: nil];
    [gone display];
    [goneDocument scrollPoint: NSMakePoint (0, 300)];
    [gone orderOut: nil];
    [goneView removeFromSuperview];
    RELEASE (goneDocument);
    RELEASE (goneView);
    [gone setReleasedWhenClosed: NO];
    RELEASE (gone);
    [pool release];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.6]];
  }

  detail = [NSString stringWithFormat: @"clip %@ %@ the scroller %@; a press on it at rest: %@, shown: %@, faded: %@; "
    @"slider ink %lu at rest, %lu shown",
    NSStringFromRect (clip), under ? @"runs under" : @"stops short of", NSStringFromRect (strip),
    [hitRest class], [hitShown class], [hitFaded class], (unsigned long)inkRest, (unsigned long)inkShown];
  if (under && hitRest != scroller && hitShown == scroller && hitFaded != scroller && inkRest == 0 && inkShown > 0)
    {
      [self pass: @"overlay-scrollers" detail: detail];
    }
  else
    {
      [self fail: @"overlay-scrollers" detail: detail];
    }
}

/* A window manager asked to close a header-bar window (Alt+F4) kills the
   app unless the window lists WM_DELETE_WINDOW, which libs-back lists only
   for windows it decorates. The theme lists it for closable windows and
   only then lets the window manager close them; a window that can't be
   closed gets neither. Ordered out and in again, as libs-back sets
   WM_PROTOCOLS anew each time. */
- (void) checkWindowManagerClose
{
  Class theme = NSClassFromString (@"GnomeTheme");
  NSUInteger styles[2] = { NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask,
                           NSTitledWindowMask | NSResizableWindowMask };
  NSString *wanted[2] = { @"WM_DELETE_WINDOW yes, close yes", @"WM_DELETE_WINDOW no, close no" };
  NSString *states[2];
  NSWindow *window;
  BOOL ok = YES;
  int i;

  if (QuirkProbeDrawsDecorations () == NO)
    {
      [self skip: @"wm-close" detail: @"the window manager draws the decorations"];
      return;
    }
  if ([theme respondsToSelector: @selector(windowManagerCloseStateForWindow:)] == NO)
    {
      [self skip: @"wm-close" detail: @"no +[GnomeTheme windowManagerCloseStateForWindow:]"];
      return;
    }
  for (i = 0; i < 2; i++)
    {
      window = [[NSWindow alloc] initWithContentRect: NSMakeRect (40, 40, 300, 200)
                                           styleMask: styles[i]
                                             backing: NSBackingStoreBuffered
                                               defer: NO];
      [window orderFront: nil];
      [window orderOut: nil];
      [window orderFront: nil];
      states[i] = [theme windowManagerCloseStateForWindow: window];
      if (states[i] == nil)
        {
          states[i] = @"(no X window)";
        }
      ok = ok && [states[i] isEqualToString: wanted[i]];
      [window orderOut: nil];
      RELEASE (window);
    }
  if (ok)
    {
      [self pass: @"wm-close" detail: [NSString stringWithFormat: @"closable: %@; not closable: %@",
                                                states[0], states[1]]];
    }
  else
    {
      [self fail: @"wm-close" detail: [NSString stringWithFormat: @"closable: %@ (want %@); not closable: %@ (want %@)",
                                                states[0], wanted[0], states[1], wanted[1]]];
    }
}

/* The window types the theme gives windows, as GTK's
   (_NET_WM_WINDOW_TYPE, plugins-themes-Adwaita#15). The probe's display
   has no window manager to set them for, so this asks the theme what it
   would set; run-mutter-check.sh reads one off a window. */
- (void) checkWindowTypes
{
  Class theme = NSClassFromString (@"GnomeTheme");
  Class panelClass = NSClassFromString (@"GSTTPanel");
  NSPopUpButton *popUp;
  NSWindow *toolTip, *alert;
  NSMenu *barMenu = nil;
  NSEnumerator *enumerator;
  NSMenuItem *item;
  NSString *wantedBarMenu, *detail;
  NSString *types[6];
  NSString *wanted[6];
  BOOL ok = YES;
  int i;

  if ([theme respondsToSelector: @selector(windowTypeForWindow:)] == NO || panelClass == Nil)
    {
      [self skip: @"window-types" detail: @"no +[GnomeTheme windowTypeForWindow:] or GSTTPanel"];
      return;
    }
  toolTip = [[panelClass alloc] initWithContentRect: NSMakeRect (0, 0, 100, 25)
                                          styleMask: NSBorderlessWindowMask
                                            backing: NSBackingStoreRetained
                                              defer: YES];
  popUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect (0, 0, 120, 30) pullsDown: NO];
  [popUp addItemWithTitle: @"One"];
  alert = NSGetAlertPanel (@"Title", @"Message", @"OK", nil, nil);
  enumerator = [[[NSApp mainMenu] itemArray] objectEnumerator];
  while (barMenu == nil && (item = [enumerator nextObject]) != nil)
    {
      barMenu = [item submenu];
    }
  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      wantedBarMenu = @"(libs-back's)";
    }
  else if (QuirkProbeUsesPrimaryMenu ())
    {
      wantedBarMenu = @"_NET_WM_WINDOW_TYPE_POPUP_MENU";
    }
  else
    {
      wantedBarMenu = @"_NET_WM_WINDOW_TYPE_DROPDOWN_MENU";
    }

  types[0] = [theme windowTypeForWindow: toolTip];
  wanted[0] = @"_NET_WM_WINDOW_TYPE_TOOLTIP";
  types[1] = [theme windowTypeForWindow: [[[popUp menu] menuRepresentation] window]];
  wanted[1] = @"_NET_WM_WINDOW_TYPE_POPUP_MENU";
  types[2] = [theme windowTypeForWindow: [[barMenu menuRepresentation] window]];
  wanted[2] = wantedBarMenu;
  types[3] = [theme windowTypeForWindow: alert];
  wanted[3] = @"_NET_WM_WINDOW_TYPE_DIALOG";
  types[4] = [theme windowTypeForWindow: [[GSDragView sharedDragView] window]];
  wanted[4] = @"_NET_WM_WINDOW_TYPE_DND";
  types[5] = [theme windowTypeForWindow: _controlsWindow];
  wanted[5] = @"(libs-back's)";
  for (i = 0; i < 6; i++)
    {
      if (types[i] == nil)
        {
          types[i] = @"(libs-back's)";
        }
      ok = ok && [types[i] isEqualToString: wanted[i]];
    }
  detail = [NSString stringWithFormat: @"tool tip %@, pop-up button's menu %@, menu bar's menu %@ (want %@), "
    @"alert %@, drag image %@, window %@",
    types[0], types[1], types[2], wanted[2], types[3], types[4], types[5]];
  if (ok)
    {
      [self pass: @"window-types" detail: detail];
    }
  else
    {
      [self fail: @"window-types" detail: detail];
    }
  NSReleaseAlertPanel (alert);
  RELEASE (popUp);
  RELEASE (toolTip);
}

/* Whether `area` has a pixel at least `contrast` from
   `base` (the sum of the channels' differences). */
static BOOL
QuirkProbeInkIn(NSBitmapImageRep *rep, NSRect area, const NSUInteger base[3], long contrast)
{
  NSInteger x, y;
  NSUInteger rgb[3];

  for (y = NSMinY (area); y < NSMaxY (area); y++)
    {
      for (x = NSMinX (area); x < NSMaxX (area); x++)
        {
          QuirkProbePixelAt (rep, x, y, rgb);
          if (labs ((long)rgb[0] - (long)base[0]) + labs ((long)rgb[1] - (long)base[1])
              + labs ((long)rgb[2] - (long)base[2]) >= contrast)
            {
              return YES;
            }
        }
    }
  return NO;
}

/* The window tab bar (#63), as libadwaita 1.7's AdwTabBar measured from
   Reference/AdwaitaTabBar/adwaita_tab_bar.py: a 40pt bar in the window's
   colour; 34pt tabs, 6pt in from the ends and 5pt apart; the selected tab
   filled with the foreground at 10% (#e6e6e7 light, #39393c dark); a 1px
   separator at 15% between unselected tabs (#dbdbde, #434346), 50% in
   high contrast (#949497, #909092), where the selected tab has a 1px
   outline at 50% instead; a close button on the selected (and hovered)
   tab only. The bar comes from the shared tabbing code the theme builds
   in, through Apple's NSWindow tabbing API. */
- (void) checkWindowTabs
{
  typedef NSView *(*BarFunction)(NSWindow *);
  BarFunction barFor = (BarFunction)dlsym (RTLD_DEFAULT, "GSWindowTabBarViewForWindow");
  NSColor *windowColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL dark = [windowColor redComponent] < 0.5;
  BOOL highContrast = [[NSUserDefaults standardUserDefaults] boolForKey: @"ProbeHighContrast"];
  NSWindow *windows[3];
  NSView *bar;
  NSBitmapImageRep *rep;
  NSRect t0, t1, t2, close0, close1;
  NSUInteger background[3], fill[3], edge[3], separator[3];
  unsigned int wantBar, wantFill, wantSeparator;
  NSInteger y, separatorX;
  BOOL heightOK, colourOK, outlineOK, separatorOK, closeOK, closeShown, closeHidden;
  NSString *style;
  int i;

  if (barFor == NULL || [NSWindow instancesRespondToSelector: @selector(addTabbedWindow:ordered:)] == NO)
    {
      [self fail: @"window-tabs" detail: @"the tabbing code isn't in the theme (no GSWindowTabBarViewForWindow)"];
      return;
    }
  for (i = 0; i < 3; i++)
    {
      windows[i] = [self windowWithFrame: NSMakeRect (80 + 20 * i, 80, 500, 200)
                                   title: [NSString stringWithFormat: @"Probe Tab %d", i + 1]];
      [windows[i] setTabbingIdentifier: @"QuirkProbeTabs"];
    }
  [windows[0] orderFront: nil];
  [windows[0] addTabbedWindow: windows[1] ordered: NSWindowAbove];
  [windows[1] addTabbedWindow: windows[2] ordered: NSWindowAbove];
  [[windows[0] tabGroup] setSelectedWindow: windows[0]];
  bar = barFor (windows[0]);
  if (bar == nil || [bar numberOfTabs] != 3)
    {
      [self fail: @"window-tabs" detail: [NSString stringWithFormat: @"no bar with three tabs (bar %@)", bar]];
      for (i = 0; i < 3; i++)
        {
          [windows[i] orderOut: nil];
        }
      return;
    }
  [windows[0] display];
  rep = QuirkProbeRender (bar);
  t0 = [bar rectForTabAtIndex: 0];
  t1 = [bar rectForTabAtIndex: 1];
  t2 = [bar rectForTabAtIndex: 2];
  close0 = [bar closeButtonRectForTabAtIndex: 0];
  close1 = [bar closeButtonRectForTabAtIndex: 1];
  y = (NSInteger)(NSHeight ([bar bounds]) / 2.0);

  /* Height and layout. */
  heightOK = fabs (NSHeight ([bar frame]) - 40.0) < 0.01
    && fabs (NSMinX (t0) - 6.0) < 0.01 && fabs (NSMinX (t1) - NSMaxX (t0) - 5.0) < 0.01;

  /* Colours: the bar's background between the last tab and "+" is the
     gap; the selected tab's inside a little in from its left edge; its
     edge pixel; the separator between tabs 2 and 3. */
  QuirkProbePixelAt (rep, (NSInteger)NSMaxX (t2) + 2, y, background);
  QuirkProbePixelAt (rep, (NSInteger)NSMinX (t0) + 12, y, fill);
  QuirkProbePixelAt (rep, (NSInteger)NSMinX (t0), y, edge);
  separatorX = (NSInteger)floor (NSMinX (t2) - 2.5);
  QuirkProbePixelAt (rep, separatorX, y, separator);
  if (dark)
    {
      wantBar = 0x222226;
      wantFill = 0x39393c;
      wantSeparator = highContrast ? 0x909092 : 0x434346;
    }
  else
    {
      wantBar = 0xfafafb;
      wantFill = 0xe6e6e7;
      wantSeparator = highContrast ? 0x949497 : 0xdbdbde;
    }
  colourOK = QuirkProbeNear (background, wantBar, 3) && QuirkProbeNear (fill, wantFill, 3);
  separatorOK = QuirkProbeNear (separator, wantSeparator, 6);
  /* The outline is at 50%, as the high contrast separator. */
  outlineOK = highContrast
    ? QuirkProbeNear (edge, wantSeparator, 14)
    : (labs ((long)edge[0] - (long)fill[0]) <= 3 && labs ((long)edge[2] - (long)fill[2]) <= 3);

  /* The close button: the selected tab's has its X; the unselected tab's
     rect is empty and nothing is drawn where the button would be. */
  closeShown = NSIsEmptyRect (close0) == NO
    && QuirkProbeInkIn (rep, NSInsetRect (close0, 6, 6), fill, 150);
  closeHidden = NSIsEmptyRect (close1)
    && QuirkProbeInkIn (rep, NSMakeRect (NSMaxX (t1) - 22, y - 6, 12, 12), background, 150) == NO;
  closeOK = closeShown && closeHidden;
  for (i = 0; i < 3; i++)
    {
      [windows[i] orderOut: nil];
    }

  style = highContrast ? (dark ? @"high contrast dark" : @"high contrast") : (dark ? @"dark" : @"light");
  if (heightOK)
    {
      [self pass: @"window-tabs-height" detail: [NSString stringWithFormat: @"bar %.0fpt, first tab at %.0f, spacing %.0f",
        NSHeight ([bar frame]), NSMinX (t0), NSMinX (t1) - NSMaxX (t0)]];
    }
  else
    {
      [self fail: @"window-tabs-height" detail: [NSString stringWithFormat: @"bar %.0fpt (want 40), first tab at %.0f (want 6), spacing %.0f (want 5)",
        NSHeight ([bar frame]), NSMinX (t0), NSMinX (t1) - NSMaxX (t0)]];
    }
  {
    NSString *detail = [NSString stringWithFormat: @"%@: bar %@ (want %@), selected %@ (want %@), its edge %@ (%@), separator %@ (want %@)",
      style, QuirkProbeHex (background), [NSString stringWithFormat: @"#%06x", wantBar], QuirkProbeHex (fill), [NSString stringWithFormat: @"#%06x", wantFill],
      QuirkProbeHex (edge), highContrast ? @"want a 50% outline" : @"want no outline",
      QuirkProbeHex (separator), [NSString stringWithFormat: @"#%06x", wantSeparator]];

    if (colourOK && separatorOK && outlineOK)
      {
        [self pass: @"window-tabs-colours" detail: detail];
      }
    else
      {
        [self fail: @"window-tabs-colours" detail: detail];
      }
  }
  {
    NSString *detail = [NSString stringWithFormat: @"selected tab's close button %@, unselected tab's %@",
      closeShown ? @"drawn" : @"missing", closeHidden ? @"hidden" : @"shown"];

    if (closeOK)
      {
        [self pass: @"window-tabs-close" detail: detail];
      }
    else
      {
        [self fail: @"window-tabs-close" detail: detail];
      }
  }
}

/* Window tabs, phase 2 (#65). A dragged tab is AdwTabBar's
   tab:selected:active: the foreground at 19% over the bar (nearly twice
   the selected tab's 10%), opaque, with its close button. A scroll fade is
   42pt: the bar's colour, opaque for 6pt at the edge, then fading out
   linearly over 36pt. */
/* A tab with no close button (neither selected nor hovered) gives its
   title the tab's whole width, less 8pt each side, as AdwTab does: a
   126pt tab shows "Document 3.txt" in full. The title used to keep room
   for a close button at each end, and was cut to "Doc…". */
- (void) checkWindowTabTitleWidth
{
  GSTheme *theme = [GSTheme theme];
  NSString *title = @"Document 3.txt";
  NSWindow *window;
  NSImage *canvas;
  NSBitmapImageRep *rep;
  NSRect tabRect = NSMakeRect (0, 0, 126, 40);
  NSDictionary *attributes = [NSDictionary dictionaryWithObject: [NSFont systemFontOfSize: 0]
                                                         forKey: NSFontAttributeName];
  CGFloat full = [title sizeWithAttributes: attributes].width;
  NSColor *background;
  NSUInteger savedBackground = QuirkProbeInkBackground;
  QuirkProbeInk ink;
  NSString *detail;

  if ([NSWindow instancesRespondToSelector: @selector(tab)] == NO
    || [theme respondsToSelector: @selector(drawWindowTab:inRect:state:window:)] == NO)
    {
      [self fail: @"window-tab-title-width" detail: @"the tabbing code isn't in the theme"];
      return;
    }
  window = [self windowWithFrame: NSMakeRect (80, 80, 300, 100) title: title];
  background = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  canvas = AUTORELEASE ([[NSImage alloc] initWithSize: tabRect.size]);
  [canvas lockFocus];
  [background set];
  NSRectFill (tabRect);
  [(id)theme drawWindowTab: [(id)window tab] inRect: tabRect state: 0 window: window];
  rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: tabRect]);
  [canvas unlockFocus];
  QuirkProbeInkBackground = (NSUInteger)floor (([background redComponent] + [background greenComponent]
                                                + [background blueComponent]) * 255.0 + 0.5);
  ink = QuirkProbeMeasureIn (rep, QuirkProbeIsInk, NSMakeRect (0, 0, NSWidth (tabRect), NSHeight (tabRect)));
  QuirkProbeInkBackground = savedBackground;
  detail = [NSString stringWithFormat: @"\"%@\" in a 126pt tab with no close button: ink %ldpt wide, "
    @"the whole title %.0fpt", title, (long)ink.width, full];
  if (ink.width >= full - 4.0)
    {
      [self pass: @"window-tab-title-width" detail: detail];
    }
  else
    {
      [self fail: @"window-tab-title-width" detail: detail];
    }
}

- (void) checkWindowTabsDragAndFade
{
  typedef NSView *(*BarFunction)(NSWindow *);
  BarFunction barFor = (BarFunction)dlsym (RTLD_DEFAULT, "GSWindowTabBarViewForWindow");
  GSTheme *theme = [GSTheme theme];
  NSWindow *windows[3];
  NSView *bar;
  NSBitmapImageRep *rep;
  NSRect t0, t1, close1;
  NSUInteger barRGB[3], selected[3], dragged[3];
  NSInteger y, i;
  CGFloat slotX;
  double selectedStep, draggedStep;
  BOOL dragOK, closeOK;
  NSImage *canvas;
  NSBitmapImageRep *fadeRep;
  NSUInteger atEdge[3], inner[3], middle[3], outside[3], fadeBar[3];
  CGFloat fadeWidth;
  BOOL fadeOK;
  NSString *detail;

  if (barFor == NULL || [NSWindow instancesRespondToSelector: @selector(addTabbedWindow:ordered:)] == NO)
    {
      [self fail: @"window-tabs-drag" detail: @"the tabbing code isn't in the theme"];
      return;
    }
  for (i = 0; i < 3; i++)
    {
      windows[i] = [self windowWithFrame: NSMakeRect (80 + 20 * i, 80, 500, 200)
                                   title: [NSString stringWithFormat: @"Probe Drag %ld", (long)i + 1]];
      [windows[i] setTabbingIdentifier: @"QuirkProbeDragTabs"];
    }
  [windows[0] orderFront: nil];
  [windows[0] addTabbedWindow: windows[1] ordered: NSWindowAbove];
  [windows[1] addTabbedWindow: windows[2] ordered: NSWindowAbove];
  [[windows[0] tabGroup] setSelectedWindow: windows[0]];
  bar = barFor (windows[0]);
  slotX = (bar != nil) ? NSMinX ([bar rectForTabAtIndex: 1]) : 0.0;
  /* Tab 2 as the bar has it while the pointer drags it. */
  NS_DURING
    {
      [bar setValue: [NSNumber numberWithBool: YES] forKey: @"_dragging"];
      [bar setValue: [NSNumber numberWithUnsignedInteger: 1] forKey: @"_dragIndex"];
      [bar setValue: [NSNumber numberWithBool: NO] forKey: @"_dragDetached"];
      /* Its slot kept, taken 40pt right, over the third tab. */
      [bar setValue: [NSNumber numberWithUnsignedInteger: 1] forKey: @"_dragSlot"];
      [bar setValue: [NSNumber numberWithDouble: slotX + 40.0] forKey: @"_dragX"];
    }
  NS_HANDLER
    {
      bar = nil;
    }
  NS_ENDHANDLER
  if (bar == nil)
    {
      [self fail: @"window-tabs-drag" detail: @"no bar, or its drag state can't be set"];
      for (i = 0; i < 3; i++)
        {
          [windows[i] orderOut: nil];
        }
      return;
    }
  [bar setNeedsDisplay: YES];
  [windows[0] display];
  rep = QuirkProbeRender (bar);
  t0 = [bar rectForTabAtIndex: 0];
  t1 = [bar rectForTabAtIndex: 1];
  close1 = [bar closeButtonRectForTabAtIndex: 1];
  y = (NSInteger)(NSHeight ([bar bounds]) / 2.0);
  QuirkProbePixelAt (rep, (NSInteger)NSMaxX ([bar rectForTabAtIndex: 2]) + 2, y, barRGB);
  QuirkProbePixelAt (rep, (NSInteger)NSMinX (t0) + 12, y, selected);
  QuirkProbePixelAt (rep, (NSInteger)NSMinX (t1) + 12, y, dragged);
  [self saveWindow: windows[0] named: @"window-tabs-drag"];
  [bar setValue: [NSNumber numberWithBool: NO] forKey: @"_dragging"];
  for (i = 0; i < 3; i++)
    {
      [windows[i] orderOut: nil];
    }
  selectedStep = (double)((long)selected[0] - (long)barRGB[0]);
  draggedStep = (double)((long)dragged[0] - (long)barRGB[0]);
  dragOK = fabs (selectedStep) >= 8 && fabs (draggedStep - 1.9 * selectedStep) <= 4.0;
  closeOK = NSIsEmptyRect (close1) == NO
    && QuirkProbeInkIn (rep, NSInsetRect (close1, 6, 6), dragged, 150);
  detail = [NSString stringWithFormat: @"bar %@, selected %@, dragged %@ (red %+.0f against the selected's %+.0f; want 1.9 times); "
    @"dragged tab's close button %@",
    QuirkProbeHex (barRGB), QuirkProbeHex (selected), QuirkProbeHex (dragged), draggedStep, selectedStep,
    closeOK ? @"drawn" : @"missing"];
  if (dragOK && closeOK)
    {
      [self pass: @"window-tabs-drag" detail: detail];
    }
  else
    {
      [self fail: @"window-tabs-drag" detail: detail];
    }

  /* The fade at the end edge, over red, from x 0 to 100: 42pt from 58. */
  fadeWidth = [(id)theme windowTabBarScrollFadeWidthForWindow: windows[0]];
  canvas = AUTORELEASE ([[NSImage alloc] initWithSize: NSMakeSize (100, 34)]);
  [canvas lockFocus];
  [[NSColor colorWithCalibratedRed: 1.0 green: 0.0 blue: 0.0 alpha: 1.0] set];
  NSRectFill (NSMakeRect (0, 0, 100, 34));
  [(id)theme drawWindowTabBarScrollFadeInRect: NSMakeRect (100 - fadeWidth, 0, fadeWidth, 34)
                                         edge: NSMaxXEdge
                                       window: windows[0]];
  fadeRep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: NSMakeRect (0, 0, 100, 34)]);
  [canvas unlockFocus];
  {
    NSColor *barColor = [[NSColor windowBackgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    fadeBar[0] = (NSUInteger)floor ([barColor redComponent] * 255.0 + 0.5);
    fadeBar[1] = (NSUInteger)floor ([barColor greenComponent] * 255.0 + 0.5);
    fadeBar[2] = (NSUInteger)floor ([barColor blueComponent] * 255.0 + 0.5);
  }
  QuirkProbePixelAt (fadeRep, 99, 17, atEdge);
  QuirkProbePixelAt (fadeRep, 95, 17, inner);
  QuirkProbePixelAt (fadeRep, 100 - 6 - 18, 17, middle);
  QuirkProbePixelAt (fadeRep, 100 - (NSInteger)fadeWidth - 1, 17, outside);
  /* Green goes from the bar's at the edge to 0 (red) where the fade ends. */
  fadeOK = fabs (fadeWidth - 42.0) < 0.01
    && labs ((long)atEdge[1] - (long)fadeBar[1]) <= 2 && labs ((long)inner[1] - (long)fadeBar[1]) <= 2
    && labs ((long)middle[1] - (long)fadeBar[1] / 2) <= 12
    && outside[0] > 240 && outside[1] < 10;
  detail = [NSString stringWithFormat: @"%.0fpt (want 42); green %lu at the edge and %lu 5pt in (bar %lu), "
    @"%lu halfway along the fade (want about %lu), %lu just outside it (want 0)",
    fadeWidth, (unsigned long)atEdge[1], (unsigned long)inner[1], (unsigned long)fadeBar[1],
    (unsigned long)middle[1], (unsigned long)(fadeBar[1] / 2), (unsigned long)outside[1]];
  if (fadeOK)
    {
      [self pass: @"window-tabs-fade" detail: detail];
    }
  else
    {
      [self fail: @"window-tabs-fade" detail: detail];
    }
}

- (void) checkFirstWindows: (NSTimer *)timer
{
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"file-chooser"])
    {
      [self checkFileChooser];
      return;
    }
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"print-dialog"])
    {
      [self checkPrintDialog];
      return;
    }
  /* -ProbeOnly lists-demo: for screenshots beside GTK's (#66). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"lists-demo"])
    {
      [self showListsDemo];
      return;
    }
  /* -ProbeOnly popover-demo: for screenshots beside GTK's (#74). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"popover-demo"])
    {
      [self showPopoverDemo];
      return;
    }
  /* -ProbeOnly lists: libadwaita's lists alone (#66). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"lists"])
    {
      [self checkDropDownList];
  [self checkDropDownEmpty];
      [self checkSourceList];
      [self finish];
      return;
    }
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"menu-timing"])
    {
      [self checkMenuTiming];
      return;
    }
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"scroller-drag"])
    {
      [self checkScrollerDrag];
      return;
    }
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"context-menu"])
    {
      [self checkContextMenu];
      return;
    }
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"context-menu-demo"])
    {
      [self showContextMenuDemo];
      return;
    }
  /* -ProbeOnly live-settings: GNOME's settings changed while the probe
     runs (make check-live-settings). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"live-settings"])
    {
      [self checkLiveSettings];
      [self finish];
      return;
    }
  /* -ProbeOnly hidpi-fonts: the font hinting at GSScaleFactor 2 and 1
     (make check-hidpi). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"hidpi-fonts"])
    {
      [self checkHiDPIFontHinting];
      [self checkWindowEdgeAtScale];
      [self finish];
      return;
    }
  /* -ProbeOnly accent: GNOME's accent at launch (make check-live-settings). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"accent"])
    {
      [self checkAccentAtLaunch];
      [self finish];
      return;
    }
  /* -ProbeOnly forced-scheme: a per-app light or dark scheme over
     GNOME's (make check-color-scheme). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"forced-scheme"])
    {
      [self checkForcedColorScheme];
      [self finish];
      return;
    }
  /* -ProbeOnly text-scaling, for the runs with GNOME's Large Text
     (make check-text-scaling). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"text-scaling"])
    {
      [self checkTextScaling];
      [self finish];
      return;
    }
  /* -ProbeOnly nib-metrics, for the runs with -GnomeThemeMetrics set
     (make check-nib-metrics). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"nib-metrics"])
    {
      [self checkNibMetrics];
      [self finish];
      return;
    }
  /* -ProbeOnly toolbar-overflow: the » menu by visibilityPriority, in a
     window's toolbar and (with the theme's decorations) the header bar. */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"toolbar-overflow"])
    {
      [self checkToolbarPriorityOverflow];
      [self checkHeaderBarToolbarPriorityOverflow];
      [self finish];
      return;
    }
  /* -ProbeOnly header-bar: the header bar's checks alone, for the dark and
     high contrast runs (the other checks assume the light palette). */
  if ([[[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOnly"] isEqualToString: @"header-bar"])
    {
      [self checkHeaderBar];
  [self checkHeaderBarToolbar];
  [self checkHeaderBarToolbarItemClick];
  [self checkHeaderBarToolbarItemDrag];
  [self checkHeaderBarDocumentTitle];
  [self checkHeaderBarToolbarLive];
  [self checkHeaderBarToolbarPriorityOverflow];
      [self checkSegmentedSelection];
      [self checkSegmentSeparator];
      [self checkSegmentedDisabled];
      [self checkHeaderBarSegmentedDisabled];
      [self checkMenuSeparatorAndShortcut];
      [self checkTemplateImages];
  [self checkOverlayScrollers];
  [self checkOverlayScrollerCursor];
  [self checkAutohiddenScrollerCursor];
  [self checkSwitch];
  [self checkControlColors];
  [self checkAccentButtons];
  [self checkAccentYields];
  [self checkSliderKnob];
  [self checkScrollViewFrame];
  [self checkPopUpChevron];
  [self checkTableBackground];
  [self checkContentBackground];
  [self checkPaletteLookup];
  [self checkTableSelection];
  [self checkPopUpMenuArrowImage];
  [self checkPopUpTitleTruncation];
  [self checkPopUpDisabled];
  [self checkSubmenuAtScreenEdge];
  [self checkSubmenuLinesUpWithItem];
  [self checkSortIndicator];
  [self checkSortIndicatorNarrow];
  [self checkDropDownComboFocus];
  [self checkBrowserTitles];
  [self checkBrowserLists];
  [self checkBrowserSelection];
  [self checkShapedButtons];
  [self checkFlatButtons];
  [self checkEditableComboWeight];
  [self checkComboSeparator];
  [self checkBoxes];
  [self checkColumnHeaderColours];
  [self checkDimLabelOpacity];
  [self checkLevelAndActivity];
  [self checkProgressFill];
  [self checkSliderTickMarks];
  [self checkSplitViewDividers];
  [self checkBottomTabs];
  [self checkBorderlessPopUp];
  [self checkImageFrames];
  [self checkRulerMarks];
  [self checkPopUpArchivedArrow];
  [self checkBrowserScrollerBezel];
  [self checkPanelIcons];
  [self checkAboutPanel];
  [self checkTintedImageReps];
  [self checkMenuHoverTextColor];
  [self checkSearchPlaceholderFocused];
  [self checkStringValueWhileTyping];
  [self checkPopoverPanel];
  [self checkAutohideTileSettles];
  [self checkWindowTabs];
  [self checkWindowTabsDragAndFade];
  [self checkWindowTabTitleWidth];
  [self checkDropDownList];
  [self checkDropDownEmpty];
  [self checkSourceList];
      [self finish];
      return;
    }
  [self saveWindow: _controlsWindow named: @"controls"];
  [self saveWindow: _toolbarWindow named: @"toolbar"];
  [self saveWindow: _tableWindow named: @"tables"];
  [self checkThemeDomain];
  [self checkTextWidth];
  [self checkTextScaling];
  [self checkImageFreeButton];
  [self checkShortcutLabels];
  [self checkCustomBackgroundField];
  [self checkFieldEditorOnPixels];
  [self checkSecureBullets];
  [self checkInlineMenuRow];
  [self checkSizedButtons];
  [self checkFixedButtons];
  [self checkSteppers];
  [self checkColorWell];
  [self checkColorWellEdge];
  [self checkDestructiveButtons];
  [self checkRealDestructiveFlag];
  [self checkThemeImages2x];
  [self checkLabels];
  [self checkToolbar];
  [self checkTables];
  [self checkMenuBar];
  [self checkMenuBarClick];
  [self checkToolbarEdges];
  [self checkToolbarHover];
  [self checkPopUpButton];
  [self checkPopUpClick];
  [self checkPopUpListKeepsSize];
  [self checkButtonFocusRing];
  [self checkFocusVisiblePerWindow];
  [self checkControlHeights];
  [self checkCheckboxGap];
  [self checkTableDensity];
  [self checkTabView];
  [self checkToolbarDisplayMode];
  [self checkToolbarRowHeight];
  [self checkToolbarViewItemWidth];
  [self checkToolbarPriorityOverflow];
  [self checkSegmentedSelection];
  [self checkSegmentSeparator];
      [self checkSegmentedDisabled];
      [self checkHeaderBarSegmentedDisabled];
  [self checkMenuSeparatorAndShortcut];
  [self checkApplicationMenuPosition];
  [self checkMenuBarOverflow];
  [self checkCocoaApplicationMenu];
  [self checkGormControls];
  [self checkMetricsMode];
  [self checkNibMetrics];
  [self checkPrimaryMenu];
  [self checkHeaderBar];
  [self checkHeaderBarToolbar];
  [self checkHeaderBarToolbarItemClick];
  [self checkHeaderBarToolbarItemDrag];
  [self checkHeaderBarDocumentTitle];
  [self checkHeaderBarToolbarLive];
  [self checkHeaderBarToolbarPriorityOverflow];
  [self checkFonts];
  [self checkToolTip];
  [self checkHiddenWindows];
  [self checkWindowTypes];
  [self checkWindowManagerClose];
  [self checkTemplateImages];
  [self checkOverlayScrollers];
  [self checkOverlayScrollerCursor];
  [self checkAutohiddenScrollerCursor];
  [self checkSwitch];
  [self checkControlColors];
  [self checkAccentButtons];
  [self checkAccentYields];
  [self checkSliderKnob];
  [self checkScrollViewFrame];
  [self checkPopUpChevron];
  [self checkTableBackground];
  [self checkContentBackground];
  [self checkPaletteLookup];
  [self checkTableSelection];
  [self checkPopUpMenuArrowImage];
  [self checkPopUpTitleTruncation];
  [self checkPopUpDisabled];
  [self checkSubmenuAtScreenEdge];
  [self checkSubmenuLinesUpWithItem];
  [self checkSortIndicator];
  [self checkSortIndicatorNarrow];
  [self checkDropDownComboFocus];
  [self checkBrowserTitles];
  [self checkBrowserLists];
  [self checkBrowserSelection];
  [self checkShapedButtons];
  [self checkFlatButtons];
  [self checkEditableComboWeight];
  [self checkComboSeparator];
  [self checkBoxes];
  [self checkColumnHeaderColours];
  [self checkDimLabelOpacity];
  [self checkLevelAndActivity];
  [self checkProgressFill];
  [self checkSliderTickMarks];
  [self checkSplitViewDividers];
  [self checkBottomTabs];
  [self checkBorderlessPopUp];
  [self checkImageFrames];
  [self checkRulerMarks];
  [self checkPopUpArchivedArrow];
  [self checkBrowserScrollerBezel];
  [self checkPanelIcons];
  [self checkAboutPanel];
  [self checkTintedImageReps];
  [self checkMenuHoverTextColor];
  [self checkSearchPlaceholderFocused];
  [self checkStringValueWhileTyping];
  [self checkPopoverPanel];
  [self checkAutohideTileSettles];
  [self checkWindowTabs];
  [self checkWindowTabsDragAndFade];
  [self checkWindowTabTitleWidth];
  [self checkDropDownList];
  [self checkDropDownEmpty];
  [self checkSourceList];

  /* Auxiliary windows made after launch: a Settings window, a window whose
     delegate turns the menu bar off, and a Preferences window whose
     delegate keeps it. */
  _latePrefsWindow = [self windowWithFrame: NSMakeRect (800, 560, 200, 80) title: @"Settings\u2026"];
  [_latePrefsWindow makeKeyAndOrderFront: nil];
  _optOutWindow = [self windowWithFrame: NSMakeRect (800, 680, 200, 80) title: @"Inspector"];
  [_optOutWindow setDelegate: self];
  [_optOutWindow makeKeyAndOrderFront: nil];
  _optInWindow = [self windowWithFrame: NSMakeRect (1020, 560, 200, 80) title: @"Preferences"];
  [_optInWindow setDelegate: self];
  [_optInWindow makeKeyAndOrderFront: nil];

  _lateWindow = [self windowWithFrame: NSMakeRect (480, 560, 300, 100) title: @"QuirkProbe Late Window"];
  [_lateWindow makeKeyAndOrderFront: nil];
  [self after: QuirkProbeSettleDelay perform: @selector(checkLateWindow:)];
}

/* The menu bar answer for the windows the probe is the delegate of. */
- (BOOL) windowShouldShowMenuBar: (NSWindow *)window
{
  return window != _optOutWindow;
}

/* GNOME apps keep their menus out of auxiliary windows. */
- (void) checkAuxiliaryWindowMenus
{
  NSMenu *mainMenu = [NSApp mainMenu];
  NSString *detail = [NSString stringWithFormat: @"menu bar on: Preferences at launch %@, Settings… later %@, "
    @"delegate says no %@, Preferences whose delegate says yes %@",
    [_launchPrefsWindow menu] == mainMenu ? @"yes" : @"no",
    [_latePrefsWindow menu] == mainMenu ? @"yes" : @"no",
    [_optOutWindow menu] == mainMenu ? @"yes" : @"no",
    [_optInWindow menu] == mainMenu ? @"yes" : @"no"];

  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      [self skip: @"auxiliary-window-no-menu" detail: @"needs -NSMenuInterfaceStyle NSWindows95InterfaceStyle"];
    }
  else if ([_launchPrefsWindow menu] == nil && [_latePrefsWindow menu] == nil
    && [_optOutWindow menu] == nil && [_optInWindow menu] == mainMenu)
    {
      [self pass: @"auxiliary-window-no-menu" detail: detail];
    }
  else
    {
      [self fail: @"auxiliary-window-no-menu" detail: detail];
    }
}

- (void) checkLateWindow: (NSTimer *)timer
{
  [self checkAuxiliaryWindowMenus];
  [self saveWindow: _launchPrefsWindow named: @"preferences-window"];
  NSMenu *mainMenu = [NSApp mainMenu];

  [self saveWindow: _lateWindow named: @"late-window"];
  if (NSInterfaceStyleForKey (@"NSMenuInterfaceStyle", nil) != NSWindows95InterfaceStyle)
    {
      [self skip: @"late-window-menu" detail: @"needs -NSMenuInterfaceStyle NSWindows95InterfaceStyle"];
    }
  else if ([_controlsWindow menu] != mainMenu)
    {
      [self fail: @"late-window-menu" detail: @"the first window has no menu either"];
    }
  else if ([_lateWindow menu] == mainMenu)
    {
      [self pass: @"late-window-menu" detail: @"a window created after launch shows the main menu"];
    }
  else
    {
      [self fail: @"late-window-menu" detail: @"a window created after launch has no menu"];
    }
  [self after: 0.1 perform: @selector(runAlert:)];
}

- (void) runAlert: (NSTimer *)timer
{
  NSAlert *alert = [[NSAlert alloc] init];

  [alert setMessageText: @"Remove this library?"];
  [alert setInformativeText: _alertText];
  [alert addButtonWithTitle: @"Remove"];
  [alert addButtonWithTitle: @"Cancel"];
  /* The alert runs a modal loop; the check fires inside it. */
  [self after: QuirkProbeSettleDelay perform: @selector(checkAlert:) mode: NSModalPanelRunLoopMode];
  [alert runModal];
  RELEASE (alert);
  [self finish];
}

- (void) checkAlert: (NSTimer *)timer
{
  NSWindow *panel = [NSApp modalWindow];
  NSView *text = QuirkProbeFindText ([panel contentView], _alertText);

  [self saveWindow: panel named: @"alert"];
  if (text == nil)
    {
      [self fail: @"alert-informative-text-wraps" detail: @"informative text view not found"];
    }
  else
    {
      [self checkLabel: text ident: @"alert-informative-text-wraps" lineHeight: [self lineHeight]];
    }
  [self checkAlertLayout: panel];
  /* With the header bar, an alert has none (as AdwAlertDialog): a 1pt
     border round its content, and it can still take the keyboard (it
     isn't key here: the late window is, on a display without a window
     manager). */
  if (QuirkProbeDrawsDecorations ())
    {
      NSView *frameView = [[panel contentView] superview];
      CGFloat top = QuirkProbeTopGap (frameView, [[panel contentView] frame]);
      NSString *detail = [NSString stringWithFormat: @"content %gpt from the top, %@ buttons, %@",
        top, [QuirkProbeWindowButtons (frameView) count] > 0 ? @"with" : @"no",
        [panel canBecomeKeyWindow] ? @"can become key" : @"can't become key"];

      if (top == 1 && [QuirkProbeWindowButtons (frameView) count] == 0 && [panel canBecomeKeyWindow])
        [self pass: @"header-bar-alert" detail: detail];
      else
        [self fail: @"header-bar-alert" detail: detail];
    }
  /* -stopModal takes effect when the modal loop next handles an event. */
  [NSApp stopModal];
  [NSApp postEvent: [NSEvent otherEventWithType: NSApplicationDefined
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                      timestamp: 0
                                   windowNumber: [panel windowNumber]
                                        context: nil
                                        subtype: 0
                                          data1: 0
                                          data2: 0]
           atStart: NO];
  [self after: 1.0 perform: @selector(forceEndAlert:) mode: NSModalPanelRunLoopMode];
}

/* Laid out like AdwAlertDialog: no icon or line, the heading centred, the
   buttons one row of equal widths with the default (Remove) at the right. */
- (void) checkAlertLayout: (NSWindow *)panel
{
  NSEnumerator *enumerator = [[[panel contentView] subviews] objectEnumerator];
  NSView *view;
  NSButton *remove = nil, *cancel = nil;
  NSUInteger visibleIcons = 0, visibleLines = 0;
  NSTextField *heading = (NSTextField *)QuirkProbeFindText ([panel contentView], @"Remove this library?");
  QuirkProbeInk headingInk = { 0 };
  CGFloat leftGap = 0.0, rightGap = 0.0;
  BOOL centred = NO;
  NSString *detail;

  while ((view = [enumerator nextObject]) != nil)
    {
      if ([view isHidden])
        {
          continue;
        }
      if ([view isKindOfClass: [NSBox class]])
        {
          visibleLines++;
        }
      else if ([view isKindOfClass: [NSButton class]])
        {
          NSString *title = [(NSButton *)view title];

          if ([title isEqualToString: @"Remove"])
            remove = (NSButton *)view;
          else if ([title isEqualToString: @"Cancel"])
            cancel = (NSButton *)view;
          else if ([(NSButton *)view isBordered] == NO)
            visibleIcons++;
        }
    }
  /* Measured from the drawing, not -alignment: libs-gui after 0.32 numbers
     NSTextAlignment differently, so the constants this probe was built with
     may mean another alignment to the libs-gui it runs with. */
  if (heading != nil)
    {
      headingInk = QuirkProbeTextInk (heading);
      leftGap = headingInk.minX;
      rightGap = NSWidth ([heading bounds]) - headingInk.minX - headingInk.width;
      centred = headingInk.count > 0 && fabs (leftGap - rightGap) <= 3.0;
    }
  detail = [NSString stringWithFormat: @"%lu icons, %lu lines; Remove %@, Cancel %@; heading %@ (ink %.0f from the left, %.0f from the right)",
    (unsigned long)visibleIcons, (unsigned long)visibleLines,
    NSStringFromRect ([remove frame]), NSStringFromRect ([cancel frame]),
    centred ? @"centred" : @"not centred", leftGap, rightGap];
  if (remove != nil && cancel != nil && visibleIcons == 0 && visibleLines == 0
    && NSWidth ([remove frame]) == NSWidth ([cancel frame])
    && NSMinY ([remove frame]) == NSMinY ([cancel frame])
    && NSMinX ([remove frame]) > NSMaxX ([cancel frame])
    && centred)
    {
      [self pass: @"alert-adwaita-layout" detail: detail];
    }
  else
    {
      [self fail: @"alert-adwaita-layout" detail: detail];
    }
}

/* Fallback when -stopModal hasn't ended the alert (seen with the default
   theme). */
- (void) forceEndAlert: (NSTimer *)timer
{
  if ([NSApp modalWindow] != nil)
    {
      [NSApp abortModal];
    }
}

- (void) finish
{
  printf ("SUMMARY pass=%lu fail=%lu known=%lu skip=%lu\n",
          (unsigned long)_passed, (unsigned long)_failed,
          (unsigned long)_known, (unsigned long)_skipped);
  fflush (stdout);
  exit (_failed > 255 ? 255 : (int)_failed);
}

#pragma mark Application delegate

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  NSString *output = [[NSUserDefaults standardUserDefaults] stringForKey: @"ProbeOutput"];
  NSBundle *themeBundle = [[GSTheme theme] bundle];

  if ([output length] > 0)
    {
      ASSIGN (_outputDirectory, output);
      [[NSFileManager defaultManager] createDirectoryAtPath: output
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: NULL];
    }
  printf ("THEME %s\n", themeBundle ? [[themeBundle bundlePath] UTF8String] : "(default)");
  printf ("THEMECLASS %s\n", [NSStringFromClass ([[GSTheme theme] class]) UTF8String]);
  fflush (stdout);

  [self buildWindows];
  [self after: QuirkProbeSettleDelay perform: @selector(checkFirstWindows:)];
}

@end
