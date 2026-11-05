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

/* A toolbar too narrow for its items: the » menu takes them by
   visibilityPriority, lowest first and right to left within one, as
   WinUITheme does (libs-gui took them from the end). A separator goes
   with the item on its left, the items kept are side by side, the others
   hidden, and the » menu lists them in the toolbar's order. Items that
   went before a wide one with their priority come back when they fit.
   With every item Standard, the toolbar is as libs-gui lays it out.
   Dragging while customising puts an item where the pointer is among the
   items kept. */

#import "QuirkProbe.h"

#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>

@interface QuirkProbe (ToolbarOverflowResults)
- (void) pass: (NSString *)ident detail: (NSString *)detail;
- (void) fail: (NSString *)ident detail: (NSString *)detail;
- (void) skip: (NSString *)ident detail: (NSString *)detail;
- (void) saveWindow: (NSWindow *)window named: (NSString *)name;
- (NSWindow *) windowWithFrame: (NSRect)frame title: (NSString *)title;
@end

@interface NSToolbar (QuirkProbeToolbarOverflowPrivate)
- (NSView *) _toolbarView;
@end

@interface NSToolbarItem (QuirkProbeToolbarOverflowPrivate)
- (NSView *) _backView;
@end

@interface NSView (QuirkProbeToolbarOverflowPrivate)
- (NSMenu *) overflowMenu;
- (int) _insertionIndexAtPoint: (NSPoint)location;
@end

@interface NSObject (QuirkProbeToolbarOverflowDragPrivate)
+ (void) setDraggedItemIndex: (NSUInteger)index;
@end

/* Each item an 80pt slot as libs-gui counts it: a 60pt view and its 10pt
   insets, or `widths`' view width. `identifiers` in order; `priorities`
   by identifier, Standard when absent. */
@interface QuirkProbeOverflowToolbarDelegate : NSObject
{
@public
  NSArray *identifiers;
  NSDictionary *priorities;
  NSDictionary *widths;
}
@end

@implementation QuirkProbeOverflowToolbarDelegate

- (void) dealloc
{
  RELEASE (identifiers);
  RELEASE (priorities);
  RELEASE (widths);
  [super dealloc];
}

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = AUTORELEASE ([[NSToolbarItem alloc] initWithItemIdentifier: identifier]);
  CGFloat width = [widths objectForKey: identifier] ? [[widths objectForKey: identifier] doubleValue] : 60.0;
  NSButton *button = AUTORELEASE ([[NSButton alloc] initWithFrame: NSMakeRect (0, 0, width, 24)]);

  [button setTitle: identifier];
  [item setLabel: identifier];
  [item setView: button];
  [item setMinSize: NSMakeSize (width, 24)];
  [item setMaxSize: NSMakeSize (width, 24)];
  [item setVisibilityPriority: [[priorities objectForKey: identifier] integerValue]];
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return identifiers;
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return identifiers;
}

@end

/* ScreenshotTool 0.3.2's toolbar: Tools, Colour and Copy never go
   (the app's minimum width; User here), Save and Share are High, its
   custom actions Standard, Undo and Redo Low. */
static NSArray *
QuirkProbeOverflowScreenshotToolItems(void)
{
  return [NSArray arrayWithObjects: @"Undo", @"Redo", @"Tools", @"Colour", NSToolbarFlexibleSpaceItemIdentifier,
                  @"Save", @"Copy", @"Share", @"Action", nil];
}

static NSDictionary *
QuirkProbeOverflowScreenshotToolPriorities(void)
{
  NSNumber *low = [NSNumber numberWithInteger: NSToolbarItemVisibilityPriorityLow];
  NSNumber *high = [NSNumber numberWithInteger: NSToolbarItemVisibilityPriorityHigh];
  NSNumber *user = [NSNumber numberWithInteger: NSToolbarItemVisibilityPriorityUser];

  return [NSDictionary dictionaryWithObjectsAndKeys: low, @"Undo", low, @"Redo", user, @"Tools", user, @"Colour",
                       high, @"Save", user, @"Copy", high, @"Share", nil];
}

/* What a toolbar shows: the items kept (as -visibleItems), those hidden,
   the » menu's titles, and the problems with how the kept ones are
   placed (side by side from the start, outside the toolbar's
   header-bar title space). */
typedef struct
{
  NSString *kept;
  NSString *hidden;
  NSString *menu;
  NSString *placement;
  CGFloat width;
} QuirkProbeOverflowState;

static NSString *
QuirkProbeOverflowName(NSToolbarItem *item)
{
  NSString *identifier = [item itemIdentifier];

  if ([identifier isEqualToString: NSToolbarFlexibleSpaceItemIdentifier])
    {
      return @"~";
    }
  if ([identifier isEqualToString: NSToolbarSeparatorItemIdentifier])
    {
      return @"|";
    }
  return identifier;
}

/* ScreenshotTool's Tools: nine segments, a 300pt view here. */
static NSDictionary *
QuirkProbeOverflowWideTools(void)
{
  return [NSDictionary dictionaryWithObject: [NSNumber numberWithDouble: 300.0] forKey: @"Tools"];
}

static QuirkProbeOverflowState
QuirkProbeOverflowStateOf(NSToolbar *toolbar, BOOL contiguous)
{
  QuirkProbeOverflowState state;
  NSView *toolbarView = [toolbar _toolbarView];
  NSArray *visible = [toolbar visibleItems];
  NSMutableArray *kept = [NSMutableArray array], *hidden = [NSMutableArray array];
  NSMutableArray *titles = [NSMutableArray array], *problems = [NSMutableArray array];
  NSEnumerator *enumerator = [[toolbar items] objectEnumerator];
  NSToolbarItem *item;
  NSView *subview, *mark = nil;
  NSMenu *menu;
  CGFloat x = -1.0;
  NSInteger i;
  BOOL afterSpace = NO;

  while ((item = [enumerator nextObject]) != nil)
    {
      NSView *backView = [item _backView];
      NSRect frame = [backView frame];

      if ([visible containsObject: item])
        {
          [kept addObject: QuirkProbeOverflowName (item)];
          if ([backView isHidden])
            {
              [problems addObject: [NSString stringWithFormat: @"%@ hidden", QuirkProbeOverflowName (item)]];
            }
          /* After the header bar's title space, the items end at the
             end: a gap, never an overlap. */
          if (contiguous && x >= 0.0 && (afterSpace ? NSMinX (frame) < x - 0.5 : fabs (NSMinX (frame) - x) > 0.5))
            {
              [problems addObject: [NSString stringWithFormat: @"%@ at %g, not %g",
                QuirkProbeOverflowName (item), NSMinX (frame), x]];
            }
          if (contiguous && x < 0.0 && NSMinX (frame) > 0.5)
            {
              [problems addObject: [NSString stringWithFormat: @"%@ at %g, not 0", QuirkProbeOverflowName (item), NSMinX (frame)]];
            }
          x = NSMaxX (frame);
          afterSpace = [[item itemIdentifier] isEqualToString: NSToolbarFlexibleSpaceItemIdentifier];
        }
      else
        {
          [hidden addObject: QuirkProbeOverflowName (item)];
        }
    }
  enumerator = [[toolbarView subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview respondsToSelector: @selector(overflowMenu)])
        {
          mark = subview;
        }
    }
  if (mark != nil)
    {
      menu = [mark overflowMenu];
      for (i = 0; i < [menu numberOfItems]; i++)
        {
          [titles addObject: [[menu itemAtIndex: i] title]];
        }
    }
  /* Every item kept is visible, the others aren't: hidden, or past the
     clip view's end as libs-gui leaves them. */
  enumerator = [[toolbarView subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview isKindOfClass: [NSClipView class]] == NO)
        {
          continue;
        }
      enumerator = [[toolbar items] objectEnumerator];
      while ((item = [enumerator nextObject]) != nil)
        {
          NSView *backView = [item _backView];
          BOOL shown = [backView isHidden] == NO && NSMinX ([backView frame]) < NSWidth ([subview frame]) - 0.5;

          if ([visible containsObject: item] == NO && shown && NSWidth ([backView frame]) > 0.5)
            {
              [problems addObject: [NSString stringWithFormat: @"%@ (in the » menu) shown", QuirkProbeOverflowName (item)]];
            }
          if ([visible containsObject: item] && NSMaxX ([backView frame]) > NSWidth ([subview frame]) + 0.5)
            {
              [problems addObject: [NSString stringWithFormat: @"%@ clipped", QuirkProbeOverflowName (item)]];
            }
        }
      break;
    }
  state.kept = [kept componentsJoinedByString: @" "];
  state.hidden = [hidden componentsJoinedByString: @" "];
  state.menu = mark != nil && [mark superview] != nil ? [titles componentsJoinedByString: @" "] : @"(no »)";
  state.placement = [problems count] ? [problems componentsJoinedByString: @", "] : @"ok";
  state.width = NSWidth ([toolbarView frame]);
  return state;
}

static NSString *
QuirkProbeOverflowDescription(QuirkProbeOverflowState state)
{
  return [NSString stringWithFormat: @"toolbar %g: kept %@; » menu %@; placement %@",
    state.width, state.kept, state.menu, state.placement];
}

void QuirkProbeFillWithBackground (NSBitmapImageRep *rep, NSView *view);

/* The » mark drawn alone: the darkest and lightest grey levels (0 to
   255) of its opaque pixels, the mark's ink and what is behind it in
   either order; -1 with no mark. */
static CGFloat
QuirkProbeOverflowMarkInk(NSToolbar *toolbar, CGFloat *lightest)
{
  NSEnumerator *enumerator = [[[toolbar _toolbarView] subviews] objectEnumerator];
  NSView *subview, *mark = nil;
  NSBitmapImageRep *rep;
  NSInteger x, y;
  CGFloat darkest = -1.0;

  *lightest = -1.0;
  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview respondsToSelector: @selector(overflowMenu)] && [subview superview] != nil)
        {
          mark = subview;
        }
    }
  if (mark == nil)
    {
      return -1.0;
    }
  rep = [mark bitmapImageRepForCachingDisplayInRect: [mark bounds]];
  QuirkProbeFillWithBackground (rep, mark);
  [mark cacheDisplayInRect: [mark bounds] toBitmapImageRep: rep];
  for (y = 0; y < [rep pixelsHigh]; y++)
    {
      for (x = 0; x < [rep pixelsWide]; x++)
        {
          NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
          CGFloat grey;

          if (color == nil || [color alphaComponent] < 0.5)
            {
              continue;
            }
          grey = 255.0 * (0.299 * [color redComponent] + 0.587 * [color greenComponent]
                          + 0.114 * [color blueComponent]);
          darkest = darkest < 0.0 ? grey : MIN (darkest, grey);
          *lightest = MAX (*lightest, grey);
        }
    }
  return darkest;
}

@implementation QuirkProbe (ToolbarOverflow)

/* The » mark in the text colour, so it shows on what is behind it in the
   dark style too: libs-gui's is black (#83). */
- (void) checkOverflowMark: (NSString *)ident
{
  NSWindow *window;
  NSToolbar *toolbar = [self overflowToolbarIn: &window identifiers: QuirkProbeOverflowScreenshotToolItems ()
                                    priorities: QuirkProbeOverflowScreenshotToolPriorities () width: 500.0 name: ident];
  CGFloat lightest = -1.0;
  CGFloat darkest = QuirkProbeOverflowMarkInk (toolbar, &lightest);
  NSString *detail = [NSString stringWithFormat: @"» greys %.0f to %.0f (want 90 apart)", darkest, lightest];

  [self saveWindow: window named: ident];
  [window orderOut: nil];
  if (darkest >= 0.0 && lightest - darkest >= 90.0)
    {
      [self pass: ident detail: detail];
    }
  else
    {
      [self fail: ident detail: darkest < 0.0 ? @"no » drawn" : detail];
    }
}

/* A window holding a toolbar of `identifiers`, its toolbar `width` wide. */
- (NSToolbar *) overflowToolbarIn: (NSWindow **)windowOut
                      identifiers: (NSArray *)identifiers
                       priorities: (NSDictionary *)priorities
                            width: (CGFloat)width
                             name: (NSString *)name
{
  return [self overflowToolbarIn: windowOut identifiers: identifiers priorities: priorities
                      itemWidths: nil width: width name: name];
}

- (NSToolbar *) overflowToolbarIn: (NSWindow **)windowOut
                      identifiers: (NSArray *)identifiers
                       priorities: (NSDictionary *)priorities
                       itemWidths: (NSDictionary *)itemWidths
                            width: (CGFloat)width
                             name: (NSString *)name
{
  static int serial = 0;
  QuirkProbeOverflowToolbarDelegate *delegate = AUTORELEASE ([QuirkProbeOverflowToolbarDelegate new]);
  NSWindow *window = [self windowWithFrame: NSMakeRect (40, 200, width, 160) title: name];
  NSString *identifier = [NSString stringWithFormat: @"QuirkProbeOverflow%d", serial++];
  NSToolbar *toolbar = AUTORELEASE ([[NSToolbar alloc] initWithIdentifier: identifier]);
  NSSize content;

  ASSIGN (delegate->identifiers, identifiers);
  ASSIGN (delegate->priorities, priorities);
  ASSIGN (delegate->widths, itemWidths);
  /* The window keeps it: a toolbar doesn't retain its delegate. */
  objc_setAssociatedObject (window, &serial, delegate, OBJC_ASSOCIATION_RETAIN);
  [toolbar setDisplayMode: NSToolbarDisplayModeIconOnly];
  [toolbar setDelegate: delegate];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  [window display];
  /* The toolbar `width` wide: the header bar's toolbar is narrower than
     the window, by its buttons. */
  content = [[window contentView] frame].size;
  content.width += width - NSWidth ([[toolbar _toolbarView] frame]);
  [window setContentSize: content];
  [window display];
  *windowOut = window;
  return toolbar;
}

- (void) checkOverflowCase: (NSString *)ident
               identifiers: (NSArray *)identifiers
                priorities: (NSDictionary *)priorities
                     width: (CGFloat)width
                      kept: (NSString *)kept
                      menu: (NSString *)menu
                contiguous: (BOOL)contiguous
{
  [self checkOverflowCase: ident identifiers: identifiers priorities: priorities itemWidths: nil
                    width: width kept: kept menu: menu contiguous: contiguous];
}

- (void) checkOverflowCase: (NSString *)ident
               identifiers: (NSArray *)identifiers
                priorities: (NSDictionary *)priorities
                itemWidths: (NSDictionary *)itemWidths
                     width: (CGFloat)width
                      kept: (NSString *)kept
                      menu: (NSString *)menu
                contiguous: (BOOL)contiguous
{
  NSWindow *window;
  NSToolbar *toolbar = [self overflowToolbarIn: &window identifiers: identifiers priorities: priorities
                                    itemWidths: itemWidths width: width name: ident];
  QuirkProbeOverflowState state = QuirkProbeOverflowStateOf (toolbar, contiguous);
  NSString *detail = QuirkProbeOverflowDescription (state);

  [self saveWindow: window named: ident];
  [window orderOut: nil];
  if (fabs (state.width - width) < 0.5 && [state.kept isEqualToString: kept] && [state.menu isEqualToString: menu]
    && [state.placement isEqualToString: @"ok"])
    {
      [self pass: ident detail: detail];
    }
  else
    {
      [self fail: ident detail: [NSString stringWithFormat: @"%@ (expected kept %@; » menu %@)", detail, kept, menu]];
    }
}

/* Over a range of widths: no item kept while one of lower priority, or
   (with every item the same width, so none comes back) of the same
   priority further right, is in the » menu, and the kept items placed as
   above. With `itemWidths`, items of the same priority come back. */
- (void) checkOverflowSweep: (NSString *)ident contiguous: (BOOL)contiguous
{
  [self checkOverflowSweep: ident contiguous: contiguous itemWidths: nil];
}

- (void) checkOverflowSweep: (NSString *)ident contiguous: (BOOL)contiguous itemWidths: (NSDictionary *)itemWidths
{
  NSArray *identifiers = QuirkProbeOverflowScreenshotToolItems ();
  NSDictionary *priorities = QuirkProbeOverflowScreenshotToolPriorities ();
  NSMutableArray *failures = [NSMutableArray array];
  int overflowed = 0;
  CGFloat width;

  for (width = 160.0; width <= (itemWidths != nil ? 1000.0 : 760.0); width += 20.0)
    {
      NSWindow *window;
      NSToolbar *toolbar = [self overflowToolbarIn: &window identifiers: identifiers priorities: priorities
                                        itemWidths: itemWidths width: width name: ident];
      QuirkProbeOverflowState state = QuirkProbeOverflowStateOf (toolbar, contiguous);
      NSArray *visible = [toolbar visibleItems];
      NSArray *items = [toolbar items];
      NSUInteger i, j;

      if ([visible count] < [items count])
        {
          overflowed++;
        }
      for (i = 0; i < [items count]; i++)
        {
          NSToolbarItem *dropped = [items objectAtIndex: i];

          if ([visible containsObject: dropped] || [dropped view] == nil)
            {
              continue;
            }
          for (j = 0; j < [items count]; j++)
            {
              NSToolbarItem *other = [items objectAtIndex: j];

              if ([visible containsObject: other] && [other view] != nil
                && ([other visibilityPriority] < [dropped visibilityPriority]
                    || (itemWidths == nil && [other visibilityPriority] == [dropped visibilityPriority] && j > i)))
                {
                  [failures addObject: [NSString stringWithFormat: @"%g: %@ kept, %@ in the »", width,
                    [other itemIdentifier], [dropped itemIdentifier]]];
                }
            }
        }
      if ([state.placement isEqualToString: @"ok"] == NO)
        {
          [failures addObject: [NSString stringWithFormat: @"%g: %@", width, state.placement]];
        }
      [window orderOut: nil];
    }
  if (overflowed > 0 && [failures count] == 0)
    {
      [self pass: ident detail: [NSString stringWithFormat: @"%d widths with », by priority", overflowed]];
    }
  else
    {
      [self fail: ident detail: [NSString stringWithFormat: @"%d widths with »: %@", overflowed,
        [failures componentsJoinedByString: @"; "]]];
    }
}

- (void) checkToolbarPriorityOverflow
{
  NSArray *screenshotTool = QuirkProbeOverflowScreenshotToolItems ();
  NSArray *separated = [NSArray arrayWithObjects: @"A", NSToolbarSeparatorItemIdentifier, @"B",
                                NSToolbarSeparatorItemIdentifier, @"C", @"D", nil];
  NSDictionary *lowB = [NSDictionary dictionaryWithObject: [NSNumber numberWithInteger: NSToolbarItemVisibilityPriorityLow]
                                                   forKey: @"B"];
  NSDictionary *lowA = [NSDictionary dictionaryWithObject: [NSNumber numberWithInteger: NSToolbarItemVisibilityPriorityLow]
                                                   forKey: @"A"];
  NSWindow *window;
  NSToolbar *toolbar;
  CGFloat separator, width;

  /* At 500pt (472pt beside the »), 640pt of items: Redo, Undo, then
     Action (Standard) go; at 420pt, Share too (the High item
     furthest right). libs-gui kept Undo to Save. */
  [self checkOverflowCase: @"toolbar-overflow-priority"
              identifiers: screenshotTool
               priorities: QuirkProbeOverflowScreenshotToolPriorities ()
                    width: 500.0
                     kept: @"Tools Colour ~ Save Copy Share"
                     menu: @"Undo Redo Action"
               contiguous: YES];
  [self checkOverflowCase: @"toolbar-overflow-priority-high"
              identifiers: screenshotTool
               priorities: QuirkProbeOverflowScreenshotToolPriorities ()
                    width: 420.0
                     kept: @"Tools Colour ~ Save Copy"
                     menu: @"Undo Redo Share Action"
               contiguous: YES];
  /* Every item Standard: the items from the start, as libs-gui keeps
     them. */
  [self checkOverflowCase: @"toolbar-overflow-standard"
              identifiers: screenshotTool
               priorities: [NSDictionary dictionary]
                    width: 500.0
                     kept: @"Undo Redo Tools Colour ~ Save"
                     menu: @"Copy Share Action"
               contiguous: NO];
  [self checkOverflowCase: @"toolbar-overflow-wide"
              identifiers: screenshotTool
               priorities: QuirkProbeOverflowScreenshotToolPriorities ()
                    width: 760.0
                     kept: @"Undo Redo Tools Colour ~ Save Copy Share Action"
                     menu: @"(no »)"
               contiguous: NO];

  /* A separator goes with the item on its left: B and the separator after
     it, leaving A | C D; A going takes its separator too. Room for all
     but B and one separator (10pt to spare). */
  toolbar = [self overflowToolbarIn: &window identifiers: separated priorities: lowB width: 600.0
                               name: @"toolbar-overflow-separator-probe"];
  separator = NSWidth ([[[[toolbar items] objectAtIndex: 1] _backView] frame]);
  [window orderOut: nil];
  width = floor (4.0 * 80.0 + 2.0 * separator - 80.0 - separator + 28.0 + 10.0);
  [self checkOverflowCase: @"toolbar-overflow-separator"
              identifiers: separated
               priorities: lowB
                    width: width
                     kept: @"A | C D"
                     menu: @"B"
               contiguous: YES];
  [self checkOverflowCase: @"toolbar-overflow-leading-separator"
              identifiers: separated
               priorities: lowA
                    width: width
                     kept: @"B | C D"
                     menu: @"A"
               contiguous: YES];

  [self checkOverflowSweep: @"toolbar-overflow-sweep" contiguous: YES];

  /* With a 320pt Tools (a 300pt view): at 300pt (272pt beside the »),
     Copy, Colour and then Tools go, the User items; Colour and Copy fit
     again without Tools and come back. Save and Share (High) stay in the
     ». The rule kept only the flexible space. */
  [self checkOverflowCase: @"toolbar-overflow-same-priority-returns"
              identifiers: screenshotTool
               priorities: QuirkProbeOverflowScreenshotToolPriorities ()
               itemWidths: QuirkProbeOverflowWideTools ()
                    width: 300.0
                     kept: @"Colour ~ Copy"
                     menu: @"Undo Redo Tools Save Share Action"
               contiguous: YES];
  [self checkOverflowSweep: @"toolbar-overflow-sweep-wide" contiguous: YES itemWidths: QuirkProbeOverflowWideTools ()];

  [self checkToolbarOverflowDragIndex];
  [self checkOverflowMark: @"toolbar-overflow-mark"];
}

/* Where -_insertionIndexAtPoint: puts an item dragged while customising,
   at `point` (in the window), with `dragged` the index of the item being
   dragged (NSNotFound for a new one): the name of the item it ends up
   before ("end" for the last). */
static NSString *
QuirkProbeOverflowDropBefore(NSToolbar *toolbar, NSUInteger dragged, NSPoint point)
{
  NSView *toolbarView = [toolbar _toolbarView];
  Class toolbarViewClass = NSClassFromString (@"GSToolbarView");
  NSMutableArray *names = [NSMutableArray array];
  NSEnumerator *enumerator = [[toolbar items] objectEnumerator];
  NSToolbarItem *item;
  NSUInteger index;

  while ((item = [enumerator nextObject]) != nil)
    {
      [names addObject: QuirkProbeOverflowName (item)];
    }
  [toolbarViewClass setDraggedItemIndex: dragged];
  index = (NSUInteger)[toolbarView _insertionIndexAtPoint: point];
  [toolbarViewClass setDraggedItemIndex: NSNotFound];
  /* As -[NSToolbar _moveItemFromIndex:toIndex:...]: out, then in. */
  if (dragged != NSNotFound)
    {
      [names removeObjectAtIndex: dragged];
    }
  return index < [names count] ? [names objectAtIndex: index] : @"end";
}

/* A point in the window `offset` points from `name`'s slot's left edge
   (its right edge when negative). */
static NSPoint
QuirkProbeOverflowPointAt(NSToolbar *toolbar, NSString *name, CGFloat offset)
{
  NSEnumerator *enumerator = [[toolbar items] objectEnumerator];
  NSToolbarItem *item;

  while ((item = [enumerator nextObject]) != nil)
    {
      if ([QuirkProbeOverflowName (item) isEqualToString: name])
        {
          NSView *backView = [item _backView];
          NSRect frame = [backView frame];
          NSPoint point = NSMakePoint (offset >= 0.0 ? NSMinX (frame) + offset : NSMaxX (frame) + offset, NSMidY (frame));

          return [[backView superview] convertPoint: point toView: nil];
        }
    }
  return NSZeroPoint;
}

/* ScreenshotTool's toolbar at 500pt keeps Tools Colour ~ Save Copy Share
   (indexes 2 to 7), Undo, Redo and Action in the ». libs-gui took a
   position among the kept items for an index among all of them. */
- (void) checkToolbarOverflowDragIndex
{
  NSString *ident = @"toolbar-overflow-drag-index";
  NSArray *identifiers = QuirkProbeOverflowScreenshotToolItems ();
  NSWindow *window;
  NSToolbar *toolbar;
  NSMutableArray *failures = [NSMutableArray array];
  NSString *got;
  struct { NSString *what; NSUInteger dragged; NSString *at; CGFloat offset; NSString *expected; } cases[] = {
    { @"new item at Save's left", NSNotFound, @"Save", 2.0, @"Save" },
    { @"new item at Share's right", NSNotFound, @"Share", -2.0, @"Action" },
    { @"Copy to Tools' left", 6, @"Tools", 2.0, @"Tools" },
    { @"Tools to Share's right", 2, @"Share", -2.0, @"Action" },
    { @"Colour a little right", 3, @"Colour", 50.0, @"~" },
    { @"Undo (in the ») to Save's left", 0, @"Save", 2.0, @"Save" },
  };
  NSUInteger i;

  if (NSClassFromString (@"GSToolbarView") == Nil
    || [NSClassFromString (@"GSToolbarView") respondsToSelector: @selector (setDraggedItemIndex:)] == NO)
    {
      [self skip: ident detail: @"no +[GSToolbarView setDraggedItemIndex:]"];
      return;
    }
  toolbar = [self overflowToolbarIn: &window identifiers: identifiers
                         priorities: QuirkProbeOverflowScreenshotToolPriorities () width: 500.0 name: ident];
  if ([[[toolbar visibleItems] valueForKey: @"itemIdentifier"] count] != 6)
    {
      [self fail: ident detail: QuirkProbeOverflowDescription (QuirkProbeOverflowStateOf (toolbar, YES))];
      [window orderOut: nil];
      return;
    }
  for (i = 0; i < sizeof (cases) / sizeof (cases[0]); i++)
    {
      got = QuirkProbeOverflowDropBefore (toolbar, cases[i].dragged,
                                          QuirkProbeOverflowPointAt (toolbar, cases[i].at, cases[i].offset));
      if ([got isEqualToString: cases[i].expected] == NO)
        {
          [failures addObject: [NSString stringWithFormat: @"%@: before %@, not %@", cases[i].what, got, cases[i].expected]];
        }
    }
  [window orderOut: nil];
  if ([failures count] == 0)
    {
      [self pass: ident detail: [NSString stringWithFormat: @"%lu drops land by the kept items",
        (unsigned long)(sizeof (cases) / sizeof (cases[0]))]];
    }
  else
    {
      [self fail: ident detail: [failures componentsJoinedByString: @"; "]];
    }
}

/* The same in the header bar, with its title in the flexible space: the
   title keeps its room and the items after it end at the ». */
- (void) checkHeaderBarToolbarPriorityOverflow
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *searchList;

  if ([GSCurrentServer () handlesWindowDecorations])
    {
      [self skip: @"header-bar-toolbar-overflow-priority" detail: @"needs -GSX11HandlesWindowDecorations NO"];
      return;
    }
  [defaults setVolatileDomain: [NSDictionary dictionaryWithObject: @"YES" forKey: @"GnomeThemeHeaderBarToolbar"]
                      forName: @"QuirkProbeOverflowHeaderBar"];
  searchList = AUTORELEASE ([[defaults searchList] mutableCopy]);
  [searchList insertObject: @"QuirkProbeOverflowHeaderBar" atIndex: 0];
  [defaults setSearchList: searchList];

  /* At 620pt (592pt beside the »), 740pt with the title's 100pt: Redo
     and Undo go, the title keeps its room. libs-gui kept Undo to Copy. */
  [self checkOverflowCase: @"header-bar-toolbar-overflow-priority"
              identifiers: QuirkProbeOverflowScreenshotToolItems ()
               priorities: QuirkProbeOverflowScreenshotToolPriorities ()
                    width: 620.0
                     kept: @"Tools Colour ~ Save Copy Share Action"
                     menu: @"Undo Redo"
               contiguous: YES];
  [self checkOverflowCase: @"header-bar-toolbar-overflow-standard"
              identifiers: QuirkProbeOverflowScreenshotToolItems ()
               priorities: [NSDictionary dictionary]
                    width: 620.0
                     kept: @"Undo Redo Tools Colour ~ Save Copy"
                     menu: @"Share Action"
               contiguous: NO];
  [self checkOverflowSweep: @"header-bar-toolbar-overflow-sweep" contiguous: YES];
  /* With the title's 100pt, Tools doesn't fit at 400pt; Colour and Copy
     do beside the title. */
  [self checkOverflowCase: @"header-bar-toolbar-overflow-same-priority-returns"
              identifiers: QuirkProbeOverflowScreenshotToolItems ()
               priorities: QuirkProbeOverflowScreenshotToolPriorities ()
               itemWidths: QuirkProbeOverflowWideTools ()
                    width: 400.0
                     kept: @"Colour ~ Copy"
                     menu: @"Undo Redo Tools Save Share Action"
               contiguous: YES];
  [self checkOverflowSweep: @"header-bar-toolbar-overflow-sweep-wide" contiguous: YES
                itemWidths: QuirkProbeOverflowWideTools ()];
  [self checkOverflowMark: @"header-bar-toolbar-overflow-mark"];

  [searchList removeObject: @"QuirkProbeOverflowHeaderBar"];
  [defaults setSearchList: searchList];
  [defaults removeVolatileDomainForName: @"QuirkProbeOverflowHeaderBar"];
}

@end
