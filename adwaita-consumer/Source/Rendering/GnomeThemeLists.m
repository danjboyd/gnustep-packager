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

/* Tables drawn as libadwaita 1.7's lists (#66), measured from its
   stylesheet and Reference/DropDownList:

   - A combo box's list (GSComboWindow) is GtkDropDown's popover: 15pt
     corners and a popover shadow, as the theme's menus; the list 6pt from
     its top and bottom; rows 9pt above and below the text (37pt at
     Cantarell 11) and 12pt at the sides, inside pills 6pt from the
     popover's sides with 9pt corners. The pill under the pointer is the
     text colour at 10%; the chosen row has no fill, but a checkmark 6pt
     after its text. The list is as wide as the field, or wider for its
     longest item; it shows up to 400pt of rows, then scrolls.
   - A table or outline whose selectionHighlightStyle is
     NSTableViewSelectionHighlightStyleSourceList is a navigation-sidebar
     list: no background (what is behind it shows, and its scroll view
     stops drawing one), no grid, and pills 6pt from its sides with 9pt
     corners and 2pt below each: the text colour at 7% under the pointer,
     10% when selected, 13% for both. Group rows (-tableView:isGroupRow:,
     or -outlineView:isGroupItem:, which libs-gui never asks) get no pill.
     Row heights and cells stay the app's; cells are drawn 14pt in from
     the table's ends (the pill's inset and GTK's 8pt padding), so a cell
     shouldn't pad its text itself. */

#import "GnomeThemeLists.h"
#import "../GnomeTheme.h"
#import "../Adapters/GnomeThemeWindowManager.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import <math.h>

/* libadwaita 1.7: popover.menu listview rows, and .navigation-sidebar. */
static const CGFloat GnomeThemeListPillInset = 6.0;
static const CGFloat GnomeThemeListPillRadius = 9.0;
static const CGFloat GnomeThemeDropDownListPadding = 6.0;
static const CGFloat GnomeThemeDropDownRowPaddingX = 12.0;
static const CGFloat GnomeThemeDropDownRowPaddingY = 9.0;
static const CGFloat GnomeThemeDropDownCheckSize = 16.0;
static const CGFloat GnomeThemeDropDownCheckSpacing = 6.0;
static const CGFloat GnomeThemeDropDownMaxListHeight = 400.0;
static const CGFloat GnomeThemeDropDownMinWidth = 120.0;
static const CGFloat GnomeThemeDropDownCornerRadius = 15.0;
/* GtkDropDown's popover sits this far below its button. */
static const CGFloat GnomeThemeDropDownGap = 2.0;
static const CGFloat GnomeThemeSidebarRowPaddingX = 8.0;
static const CGFloat GnomeThemeSidebarRowGap = 2.0;

@interface NSComboBoxCell (GnomeThemeListsPrivate)
- (NSString *) _stringValueAtIndex: (NSInteger)index;
@end

@interface NSObject (GnomeThemeListsComboWindow)
- (void) layoutWithComboBoxCell: (NSComboBoxCell *)cell;
@end

@interface NSObject (GnomeThemeListsDelegate)
- (BOOL) tableView: (NSTableView *)tableView isGroupRow: (NSInteger)row;
- (BOOL) outlineView: (NSOutlineView *)outlineView isGroupItem: (id)item;
@end

GnomeThemeListStyle
GnomeThemeTableListStyle(NSTableView *tableView)
{
  static Class comboTableClass = Nil;

  if (tableView == nil)
    {
      return GnomeThemeListStyleNone;
    }
  if (comboTableClass == Nil)
    {
      comboTableClass = NSClassFromString (@"GSComboBoxTableView");
    }
  if (comboTableClass != Nil && [tableView isKindOfClass: comboTableClass])
    {
      return GnomeThemeListStyleDropDown;
    }
  if ([tableView selectionHighlightStyle] == NSTableViewSelectionHighlightStyleSourceList)
    {
      return GnomeThemeListStyleSidebar;
    }
  return GnomeThemeListStyleNone;
}

static BOOL
GnomeThemeListRowIsGroup(NSTableView *tableView, NSInteger row)
{
  id delegate = [tableView delegate];

  if (delegate == nil)
    {
      return NO;
    }
  if ([tableView isKindOfClass: [NSOutlineView class]]
    && [delegate respondsToSelector: @selector(outlineView:isGroupItem:)])
    {
      id item = [(NSOutlineView *)tableView itemAtRow: row];

      return item != nil && [delegate outlineView: (NSOutlineView *)tableView isGroupItem: item];
    }
  if ([delegate respondsToSelector: @selector(tableView:isGroupRow:)])
    {
      return [delegate tableView: tableView isGroupRow: row];
    }
  return NO;
}

static NSColor *
GnomeThemeListTextColor(GnomeTheme *theme)
{
  return GnomeThemeColor ((GSTheme *)theme, @"controlTextColor", [NSColor controlTextColor]);
}

/* The row under the pointer, in the one table that has it. Not retained:
   identity only, cleared as the pointer leaves the table or it goes. */
static NSTableView *GnomeThemeHoverTable = nil;
static NSInteger GnomeThemeHoverRow = -1;

static void
GnomeThemeListRedrawRow(NSTableView *tableView, NSInteger row)
{
  if (tableView != nil && row >= 0 && row < [tableView numberOfRows])
    {
      [tableView setNeedsDisplayInRect: [tableView rectOfRow: row]];
    }
}

/* Owns the tracking rect that tells the hovered table the pointer left
   (mouse-moved events go to the view under the pointer, so the table
   hears of no move outside it). */
@interface GnomeThemeListHoverTracker : NSObject
{
  NSTrackingRectTag _tag;
}
+ (GnomeThemeListHoverTracker *) sharedTracker;
- (void) setTable: (NSTableView *)tableView row: (NSInteger)row;
@end

@implementation GnomeThemeListHoverTracker

+ (GnomeThemeListHoverTracker *) sharedTracker
{
  static GnomeThemeListHoverTracker *tracker = nil;

  if (tracker == nil)
    {
      tracker = [GnomeThemeListHoverTracker new];
    }
  return tracker;
}

- (void) setTable: (NSTableView *)tableView row: (NSInteger)row
{
  if (tableView == GnomeThemeHoverTable && row == GnomeThemeHoverRow)
    {
      return;
    }
  if (tableView != GnomeThemeHoverTable)
    {
      if (GnomeThemeHoverTable != nil && _tag != 0)
        {
          [GnomeThemeHoverTable removeTrackingRect: _tag];
        }
      _tag = 0;
      if (tableView != nil)
        {
          _tag = [tableView addTrackingRect: [tableView visibleRect]
                                      owner: self
                                   userData: NULL
                               assumeInside: YES];
        }
    }
  GnomeThemeListRedrawRow (GnomeThemeHoverTable, GnomeThemeHoverRow);
  GnomeThemeHoverTable = tableView;
  GnomeThemeHoverRow = (tableView != nil) ? row : -1;
  GnomeThemeListRedrawRow (GnomeThemeHoverTable, GnomeThemeHoverRow);
}

- (void) mouseEntered: (NSEvent *)event
{
  (void)event;
}

- (void) mouseExited: (NSEvent *)event
{
  (void)event;
  [self setTable: nil row: -1];
}

@end

void
GnomeThemeListClearHover(void)
{
  [[GnomeThemeListHoverTracker sharedTracker] setTable: nil row: -1];
}

static BOOL
GnomeThemeListRowIsHovered(NSTableView *tableView, NSInteger row)
{
  return tableView == GnomeThemeHoverTable && row == GnomeThemeHoverRow;
}

void
GnomeThemeDrawListPills(GnomeTheme *theme, NSTableView *tableView, NSRect clipRect)
{
  GnomeThemeListStyle style = GnomeThemeTableListStyle (tableView);
  NSColor *textColor = GnomeThemeListTextColor (theme);
  NSRange rows = [tableView rowsInRect: clipRect];
  NSUInteger row;

  for (row = rows.location; row < NSMaxRange (rows); row++)
    {
      BOOL hovered = GnomeThemeListRowIsHovered (tableView, (NSInteger)row);
      BOOL selected = [tableView isRowSelected: (NSInteger)row];
      CGFloat alpha = 0.0;
      NSRect pill;

      if (style == GnomeThemeListStyleDropDown)
        {
          alpha = hovered ? 0.10 : 0.0;
        }
      else if (selected)
        {
          alpha = hovered ? 0.13 : 0.10;
        }
      else if (hovered)
        {
          alpha = 0.07;
        }
      if (alpha == 0.0 || GnomeThemeListRowIsGroup (tableView, (NSInteger)row))
        {
          continue;
        }

      pill = NSInsetRect ([tableView rectOfRow: (NSInteger)row], GnomeThemeListPillInset, 0.0);
      if (style == GnomeThemeListStyleSidebar && NSHeight (pill) > 4.0 * GnomeThemeSidebarRowGap)
        {
          pill.size.height -= GnomeThemeSidebarRowGap;
          if ([tableView isFlipped] == NO)
            {
              pill.origin.y += GnomeThemeSidebarRowGap;
            }
        }
      if (NSIsEmptyRect (pill))
        {
          continue;
        }
      [[textColor colorWithAlphaComponent: alpha] set];
      [[NSBezierPath bezierPathWithRoundedRect: pill
                                       xRadius: GnomeThemeListPillRadius
                                       yRadius: GnomeThemeListPillRadius] fill];
    }
}

void
GnomeThemeDrawDropDownCheckmark(GnomeTheme *theme, NSTableView *tableView, NSInteger row)
{
  NSTableColumn *column = [[tableView tableColumns] count] > 0
    ? [[tableView tableColumns] objectAtIndex: 0] : nil;
  NSCell *cell = [column dataCellForRow: row];
  NSRect rowRect = [tableView rectOfRow: row];
  NSRect textRect = [tableView frameOfCellAtColumn: 0 row: row];
  NSString *text = nil;
  NSDictionary *attributes = nil;
  CGFloat textWidth = 0.0;
  CGFloat x, top, flip;
  NSRect check;
  NSBezierPath *path = [NSBezierPath bezierPath];

  if (cell == nil || row < 0 || row >= [tableView numberOfRows])
    {
      return;
    }
  {
    id dataSource = [tableView dataSource];

    if ([dataSource respondsToSelector: @selector(tableView:objectValueForTableColumn:row:)])
      {
        text = [[dataSource tableView: tableView objectValueForTableColumn: column row: row] description];
      }
  }
  if (text != nil && [cell font] != nil)
    {
      attributes = [NSDictionary dictionaryWithObject: [cell font] forKey: NSFontAttributeName];
      textWidth = ceil ([text sizeWithAttributes: attributes].width);
    }

  /* After the text, as GTK's (the cell draws it from its frame's start), and
     never past the row's padding. */
  x = NSMinX (textRect) + textWidth + GnomeThemeDropDownCheckSpacing;
  x = MIN (x, NSMaxX (rowRect) - GnomeThemeListPillInset - GnomeThemeDropDownRowPaddingX
                - GnomeThemeDropDownCheckSize);
  check = NSMakeRect (floor (x), floor (NSMidY (rowRect) - GnomeThemeDropDownCheckSize / 2.0),
                      GnomeThemeDropDownCheckSize, GnomeThemeDropDownCheckSize);

  /* object-select-symbolic: a 16pt check, its stroke 2pt; y runs down in
     a flipped table. */
  top = [tableView isFlipped] ? NSMinY (check) : NSMaxY (check);
  flip = [tableView isFlipped] ? 1.0 : -1.0;
  [path moveToPoint: NSMakePoint (NSMinX (check) + 2.5, top + flip * 8.5)];
  [path lineToPoint: NSMakePoint (NSMinX (check) + 6.0, top + flip * 12.0)];
  [path lineToPoint: NSMakePoint (NSMinX (check) + 13.5, top + flip * 4.5)];
  [path setLineWidth: 2.0];
  [path setLineCapStyle: NSRoundLineCapStyle];
  [path setLineJoinStyle: NSRoundLineJoinStyle];
  [GnomeThemeListTextColor (theme) set];
  [path stroke];
}

CGFloat
GnomeThemeDropDownRowHeight(NSFont *font)
{
  CGFloat textHeight = 19.0;

  if (font != nil)
    {
      textHeight = ceil ([font ascender] - [font descender]);
    }
  return textHeight + 2.0 * GnomeThemeDropDownRowPaddingY;
}

NSInteger
GnomeThemeDropDownVisibleRows(CGFloat rowHeight, NSInteger count)
{
  NSInteger fit = (NSInteger)floor ((GnomeThemeDropDownMaxListHeight - 2.0 * GnomeThemeDropDownListPadding)
                                    / MAX (rowHeight, 1.0));

  return MAX (1, MIN (MAX (count, 1), MAX (fit, 1)));
}

/* The popover a combo box's list sits in: the menu's background and
   border, with 15pt corners where the window has an alpha channel (as
   the theme's menus); the list 6pt from its top and bottom. */
@interface GnomeThemeDropDownPopoverView : NSView
@end

@implementation GnomeThemeDropDownPopoverView

- (BOOL) isOpaque
{
  return NO;
}

- (void) drawRect: (NSRect)dirtyRect
{
  GSTheme *theme = [GSTheme theme];
  NSRect bounds = [self bounds];
  NSColor *fill = GnomeThemeColor (theme, @"menuBackgroundColor", [NSColor controlBackgroundColor]);
  NSColor *border = GnomeThemeColor (theme, @"menuBorderColor", [NSColor controlShadowColor]);

  (void)dirtyRect;
  if ([self window] != nil && GnomeThemeWindowManagerHasAlpha ([self window]))
    {
      NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect (bounds, 0.5, 0.5)
                                                           xRadius: GnomeThemeDropDownCornerRadius
                                                           yRadius: GnomeThemeDropDownCornerRadius];

      NSRectFillUsingOperation (bounds, NSCompositeClear);
      [fill set];
      [path fill];
      [border set];
      [path setLineWidth: 1.0];
      [path stroke];
    }
  else
    {
      [fill set];
      NSRectFill (bounds);
      [border set];
      NSFrameRectWithWidth (bounds, 1.0);
    }
}

@end

void
GnomeThemeInstallDropDownPopover(NSWindow *window)
{
  NSView *contentView = [window contentView];
  NSScrollView *scrollView = nil;
  GnomeThemeDropDownPopoverView *popover = nil;

  if (contentView == nil || [contentView isKindOfClass: [GnomeThemeDropDownPopoverView class]])
    {
      return;
    }
  /* GSComboWindow's content: an NSBox holding the list's scroll view. */
  if ([contentView isKindOfClass: [NSBox class]]
    && [[(NSBox *)contentView contentView] isKindOfClass: [NSScrollView class]])
    {
      scrollView = (NSScrollView *)[(NSBox *)contentView contentView];
    }
  if (scrollView == nil)
    {
      return;
    }

  popover = [[GnomeThemeDropDownPopoverView alloc] initWithFrame: [contentView frame]];
  [popover setAutoresizesSubviews: YES];
  RETAIN (scrollView);
  [scrollView removeFromSuperview];
  [scrollView setFrame: NSInsetRect ([popover bounds], 0.0, GnomeThemeDropDownListPadding)];
  [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [popover addSubview: scrollView];
  RELEASE (scrollView);
  [window setContentView: popover];
  RELEASE (popover);
  [window setBackgroundColor: [NSColor clearColor]];
  [window setAcceptsMouseMovedEvents: YES];
}

/* A sidebar table's window sends it the pointer's moves (for the hover
   pill), and its scroll view shows what is behind it. */
static void
GnomeThemePrepareSidebarTable(NSTableView *tableView)
{
  if (GnomeThemeTableListStyle (tableView) != GnomeThemeListStyleSidebar)
    {
      return;
    }
  if ([tableView window] != nil && [[tableView window] acceptsMouseMovedEvents] == NO)
    {
      [[tableView window] setAcceptsMouseMovedEvents: YES];
    }
  if ([tableView enclosingScrollView] != nil
    && [[tableView enclosingScrollView] documentView] == tableView
    && [[tableView enclosingScrollView] drawsBackground])
    {
      [[tableView enclosingScrollView] setDrawsBackground: NO];
    }
}

@implementation GnomeTheme (ListsOverrides)

/* Drop-down rows: the chosen one's checkmark after the cells. */
- (void) drawTableViewRow: (NSInteger)rowIndex
                 clipRect: (NSRect)clipRect
                   inView: (NSTableView *)tableView
{
  [super drawTableViewRow: rowIndex clipRect: clipRect inView: tableView];
  if (GnomeThemeTableListStyle (tableView) == GnomeThemeListStyleDropDown
    && [tableView isRowSelected: rowIndex])
    {
      GnomeThemeDrawDropDownCheckmark (self, tableView, rowIndex);
    }
}

/* Cells sit inside the pills and their padding: from the first column's
   start and the last column's end (also for editing and hit testing). A
   drop-down row keeps room for its checkmark. */
- (NSRect) _overrideNSTableViewMethod_frameOfCellAtColumn: (NSInteger)column
                                                      row: (NSInteger)row
{
  typedef NSRect (*FrameIMP)(id, SEL, NSInteger, NSInteger);
  FrameIMP originalIMP = (FrameIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTableView class]);
  NSRect frame = (originalIMP != NULL) ? originalIMP (self, _cmd, column, row) : NSZeroRect;
  NSTableView *tableView = (NSTableView *)self;
  GnomeThemeListStyle style = GnomeThemeTableListStyle (tableView);
  CGFloat lead, trail;

  if (style == GnomeThemeListStyleNone)
    {
      return frame;
    }
  if (style == GnomeThemeListStyleDropDown)
    {
      lead = GnomeThemeListPillInset + GnomeThemeDropDownRowPaddingX;
      trail = GnomeThemeListPillInset + GnomeThemeDropDownRowPaddingX
        + GnomeThemeDropDownCheckSpacing + GnomeThemeDropDownCheckSize;
    }
  else
    {
      lead = GnomeThemeListPillInset + GnomeThemeSidebarRowPaddingX;
      trail = lead;
    }
  /* Without libs-gui's 2pt either side for a grid, which isn't drawn. */
  if (NSIsEmptyRect (frame) == NO)
    {
      NSRect columnRect = [tableView rectOfColumn: column];
      CGFloat spacing = [tableView intercellSpacing].width;

      frame.origin.x = NSMinX (columnRect) + spacing / 2.0;
      frame.size.width = NSWidth (columnRect) - spacing;
    }
  if (column == 0)
    {
      frame.origin.x += lead;
      frame.size.width -= lead;
    }
  if (column == [tableView numberOfColumns] - 1)
    {
      frame.size.width -= trail;
    }
  frame.size.width = MAX (0.0, frame.size.width);
  return frame;
}

/* What is behind a list shows through it. */
- (BOOL) _overrideNSTableViewMethod_isOpaque
{
  typedef BOOL (*OpaqueIMP)(id, SEL);
  OpaqueIMP originalIMP = (OpaqueIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTableView class]);

  if (GnomeThemeTableListStyle ((NSTableView *)self) != GnomeThemeListStyleNone)
    {
      return NO;
    }
  return (originalIMP != NULL) ? originalIMP (self, _cmd) : YES;
}

- (void) _overrideNSTableViewMethod_mouseMoved: (NSEvent *)event
{
  typedef void (*MovedIMP)(id, SEL, NSEvent *);
  MovedIMP originalIMP = (MovedIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTableView class]);
  NSTableView *tableView = (NSTableView *)self;

  if (GnomeThemeTableListStyle (tableView) != GnomeThemeListStyleNone)
    {
      NSPoint point = [tableView convertPoint: [event locationInWindow] fromView: nil];
      NSInteger row = NSPointInRect (point, [tableView visibleRect]) ? [tableView rowAtPoint: point] : -1;

      [[GnomeThemeListHoverTracker sharedTracker] setTable: (row >= 0) ? tableView : nil
                                                       row: row];
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, event);
    }
}

- (void) _overrideNSTableViewMethod_setSelectionHighlightStyle: (NSTableViewSelectionHighlightStyle)style
{
  typedef void (*SetStyleIMP)(id, SEL, NSTableViewSelectionHighlightStyle);
  SetStyleIMP originalIMP = (SetStyleIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTableView class]);

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, style);
    }
  GnomeThemePrepareSidebarTable ((NSTableView *)self);
  [(NSTableView *)self setNeedsDisplay: YES];
}

- (void) _overrideNSTableViewMethod_viewDidMoveToWindow
{
  typedef void (*MovedIMP)(id, SEL);
  MovedIMP originalIMP = (MovedIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTableView class]);

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if ((NSTableView *)self == GnomeThemeHoverTable)
    {
      [[GnomeThemeListHoverTracker sharedTracker] setTable: nil row: -1];
    }
  GnomeThemePrepareSidebarTable ((NSTableView *)self);
}

/* GSComboWindow, private to libs-gui: a popover (NSUtilityWindowMask on a
   borderless window, as the theme's menus) so a libs-back with popover
   shadows draws one round it; only with the header bar. */
- (id) _overrideGSComboWindowMethod_initWithContentRect: (NSRect)contentRect
                                              styleMask: (NSUInteger)style
                                                backing: (NSBackingStoreType)backing
                                                  defer: (BOOL)flag
{
  typedef id (*InitIMP)(id, SEL, NSRect, NSUInteger, NSBackingStoreType, BOOL);
  InitIMP originalIMP = (InitIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSComboWindow"));
  id window;

  if (style == NSBorderlessWindowMask && GnomeThemeUsesHeaderBar ())
    {
      style |= NSUtilityWindowMask;
    }
  window = (originalIMP != NULL) ? originalIMP (self, _cmd, contentRect, style, backing, flag) : self;
  if (window != nil)
    {
      GnomeThemeInstallDropDownPopover ((NSWindow *)window);
    }
  return window;
}

/* GtkDropDown's popover size: as wide as the field, or as its longest
   item needs (at least 120pt), and the rows' height with 6pt above and
   below. */
- (void) _overrideGSComboWindowMethod_layoutWithComboBoxCell: (NSComboBoxCell *)cell
{
  typedef void (*LayoutIMP)(id, SEL, NSComboBoxCell *);
  LayoutIMP originalIMP = (LayoutIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSComboWindow"));
  NSWindow *window = (NSWindow *)self;
  NSView *controlView = [cell controlView];
  Ivar frameIvar = class_getInstanceVariable ([NSComboBoxCell class], "_lastValidFrame");
  NSRect cellFrame = (frameIvar != NULL)
    ? *(NSRect *)((char *)cell + ivar_getOffset (frameIvar)) : [controlView bounds];
  NSInteger count = [cell numberOfItems];
  NSInteger shown = MAX (1, MIN (count, [cell numberOfVisibleItems]));
  CGFloat rowHeight = [cell itemHeight];
  NSDictionary *attributes = nil;
  CGFloat widest = 0.0;
  CGFloat width, height;
  NSInteger index;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, cell);
    }
  if ([cell font] != nil)
    {
      attributes = [NSDictionary dictionaryWithObject: [cell font] forKey: NSFontAttributeName];
    }
  for (index = 0; index < count && index < 2000; index++)
    {
      NSString *string = [cell _stringValueAtIndex: index];

      if (string != nil)
        {
          widest = MAX (widest, [string sizeWithAttributes: attributes].width);
        }
    }
  width = 2.0 * (GnomeThemeListPillInset + GnomeThemeDropDownRowPaddingX)
    + ceil (widest) + GnomeThemeDropDownCheckSpacing + GnomeThemeDropDownCheckSize;
  if (count > shown && GnomeThemeUsesOverlayScrollers () == NO)
    {
      width += [NSScroller scrollerWidth];
    }
  width = MAX (MAX (width, GnomeThemeDropDownMinWidth), NSWidth (cellFrame));
  height = 2.0 * GnomeThemeDropDownListPadding + shown * rowHeight;
  [window setFrame: [window frameRectForContentRect: NSMakeRect (0.0, 0.0, width, height)]
           display: NO];
}

/* Below the field, its left edges lined up, 2pt down; above it when there
   is no room below. */
- (void) _overrideGSComboWindowMethod_positionWithComboBoxCell: (NSComboBoxCell *)cell
{
  NSWindow *window = (NSWindow *)self;
  NSView *controlView = [cell controlView];
  NSWindow *parent = [controlView window];
  Ivar frameIvar = class_getInstanceVariable ([NSComboBoxCell class], "_lastValidFrame");
  NSRect cellFrame = (frameIvar != NULL)
    ? *(NSRect *)((char *)cell + ivar_getOffset (frameIvar)) : [controlView bounds];
  NSRect fieldInWindow, frame, visible;
  NSPoint bottomLeft, topLeft;

  [(id)window layoutWithComboBoxCell: cell];
  frame = [window frame];
  if (parent == nil || NSIsEmptyRect (frame))
    {
      return;
    }
  fieldInWindow = [controlView convertRect: cellFrame toView: nil];
  bottomLeft = [parent convertBaseToScreen: fieldInWindow.origin];
  topLeft = [parent convertBaseToScreen: NSMakePoint (NSMinX (fieldInWindow), NSMaxY (fieldInWindow))];
  visible = [[parent screen] visibleFrame];

  frame.origin.x = bottomLeft.x;
  frame.origin.y = MIN (bottomLeft.y, topLeft.y) - GnomeThemeDropDownGap - NSHeight (frame);
  if (NSIsEmptyRect (visible) == NO)
    {
      if (NSMinY (frame) < NSMinY (visible)
        && MAX (bottomLeft.y, topLeft.y) + GnomeThemeDropDownGap + NSHeight (frame) <= NSMaxY (visible))
        {
          frame.origin.y = MAX (bottomLeft.y, topLeft.y) + GnomeThemeDropDownGap;
        }
      frame.origin.x = MAX (NSMinX (visible), MIN (NSMinX (frame), NSMaxX (visible) - NSWidth (frame)));
    }
  [window setFrame: frame display: NO];
}

@end
