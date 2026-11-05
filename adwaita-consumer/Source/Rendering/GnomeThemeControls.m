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

#import "../GnomeTheme.h"
#import "../Settings/GnomeThemeMetrics.h"
#import "../Settings/GnomeThemeSettings.h"
#import "GnomeThemeLists.h"

#import <AppKit/AppKit.h>
#import <AppKit/NSGraphics.h>
#import <GNUstepGUI/GSFontInfo.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import <math.h>

/* GSToolbarButton, private to libs-gui. */
@protocol GnomeThemeToolbarButton
- (NSToolbarItem *) toolbarItem;
@end

/* An item's slot in the toolbar (a GSToolbarButton or GSToolbarBackView),
   private to libs-gui. */
@interface NSToolbarItem (GnomeThemeToolbarPrivate)
- (NSView *) _backView;
@end

/* GSToolbarView, private to libs-gui: the index in the toolbar of the
   item being dragged while customising (NSNotFound for one coming in). */
@interface NSObject (GnomeThemeToolbarViewPrivate)
+ (NSUInteger) draggedItemIndex;
@end

/* Associated-object keys on a toolbar button: its hover tracking-rect tag,
   and whether the pointer is over it. */
static char GnomeThemeToolbarButtonTrackingKey;
static char GnomeThemeToolbarButtonHoverKey;
/* On a toolbar whose display mode is the theme's default, not the app's. */
static char GnomeThemeToolbarDefaultModeKey;

/* Owns toolbar buttons' tracking rects and records hover from their
   enter/exit events. (The window's -mouseLocationOutsideOfEventStream can't
   be used at draw time: it goes stale.) */
@interface GnomeThemeToolbarHoverTracker : NSObject
+ (GnomeThemeToolbarHoverTracker *) sharedTracker;
@end

@implementation GnomeThemeToolbarHoverTracker

+ (GnomeThemeToolbarHoverTracker *) sharedTracker
{
  static GnomeThemeToolbarHoverTracker *tracker = nil;

  if (tracker == nil)
    {
      tracker = [GnomeThemeToolbarHoverTracker new];
    }
  return tracker;
}

- (void) setHover: (BOOL)hover forEvent: (NSEvent *)event
{
  NSView *button = (NSView *)[event userData];

  if (button == nil)
    {
      return;
    }
  objc_setAssociatedObject (button, &GnomeThemeToolbarButtonHoverKey,
                            hover ? [NSNumber numberWithBool: YES] : nil,
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [button setNeedsDisplay: YES];
}

- (void) mouseEntered: (NSEvent *)event
{
  [self setHover: YES forEvent: event];
}

- (void) mouseExited: (NSEvent *)event
{
  [self setHover: NO forEvent: event];
}

@end

@interface NSComboBoxCell (GnomeThemePrivate)
- (void) _didClickWithinButton: (id)sender;
- (void) _performClickWithFrame: (NSRect)cellFrame
                         inView: (NSView *)controlView;
- (id) _popUp;
@end

@interface NSPopUpButtonCell (GnomeThemePrivate)
- (NSImage *) _currentArrowImage;
@end

@interface NSObject (GnomeThemeComboPopupPrivate)
- (void) popUpForComboBoxCell: (NSComboBoxCell *)cell;
@end

@interface NSCell (GnomeThemePrivateEditing)
- (BOOL) _inEditing;
@end

@interface NSGlyphGenerator (GnomeThemePrivateFonts)
- (NSFont *) fontForCharactersWithAttributes: (NSDictionary *)attributes;
@end

/* GTK's password character, ● (GtkText's default invisible character),
   for libs-gui's bullet, •, about half its size. */
#define GnomeThemeSecureCharacter 0x25CF
#define GnomeThemeLibsGuiBullet 0x2022

@interface NSTextFieldCell (GnomeThemePrivateTextDrawing)
- (BOOL) _inEditing;
- (NSAttributedString *) _drawAttributedString;
- (void) _drawBackgroundWithFrame: (NSRect)cellFrame
                            inView: (NSView *)controlView;
- (void) _drawEditorWithFrame: (NSRect)cellFrame
                       inView: (NSView *)controlView;
- (BOOL) _shouldShortenStringForRect: (NSRect)titleRect
                                size: (NSSize)titleSize
                              length: (NSUInteger)length;
- (NSAttributedString *) _resizeAttributedString: (NSAttributedString *)attrstring
                                         forRect: (NSRect)titleRect;
@end

static NSView *GnomeThemeLastFocusedEntryView = nil;

/* Between a checkbox or radio indicator and its label: GTK's checkbutton
   border-spacing, which leaves about 5px before the first glyph. */
static const CGFloat GnomeThemeIndicatorLabelGap = 4.0;

static GnomeTheme *GnomeThemeActiveTheme(void);

/* In the window of `cell`, drawn in `controlView` or nil (#24). */
static CGFloat
GnomeThemeIndicatorMinimumSize(NSCell *cell, NSView *controlView)
{
  GnomeTheme *theme = GnomeThemeActiveTheme ();

  return (theme != nil) ? [[theme metricsForCell: cell inView: controlView] indicatorMinimumSize] : 18.0;
}

/* GTK's focus-visible, a window's own: buttons, checkboxes and other
   non-text controls show their focus ring only after a key press in their
   window, and hide it again on a pointer press there. A dialog opened with
   the mouse, or with a shortcut in another window (LinDirStat's Ctrl+,
   Preferences, #85), shows no ring on its first key view. Text entries
   show theirs whenever they have focus, as in GTK. On a window, its
   NSNumber. */
static char GnomeThemeFocusVisibleKey;

static BOOL
GnomeThemeWindowFocusVisible(NSWindow *window)
{
  return window != nil && [objc_getAssociatedObject (window, &GnomeThemeFocusVisibleKey) boolValue];
}

@interface NSSearchFieldCell (GnomeThemePrivateLayout)
- (NSButtonCell *) cancelButtonCell;
- (NSButtonCell *) searchButtonCell;
- (NSRect) searchButtonRectForBounds: (NSRect)rect;
- (NSRect) cancelButtonRectForBounds: (NSRect)rect;
- (NSRect) searchTextRectForBounds: (NSRect)rect;
@end

static NSRect GnomeThemeCenteredRect(NSRect frame, CGFloat width, CGFloat height);
static NSRect GnomeThemeIndicatorFocusRect(NSButtonCell *cell, NSRect cellFrame);

static inline GnomeTheme *
GnomeThemeActiveTheme(void)
{
  GSTheme *theme = [GSTheme theme];

  if ([theme isKindOfClass: [GnomeTheme class]] == NO)
    {
      return nil;
    }

  return (GnomeTheme *)theme;
}

static inline BOOL
GnomeThemeStateIsDisabled(GSThemeControlState state)
{
  return (state == GSThemeDisabledState);
}

static inline BOOL
GnomeThemeStateIsHighlighted(GSThemeControlState state)
{
  return (state == GSThemeHighlightedState
    || state == GSThemeHighlightedFirstResponderState);
}

static inline BOOL
GnomeThemeStateIsSelected(GSThemeControlState state)
{
  return (state == GSThemeSelectedState
    || state == GSThemeSelectedFirstResponderState);
}

NSColor *
GnomeThemeColor(GSTheme *theme, NSString *key, NSColor *fallback)
{
  NSColor *color = nil;

  if (theme != nil && key != nil)
    {
      color = [[theme colors] colorWithKey: key];
      if (color == nil)
        {
          color = [theme colorNamed: key state: GSThemeNormalState];
        }
    }

  return (color != nil) ? color : fallback;
}

static NSColor *
GnomeThemeBlend(NSColor *fromColor, NSColor *toColor, CGFloat fraction)
{
  NSColor *result = nil;

  if (fromColor == nil)
    {
      return toColor;
    }
  if (toColor == nil)
    {
      return fromColor;
    }

  result = [fromColor blendedColorWithFraction: fraction ofColor: toColor];
  return (result != nil) ? result : fromColor;
}

static NSBezierPath *
GnomeThemeRoundedPath(NSRect rect, CGFloat radius)
{
  CGFloat clampedRadius = MIN (radius, MIN (rect.size.width, rect.size.height) / 2.0);

  if (clampedRadius <= 0.0)
    {
      return [NSBezierPath bezierPathWithRect: rect];
    }

  return [NSBezierPath bezierPathWithRoundedRect: rect
                                         xRadius: clampedRadius
                                         yRadius: clampedRadius];
}

static NSBezierPath *
GnomeThemeSegmentedControlPath(NSRect rect,
                               CGFloat radius,
                               BOOL roundedLeft,
                               BOOL roundedRight)
{
  CGFloat clampedRadius = MIN (radius, MIN (rect.size.width, rect.size.height) / 2.0);
  CGFloat minX = NSMinX (rect);
  CGFloat maxX = NSMaxX (rect);
  CGFloat minY = NSMinY (rect);
  CGFloat maxY = NSMaxY (rect);
  NSBezierPath *path = nil;

  if (clampedRadius <= 0.0 || (roundedLeft == NO && roundedRight == NO))
    {
      return [NSBezierPath bezierPathWithRect: rect];
    }

  if (roundedLeft && roundedRight)
    {
      return GnomeThemeRoundedPath (rect, clampedRadius);
    }

  path = [NSBezierPath bezierPath];
  [path moveToPoint: NSMakePoint (minX + (roundedLeft ? clampedRadius : 0.0), minY)];
  [path lineToPoint: NSMakePoint (maxX - (roundedRight ? clampedRadius : 0.0), minY)];

  if (roundedRight)
    {
      [path appendBezierPathWithArcFromPoint: NSMakePoint (maxX, minY)
                                     toPoint: NSMakePoint (maxX, minY + clampedRadius)
                                      radius: clampedRadius];
      [path lineToPoint: NSMakePoint (maxX, maxY - clampedRadius)];
      [path appendBezierPathWithArcFromPoint: NSMakePoint (maxX, maxY)
                                     toPoint: NSMakePoint (maxX - clampedRadius, maxY)
                                      radius: clampedRadius];
    }
  else
    {
      [path lineToPoint: NSMakePoint (maxX, minY)];
      [path lineToPoint: NSMakePoint (maxX, maxY)];
    }

  [path lineToPoint: NSMakePoint (minX + (roundedLeft ? clampedRadius : 0.0), maxY)];

  if (roundedLeft)
    {
      [path appendBezierPathWithArcFromPoint: NSMakePoint (minX, maxY)
                                     toPoint: NSMakePoint (minX, maxY - clampedRadius)
                                      radius: clampedRadius];
      [path lineToPoint: NSMakePoint (minX, minY + clampedRadius)];
      [path appendBezierPathWithArcFromPoint: NSMakePoint (minX, minY)
                                     toPoint: NSMakePoint (minX + clampedRadius, minY)
                                      radius: clampedRadius];
    }
  else
    {
      [path lineToPoint: NSMakePoint (minX, maxY)];
      [path lineToPoint: NSMakePoint (minX, minY)];
    }

  [path closePath];
  return path;
}

static void
GnomeThemeFillAndStrokeRoundedRect(NSRect rect,
                                   CGFloat radius,
                                   NSColor *fillColor,
                                   NSColor *strokeColor,
                                   CGFloat strokeWidth)
{
  NSBezierPath *path = GnomeThemeRoundedPath (rect, radius);

  if (fillColor != nil)
    {
      [fillColor set];
      [path fill];
    }

  if (strokeColor != nil && strokeWidth > 0.0)
    {
      [strokeColor set];
      [path setLineWidth: strokeWidth];
      [path stroke];
    }
}

static void
GnomeThemeStrokeEntryCaps(NSRect rect, CGFloat radius, NSColor *strokeColor)
{
  CGFloat inset = MAX (1.0, floor (radius * 0.72));

  if (strokeColor == nil || rect.size.width <= 0.0 || rect.size.height <= 0.0)
    {
      return;
    }

  [strokeColor set];
  [NSBezierPath strokeLineFromPoint: NSMakePoint (NSMinX (rect), NSMinY (rect) + inset)
                            toPoint: NSMakePoint (NSMinX (rect), NSMaxY (rect) - inset)];
  [NSBezierPath strokeLineFromPoint: NSMakePoint (NSMaxX (rect), NSMinY (rect) + inset)
                            toPoint: NSMakePoint (NSMaxX (rect), NSMaxY (rect) - inset)];
}

static BOOL
GnomeThemeViewHasFocus(NSView *view)
{
  id firstResponder = nil;
  id currentEditor = nil;

  if (view == nil || [view window] == nil)
    {
      return NO;
    }

  firstResponder = [[view window] firstResponder];
  if (firstResponder == view)
    {
      return YES;
    }

  if ([view respondsToSelector: @selector(currentEditor)])
    {
      currentEditor = [(id)view currentEditor];
      if (currentEditor != nil && currentEditor == firstResponder)
        {
          if ([firstResponder respondsToSelector: @selector(delegate)])
            {
              return ([firstResponder delegate] == view);
            }
          return YES;
        }
    }

  if ([firstResponder respondsToSelector: @selector(delegate)])
    {
      return ([firstResponder delegate] == view);
    }

  return NO;
}

static void
GnomeThemeTrackFocusedEntryView(NSView *view)
{
  if (view == nil)
    {
      return;
    }

  if (GnomeThemeLastFocusedEntryView != nil
    && GnomeThemeLastFocusedEntryView != view)
    {
      NSView *previous = GnomeThemeLastFocusedEntryView;
      [GnomeThemeLastFocusedEntryView setNeedsDisplay: YES];
      if ([previous superview] != nil)
        {
          [[previous superview] setNeedsDisplayInRect: [previous frame]];
        }
      [previous displayIfNeeded];
    }

  if (GnomeThemeLastFocusedEntryView != view)
    {
      RETAIN (view);
      RELEASE (GnomeThemeLastFocusedEntryView);
      GnomeThemeLastFocusedEntryView = view;
    }

  [view setNeedsDisplay: YES];
  if ([view superview] != nil)
    {
      [[view superview] setNeedsDisplayInRect: [view frame]];
    }
  if ([view window] != nil)
    {
      [[view window] setViewsNeedDisplay: YES];
    }
}

static BOOL
GnomeThemeViewShowsFocusRing(NSView *view)
{
  return GnomeThemeWindowFocusVisible ([view window]) && GnomeThemeViewHasFocus (view);
}

/* Redraws a window's focused view, so its ring follows focus-visible. */
static void
GnomeThemeRedisplayFocusedView(NSWindow *window)
{
  id responder = [window firstResponder];

  if ([window isVisible] == NO)
    {
      return;
    }
  /* An editing text field's first responder is its field editor. */
  if ([responder isKindOfClass: [NSText class]]
    && [[responder delegate] isKindOfClass: [NSView class]])
    {
      responder = [responder delegate];
    }
  if ([responder isKindOfClass: [NSView class]])
    {
      [responder setNeedsDisplay: YES];
    }
}

static BOOL
GnomeThemeViewEnabled(NSView *view)
{
  if (view != nil && [view respondsToSelector: @selector(isEnabled)])
    {
      return [(id)view isEnabled];
    }

  return YES;
}

static void
GnomeThemeDrawFocusRing(GnomeTheme *theme, NSRect rect, CGFloat radius)
{
  NSColor *focusColor = GnomeThemeColor (theme,
                                         @"keyboardFocusIndicatorColor",
                                         [NSColor keyboardFocusIndicatorColor]);
  NSColor *backgroundColor = GnomeThemeColor (theme,
                                              @"windowBackgroundColor",
                                              [NSColor windowBackgroundColor]);

  focusColor = GnomeThemeBlend (focusColor, backgroundColor, 0.68);
  GnomeThemeFillAndStrokeRoundedRect (rect, radius, nil, focusColor, 2.5);
}

/* libadwaita's pan-down-symbolic as pop-ups and combo boxes show it: 10px
   wide and about 7px high with its 2px stroke (#59). */
static void
GnomeThemeDrawPopupChevron(NSRect rect, NSColor *color, BOOL flipped)
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  NSPoint center = NSMakePoint (floor (NSMidX (rect)), floor (NSMidY (rect)));
  CGFloat halfWidth = 4.0;
  CGFloat halfHeight = 2.25;
  CGFloat topY = center.y + (flipped ? -halfHeight : halfHeight);
  CGFloat bottomY = center.y + (flipped ? halfHeight : -halfHeight);

  [path moveToPoint: NSMakePoint (center.x - halfWidth, topY)];
  [path lineToPoint: NSMakePoint (center.x, bottomY)];
  [path lineToPoint: NSMakePoint (center.x + halfWidth, topY)];
  [path setLineWidth: 2.0];
  [path setLineCapStyle: NSRoundLineCapStyle];
  [path setLineJoinStyle: NSRoundLineJoinStyle];
  [color set];
  [path stroke];
}

/* GtkExpander's arrow: pan-end-symbolic collapsed, pan-down-symbolic
   expanded, the icons' 2pt chevron in a 16pt box centred in `rect`. */
static void
GnomeThemeDrawExpanderArrow(NSRect rect, BOOL expanded, NSColor *color, BOOL flipped)
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  NSPoint centre = NSMakePoint (floor (NSMidX (rect)), floor (NSMidY (rect)));
  CGFloat down = flipped ? 1.0 : -1.0;

  if (expanded)
    {
      [path moveToPoint: NSMakePoint (centre.x - 4.0, centre.y - 2.0 * down)];
      [path lineToPoint: NSMakePoint (centre.x, centre.y + 2.0 * down)];
      [path lineToPoint: NSMakePoint (centre.x + 4.0, centre.y - 2.0 * down)];
    }
  else
    {
      [path moveToPoint: NSMakePoint (centre.x - 2.0, centre.y - 4.0)];
      [path lineToPoint: NSMakePoint (centre.x + 2.0, centre.y)];
      [path lineToPoint: NSMakePoint (centre.x - 2.0, centre.y + 4.0)];
    }
  [path setLineWidth: 2.0];
  [path setLineCapStyle: NSRoundLineCapStyle];
  [path setLineJoinStyle: NSRoundLineJoinStyle];
  [color set];
  [path stroke];
}

static CGFloat
GnomeThemeComboBoxButtonWidth(NSRect cellFrame)
{
  return MIN (24.0, MAX (20.0, floor (cellFrame.size.height * 0.72)));
}

/* Set while a pop-up button cell draws its title (see
   -_overrideNSPopUpButtonCellMethod_drawInteriorWithFrame:inView:). */
static BOOL GnomeThemeDrawingPopUpTitle = NO;

static NSRect
GnomeThemeComboBoxButtonRect(NSRect cellFrame)
{
  CGFloat buttonWidth = GnomeThemeComboBoxButtonWidth (cellFrame);

  return NSMakeRect (NSMaxX (cellFrame) - buttonWidth - 2.0,
                     NSMinY (cellFrame) + 2.0,
                     buttonWidth,
                     MAX (0.0, cellFrame.size.height - 4.0));
}

static void
GnomeThemeResolveEntryColors(GnomeTheme *theme,
                             NSView *view,
                             BOOL enabled,
                             BOOL focused,
                             BOOL readonlyField,
                             NSColor **fillOut,
                             NSColor **borderOut,
                             CGFloat *lineWidthOut)
{
  NSColor *windowFill = GnomeThemeColor (theme,
                                         @"windowBackgroundColor",
                                         [NSColor windowBackgroundColor]);
  NSColor *textFill = GnomeThemeColor (theme,
                                       @"textBackgroundColor",
                                       [NSColor textBackgroundColor]);
  NSColor *controlFill = GnomeThemeColor (theme,
                                          @"controlColor",
                                          [NSColor controlColor]);
  NSColor *shadowColor = GnomeThemeColor (theme,
                                          @"controlShadowColor",
                                          [NSColor controlShadowColor]);
  /* The focused entry's ring is the accent as text (libadwaita's
     accent_color), not the fills' accent. */
  NSColor *accentColor = GnomeThemeColor (theme,
                                          @"highlightColor",
                                          [NSColor highlightColor]);
  /* libadwaita's entries are its buttons' colour, half opacity disabled. */
  NSColor *fillColor = GnomeThemeColor (theme, @"GnomeThemeButtonColor",
                                               GnomeThemeBlend (controlFill, windowFill, 0.10));
  NSColor *borderColor = nil;
  CGFloat lineWidth = 0.0;

  (void)view;
  (void)textFill;
  (void)shadowColor;

  if (readonlyField)
    {
      fillColor = GnomeThemeBlend (fillColor, windowFill, 0.14);
    }

  /* High contrast outlines entries, as libadwaita does (the foreground at
     50%); a focused one has its accent ring instead. */
  borderColor = GnomeThemeColor (theme, @"GnomeThemeOutlineColor", nil);
  lineWidth = (borderColor != nil) ? 1.0 : 0.0;
  if (enabled == NO)
    {
      fillColor = GnomeThemeColor (theme, @"GnomeThemeButtonDisabledColor",
                                          GnomeThemeBlend (fillColor, windowFill, 0.42));
      if (borderColor != nil)
        {
          borderColor = GnomeThemeBlend (borderColor, windowFill, 0.6);
        }
    }
  else if (focused)
    {
      borderColor = GnomeThemeBlend (accentColor, windowFill, 0.28);
      lineWidth = 2.0;
    }

  if (fillOut != NULL)
    {
      *fillOut = fillColor;
    }
  if (borderOut != NULL)
    {
      *borderOut = borderColor;
    }
  if (lineWidthOut != NULL)
    {
      *lineWidthOut = lineWidth;
    }
}

static void
GnomeThemeDrawEntryChrome(GnomeTheme *theme,
                          NSView *view,
                          NSRect frame,
                          BOOL enabled,
                          BOOL focused,
                          BOOL readonlyField)
{
  NSColor *fillColor = nil;
  NSColor *borderColor = nil;
  CGFloat borderWidth = 0.0;
  CGFloat radius = 10.0;
  NSRect borderRect = NSInsetRect (frame, 0.5, 0.5);

  GnomeThemeResolveEntryColors (theme,
                                view,
                                enabled,
                                focused && enabled,
                                readonlyField,
                                &fillColor,
                                &borderColor,
                                &borderWidth);
  /* A background the app chose (not the text background every field has)
     fills the entry: Gorm's CustomView palette item is a dark tile with a
     white class name, which drew as a pale read-only entry with the name
     barely showing (#27). */
  if ([view isKindOfClass: [NSTextField class]] && [(NSTextField *)view drawsBackground])
    {
      NSColor *background = [(NSTextField *)view backgroundColor];

      if (background != nil && [background isEqual: [NSColor textBackgroundColor]] == NO
        && [background isEqual: [NSColor controlBackgroundColor]] == NO)
        {
          fillColor = background;
        }
    }

  GnomeThemeFillAndStrokeRoundedRect (borderRect,
                                      radius,
                                      fillColor,
                                      borderColor,
                                      borderWidth);

  if (borderColor != nil && borderWidth > 0.0)
    {
      GnomeThemeStrokeEntryCaps (borderRect, radius, borderColor);
    }
}

/* Whether image is the system image of that name. The name is looked up
   only for an image there is: +imageNamed: loads it, and classifying every
   button on its first draw loaded eight images (about 120ms at launch),
   for buttons that mostly have none (#50). The comparison is by identity,
   not -name: GNUstep maps names such as NSSwitch to its own image files,
   whose names differ. */
static BOOL
GnomeThemeImageHasName(NSImage *image, NSString *name)
{
  return image != nil && image == [NSImage imageNamed: name];
}

static BOOL
GnomeThemeButtonCellUsesSearchImage(NSButtonCell *cell)
{
  return GnomeThemeImageHasName ([cell image], @"GSSearch");
}

static BOOL
GnomeThemeButtonCellUsesCancelImage(NSButtonCell *cell)
{
  return GnomeThemeImageHasName ([cell image], @"GSStop");
}

/* libadwaita's system-search-symbolic in a 16px square: a lens 12px
   across with a 1.5px stroke at the top left, its handle to the bottom
   right (#59). The search field is flipped: y grows down. */
static void
GnomeThemeDrawSearchGlyph(NSRect rect, NSColor *color)
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  NSRect icon = GnomeThemeCenteredRect (rect, 16.0, 16.0);
  NSRect lens = NSMakeRect (floor (NSMinX (icon)) + 1.75, floor (NSMinY (icon)) + 1.75, 10.5, 10.5);

  [path appendBezierPathWithOvalInRect: lens];
  [path moveToPoint: NSMakePoint (NSMaxX (lens) - 1.25, NSMaxY (lens) - 1.25)];
  [path lineToPoint: NSMakePoint (NSMinX (icon) + 14.5, NSMinY (icon) + 14.5)];
  [path setLineWidth: 1.5];
  [path setLineCapStyle: NSRoundLineCapStyle];
  [path setLineJoinStyle: NSRoundLineJoinStyle];
  [color set];
  [path stroke];
}

/* libadwaita's edit-clear-symbolic in a 16px square: a backspace key
   pointing left, 16x12, filled, with an x cut out of its body (#59). The
   cut is a cross outline appended to the key's outline and filled
   even-odd, so whatever is behind shows through it. */
static void
GnomeThemeDrawCancelGlyph(NSRect rect, NSColor *fillColor, NSColor *markColor)
{
  NSRect icon = GnomeThemeCenteredRect (rect, 16.0, 16.0);
  CGFloat left = floor (NSMinX (icon)), top = floor (NSMinY (icon)) + 2.0;
  NSBezierPath *path = [NSBezierPath bezierPath];
  NSPoint centre = NSMakePoint (left + 10.0, top + 6.0);
  /* The x: a plus outline (arms 1.75px wide, 6.5px across) turned 45 degrees. */
  CGFloat h = 0.875, l = 3.25;
  CGFloat plus[12][2] = { { h, l }, { h, h }, { l, h }, { l, -h }, { h, -h }, { h, -l },
                          { -h, -l }, { -h, -h }, { -l, -h }, { -l, h }, { -h, h }, { -h, l } };
  int i;

  (void)markColor;
  [path moveToPoint: NSMakePoint (left, top + 6.0)];
  [path lineToPoint: NSMakePoint (left + 4.5, top)];
  [path lineToPoint: NSMakePoint (left + 16.0, top)];
  [path lineToPoint: NSMakePoint (left + 16.0, top + 12.0)];
  [path lineToPoint: NSMakePoint (left + 4.5, top + 12.0)];
  [path closePath];
  for (i = 0; i < 12; i++)
    {
      NSPoint p = NSMakePoint (centre.x + (plus[i][0] - plus[i][1]) * M_SQRT1_2,
                               centre.y + (plus[i][0] + plus[i][1]) * M_SQRT1_2);

      if (i == 0)
        {
          [path moveToPoint: p];
        }
      else
        {
          [path lineToPoint: p];
        }
    }
  [path closePath];
  [path setWindingRule: NSEvenOddWindingRule];
  [fillColor set];
  [path fill];
}

static BOOL GnomeThemeIsDropDownComboBox(id view);

static NSString *
GnomeThemeComboBoxDisplayString(NSComboBoxCell *cell)
{
  NSString *value = nil;
  id object = [cell objectValueOfSelectedItem];

  if ([object respondsToSelector: @selector(description)])
    {
      value = [object description];
    }
  if ([value length] == 0)
    {
      value = [cell stringValue];
    }

  return value;
}

static NSRect
GnomeThemeComboBoxTextRect(NSComboBoxCell *cell, NSRect cellFrame)
{
  NSRect textRect = [cell drawingRectForBounds: cellFrame];
  CGFloat leftInset = 12.0;
  CGFloat rightInset = GnomeThemeComboBoxButtonWidth (cellFrame) + 12.0;

  textRect.origin.x += leftInset;
  textRect.size.width = MAX (0.0, textRect.size.width - leftInset - rightInset);
  return textRect;
}

static NSButtonCell *
GnomeThemeComboBoxButtonCell(NSComboBoxCell *cell)
{
  id buttonCell = nil;

  if (cell == nil)
    {
      return nil;
    }

  NS_DURING
    {
      buttonCell = [cell valueForKey: @"_buttonCell"];
    }
  NS_HANDLER
    {
      buttonCell = nil;
    }
  NS_ENDHANDLER

  if ([buttonCell isKindOfClass: [NSButtonCell class]] == NO)
    {
      return nil;
    }

  return (NSButtonCell *)buttonCell;
}

static void
GnomeThemeNeutralizeComboBoxButtonCell(NSComboBoxCell *cell)
{
  NSButtonCell *buttonCell = GnomeThemeComboBoxButtonCell (cell);

  if (buttonCell == nil)
    {
      return;
    }

  [buttonCell setHighlighted: NO];
  [buttonCell setBordered: NO];
  [buttonCell setHighlightsBy: 0];
  [buttonCell setShowsStateBy: 0];
  [buttonCell setImage: nil];
  [buttonCell setAlternateImage: nil];
  if ([buttonCell respondsToSelector: @selector(setTransparent:)])
    {
      [(id)buttonCell setTransparent: YES];
    }
}

static void
GnomeThemeConfigureComboBoxPopupMetrics(NSComboBoxCell *cell)
{
  NSInteger itemCount = 0;
  NSInteger visibleItems = 0;
  CGFloat itemHeight = 0.0;

  if (cell == nil)
    {
      return;
    }

  /* GtkDropDown's rows and list height (GnomeThemeLists.m). */
  itemCount = [cell numberOfItems];
  itemHeight = GnomeThemeDropDownRowHeight ([cell font]);
  visibleItems = GnomeThemeDropDownVisibleRows (itemHeight, itemCount);

  [cell setItemHeight: itemHeight];
  [cell setIntercellSpacing: NSMakeSize (0.0, 0.0)];
  [cell setNumberOfVisibleItems: visibleItems];
  [cell setHasVerticalScroller: (itemCount > visibleItems)];
}

static void
GnomeThemeStyleComboBoxPopupView(NSView *view,
                                 GnomeTheme *theme,
                                 BOOL showScroller)
{
  NSArray *subviews = nil;
  NSUInteger index = 0;

  if (view == nil)
    {
      return;
    }

  if ([view isKindOfClass: [NSScrollView class]])
    {
      NSScrollView *scrollView = (NSScrollView *)view;
      [scrollView setBorderType: NSNoBorder];
      [scrollView setDrawsBackground: NO];
      [scrollView setHasVerticalScroller: showScroller];
      [scrollView setAutohidesScrollers: YES];
      if (showScroller == NO)
        {
          [scrollView setVerticalScroller: nil];
        }
      if ([scrollView contentView] != nil)
        {
          [[scrollView contentView] setDrawsBackground: NO];
        }
    }
  else if ([view isKindOfClass: [NSTableView class]])
    {
      /* Its rows' height comes from the cell's item height; it draws no
         background of its own (GnomeThemeLists.m). */
      NSTableView *tableView = (NSTableView *)view;
      [tableView setIntercellSpacing: NSMakeSize (0.0, 0.0)];
      [tableView setGridStyleMask: NSTableViewGridNone];
      [tableView setUsesAlternatingRowBackgroundColors: NO];
    }

  subviews = [view subviews];
  for (index = 0; index < [subviews count]; index++)
    {
      GnomeThemeStyleComboBoxPopupView ([subviews objectAtIndex: index],
                                        theme,
                                        showScroller);
    }
}

static void
GnomeThemeStyleComboBoxPopup(NSComboBoxCell *cell, GnomeTheme *theme)
{
  id popup = nil;
  NSWindow *window = nil;
  NSView *contentView = nil;
  BOOL showScroller = NO;

  if (cell == nil)
    {
      return;
    }

  NS_DURING
    {
      popup = [cell valueForKey: @"_popup"];
    }
  NS_HANDLER
    {
      popup = nil;
    }
  NS_ENDHANDLER

  if (popup == nil)
    {
      return;
    }

  if ([popup isKindOfClass: [NSWindow class]])
    {
      window = (NSWindow *)popup;
    }
  else if ([popup respondsToSelector: @selector(window)])
    {
      window = [popup window];
    }

  if (window == nil)
    {
      return;
    }

  /* GtkDropDown's popover (GnomeThemeLists.m); a list made before the
     theme was active gets it now. */
  showScroller = ([cell numberOfItems] > [cell numberOfVisibleItems]);
  GnomeThemeInstallDropDownPopover (window);
  GnomeThemeListClearHover ();
  contentView = [window contentView];
  if (contentView != nil)
    {
      [contentView setNeedsDisplay: YES];
      GnomeThemeStyleComboBoxPopupView (contentView, theme, showScroller);
    }
}

/* libadwaita's trough: 8px, whatever the bar's height (Cocoa's are 20pt
   or 16pt tall), centred. */
static NSRect
GnomeThemeProgressTrackRect(NSRect bounds)
{
  CGFloat thickness = MIN (8.0, floor (bounds.size.height));
  NSRect trackRect = bounds;

  trackRect.origin.x += 1.0;
  trackRect.size.width = MAX (0.0, trackRect.size.width - 2.0);
  trackRect.origin.y = floor (NSMidY (bounds) - (thickness / 2.0));
  trackRect.size.height = thickness;

  return trackRect;
}

static NSInteger
GnomeThemeSegmentIndexAtPoint(NSSegmentedCell *cell,
                              NSRect cellFrame,
                              NSPoint point)
{
  NSInteger segmentCount = [cell segmentCount];
  CGFloat explicitWidth = 0.0;
  NSInteger flexibleSegments = 0;
  CGFloat defaultWidth = 0.0;
  CGFloat cursorX = NSMinX (cellFrame);
  NSInteger index = 0;

  if (segmentCount <= 0 || NSPointInRect (point, cellFrame) == NO)
    {
      return NSNotFound;
    }

  for (index = 0; index < segmentCount; index++)
    {
      CGFloat width = [cell widthForSegment: index];

      if (width > 0.0)
        {
          explicitWidth += width;
        }
      else
        {
          flexibleSegments++;
        }
    }

  if (flexibleSegments > 0)
    {
      defaultWidth = MAX (0.0, (cellFrame.size.width - explicitWidth) / flexibleSegments);
    }

  for (index = 0; index < segmentCount; index++)
    {
      CGFloat width = [cell widthForSegment: index];

      if (width <= 0.0)
        {
          width = defaultWidth;
        }

      if (point.x < (cursorX + width) || index == (segmentCount - 1))
        {
          return index;
        }

      cursorX += width;
    }

  return NSNotFound;
}

/* libadwaita's list-remove/add-symbolic: 10px across, 2px strokes (#59),
   or less in a half too small for it (a Cocoa stepper's). On a pixel
   boundary, so the 2px strokes stay sharp. */
static void
GnomeThemeDrawStepperGlyph(NSRect rect, BOOL increment, NSColor *color)
{
  CGFloat span = MAX (3.0, MIN (5.0, floor ((MIN (NSWidth (rect), NSHeight (rect)) - 4.0) / 2.0)));
  NSPoint center = NSMakePoint (floor (NSMidX (rect)), floor (NSMidY (rect)));
  NSBezierPath *path = [NSBezierPath bezierPath];

  [path moveToPoint: NSMakePoint (center.x - span, center.y)];
  [path lineToPoint: NSMakePoint (center.x + span, center.y)];

  if (increment)
    {
      [path moveToPoint: NSMakePoint (center.x, center.y - span)];
      [path lineToPoint: NSMakePoint (center.x, center.y + span)];
    }

  [path setLineWidth: 2.0];
  [path setLineCapStyle: NSButtLineCapStyle];
  [color set];
  [path stroke];
}

static BOOL
GnomeThemeScrollerShowsOverflow(NSScroller *scroller)
{
  if (scroller == nil || [scroller isEnabled] == NO)
    {
      return NO;
    }

  return ([scroller knobProportion] < 0.999);
}

static BOOL
GnomeThemeScrollerIsHorizontal(NSScroller *scroller)
{
  NSRect bounds = [scroller bounds];

  return (bounds.size.width >= bounds.size.height);
}

static NSColor *
GnomeThemeScrollerBackgroundColor(NSScroller *scroller)
{
  NSView *superview = [scroller superview];

  if ([superview isKindOfClass: [NSScrollView class]])
    {
      return [(NSScrollView *)superview backgroundColor];
    }

  return [NSColor clearColor];
}

static void
GnomeThemeEraseScrollerRect(NSScroller *scroller, NSRect rect)
{
  NSColor *backgroundColor = GnomeThemeScrollerBackgroundColor (scroller);

  if (backgroundColor != nil)
    {
      [backgroundColor set];
      NSRectFill (rect);
    }
}

/* An overlay-style scroll indicator, as in libadwaita: no track, just a thin
   rounded slider along the outer edge in a dim text colour, thicker and
   darker while it is being dragged. The scroller strip itself shows the
   scroll view's background. (libadwaita also hides the indicator until the
   pointer moves or the view scrolls; GNUstep has no hover tracking for
   scrollers, so it stays visible while the content overflows.) */
static void
GnomeThemeDrawModernScroller(GnomeTheme *theme,
                             NSScroller *scroller,
                             NSRect rect,
                             NSScrollerPart hitPart,
                             BOOL isHorizontal)
{
  NSRect bounds = [scroller bounds];
  NSRect knobRect = [scroller rectForPart: NSScrollerKnob];
  NSColor *backgroundColor = GnomeThemeScrollerBackgroundColor (scroller);
  BOOL dragging = (hitPart == NSScrollerKnob);
  NSColor *textColor = GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor]);
  NSColor *thumbFill = GnomeThemeBlend (textColor, backgroundColor, dragging ? 0.5 : 0.7);
  CGFloat minorAxis = isHorizontal ? bounds.size.height : bounds.size.width;
  CGFloat thickness = MIN (dragging ? 8.0 : 4.0, MAX (2.0, minorAxis - 4.0));
  CGFloat edgeMargin = 3.0;
  CGFloat endInset = 2.0;

  (void)rect;

  if (backgroundColor != nil)
    {
      [backgroundColor set];
      NSRectFill (bounds);
    }

  if (isHorizontal)
    {
      /* Along the bottom edge (the scroller is flipped: larger y is lower). */
      CGFloat y = [scroller isFlipped]
        ? NSMaxY (bounds) - edgeMargin - thickness
        : NSMinY (bounds) + edgeMargin;

      knobRect = NSMakeRect (NSMinX (knobRect) + endInset, y,
                             MAX (0.0, NSWidth (knobRect) - 2.0 * endInset), thickness);
    }
  else
    {
      knobRect = NSMakeRect (NSMaxX (bounds) - edgeMargin - thickness,
                             NSMinY (knobRect) + endInset,
                             thickness, MAX (0.0, NSHeight (knobRect) - 2.0 * endInset));
    }

  knobRect = NSIntersectionRect (knobRect, bounds);
  if (NSIsEmptyRect (knobRect) == NO && thumbFill != nil)
    {
      GnomeThemeFillAndStrokeRoundedRect (knobRect,
                                          floor (thickness / 2.0),
                                          thumbFill,
                                          nil,
                                          0.0);
    }
}

static BOOL
GnomeThemeButtonCellIsCheckbox(NSButtonCell *cell)
{
  return (GnomeThemeImageHasName ([cell image], @"NSSwitch")
    || GnomeThemeImageHasName ([cell alternateImage], @"NSHighlightedSwitch"));
}

static BOOL
GnomeThemeButtonCellIsRadio(NSButtonCell *cell)
{
  return (GnomeThemeImageHasName ([cell image], @"NSRadioButton")
    || GnomeThemeImageHasName ([cell alternateImage], @"NSHighlightedRadioButton"));
}

static BOOL
GnomeThemeButtonCellUsesLegacyReturnImage(NSButtonCell *cell)
{
  return (GnomeThemeImageHasName ([cell image], @"common_ret")
    || GnomeThemeImageHasName ([cell alternateImage], @"common_retH"));
}

static BOOL
GnomeThemeUsesScreenFonts(void)
{
  NSGraphicsContext *context = GSCurrentContext ();
  NSAffineTransform *transform = GSCurrentCTM (context);
  NSAffineTransformStruct matrix = [transform transformStruct];

  return (matrix.m11 == 1.0
    && matrix.m12 == 0.0
    && matrix.m21 == 0.0
    && fabs (matrix.m22) == 1.0);
}

static BOOL
GnomeThemeIsSecureTextFieldCell(NSTextFieldCell *cell)
{
  Class secureCellClass = NSClassFromString (@"NSSecureTextFieldCell");

  return (secureCellClass != Nil && [cell isKindOfClass: secureCellClass]);
}

static NSFont *
GnomeThemeControlFontForSecureTextFieldCell(NSTextFieldCell *cell)
{
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSFont *font = (theme != nil) ? [[theme settings] interfaceFont] : nil;

  if (font == nil)
    {
      font = [NSFont controlContentFontOfSize: 0.0];
    }
  if (font == nil)
    {
      font = [NSFont systemFontOfSize: 12.0];
    }

  (void)cell;
  return font;
}

static NSAttributedString *
GnomeThemeSecureTextDisplayString(NSTextFieldCell *cell,
                                  NSAttributedString *string)
{
  NSMutableAttributedString *mutableString = nil;
  NSFont *font = nil;
  NSRange fullRange;

  if (GnomeThemeIsSecureTextFieldCell (cell) == NO || [string length] == 0)
    {
      return string;
    }

  mutableString = AUTORELEASE ([string mutableCopy]);
  fullRange = NSMakeRange (0, [mutableString length]);
  {
    unichar bullet = GnomeThemeLibsGuiBullet;
    unichar circle = GnomeThemeSecureCharacter;

    [[mutableString mutableString] replaceOccurrencesOfString: [NSString stringWithCharacters: &bullet length: 1]
                                                   withString: [NSString stringWithCharacters: &circle length: 1]
                                                      options: 0
                                                        range: fullRange];
  }
  font = GnomeThemeControlFontForSecureTextFieldCell (cell);
  if (font != nil)
    {
      [mutableString addAttribute: NSFontAttributeName
                            value: font
                            range: fullRange];
    }

  return mutableString;
}

static void
GnomeThemeDrawAttributedStringWithEditorLayout(NSTextFieldCell *cell,
                                               NSAttributedString *string,
                                               NSRect rect,
                                               NSView *controlView)
{
  static NSTextStorage *textStorage = nil;
  static NSLayoutManager *layoutManager = nil;
  static NSTextContainer *textContainer = nil;
  NSGraphicsContext *context = GSCurrentContext ();
  NSSize titleSize;
  NSRange glyphRange;
  BOOL viewFlipped;

  if ([string length] == 0 || NSWidth (rect) <= 0.0 || NSHeight (rect) <= 0.0)
    {
      return;
    }

  string = GnomeThemeSecureTextDisplayString (cell, string);

  if (textStorage == nil)
    {
      textStorage = [[NSTextStorage alloc] init];
      layoutManager = [[NSLayoutManager alloc] init];
      textContainer = [[NSTextContainer alloc] initWithContainerSize: rect.size];
      [textContainer setLineFragmentPadding: 0.0];
      [textStorage addLayoutManager: layoutManager];
      [layoutManager addTextContainer: textContainer];
    }

  titleSize = [string size];
  if ([cell _shouldShortenStringForRect: rect size: titleSize length: [string length]])
    {
      string = [cell _resizeAttributedString: string forRect: rect];
    }

  [textStorage setAttributedString: string];
  [textContainer setContainerSize: rect.size];
  if ([layoutManager respondsToSelector: @selector(setUsesScreenFonts:)])
    {
      [(id)layoutManager setUsesScreenFonts: GnomeThemeUsesScreenFonts ()];
    }

  glyphRange = [layoutManager glyphRangeForBoundingRect: NSMakeRect (0.0,
                                                                     0.0,
                                                                     rect.size.width,
                                                                     rect.size.height)
                                        inTextContainer: textContainer];
  viewFlipped = (controlView != nil) ? [controlView isFlipped] : NO;

  DPSgsave (context);
  DPSrectclip (context, NSMinX (rect), NSMinY (rect), NSWidth (rect), NSHeight (rect));

  if (viewFlipped)
    {
      [layoutManager drawBackgroundForGlyphRange: glyphRange atPoint: rect.origin];
      [layoutManager drawGlyphsForGlyphRange: glyphRange atPoint: rect.origin];
    }
  else
    {
      /* Text fields are flipped; this is a cell drawn in some other view,
         such as an NSBox's title (Gorm's inspectors). Flipping the context
         here drew the glyphs mirrored, so let string drawing handle it. */
      [string drawInRect: rect];
    }

  DPSgrestore (context);
}

static NSFont *
GnomeThemeResolvedEditorFont(NSTextFieldCell *cell)
{
  NSFont *font = [cell font];
  GnomeTheme *theme = GnomeThemeActiveTheme ();

  if (GnomeThemeIsSecureTextFieldCell (cell))
    {
      return GnomeThemeControlFontForSecureTextFieldCell (cell);
    }

  if (font == nil && theme != nil)
    {
      font = [[theme settings] interfaceFont];
    }

  if (font == nil)
    {
      font = [NSFont systemFontOfSize: 12.0];
    }

  return font;
}

static void
GnomeThemeConfigureEditorLayout(NSTextView *textView)
{
  NSLayoutManager *layoutManager = nil;
  NSTextContainer *textContainer = nil;

  if (textView == nil)
    {
      return;
    }

  [textView setTextContainerInset: NSZeroSize];
  textContainer = [textView textContainer];
  if (textContainer != nil)
    {
      [textContainer setLineFragmentPadding: 0.0];
    }

  layoutManager = [textView layoutManager];
  if ([layoutManager respondsToSelector: @selector(setUsesScreenFonts:)])
    {
      [(id)layoutManager setUsesScreenFonts: GnomeThemeUsesScreenFonts ()];
    }
}

static NSDictionary *
GnomeThemeEditorTypingAttributes(NSTextFieldCell *cell, NSTextView *textView, NSFont *font)
{
  NSMutableDictionary *attributes = nil;
  NSDictionary *cellAttributes = [cell _nonAutoreleasedTypingAttributes];
  NSDictionary *editorAttributes = [textView typingAttributes];
  NSMutableParagraphStyle *paragraphStyle = nil;

  if (editorAttributes != nil)
    {
      attributes = [editorAttributes mutableCopy];
    }
  else if (cellAttributes != nil)
    {
      attributes = [cellAttributes mutableCopy];
    }
  else
    {
      attributes = [[NSMutableDictionary alloc] init];
    }

  if (cellAttributes != nil)
    {
      NSEnumerator *enumerator = [cellAttributes keyEnumerator];
      id key = nil;

      while ((key = [enumerator nextObject]) != nil)
        {
          id value = [cellAttributes objectForKey: key];

          if (value != nil)
            {
              [attributes setObject: value forKey: key];
            }
        }
      RELEASE (cellAttributes);
    }

  if (font != nil)
    {
      [attributes setObject: font forKey: NSFontAttributeName];
    }

  paragraphStyle = AUTORELEASE ([[NSMutableParagraphStyle alloc] init]);
  [paragraphStyle setAlignment: [cell alignment]];
  [attributes setObject: paragraphStyle forKey: NSParagraphStyleAttributeName];

  return AUTORELEASE (attributes);
}

static NSAttributedString *
GnomeThemeNormalizedEditorContent(NSTextFieldCell *cell, NSDictionary *attributes)
{
  NSAttributedString *cellContent = [cell attributedStringValue];
  NSMutableAttributedString *mutableContent = nil;
  NSRange fullRange;
  id value = nil;

  if ([cellContent length] == 0)
    {
      return nil;
    }

  mutableContent = AUTORELEASE ([cellContent mutableCopy]);
  fullRange = NSMakeRange (0, [mutableContent length]);

  value = [attributes objectForKey: NSFontAttributeName];
  if (value != nil)
    {
      [mutableContent addAttribute: NSFontAttributeName value: value range: fullRange];
    }

  value = [attributes objectForKey: NSForegroundColorAttributeName];
  if (value != nil)
    {
      [mutableContent addAttribute: NSForegroundColorAttributeName
                             value: value
                             range: fullRange];
    }

  value = [attributes objectForKey: NSParagraphStyleAttributeName];
  if (value != nil)
    {
      [mutableContent addAttribute: NSParagraphStyleAttributeName
                             value: value
                             range: fullRange];
    }

  return mutableContent;
}

static void GnomeThemeSuppressEditorBackground(NSText *textObject);

static void
GnomeThemeApplyEditorFont(NSTextFieldCell *cell, NSText *textObject)
{
  NSFont *font = nil;
  NSTextView *textView = nil;
  NSDictionary *typingAttributes = nil;
  NSAttributedString *content = nil;
  NSTextStorage *textStorage = nil;

  if (textObject == nil)
    {
      return;
    }

  font = GnomeThemeResolvedEditorFont (cell);
  if (font == nil)
    {
      return;
    }

  [textObject setFont: font];

  if ([textObject isKindOfClass: [NSTextView class]] == NO)
    {
      return;
    }

  textView = (NSTextView *)textObject;
  GnomeThemeSuppressEditorBackground (textObject);
  GnomeThemeConfigureEditorLayout (textView);
  typingAttributes = GnomeThemeEditorTypingAttributes (cell, textView, font);
  if (typingAttributes != nil)
    {
      [textView setTypingAttributes: typingAttributes];
    }

  content = GnomeThemeNormalizedEditorContent (cell, typingAttributes);
  if (content == nil)
    {
      return;
    }

  textStorage = [textView textStorage];
  if (textStorage != nil)
    {
      [textStorage setAttributedString: content];
    }
}

static void
GnomeThemeSuppressEditorBackground(NSText *textObject)
{
  NSView *clipView = nil;

  if (textObject == nil)
    {
      return;
    }

  [textObject setDrawsBackground: NO];
  [textObject setBackgroundColor: [NSColor clearColor]];

  if ([textObject isKindOfClass: [NSView class]] == NO)
    {
      return;
    }

  clipView = [(NSView *)textObject superview];
  if ([clipView isKindOfClass: [NSClipView class]])
    {
      [(NSClipView *)clipView setDrawsBackground: NO];
      [(NSClipView *)clipView setBackgroundColor: [NSColor clearColor]];
    }
}

/* Bold, as libadwaita's button titles, unless the window of `cell` (drawn
   in `controlView`, or nil) has compact metrics. */
static NSFont *
GnomeThemeEmphasizedFont(NSFont *font, NSCell *cell, NSView *controlView)
{
  NSFontManager *fontManager = [NSFontManager sharedFontManager];
  NSFont *boldFont = nil;

  if (font == nil || fontManager == nil)
    {
      return font;
    }

  if ([[GnomeThemeActiveTheme () metricsForCell: cell inView: controlView] emphasizesButtonTitles] == NO)
    {
      return font;
    }
  boldFont = [fontManager convertFont: font toHaveTrait: NSBoldFontMask];
  return (boldFont != nil) ? boldFont : font;
}

static void
GnomeThemeDrawIndicatorLabel(NSButtonCell *cell,
                             NSRect titleRect,
                             NSView *controlView,
                             BOOL enabled)
{
  NSAttributedString *title = [cell attributedTitle];

  if ([title length] == 0)
    {
      return;
    }

  if (enabled == NO)
    {
      NSMutableAttributedString *mutableTitle = AUTORELEASE ([title mutableCopy]);

      [mutableTitle addAttribute: NSForegroundColorAttributeName
                           value: [NSColor disabledControlTextColor]
                           range: NSMakeRange (0, [mutableTitle length])];
      title = mutableTitle;
    }

  [cell drawTitle: title withFrame: titleRect inView: controlView];
}

static void
GnomeThemeDrawButtonLabel(NSButtonCell *cell,
                          NSRect titleRect,
                          NSView *controlView,
                          NSColor *textColor)
{
  NSAttributedString *title = [cell attributedTitle];

  if ([title length] == 0)
    {
      return;
    }

  if (textColor != nil)
    {
      NSMutableAttributedString *mutableTitle = AUTORELEASE ([title mutableCopy]);
      NSFont *font = [cell font];

      if (font == nil)
        {
          font = [NSFont controlContentFontOfSize: 0.0];
        }
      font = GnomeThemeEmphasizedFont (font, cell, controlView);

      [mutableTitle addAttribute: NSForegroundColorAttributeName
                           value: textColor
                           range: NSMakeRange (0, [mutableTitle length])];
      if (font != nil)
        {
          [mutableTitle addAttribute: NSFontAttributeName
                               value: font
                               range: NSMakeRange (0, [mutableTitle length])];
        }
      title = mutableTitle;
    }

  [cell drawTitle: title withFrame: titleRect inView: controlView];
}

/* What a title needs beyond its measured width: a title even a pixel short
   of its width wraps its last word onto a clipped second line. */
static const CGFloat GnomeThemeButtonTitleSlack = 4.0;

/* The least padding a bordered button's title keeps when the app made the
   button too narrow for the full padding. */
static const CGFloat GnomeThemeButtonMinimumPadding = 4.0;

static NSSize GnomeThemeButtonLabelSize(NSButtonCell *cell);

static NSRect
GnomeThemeButtonTitleRect(NSButtonCell *cell, NSRect cellFrame)
{
  NSRect titleRect = [cell drawingRectForBounds: cellFrame];
  CGFloat padding, extra, needed;

  if ([cell isKindOfClass: [NSPopUpButtonCell class]])
    {
      CGFloat leftInset = 14.0;
      CGFloat rightInset = GnomeThemeComboBoxButtonWidth (cellFrame) + 10.0;

      titleRect.origin.x += leftInset;
      titleRect.size.width = MAX (0.0, titleRect.size.width - leftInset - rightInset);
      return titleRect;
    }
  if ([cell isBordered] == NO && [cell isBezeled] == NO)
    {
      return NSInsetRect (titleRect, 4.0, 0.0);
    }

  /* The rounded styles' margins (-buttonMarginsForCell:style:state:) are
     already GTK's text button padding; the other bezels' are only their
     border, so the title keeps 10pt more. */
  switch ([cell bezelStyle])
    {
      case NSRoundedBezelStyle:
      case NSRoundRectBezelStyle:
      case NSTexturedRoundedBezelStyle:
        extra = [[GnomeThemeActiveTheme () metricsForCell: cell inView: nil] buttonHorizontalPadding] > 0.0
          ? 0.0 : 10.0;
        break;

      default:
        extra = 10.0;
        break;
    }
  padding = NSMinX (titleRect) - NSMinX (cellFrame) + extra;

  /* GTK grows a button to fit its label; an app's fixed frame can't grow, so
     the padding gives way before the title does ("12" in a 64pt button). */
  needed = GnomeThemeButtonLabelSize (cell).width + GnomeThemeButtonTitleSlack;
  if (NSWidth (cellFrame) - 2.0 * padding < needed)
    {
      padding = MAX (MIN (padding, GnomeThemeButtonMinimumPadding),
                     floor ((NSWidth (cellFrame) - needed) / 2.0));
    }

  titleRect.origin.x = NSMinX (cellFrame) + padding;
  titleRect.size.width = MAX (0.0, NSWidth (cellFrame) - 2.0 * padding);

  return titleRect;
}

/* A one-line control's height as GTK's, the height a push button gets from
   -cellSize: a line of `font` with 6pt above and below, and at least 34pt
   (GtkButton, GtkEntry and GtkDropDown). */
static CGFloat
GnomeThemeControlRowHeight(NSFont *font)
{
  NSDictionary *attributes;

  if (font == nil)
    {
      font = [NSFont controlContentFontOfSize: 0.0];
    }
  attributes = [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName];
  return MAX (34.0, ceil ([@"Ag" sizeWithAttributes: attributes].height + 12.0));
}

static NSSize
GnomeThemeButtonLabelSize(NSButtonCell *cell)
{
  NSAttributedString *title = [cell attributedTitle];
  NSFont *font = [cell font];
  NSMutableDictionary *attributes = nil;
  NSSize size = NSZeroSize;

  if ([title length] == 0)
    {
      return size;
    }

  if (font == nil)
    {
      font = [NSFont controlContentFontOfSize: 0.0];
    }
  font = GnomeThemeEmphasizedFont (font, cell, nil);

  attributes = AUTORELEASE ([[NSMutableDictionary alloc] init]);
  if (font != nil)
    {
      [attributes setObject: font forKey: NSFontAttributeName];
    }

  size = [[title string] sizeWithAttributes: attributes];
  size.width = ceil (size.width);
  size.height = ceil (size.height);
  return size;
}

/* A checkbox or radio indicator: at the start of the content, or at its end
   for a cell whose image goes to the right of its title (Gorm's inspectors
   use these: "Command [x]"). */
static BOOL
GnomeThemeIndicatorTrails(NSButtonCell *cell)
{
  return [cell imagePosition] == NSImageRight;
}

static NSRect
GnomeThemeIndicatorRectInContent(NSButtonCell *cell, NSRect contentRect, CGFloat indicatorSize)
{
  CGFloat x = GnomeThemeIndicatorTrails (cell)
    ? NSMaxX (contentRect) - 2.0 - indicatorSize
    : contentRect.origin.x + 2.0;

  return NSMakeRect (x, NSMidY (contentRect) - (indicatorSize / 2.0), indicatorSize, indicatorSize);
}

/* The title's rect beside the indicator. */
static NSRect
GnomeThemeIndicatorTitleRect(NSButtonCell *cell, NSRect contentRect, NSRect indicatorRect)
{
  NSRect titleRect = contentRect;

  if (GnomeThemeIndicatorTrails (cell))
    {
      titleRect.size.width = MAX (0.0, NSMinX (indicatorRect) - GnomeThemeIndicatorLabelGap - NSMinX (contentRect));
    }
  else
    {
      titleRect.origin.x = NSMaxX (indicatorRect) + GnomeThemeIndicatorLabelGap;
      titleRect.size.width = MAX (0.0, NSMaxX (contentRect) - titleRect.origin.x);
    }
  return titleRect;
}

static NSRect
GnomeThemeIndicatorFocusRect(NSButtonCell *cell, NSRect cellFrame)
{
  NSRect contentRect = [cell drawingRectForBounds: cellFrame];
  CGFloat indicatorSize = MAX (GnomeThemeIndicatorMinimumSize (cell, nil),
                               floor (contentRect.size.height * 0.58));
  NSRect indicatorRect = GnomeThemeIndicatorRectInContent (cell, contentRect, indicatorSize);
  NSSize labelSize = GnomeThemeButtonLabelSize (cell);
  CGFloat labelWidth = MIN (labelSize.width,
                            NSWidth (GnomeThemeIndicatorTitleRect (cell, contentRect, indicatorRect)));
  NSRect focusRect = indicatorRect;

  if (labelWidth > 0.0)
    {
      focusRect.size.width = NSWidth (indicatorRect) + GnomeThemeIndicatorLabelGap + labelWidth;
      if (GnomeThemeIndicatorTrails (cell))
        {
          focusRect.origin.x = NSMaxX (indicatorRect) - NSWidth (focusRect);
        }
    }

  focusRect = NSInsetRect (focusRect, -3.0, -3.0);
  focusRect.origin.x = floor (focusRect.origin.x);
  focusRect.origin.y = floor (focusRect.origin.y);
  focusRect.size.width = ceil (focusRect.size.width);
  focusRect.size.height = ceil (focusRect.size.height);
  return focusRect;
}

static NSRect
GnomeThemeCenteredRect(NSRect frame, CGFloat width, CGFloat height)
{
  return NSMakeRect(NSMidX (frame) - (width / 2.0),
                    NSMidY (frame) - (height / 2.0),
                    width,
                    height);
}

/* A tab view's frame and the line between its tabs and content:
   GtkNotebook's border, the separator colour (the foreground at 15%, 50%
   in high contrast). It had been controlShadowColor blended toward the
   window, which in the dark palette all but vanished. */
static NSColor *
GnomeThemeTabBorderColor(GSTheme *theme, NSColor *headerFill)
{
  return GnomeThemeColor (theme, @"GnomeThemeSeparatorColor",
                          GnomeThemeBlend (GnomeThemeColor (theme, @"controlShadowColor",
                                                            [NSColor controlShadowColor]),
                                           headerFill, 0.43));
}

static BOOL
GnomeThemeUsesFlatTabs(NSTabViewType type)
{
  return (type == NSTopTabsBezelBorder || type == NSBottomTabsBezelBorder);
}

/* An accent button (ScreenshotTool's primary buttons): libadwaita's
   .suggested-action without being the window's default button, so Return
   keeps doing what it did. An app sets it with -setGSThemeStyle:
   (@"accent", or nil for the regular button), a theme-neutral name any
   theme may implement, as WinUI's -[NSProgressIndicator setGSThemeState:];
   apps ask -respondsToSelector: first, as other themes and AppKit don't
   have it. Kept with the cell, which is what draws. */
static char GnomeThemeButtonStyleKey;

@implementation NSButtonCell (GnomeThemeStyle)

- (void) setGSThemeStyle: (NSString *)style
{
  if ([style isEqualToString: @"accent"] == NO)
    {
      style = nil;
    }
  objc_setAssociatedObject (self, &GnomeThemeButtonStyleKey, style, OBJC_ASSOCIATION_COPY_NONATOMIC);
  [[self controlView] setNeedsDisplay: YES];
}

- (NSString *) GSThemeStyle
{
  return objc_getAssociatedObject (self, &GnomeThemeButtonStyleKey);
}

@end

@implementation NSButton (GnomeThemeStyle)

- (void) setGSThemeStyle: (NSString *)style
{
  [(NSButtonCell *)[self cell] setGSThemeStyle: style];
  [self setNeedsDisplay: YES];
}

- (NSString *) GSThemeStyle
{
  return [(NSButtonCell *)[self cell] GSThemeStyle];
}

@end

/* Apple's -[NSButton hasDestructiveAction] (macOS 11), which libs-gui
   doesn't have yet (Docs/design/destructive-button-api.md): asked of the
   cell, then of its button, only where it answers, so the theme builds and
   runs on a libs-gui without it. */
@interface NSObject (GnomeThemeDestructiveAction)
- (BOOL) hasDestructiveAction;
@end

static BOOL
GnomeThemeButtonCellIsDestructive(NSCell *cell, NSView *view)
{
  if ([cell respondsToSelector: @selector(hasDestructiveAction)])
    {
      return [(id)cell hasDestructiveAction];
    }
  if ([view isKindOfClass: [NSButton class]] && [(NSButton *)view cell] == cell
    && [view respondsToSelector: @selector(hasDestructiveAction)])
    {
      return [(id)view hasDestructiveAction];
    }
  return NO;
}

/* Whether the button is one of an alert's (GSAlertPanel, drawn as
   AdwAlertDialog). */
static BOOL
GnomeThemeViewIsInAlert(NSView *view)
{
  Class alertPanel = NSClassFromString (@"GSAlertPanel");

  return alertPanel != Nil && [[view window] isKindOfClass: alertPanel];
}

BOOL
GnomeThemeButtonCellHasAccentStyle(NSCell *cell)
{
  return [cell isKindOfClass: [NSButtonCell class]]
    && [[(NSButtonCell *)cell GSThemeStyle] isEqualToString: @"accent"];
}

static BOOL
GnomeThemeViewHasAccentButton(NSView *view)
{
  NSEnumerator *enumerator;
  NSView *subview;

  if ([view isHidden])
    {
      return NO;
    }
  if ([view isKindOfClass: [NSButton class]] && GnomeThemeButtonCellHasAccentStyle ([(NSButton *)view cell]))
    {
      return YES;
    }
  enumerator = [[view subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      if (GnomeThemeViewHasAccentButton (subview))
        {
          return YES;
        }
    }
  return NO;
}

/* From the window's frame view, so a header bar's toolbar items count. */
BOOL
GnomeThemeWindowHasAccentButton(NSWindow *window)
{
  NSView *contentView = [window contentView];
  NSView *frameView = [contentView superview];

  return GnomeThemeViewHasAccentButton (frameView != nil ? frameView : contentView);
}

static BOOL
GnomeThemeButtonCellUsesPersistentAccentSelection(NSCell *cell)
{
  NSInteger showsStateByMask;

  if ([cell isKindOfClass: [NSButtonCell class]] == NO)
    {
      return NO;
    }

  showsStateByMask = [(NSButtonCell *)cell showsStateBy];
  return (showsStateByMask != NSNoCellMask);
}

/* GtkNotebook tabs: text with 13px on each side, 7px apart, the first 9px
   in from the frame; the selected one is underlined in the accent colour. */
static const CGFloat GnomeThemeTabPadding = 13.0;
static const CGFloat GnomeThemeTabGap = 7.0;
static const CGFloat GnomeThemeTabStart = 9.0;
static const CGFloat GnomeThemeTabUnderline = 4.0;
/* Shorter tab rows are GNUstep's (nib windows): see -drawTabViewRect:... */
static const CGFloat GnomeThemeTabCompactHeight = 24.0;

static void
GnomeThemeDrawTabLabel(NSString *label,
                       NSRect tabRect,
                       NSFont *font,
                       NSColor *textColor)
{
  NSDictionary *attributes = nil;
  NSSize labelSize;
  NSRect labelRect;

  if ([label length] == 0 || font == nil || textColor == nil)
    {
      return;
    }

  attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                 font, NSFontAttributeName,
                                 textColor, NSForegroundColorAttributeName,
                                 nil];
  labelSize = [label sizeWithAttributes: attributes];
  labelRect = NSInsetRect (tabRect, GnomeThemeTabPadding, 0.0);
  labelRect.origin.x = floor (NSMidX (labelRect) - (MIN (labelSize.width, labelRect.size.width) / 2.0));
  if (ceil (labelSize.height) >= NSHeight (tabRect))
    {
      /* Taller than the tab (GNUstep's short tab row): its line's bottom,
         the descenders', at the tab's bottom; above it is only the
         ascent, room the capitals don't use. */
      labelRect.origin.y = [[NSView focusView] isFlipped]
        ? NSMaxY (tabRect) - ceil (labelSize.height) : NSMinY (tabRect);
    }
  else
    {
      labelRect.origin.y = floor (NSMidY (labelRect) - (labelSize.height / 2.0));
    }
  labelRect.size.height = ceil (labelSize.height);

  [label drawInRect: labelRect withAttributes: attributes];
}

@implementation GnomeTheme (Controls)

- (void) _overrideNSApplicationMethod_sendEvent: (NSEvent *)event
{
  typedef void (*SendEventIMP)(id, SEL, NSEvent *);
  SendEventIMP originalIMP = (SendEventIMP)GnomeThemeOriginalMethod (_cmd, self, [NSApplication class]);
  NSWindow *window = [event window];
  BOOL visible = GnomeThemeWindowFocusVisible (window);

  switch ([event type])
    {
      case NSKeyDown:
        visible = YES;
        break;
      case NSLeftMouseDown:
      case NSRightMouseDown:
      case NSOtherMouseDown:
        visible = NO;
        break;
      default:
        break;
    }
  /* Before dispatch, so a click that moves focus also clears the ring of
     the view losing it. */
  if (window != nil && visible != GnomeThemeWindowFocusVisible (window))
    {
      objc_setAssociatedObject (window, &GnomeThemeFocusVisibleKey,
                                [NSNumber numberWithBool: visible], OBJC_ASSOCIATION_RETAIN);
      GnomeThemeRedisplayFocusedView (window);
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, event);
    }
}

- (void) setKeyEquivalent: (NSString *)key
             forButtonCell: (NSButtonCell *)cell
{
  BOOL isReturnKey = [key isEqualToString: @"\r"] || [key isEqualToString: @"\n"];

  if (isReturnKey)
    {
      if (GnomeThemeImageHasName ([cell image], @"common_ret"))
        {
          [cell setImage: nil];
          if ([cell imagePosition] == NSImageRight)
            {
              [cell setImagePosition: NSNoImage];
            }
        }

      if (GnomeThemeImageHasName ([cell alternateImage], @"common_retH"))
        {
          [cell setAlternateImage: nil];
        }

      return;
    }

  [super setKeyEquivalent: key forButtonCell: cell];
}

- (void) drawFocusFrame: (NSRect)frame view: (NSView *)view
{
  CGFloat radius = MIN (9.0, floor (frame.size.height / 2.0));

  /* Buttons draw their own ring: push buttons and pop-ups in -drawButton:,
     checkboxes and radios around the indicator. NSCell would put this one
     around the title. */
  if ([view isKindOfClass: [NSButton class]] || GnomeThemeWindowFocusVisible ([view window]) == NO)
    {
      return;
    }

  GnomeThemeDrawFocusRing (self, NSInsetRect (frame, -1.0, -1.0), radius + 1.0);
}

- (void) drawButton: (NSRect)frame
                 in: (NSCell *)cell
               view: (NSView *)view
              style: (int)style
              state: (GSThemeControlState)state
{
  BOOL disabled = GnomeThemeStateIsDisabled (state) || ([cell isEnabled] == NO);
  BOOL highlighted = GnomeThemeStateIsHighlighted (state);
  BOOL selected = GnomeThemeStateIsSelected (state);
  BOOL persistentAccentSelection = selected && GnomeThemeButtonCellUsesPersistentAccentSelection (cell);
  BOOL momentaryPressed = selected && (persistentAccentSelection == NO);
  BOOL focused = GnomeThemeViewShowsFocusRing (view);
  BOOL popupButton = [cell isKindOfClass: [NSPopUpButtonCell class]];
  BOOL isDefaultButton = NO;
  NSColor *fillColor = nil;
  NSColor *strokeColor = nil;
  NSColor *baseFill = GnomeThemeColor (self, @"controlColor", [NSColor controlColor]);
  NSColor *backgroundFill = GnomeThemeColor (self, @"GnomeThemeCardColor", [NSColor controlBackgroundColor]);
  NSColor *accentFill = GnomeThemeColor (self, @"selectedControlColor", [NSColor selectedControlColor]);
  NSColor *borderBase = GnomeThemeColor (self, @"controlShadowColor", [NSColor controlShadowColor]);
  /* libadwaita's button colours: the foreground at 10% over the window,
     30% pressed, half opacity disabled. */
  NSColor *buttonFill = GnomeThemeColor (self, @"GnomeThemeButtonColor",
                                                GnomeThemeBlend (baseFill, backgroundFill, 0.08));
  NSColor *pressedFill = GnomeThemeColor (self, @"GnomeThemeButtonPressedColor",
                                                 GnomeThemeBlend (baseFill, borderBase, 0.34));
  NSColor *disabledFill = GnomeThemeColor (self, @"GnomeThemeButtonDisabledColor",
                                                  GnomeThemeBlend (baseFill, backgroundFill, 0.5));
  NSColor *outlineColor = GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil);
  NSColor *disabledOutline = (outlineColor != nil)
    ? GnomeThemeBlend (outlineColor,
                       GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]),
                       0.6)
    : nil;
  NSRect buttonRect = NSInsetRect (frame, 0.5, 0.5);
  CGFloat radius = MIN (10.0, floor (buttonRect.size.height / 2.0));
  NSString *keyEquivalent = nil;

  if ([cell respondsToSelector: @selector(keyEquivalent)])
    {
      keyEquivalent = [(id)cell keyEquivalent];
      isDefaultButton = [keyEquivalent isEqualToString: @"\r"]
        || [keyEquivalent isEqualToString: @"\n"];
    }
  if (isDefaultButton == NO && view != nil && [view window] != nil)
    {
      isDefaultButton = ([[view window] defaultButtonCell] == cell);
    }
  if (isDefaultButton && GnomeThemeWindowHasAccentButton ([view window]))
    {
      isDefaultButton = NO;
    }
  /* An accent button is drawn as the default button, flat styles too:
     libadwaita's .suggested-action is filled in a header bar as well. */
  if (popupButton == NO && GnomeThemeButtonCellHasAccentStyle (cell))
    {
      isDefaultButton = YES;
      if (style == NSRecessedBezelStyle || style == NSTexturedRoundedBezelStyle
          || style == NSTexturedSquareBezelStyle)
        {
          style = NSRoundedBezelStyle;
        }
    }

  /* A borderless pop-up button (a table's pop-up cells, mostly) is
     libadwaita's flat drop-down: no fill but while pressed. libs-gui's
     NSPopUpButtonCell asks for its bezel whether or not it is bordered. */
  if (popupButton && [cell isBordered] == NO)
    {
      if (highlighted && disabled == NO)
        {
          GnomeThemeFillAndStrokeRoundedRect (buttonRect, radius, pressedFill, nil, 0.0);
        }
      if (focused && disabled == NO)
        {
          GnomeThemeDrawFocusRing (self, NSInsetRect (buttonRect, 0.75, 0.75), MAX (0.0, radius - 0.75));
        }
      return;
    }

  /* Recessed and textured buttons, Cocoa's toolbar and scope bar styles,
     are libadwaita's .flat buttons: no fill or outline at rest, the
     foreground at 16% over the window while pressed, 10% while a toggle
     is on and 19% for both. (They were the regular filled button.)
     libs-gui reports a toggle that is on as highlighted, as it does a
     pressed button, so the cell says which it is. libadwaita's 7% hover
     fill needs the pointer tracked, which GNUstep's buttons don't do. */
  if (popupButton == NO
    && (style == NSRecessedBezelStyle || style == NSTexturedRoundedBezelStyle
        || style == NSTexturedSquareBezelStyle))
    {
      NSColor *window = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
      NSColor *text = GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);
      BOOL pressed = [cell isHighlighted] && disabled == NO;
      BOOL checked = [cell state] == NSOnState && GnomeThemeButtonCellUsesPersistentAccentSelection (cell);
      CGFloat fraction = 0.0;

      if (pressed)
        {
          fraction = checked ? 0.19 : 0.16;
        }
      else if (checked)
        {
          fraction = disabled ? 0.05 : 0.10;
        }
      if (fraction > 0.0)
        {
          GnomeThemeFillAndStrokeRoundedRect (buttonRect, radius, GnomeThemeBlend (window, text, fraction), nil, 0.0);
        }
      if (focused && disabled == NO)
        {
          GnomeThemeDrawFocusRing (self, NSInsetRect (buttonRect, 0.75, 0.75), MAX (0.0, radius - 0.75));
        }
      return;
    }

  /* libadwaita's buttons have no outline; high contrast gives them one,
     the foreground at 50% (40% opacity disabled), but not the accent
     ones. */
  if (popupButton)
    {
      fillColor = buttonFill;
      strokeColor = outlineColor;

      if (disabled)
        {
          fillColor = disabledFill;
          strokeColor = disabledOutline;
        }
      else if (highlighted)
        {
          fillColor = pressedFill;
        }
    }
  else if (disabled == NO && GnomeThemeButtonCellIsDestructive (cell, view))
    {
      /* A destructive button. In an alert, AdwAlertDialog's destructive
         response: destructive_color at 15% over the dialog, the text in it
         (#c30000 or #ff938c, measured from GTK), and not the default
         button's blue. Elsewhere libadwaita's .destructive-action:
         destructive_bg_color with white text. Pressed, as the accent
         button is, darker. */
      NSColor *red = GnomeThemeColor (self, @"GnomeThemeErrorColor", [NSColor redColor]);

      if (GnomeThemeViewIsInAlert (view))
        {
          NSColor *text = GnomeThemeColor (self, @"GnomeThemeDestructiveTextColor", red);
          NSColor *window = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);

          fillColor = GnomeThemeBlend (window, text, (highlighted || momentaryPressed) ? 0.3 : 0.15);
        }
      else
        {
          fillColor = (highlighted || momentaryPressed) ? GnomeThemeBlend (red, [NSColor blackColor], 0.18) : red;
        }
    }
  else if (disabled && GnomeThemeButtonCellHasAccentStyle (cell))
    {
      /* libadwaita's disabled .suggested-action: the whole button at half
         opacity, so the blue over the window. */
      fillColor = GnomeThemeBlend (accentFill,
                                   GnomeThemeColor (self, @"windowBackgroundColor",
                                                    [NSColor windowBackgroundColor]),
                                   0.5);
    }
  else if (disabled)
    {
      fillColor = disabledFill;
      strokeColor = disabledOutline;
    }
  else if (highlighted || momentaryPressed)
    {
      if (isDefaultButton)
        {
          fillColor = GnomeThemeBlend (accentFill, [NSColor blackColor], 0.18);
        }
      else
        {
          fillColor = pressedFill;
          strokeColor = outlineColor;
        }
    }
  else if (isDefaultButton || persistentAccentSelection)
    {
      fillColor = accentFill;
    }
  else
    {
      fillColor = buttonFill;
      strokeColor = outlineColor;
    }

  /* A disclosure button is GtkExpander's arrow, with no bezel (GSTheme
     drew nothing for it); a help or circular button is libadwaita's
     .circular button, round, the help button with its "?" (both were
     rounded squares, the "?" lost). */
  if (style == NSDisclosureBezelStyle)
    {
      NSColor *arrow = disabled
        ? GnomeThemeColor (self, @"disabledControlTextColor", [NSColor disabledControlTextColor])
        : GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);

      GnomeThemeDrawExpanderArrow (frame, [cell state] == NSOnState, arrow, [view isFlipped]);
      if (focused && disabled == NO)
        {
          GnomeThemeDrawFocusRing (self, NSInsetRect (frame, 1.25, 1.25), 4.0);
        }
      return;
    }
  if (style == NSHelpButtonBezelStyle || style == NSCircularBezelStyle)
    {
      CGFloat side = floor (MIN (NSWidth (buttonRect), NSHeight (buttonRect)));

      buttonRect = NSMakeRect (floor (NSMidX (frame) - side / 2.0) + 0.5, floor (NSMidY (frame) - side / 2.0) + 0.5,
                               side - 1.0, side - 1.0);
      radius = floor (side / 2.0);
    }

  GnomeThemeFillAndStrokeRoundedRect (buttonRect, radius, fillColor, strokeColor, 1.0);

  if (style == NSHelpButtonBezelStyle && [[(NSButtonCell *)cell title] length] == 0
    && [(NSButtonCell *)cell image] == nil)
    {
      NSFont *font = [NSFont boldSystemFontOfSize: 0];
      NSColor *text = disabled
        ? GnomeThemeColor (self, @"disabledControlTextColor", [NSColor disabledControlTextColor])
        : GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName, text, NSForegroundColorAttributeName, nil];
      NSString *mark = @"?";
      NSSize size = [mark sizeWithAttributes: attributes];

      [mark drawAtPoint: NSMakePoint (floor (NSMidX (buttonRect) - size.width / 2.0),
                                      floor (NSMidY (buttonRect) - size.height / 2.0))
         withAttributes: attributes];
    }

  /* Inside the edge, like libadwaita's focus ring (outline-offset: -2px):
     the button fills its frame, so a ring outside it would be clipped. */
  if (focused && disabled == NO)
    {
      GnomeThemeDrawFocusRing (self, NSInsetRect (buttonRect, 0.75, 0.75), MAX (0.0, radius - 0.75));
    }
}

/* A bordered colour well is GTK's colour button: a flat button, pressed
   while the colour panel is attached, holding a rounded swatch (drawn by
   -drawWellInside:). Returns the swatch's rect. */
- (NSRect) drawColorWellBorder: (NSColorWell *)well
                    withBounds: (NSRect)bounds
                      withClip: (NSRect)clipRect
{
  GSThemeControlState state = GSThemeNormalState;

  if ([well isBordered] == NO)
    {
      return bounds;
    }

  if ([well isEnabled] == NO)
    {
      state = GSThemeDisabledState;
    }
  else if ([[well cell] isHighlighted])
    {
      state = GSThemeHighlightedState;
    }
  else if ([well isActive])
    {
      state = GSThemeSelectedState;
    }
  [self drawButton: bounds
                in: [well cell]
              view: well
             style: NSRoundedBezelStyle
             state: state];

  return NSInsetRect (bounds,
                      MIN (6.0, floor (NSWidth (bounds) / 4.0)),
                      MIN (5.0, floor (NSHeight (bounds) / 4.0)));
}

/* The swatch: rounded, faded when the well is disabled, and with
   libadwaita's faint inner ring (the foreground at 10%) when the colour is
   light, so a white or light grey swatch still shows its edge. GTK calls
   a colour light past an intensity of 0.5 (0.3 red, 0.59 green, 0.11
   blue); a darker one has no ring. */
- (void) _overrideNSColorWellMethod_drawWellInside: (NSRect)insideRect
{
  NSColorWell *well = (NSColorWell *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  CGFloat radius = MIN (4.0, floor (MIN (NSWidth (insideRect), NSHeight (insideRect)) / 2.0));
  NSBezierPath *path = GnomeThemeRoundedPath (insideRect, radius);
  NSBezierPath *edge = GnomeThemeRoundedPath (NSInsetRect (insideRect, 0.5, 0.5), MAX (0.0, radius - 0.5));
  NSColor *rgb = [[well color] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL light = (rgb != nil && 0.30 * [rgb redComponent] + 0.59 * [rgb greenComponent]
                + 0.11 * [rgb blueComponent] > 0.5);

  if (NSIsEmptyRect (insideRect))
    {
      return;
    }

  [NSGraphicsContext saveGraphicsState];
  [path addClip];
  [[well color] drawSwatchInRect: insideRect];
  if ([well isEnabled] == NO)
    {
      [[GnomeThemeColor (theme, @"windowBackgroundColor", [NSColor windowBackgroundColor])
         colorWithAlphaComponent: 0.5] set];
      NSRectFillUsingOperation (insideRect, NSCompositeSourceOver);
    }
  [NSGraphicsContext restoreGraphicsState];

  if (light)
    {
      /* In RGB: a palette colour may ignore -colorWithAlphaComponent:. */
      [[[GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor])
          colorUsingColorSpaceName: NSCalibratedRGBColorSpace] colorWithAlphaComponent: 0.1] set];
      [edge setLineWidth: 1.0];
      [edge stroke];
    }
}

/* Whether the segment being drawn is enabled: -drawSegment:inFrame:withView:
   knows the segment, -drawSegmentedControlSegment:... only the cell. */
static BOOL GnomeThemeSegmentBeingDrawnIsEnabled = YES;
/* Whether the segment being drawn and the one before it are both
   unselected: libadwaita's linked buttons overlap by 1px there, and the
   column where their translucent fills meet reads as a separator. */
static BOOL GnomeThemeSegmentBeingDrawnFollowsUnselected = NO;

- (void) drawSegmentedControlSegment: (NSCell *)cell
                           withFrame: (NSRect)cellFrame
                              inView: (NSView *)controlView
                               style: (NSSegmentStyle)style
                               state: (GSThemeControlState)state
                         roundedLeft: (BOOL)roundedLeft
                        roundedRight: (BOOL)roundedRight
{
  BOOL selected = GnomeThemeStateIsSelected (state);
  BOOL disabled = GnomeThemeStateIsDisabled (state) || ([cell isEnabled] == NO)
    || GnomeThemeSegmentBeingDrawnIsEnabled == NO;
  NSColor *baseFill = GnomeThemeColor (self, @"GnomeThemeCardColor", [NSColor controlBackgroundColor]);
  NSColor *segmentFill = GnomeThemeColor (self, @"controlColor", [NSColor controlColor]);
  NSColor *borderColor = GnomeThemeColor (self, @"controlShadowColor", [NSColor controlShadowColor]);
  NSColor *windowFill = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *textColor = GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);
  NSRect drawRect = NSInsetRect (cellFrame, 0.5, 0.5);
  CGFloat interiorOverlap = 1.0;
  CGFloat radius = MIN (8.0, floor (drawRect.size.height / 2.0));
  NSBezierPath *path = nil;
  NSColor *separatorFill = nil;

  (void)style;
  (void)controlView;

  /* Linked buttons have no outline or separators in libadwaita; high
     contrast outlines them and separates them with the foreground at 50%. */
  borderColor = GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil);
  /* libadwaita's linked buttons: a button's colour, and when checked the
     foreground at 30% over the window, so the selected segment stands out
     darker in the light palette and lighter in the dark one
     (plugins-themes-Adwaita#7). */
  if (selected)
    {
      segmentFill = GnomeThemeColor (self, @"GnomeThemeButtonPressedColor",
                                            GnomeThemeBlend (windowFill, textColor, 0.30));
    }
  else
    {
      segmentFill = GnomeThemeColor (self, @"GnomeThemeButtonColor",
                                            GnomeThemeBlend (segmentFill, baseFill, 0.4));
    }

  /* The overlap's colour: the button's fill once more over itself,
     measured in GTK as 9% of the way to the text colour (#d5d5d6 light,
     #4a4a4d dark). High contrast's own separator is the outline below. */
  separatorFill = GnomeThemeBlend (segmentFill, textColor, 0.09);
  if (disabled)
    {
      segmentFill = GnomeThemeBlend (segmentFill, windowFill, 0.5);
      separatorFill = GnomeThemeBlend (separatorFill, windowFill, 0.5);
      if (borderColor != nil)
        {
          borderColor = GnomeThemeBlend (borderColor, windowFill, 0.6);
        }
    }

  if (roundedLeft == NO)
    {
      drawRect.origin.x -= interiorOverlap;
      drawRect.size.width += interiorOverlap;
    }
  if (roundedRight == NO)
    {
      drawRect.size.width += interiorOverlap;
    }

  path = GnomeThemeSegmentedControlPath (drawRect, radius, roundedLeft, roundedRight);
  [segmentFill set];
  [path fill];
  if (borderColor == nil)
    {
      if (roundedLeft == NO && selected == NO && GnomeThemeSegmentBeingDrawnFollowsUnselected)
        {
          [separatorFill set];
          NSRectFillUsingOperation (NSMakeRect (floor (NSMinX (cellFrame)), NSMinY (drawRect),
                                                1.0, NSHeight (drawRect)),
                                    NSCompositeSourceOver);
        }
      return;
    }
  [borderColor set];
  [path setLineWidth: 1.0];
  [path stroke];

  if (roundedLeft == NO)
    {
      [borderColor set];
      [NSBezierPath strokeLineFromPoint: NSMakePoint (NSMinX (drawRect), NSMinY (drawRect) + 1.0)
                                toPoint: NSMakePoint (NSMinX (drawRect), NSMaxY (drawRect) - 1.0)];
    }
}

- (void) drawBorderType: (NSBorderType)aType
                  frame: (NSRect)frame
                   view: (NSView *)view
{
  BOOL enabled = GnomeThemeViewEnabled (view);
  BOOL focused = GnomeThemeViewHasFocus (view);
  BOOL textStyleControl = ([view isKindOfClass: [NSTextField class]]
    && [view isKindOfClass: [NSScrollView class]] == NO);
  BOOL readonlyField = ([view isKindOfClass: [NSTextField class]]
    && [(NSTextField *)view isEditable] == NO
    && [(NSTextField *)view isSelectable] == NO);
  NSColor *backgroundFill = GnomeThemeColor (self, @"textBackgroundColor", [NSColor textBackgroundColor]);
  NSColor *windowFill = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *borderColor = GnomeThemeColor (self, @"controlShadowColor", [NSColor controlShadowColor]);
  NSRect borderRect = NSInsetRect (frame, 0.5, 0.5);
  CGFloat radius = ([view isKindOfClass: [NSScrollView class]] ? 10.0 : 10.0);
  CGFloat borderWidth = 1.0;

  if (aType == NSNoBorder)
    {
      return;
    }

  /* libadwaita lists and column views have no frame: the list is a plain
     area on the window background. Other scroll views (text views, for
     example) keep theirs. */
  if ([view isKindOfClass: [NSScrollView class]]
    && [[(NSScrollView *)view documentView] isKindOfClass: [NSTableView class]])
    {
      return;
    }

  if ([view isKindOfClass: [NSScrollView class]])
    {
      backgroundFill = GnomeThemeBlend (backgroundFill, windowFill, 0.18);
    }
  else if (textStyleControl)
    {
      GnomeThemeDrawEntryChrome (self,
                                 view,
                                 frame,
                                 enabled,
                                 focused,
                                 readonlyField);
      return;
    }
  else
    {
      GnomeThemeResolveEntryColors (self,
                                    view,
                                    enabled,
                                    focused,
                                    readonlyField,
                                    &backgroundFill,
                                    &borderColor,
                                    &borderWidth);
    }

  if (focused && enabled && textStyleControl == NO)
    {
      GnomeThemeDrawFocusRing (self, NSInsetRect (borderRect, -0.5, -0.5), radius + 0.5);
    }

  GnomeThemeFillAndStrokeRoundedRect (borderRect,
                                      radius,
                                      backgroundFill,
                                      borderColor,
                                      borderWidth);

  if (textStyleControl && borderColor != nil && borderWidth > 0.0)
    {
      GnomeThemeStrokeEntryCaps (borderRect, radius, borderColor);
    }

  if (aType == NSGrooveBorder)
    {
      NSColor *innerStroke = GnomeThemeBlend (borderColor, backgroundFill, 0.5);
      NSRect innerRect = NSInsetRect (borderRect, 2.0, 2.0);

      GnomeThemeFillAndStrokeRoundedRect (innerRect, MAX (radius - 2.0, 4.0), nil, innerStroke, 1.0);
    }
}

/* NSBox as libadwaita draws its counterparts; GSTheme drew NeXT's.
   - A separator box (and an untitled groove 4pt or thinner, as the save
     panel's and the alert's bars) is a GtkSeparator: a 1px line, the
     foreground at 15%. GSTheme's controlShadowColor was darker than the
     window in the dark style, so the line all but vanished.
   - An untitled line-border box is libadwaita's .card, which is what apps
     use one for (Markdown Viewer's preferences): the card colour, 12px
     corners and a faint shade. Not when it is its window's content view,
     as the combo box's and the autocomplete lists' are.
   - A titled or untitled groove is a GtkFrame: a 1px border in the
     separator colour with 12px corners, the title inside it at the top
     left rather than centred on the line.
   Custom and old-style boxes, bezel borders and titles at other
   positions stay GSTheme's. */
- (void) drawBoxInClipRect: (NSRect)clipRect
                   boxType: (NSBoxType)boxType
                borderType: (NSBorderType)borderType
                    inView: (NSBox *)box
{
  NSColor *separator = GnomeThemeColor (self, @"GnomeThemeSeparatorColor", [NSColor gridColor]);
  NSColor *window = [[box window] backgroundColor];
  NSRect borderRect = [box borderRect];
  NSTitlePosition titlePosition = [box titlePosition];
  BOOL thin = (MIN (NSWidth (borderRect), NSHeight (borderRect)) <= 4.0);

  if (window == nil)
    {
      window = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
    }

  if (boxType == NSBoxSeparator
    || (boxType == NSBoxPrimary && borderType == NSGrooveBorder
        && titlePosition == NSNoTitle && thin))
    {
      NSColor *line = (boxType == NSBoxSeparator) ? [box borderColor] : nil;
      NSRect lineRect = borderRect;

      if (line == nil || [line alphaComponent] == 0.0)
        {
          line = separator;
        }
      if (boxType != NSBoxSeparator)
        {
          [window set];
          NSRectFill (NSIntersectionRect (clipRect, borderRect));
        }
      if (NSWidth (borderRect) >= NSHeight (borderRect))
        {
          lineRect.origin.y = floor (NSMidY (borderRect) - 0.5);
          lineRect.size.height = 1.0;
        }
      else
        {
          lineRect.origin.x = floor (NSMidX (borderRect) - 0.5);
          lineRect.size.width = 1.0;
        }
      [line set];
      NSRectFill (lineRect);
      return;
    }

  if ((boxType != NSBoxPrimary && boxType != NSBoxSecondary)
    || (borderType != NSLineBorder && borderType != NSGrooveBorder)
    || (titlePosition != NSNoTitle && titlePosition != NSAtTop)
    || (borderType == NSLineBorder && titlePosition == NSNoTitle
        && [[box window] contentView] == box))
    {
      [super drawBoxInClipRect: clipRect boxType: boxType borderType: borderType inView: box];
      return;
    }

  [window set];
  NSRectFill (clipRect);

  if (borderType == NSLineBorder && titlePosition == NSNoTitle)
    {
      NSColor *card = GnomeThemeColor (self, @"GnomeThemeCardColor", [NSColor controlBackgroundColor]);
      NSColor *outline = GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil);
      NSColor *shade = [NSColor colorWithCalibratedRed: 0.0 green: 0.0 blue: 6.0 / 255.0 alpha: 0.07];

      GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (borderRect, 0.5, 0.5), 12.0, card,
                                          (outline != nil) ? outline : shade, 1.0);
      return;
    }

  if (titlePosition == NSAtTop)
    {
      /* The border's top edge goes up to the title's, so the title sits
         inside the frame. */
      NSRect titleRect = [box titleRect];

      borderRect.size.height = NSMaxY (titleRect) - NSMinY (borderRect);
      GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (borderRect, 0.5, 0.5), 12.0, nil, separator, 1.0);
      titleRect.origin.x = NSMinX (borderRect) + 6.0;
      titleRect.origin.y -= 2.0;
      [[box titleCell] drawWithFrame: titleRect inView: box];
      return;
    }

  GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (borderRect, 0.5, 0.5), 12.0, nil, separator, 1.0);
}

/* An indeterminate bar is GtkProgressBar pulsing: a pill a fifth of the
   trough long in the accent, going from end to end and back (GNUstep
   filled the bar with grey stripes in turn). A spinner is AdwSpinner: a
   ring in the foreground at 15% with a quarter of it in the foreground,
   turning (GNUstep's was a NeXT image sequence). The animation's count
   comes from NSProgressIndicator, twelve a second. Determinate bars are
   GSTheme's, with the theme's bezel and fill. */
- (void) drawProgressIndicator: (NSProgressIndicator *)progress
                    withBounds: (NSRect)bounds
                      withClip: (NSRect)rect
                       atCount: (int)count
                      forValue: (double)val
{
  NSColor *accent = GnomeThemeColor (self, @"selectedControlColor", [NSColor selectedControlColor]);

  if ([progress style] == NSProgressIndicatorSpinningStyle)
    {
      NSColor *window = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
      NSColor *foreground = GnomeThemeColor (self, @"GnomeThemeForegroundColor", [NSColor controlTextColor]);
      CGFloat side = floor (MIN (NSWidth (bounds), NSHeight (bounds)));
      CGFloat thickness = MAX (2.0, floor (side / 8.0));
      NSPoint centre = NSMakePoint (NSMidX (bounds), NSMidY (bounds));
      CGFloat radius = (side - thickness) / 2.0;
      CGFloat start = -90.0 - (count % 12) * 30.0;
      NSBezierPath *ring = [NSBezierPath bezierPath];
      NSBezierPath *arc = [NSBezierPath bezierPath];

      if (radius <= 0.0)
        {
          return;
        }
      [ring appendBezierPathWithArcWithCenter: centre radius: radius startAngle: 0.0 endAngle: 360.0];
      [ring setLineWidth: thickness];
      [GnomeThemeBlend (window, foreground, 0.15) set];
      [ring stroke];
      [arc appendBezierPathWithArcWithCenter: centre radius: radius
                                  startAngle: start endAngle: start + 90.0];
      [arc setLineWidth: thickness];
      [arc setLineCapStyle: NSRoundLineCapStyle];
      [foreground set];
      [arc stroke];
      return;
    }
  if ([progress isIndeterminate] && [progress isVertical] == NO)
    {
      NSRect trough = [progress isBezeled]
        ? [self drawProgressIndicatorBezel: bounds withClip: rect]
        : GnomeThemeProgressTrackRect (bounds);
      CGFloat length = floor (NSWidth (trough) / 5.0);
      NSInteger period = 30;
      NSInteger phase = count % period;
      /* 0 to 1 and back over the period. */
      CGFloat t = (phase <= period / 2) ? (CGFloat)phase / (period / 2) : (CGFloat)(period - phase) / (period / 2);
      NSRect block = trough;

      block.size.width = length;
      block.origin.x = floor (NSMinX (trough) + (NSWidth (trough) - length) * t);
      GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (block, 0.5, 0.5), floor (NSHeight (block) / 2.0),
                                          accent, nil, 0.0);
      return;
    }
  /* libadwaita's bar fills the trough's height. libs-gui hands
     -drawProgressIndicatorBarDeterminate: the trough already, and taking
     the track out of it again left a 6pt bar in the 8pt trough. */
  if ([progress isIndeterminate] == NO && [progress isVertical] == NO)
    {
      NSRect trough = [progress isBezeled]
        ? [self drawProgressIndicatorBezel: bounds withClip: rect]
        : GnomeThemeProgressTrackRect (bounds);
      NSRect bar = trough;

      bar.size.width = floor (NSWidth (trough) * MAX (0.0, MIN (1.0, val)));
      if (NSWidth (bar) > 0.0)
        {
          [self drawProgressIndicatorBarDeterminate: bar];
        }
      return;
    }
  [super drawProgressIndicator: progress withBounds: bounds withClip: rect atCount: count forValue: val];
}

/* An image view's frame (photo, grey bezel, groove) is GtkFrame's border:
   1pt, the foreground at 15% (50% in high contrast), rounded 6pt, which
   keeps the corners of an image 2pt inside clear of it. GNUstep drew NeXT
   bevels, nearly invisible in the dark palette. The button style keeps
   the theme's button. */
- (void) drawBorderForImageFrameStyle: (NSImageFrameStyle)frameStyle
                                frame: (NSRect)frame
                                 view: (NSView *)view
{
  NSColor *border = GnomeThemeColor (self, @"GnomeThemeSeparatorColor", [NSColor gridColor]);

  if (frameStyle == NSImageFrameNone || frameStyle == NSImageFrameButton)
    {
      [super drawBorderForImageFrameStyle: frameStyle frame: frame view: view];
      return;
    }
  GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (frame, 0.5, 0.5), 6.0, nil, border, 1.0);
}

- (NSRect) drawProgressIndicatorBezel: (NSRect)bounds withClip: (NSRect)rect
{
  /* libadwaita's trough: the foreground at 15% over the window. */
  NSColor *trackFill = GnomeThemeColor (self, @"GnomeThemeTroughColor",
                                               GnomeThemeBlend ([NSColor controlColor],
                                                                [NSColor controlBackgroundColor],
                                                                0.28));
  NSRect drawRect = GnomeThemeProgressTrackRect (bounds);
  CGFloat radius = floor (drawRect.size.height / 2.0);

  (void)rect;
  /* High contrast outlines the trough (the foreground at 50%). */
  GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (drawRect, 0.5, 0.5),
                                      radius,
                                      trackFill,
                                      GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil),
                                      1.0);
  return drawRect;
}

/* The bar: bounds is the filled part of the trough. */
- (void) drawProgressIndicatorBarDeterminate: (NSRect)bounds
{
  NSColor *fillColor = GnomeThemeColor (self, @"selectedControlColor", [NSColor selectedControlColor]);
  NSRect drawRect = bounds;
  CGFloat radius = floor (drawRect.size.height / 2.0);

  GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (drawRect, 0.5, 0.5),
                                      radius,
                                      fillColor,
                                      nil,
                                      0.0);
}

- (void) drawSliderBorderAndBackground: (NSBorderType)aType
                                 frame: (NSRect)cellFrame
                                inCell: (NSCell *)cell
                          isHorizontal: (BOOL)horizontal
{
  NSSliderType type = [(NSSliderCell *)cell sliderType];

  if (type != NSLinearSlider)
    {
      [super drawSliderBorderAndBackground: aType
                                     frame: cellFrame
                                    inCell: cell
                              isHorizontal: horizontal];
    }
}

- (void) drawBarInside: (NSRect)rect
                inCell: (NSCell *)cell
               flipped: (BOOL)flipped
{
  NSSliderCell *sliderCell = (NSSliderCell *)cell;
  BOOL horizontal = (rect.size.width >= rect.size.height);
  /* libadwaita's trough: 4px, the text colour at 15% over the window
     background (#dddddd light, #434346 dark) (#56). */
  CGFloat thickness = 4.0;
  CGFloat margin = 11.0;
  CGFloat fraction = 0.0;
  NSRect trackRect = rect;
  NSRect fillRect = NSZeroRect;
  NSColor *trackFill = GnomeThemeColor (self, @"GnomeThemeTroughColor",
                                               GnomeThemeBlend ([NSColor controlColor],
                                                                [NSColor controlBackgroundColor],
                                                                0.3));
  NSColor *accentFill = GnomeThemeColor (self, @"selectedControlColor", [NSColor selectedControlColor]);

  if ([sliderCell maxValue] > [sliderCell minValue])
    {
      fraction = ([sliderCell doubleValue] - [sliderCell minValue])
        / ([sliderCell maxValue] - [sliderCell minValue]);
    }

  if (fraction < 0.0)
    {
      fraction = 0.0;
    }
  else if (fraction > 1.0)
    {
      fraction = 1.0;
    }

  if (horizontal)
    {
      trackRect.origin.x += margin;
      trackRect.size.width -= (margin * 2.0);
      trackRect.origin.y = NSMidY (rect) - (thickness / 2.0);
      trackRect.size.height = thickness;

      fillRect = trackRect;
      fillRect.size.width = trackRect.size.width * fraction;
    }
  else
    {
      trackRect.origin.y += margin;
      trackRect.size.height -= (margin * 2.0);
      trackRect.origin.x = NSMidX (rect) - (thickness / 2.0);
      trackRect.size.width = thickness;

      fillRect = trackRect;
      fillRect.size.height = trackRect.size.height * fraction;
      if (flipped == NO)
        {
          fillRect.origin.y = NSMaxY (trackRect) - fillRect.size.height;
        }
    }

  /* High contrast outlines the trough (the foreground at 50%). */
  if (GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil) != nil)
    {
      GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (trackRect, 0.5, 0.5),
                                          thickness / 2.0 - 0.5,
                                          trackFill,
                                          GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil),
                                          1.0);
    }
  else
    {
      GnomeThemeFillAndStrokeRoundedRect (trackRect, thickness / 2.0, trackFill, nil, 0.0);
    }

  if (fillRect.size.width > 0.0 && fillRect.size.height > 0.0)
    {
      GnomeThemeFillAndStrokeRoundedRect (fillRect,
                                          thickness / 2.0,
                                          accentFill,
                                          nil,
                                          0.0);
    }

  /* Tick marks (libs-gui draws none): GtkScale's marks, 1x6pt in the
     foreground at 55%, 6pt from the trough on the cell's side of it, one
     at each end of the knob's travel and evenly between. */
  if ([sliderCell numberOfTickMarks] > 0)
    {
      NSInteger count = [sliderCell numberOfTickMarks];
      BOOL after = ([sliderCell tickMarkPosition] == NSTickMarkBelow);
      /* Half that disabled, as libadwaita's insensitive scale. */
      NSColor *markColor = GnomeThemeBlend (GnomeThemeColor (self, @"windowBackgroundColor",
                                                             [NSColor windowBackgroundColor]),
                                            GnomeThemeColor (self, @"GnomeThemeForegroundColor",
                                                             [NSColor controlTextColor]),
                                            [cell isEnabled] ? 0.55 : 0.275);
      NSInteger i;

      [markColor set];
      for (i = 0; i < count; i++)
        {
          CGFloat t = (count > 1) ? (CGFloat)i / (count - 1) : 0.5;
          NSRect mark;

          if (horizontal)
            {
              /* On the trough's low-y side: below on screen unflipped,
                 above it flipped. */
              BOOL down = (after != flipped);
              CGFloat x = floor (NSMinX (trackRect) + NSWidth (trackRect) * t);

              mark = NSMakeRect (MIN (x, NSMaxX (trackRect) - 1.0),
                                 down ? NSMinY (trackRect) - 6.0 - 6.0 : NSMaxY (trackRect) + 6.0,
                                 1.0, 6.0);
            }
          else
            {
              CGFloat y = floor (NSMinY (trackRect) + NSHeight (trackRect) * t);

              mark = NSMakeRect (after ? NSMaxX (trackRect) + 6.0 : NSMinX (trackRect) - 6.0 - 6.0,
                                 MIN (y, NSMaxY (trackRect) - 1.0), 6.0, 1.0);
            }
          /* Outside the bar's rect, inside the slider. */
          if ([cell controlView] != nil)
            {
              mark = NSIntersectionRect (mark, [[cell controlView] bounds]);
            }
          NSRectFill (mark);
        }
    }
}

/* libadwaita's slider knob: 20px, light in both styles (sliderKnobColor),
   with a faint outline and a soft shadow below it (measured from
   libadwaita 1.7: about 10% black round the edge, 20% just under it,
   fading over 3px). A knob in textBackgroundColor vanished on the dark
   palette's trough (#56). */
- (void) drawKnobInCell: (NSCell *)cell
{
  NSSliderCell *sliderCell = (NSSliderCell *)cell;
  NSView *controlView = [cell controlView];
  NSRect knobRect = [sliderCell knobRectFlipped: [controlView isFlipped]];
  BOOL enabled = [cell isEnabled];
  BOOL focused = GnomeThemeViewShowsFocusRing (controlView) && enabled;
  NSColor *fillColor = GnomeThemeColor (self, @"sliderKnobColor", [NSColor whiteColor]);
  NSColor *black = [NSColor blackColor];
  CGFloat knobSize = 20.0;
  CGFloat down = [controlView isFlipped] ? 1.0 : -1.0;

  if (fillColor == nil)
    {
      fillColor = [NSColor whiteColor];
    }
  knobRect = GnomeThemeCenteredRect (knobRect, knobSize, knobSize);
  if (controlView != nil)
    {
      knobRect = [controlView centerScanRect: knobRect];
    }

  if (enabled == NO)
    {
      fillColor = GnomeThemeBlend (fillColor,
                                   GnomeThemeColor (self, @"windowBackgroundColor",
                                                    [NSColor windowBackgroundColor]),
                                   0.5);
    }

  /* The shadow below the knob: two wider, fainter discs. */
  [[black colorWithAlphaComponent: 0.06] set];
  [[NSBezierPath bezierPathWithOvalInRect:
     NSOffsetRect (NSInsetRect (knobRect, -1.5, -1.5), 0.0, 1.5 * down)] fill];
  [[black colorWithAlphaComponent: 0.1] set];
  [[NSBezierPath bezierPathWithOvalInRect:
     NSOffsetRect (NSInsetRect (knobRect, -0.5, -0.5), 0.0, 1.0 * down)] fill];

  if (focused)
    {
      GnomeThemeDrawFocusRing (self, NSInsetRect (knobRect, -2.0, -2.0), knobSize / 2.0 + 2.0);
    }

  GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (knobRect, 0.5, 0.5),
                                      knobSize / 2.0,
                                      fillColor,
                                      [black colorWithAlphaComponent: 0.1],
                                      1.0);
}

BOOL
GnomeThemeScrollViewHasFrame(NSScrollView *scrollView)
{
  return [scrollView borderType] != NSNoBorder
    && [[scrollView documentView] isKindOfClass: [NSTableView class]] == NO;
}

/* libadwaita's frame round a text view or other scrolled content: a 1px
   border, the text colour at 15% over the view's background (40% in high
   contrast, as measured), with 8px corners; GNUstep's bezel (two dark lines top and
   left, square corners) looked like a sunken Windows 9x field (#58). The
   scroll view draws before its content, so the corners can't clip it:
   the radius is at most what keeps the content's square corners inside
   the border, from the inset the content and scrollers actually have
   (4px with overlay scrollers, see -tile; GNUstep's 2px otherwise). */
static void
GnomeThemeDrawScrollViewFrame(GnomeTheme *theme, NSScrollView *scrollView)
{
  NSRect bounds = [scrollView bounds];
  NSRect used = [[scrollView contentView] frame];
  NSArray *subviews = [scrollView subviews];
  NSEnumerator *enumerator = [subviews objectEnumerator];
  NSView *subview;
  id document = [scrollView documentView];
  NSColor *text = GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor]);
  NSColor *fill = GnomeThemeColor (theme, @"textBackgroundColor", [NSColor textBackgroundColor]);
  NSColor *border;
  CGFloat inset, radius;

  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview isKindOfClass: [NSScroller class]] && [subview isHidden] == NO)
        {
          used = NSUnionRect (used, [subview frame]);
        }
    }
  inset = MIN (MIN (NSMinX (used) - NSMinX (bounds), NSMinY (used) - NSMinY (bounds)),
               MIN (NSMaxX (bounds) - NSMaxX (used), NSMaxY (bounds) - NSMaxY (used)));
  /* The largest radius whose 1px border's inner edge passes outside the
     content's corner, inset px in: (r + 0.5 - inset) * sqrt 2 <= r - 0.5. */
  radius = floor (((inset - 0.5) * M_SQRT2 - 0.5) / (M_SQRT2 - 1.0));
  radius = MAX (0.0, MIN (8.0, radius));

  if ([document respondsToSelector: @selector(drawsBackground)]
      && [document respondsToSelector: @selector(backgroundColor)]
      && [document drawsBackground] && [document backgroundColor] != nil)
    {
      fill = [document backgroundColor];
    }
  border = GnomeThemeBlend (fill, text, [[theme settings] highContrastEnabled] ? 0.4 : 0.15);
  GnomeThemeFillAndStrokeRoundedRect (NSInsetRect (bounds, 0.5, 0.5), radius, fill, border, 1.0);
}

/* Scroll views holding a table or outline view get no bezel and no line
   between the content and the scrollers (see -drawBorderType:frame:view:):
   the space GNUstep leaves for them is filled with the table's background,
   so the list reads as one plain area. Other scroll views with a border
   get libadwaita's frame; without one, GNUstep's drawing (none). */
- (void) drawScrollViewRect: (NSRect)rect
                     inView: (NSView *)view
{
  NSTableView *tableView = nil;
  NSColor *background = nil;

  if ([view isKindOfClass: [NSScrollView class]])
    {
      id documentView = [(NSScrollView *)view documentView];

      if ([documentView isKindOfClass: [NSTableView class]])
        {
          tableView = documentView;
        }
      else if (GnomeThemeScrollViewHasFrame ((NSScrollView *)view))
        {
          GnomeThemeDrawScrollViewFrame (self, (NSScrollView *)view);
          return;
        }
    }
  if (tableView == nil)
    {
      [super drawScrollViewRect: rect inView: view];
      return;
    }

  /* libadwaita's lists (a combo box's, a source list) have none
     (GnomeThemeLists.m). */
  if (GnomeThemeTableListStyle (tableView) != GnomeThemeListStyleNone)
    {
      return;
    }
  /* libadwaita's view colour, unless the app gave the table its own
     background (#62). */
  background = [tableView backgroundColor];
  if (background == nil || [background isEqual: [NSColor controlBackgroundColor]])
    {
      background = GnomeThemeColor (self, @"rowBackgroundColor",
                                           [NSColor controlBackgroundColor]);
    }
  [background set];
  NSRectFill (NSIntersectionRect (rect, [view bounds]));
}

- (void) drawScrollerRect: (NSRect)rect
                   inView: (NSView *)view
                  hitPart: (NSScrollerPart)hitPart
             isHorizontal: (BOOL)isHorizontal
{
  NSScroller *scroller = (NSScroller *)view;
  if (GnomeThemeScrollerShowsOverflow (scroller) == NO)
    {
      GnomeThemeEraseScrollerRect (scroller, [scroller bounds]);
      return;
    }

  GnomeThemeDrawModernScroller (self, scroller, rect, hitPart, isHorizontal);
}

/* GTK's spin button puts − and + side by side, each about 24pt wide, but
   Cocoa steppers are about 19x27pt and laid out for an up half and a down
   half. A stepper taller than it is wide gets the halves, + above −, as
   libadwaita's vertical spin button; a wider one keeps − and + side by
   side, as a spin button's end. */
static BOOL
GnomeThemeStepperIsVertical(NSRect frame)
{
  return NSHeight (frame) > NSWidth (frame);
}

static NSBezierPath *
GnomeThemeStepperPath(NSRect frame)
{
  NSRect drawRect = NSInsetRect (frame, 0.5, 0.5);

  if (GnomeThemeStepperIsVertical (frame))
    {
      return GnomeThemeRoundedPath (drawRect, MIN (6.0, floor (NSWidth (drawRect) / 3.0)));
    }
  return GnomeThemeSegmentedControlPath (drawRect, MIN (8.0, floor (drawRect.size.height / 2.0)), NO, YES);
}

/* libadwaita's switch: a 46x26 pill (3pt round a 20pt knob), the text
   colour at 15% when off (30% in high contrast), the accent when on; the
   knob white (a little darker in the dark palette) with a soft shadow, at
   the start when off and the end when on. Disabled, it fades to 50% (40%
   in high contrast). Smaller frames shrink it; larger ones centre it.
   (plugins-themes-Adwaita#35) */
- (void) drawSwitchInRect: (NSRect)rect
                 forState: (NSControlStateValue)state
                  enabled: (BOOL)enabled
{
  CGFloat scale = MIN (1.0, MIN (NSWidth (rect) / 46.0, NSHeight (rect) / 26.0));
  NSRect track = NSMakeRect (floor (NSMidX (rect) - 23.0 * scale), floor (NSMidY (rect) - 13.0 * scale),
                             floor (46.0 * scale), floor (26.0 * scale));
  CGFloat padding = 3.0 * scale;
  CGFloat knobSize = NSHeight (track) - 2.0 * padding;
  BOOL on = (state == NSControlStateValueOn);
  BOOL highContrast = [[self settings] highContrastEnabled];
  CGFloat opacity = enabled ? 1.0 : (highContrast ? 0.4 : 0.5);
  NSColor *text = GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);
  NSColor *background = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *view = GnomeThemeColor (self, @"GnomeThemeCardColor", [NSColor controlBackgroundColor]);
  NSColor *accent = GnomeThemeColor (self, @"selectedControlColor", [NSColor selectedControlColor]);
  /* In RGB: a palette colour may ignore -colorWithAlphaComponent:. */
  NSColor *trackColor = [(on ? accent : GnomeThemeBlend (background, text, highContrast ? 0.30 : 0.15))
                          colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  /* libadwaita's knob: white when on; when off, white with a fifth of the
     card colour (white in the light palette, #d2d2d2 in the dark). */
  NSColor *knobColor = [(on ? [NSColor whiteColor] : GnomeThemeBlend ([NSColor whiteColor], view, 0.2))
                          colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSView *focusView = [NSView focusView];
  BOOL flipped = [focusView isFlipped];
  NSRect knob = NSMakeRect (on ? NSMaxX (track) - padding - knobSize : NSMinX (track) + padding,
                            NSMinY (track) + padding, knobSize, knobSize);

  if (NSIsEmptyRect (track))
    {
      return;
    }
  [[trackColor colorWithAlphaComponent: opacity] set];
  [[NSBezierPath bezierPathWithRoundedRect: track xRadius: NSHeight (track) / 2.0 yRadius: NSHeight (track) / 2.0] fill];
  /* The knob's shadow, 0 2px 4px black at 20%, as two soft rings below it. */
  if (enabled)
    {
      CGFloat drop = flipped ? 1.0 * scale : -1.0 * scale;

      [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.08] set];
      [[NSBezierPath bezierPathWithOvalInRect: NSOffsetRect (NSInsetRect (knob, -1.0, -1.0), 0.0, 2.0 * drop)] fill];
      [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.10] set];
      [[NSBezierPath bezierPathWithOvalInRect: NSOffsetRect (knob, 0.0, drop)] fill];
    }
  [[knobColor colorWithAlphaComponent: opacity] set];
  [[NSBezierPath bezierPathWithOvalInRect: knob] fill];
  if (enabled && GnomeThemeViewShowsFocusRing (focusView))
    {
      GnomeThemeDrawFocusRing (self, NSInsetRect (track, -3.0, -3.0), NSHeight (track) / 2.0 + 3.0);
    }
}

- (NSRect) stepperUpButtonRectWithFrame: (NSRect)frame
{
  if (GnomeThemeStepperIsVertical (frame))
    {
      CGFloat bottomHeight = floor (frame.size.height / 2.0);

      return NSMakeRect (frame.origin.x,
                         frame.origin.y + bottomHeight,
                         frame.size.width,
                         frame.size.height - bottomHeight);
    }
  else
    {
      CGFloat rightWidth = ceil (frame.size.width / 2.0);

      return NSMakeRect (NSMaxX (frame) - rightWidth,
                         frame.origin.y,
                         rightWidth,
                         frame.size.height);
    }
}

- (NSRect) stepperDownButtonRectWithFrame: (NSRect)frame
{
  if (GnomeThemeStepperIsVertical (frame))
    {
      return NSMakeRect (frame.origin.x,
                         frame.origin.y,
                         frame.size.width,
                         floor (frame.size.height / 2.0));
    }
  else
    {
      CGFloat leftWidth = floor (frame.size.width / 2.0);

      return NSMakeRect (frame.origin.x,
                         frame.origin.y,
                         leftWidth,
                         frame.size.height);
    }
}

- (void) drawStepperBorder: (NSRect)frame
{
  NSRect drawRect = NSInsetRect (frame, 0.5, 0.5);
  /* A spin button's buttons: an entry's colour, with libadwaita's
     separators between them. */
  NSColor *baseFill = GnomeThemeColor (self, @"GnomeThemeButtonColor",
                                              GnomeThemeBlend (GnomeThemeColor (self,
                                                                                @"controlColor",
                                                                                [NSColor controlColor]),
                                                               GnomeThemeColor (self,
                                                                                @"windowBackgroundColor",
                                                                                [NSColor windowBackgroundColor]),
                                                               0.10));
  /* No outline, as libadwaita's; high contrast's 50% one. */
  NSColor *strokeColor = GnomeThemeColor (self, @"GnomeThemeOutlineColor", nil);
  NSColor *separatorColor = GnomeThemeColor (self, @"GnomeThemeSeparatorColor",
                                                    GnomeThemeBlend (GnomeThemeColor (self,
                                                                                      @"controlShadowColor",
                                                                                      [NSColor controlShadowColor]),
                                                                     baseFill,
                                                                     0.8));
  NSBezierPath *path = GnomeThemeStepperPath (frame);

  [baseFill set];
  [path fill];
  if (strokeColor != nil)
    {
      [strokeColor set];
      [path setLineWidth: 1.0];
      [path stroke];
    }

  [separatorColor set];
  if (GnomeThemeStepperIsVertical (frame))
    {
      CGFloat separatorY = NSMinY (frame) + floor (frame.size.height / 2.0) + 0.5;

      [NSBezierPath strokeLineFromPoint: NSMakePoint (NSMinX (drawRect) + 3.0, separatorY)
                                toPoint: NSMakePoint (NSMaxX (drawRect) - 3.0, separatorY)];
    }
  else
    {
      CGFloat separatorX = NSMinX (drawRect) + floor (drawRect.size.width / 2.0);

      [NSBezierPath strokeLineFromPoint: NSMakePoint (separatorX, NSMinY (drawRect) + 6.0)
                                toPoint: NSMakePoint (separatorX, NSMaxY (drawRect) - 6.0)];
    }
}

/* The pressed half: the stepper's shape, cut to the half. */
static void
GnomeThemeFillStepperHalf(NSRect frame, NSRect half)
{
  NSColor *fillColor = GnomeThemeColor (GnomeThemeActiveTheme (), @"GnomeThemeButtonPressedColor",
                                               GnomeThemeBlend ([NSColor controlColor],
                                                                [NSColor controlBackgroundColor],
                                                                0.34));
  NSBezierPath *path = GnomeThemeStepperPath (NSInsetRect (frame, 1.0, 1.0));

  [NSGraphicsContext saveGraphicsState];
  NSRectClip (half);
  [fillColor set];
  [path fill];
  [NSGraphicsContext restoreGraphicsState];
}

- (void) drawStepperCell: (NSCell *)cell
               withFrame: (NSRect)cellFrame
                  inView: (NSView *)controlView
             highlightUp: (BOOL)highlightUp
           highlightDown: (BOOL)highlightDown
{
  NSRect upRect = [self stepperUpButtonRectWithFrame: cellFrame];
  NSRect downRect = [self stepperDownButtonRectWithFrame: cellFrame];
  BOOL canIncrement = [cell isEnabled];
  BOOL canDecrement = canIncrement;
  NSColor *textColor = GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);
  NSColor *dimColor = GnomeThemeColor (self, @"disabledControlTextColor", [NSColor disabledControlTextColor]);

  /* As GTK's spin button: a button that can't change the value is dimmed. */
  if ([cell isKindOfClass: [NSStepperCell class]] && [(NSStepperCell *)cell valueWraps] == NO)
    {
      NSStepperCell *stepper = (NSStepperCell *)cell;

      canIncrement = canIncrement && [stepper doubleValue] < [stepper maxValue];
      canDecrement = canDecrement && [stepper doubleValue] > [stepper minValue];
    }

  [self drawStepperBorder: cellFrame];
  if (highlightUp)
    {
      GnomeThemeFillStepperHalf (cellFrame, upRect);
    }
  if (highlightDown)
    {
      GnomeThemeFillStepperHalf (cellFrame, downRect);
    }

  GnomeThemeDrawStepperGlyph (upRect, YES, canIncrement ? textColor : dimColor);
  GnomeThemeDrawStepperGlyph (downRect, NO, canDecrement ? textColor : dimColor);
}

- (void) drawStepperUpButton: (NSRect)aRect
{
  GnomeThemeDrawStepperGlyph (aRect, YES, [NSColor controlTextColor]);
}

- (void) drawStepperHighlightUpButton: (NSRect)aRect
{
  NSColor *fillColor = GnomeThemeColor (self, @"GnomeThemeButtonPressedColor",
                                               GnomeThemeBlend ([NSColor controlColor],
                                                                [NSColor controlBackgroundColor],
                                                                0.34));
  NSBezierPath *path = GnomeThemeSegmentedControlPath (NSInsetRect (aRect, 1.0, 1.0),
                                                       MIN (8.0, floor (aRect.size.height / 2.0)),
                                                       NO,
                                                       YES);

  [fillColor set];
  [path fill];
  [self drawStepperUpButton: aRect];
}

- (void) drawStepperDownButton: (NSRect)aRect
{
  GnomeThemeDrawStepperGlyph (aRect, NO, [NSColor controlTextColor]);
}

- (void) drawStepperHighlightDownButton: (NSRect)aRect
{
  NSColor *fillColor = GnomeThemeColor (self, @"GnomeThemeButtonPressedColor",
                                               GnomeThemeBlend ([NSColor controlColor],
                                                                [NSColor controlBackgroundColor],
                                                                0.34));
  NSBezierPath *path = [NSBezierPath bezierPathWithRect: NSInsetRect (aRect, 1.0, 1.0)];

  [fillColor set];
  [path fill];
  [self drawStepperDownButton: aRect];
}

- (void) drawPopUpButtonCellInteriorWithFrame: (NSRect)cellFrame
                                     withCell: (NSCell *)cell
                                       inView: (NSView *)controlView
{
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSRect buttonRect = GnomeThemeComboBoxButtonRect (cellFrame);
  /* libadwaita's drop-down: the chevron in the text colour, with no
     divider before it (#59). */
  NSColor *arrowColor = GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor]);

  /* NSPopUpButtonCell asks while it draws the title in the title's frame;
     the theme's -drawInteriorWithFrame: override draws the chevron after. */
  if (GnomeThemeDrawingPopUpTitle)
    {
      return;
    }
  (void)cell;
  if ([cell isEnabled] == NO)
    {
      arrowColor = GnomeThemeColor (theme, @"disabledControlTextColor", [NSColor disabledControlTextColor]);
    }
  GnomeThemeDrawPopupChevron (NSInsetRect (buttonRect, 6.0, 6.0),
                              arrowColor,
                              [controlView isFlipped]);
}

/* The tab height is the tab view's window's (-tabHeightForType: has no
   view to ask): a nib window's tab view keeps GNUstep's (#24). */
- (NSRect) tabViewContentRectForBounds: (NSRect)aRect
                           tabViewType: (NSTabViewType)type
                               tabView: (NSTabView *)view
{
  NSView *previous = GnomeThemeSetMetricsView (view);
  NSRect contentRect = [super tabViewContentRectForBounds: aRect
                                              tabViewType: type
                                                  tabView: view];

  GnomeThemeSetMetricsView (previous);
  return contentRect;
}

/* Top tabs look like a libadwaita GtkNotebook: a 1px frame around tabs and
   content, the tabs as plain text on the window background with a line under
   them. The content is on the window background too, as a page of a
   libadwaita view switcher (what a tab view is in a GNOME app) is: on the
   view background, the controls on it came out lighter than libadwaita's. */
- (void) drawTabViewBezelRect: (NSRect)aRect
                  tabViewType: (NSTabViewType)type
                       inView: (NSView *)view
{
  NSTabView *tabView = (NSTabView *)view;
  BOOL flipped = [view isFlipped];
  NSView *previous = GnomeThemeSetMetricsView (view);
  CGFloat tabHeight = [self tabHeightForType: type];
  NSColor *headerFill = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *contentFill = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *borderColor = GnomeThemeTabBorderColor (self, headerFill);
  NSRect headerRect;
  NSRect contentRect;
  NSRect separatorRect;
  BOOL top;

  GnomeThemeSetMetricsView (previous);
  if ([view isKindOfClass: [NSTabView class]] == NO
    || GnomeThemeUsesFlatTabs (type) == NO)
    {
      [super drawTabViewBezelRect: aRect tabViewType: type inView: view];
      return;
    }

  /* Bottom tabs are the same row below the content, its line on the
     content's side. */
  top = (type == NSTopTabsBezelBorder);
  NSDivideRect (aRect, &headerRect, &contentRect, tabHeight, (top == flipped) ? NSMinYEdge : NSMaxYEdge);
  NSDivideRect (headerRect, &separatorRect, &headerRect, 1.0, (top != flipped) ? NSMinYEdge : NSMaxYEdge);

  [headerFill set];
  NSRectFill (headerRect);
  if ([tabView drawsBackground])
    {
      [contentFill set];
      NSRectFill (contentRect);
    }
  [borderColor set];
  NSRectFill (separatorRect);
  NSFrameRect (aRect);
}

- (void) drawTabViewRect: (NSRect)rect
                  inView: (NSView *)view
               withItems: (NSArray *)items
            selectedItem: (NSTabViewItem *)selectedItem
{
  NSTabView *tabView = (NSTabView *)view;
  NSTabViewType type = [tabView tabViewType];
  BOOL truncate = [tabView allowsTruncatedLabels];
  BOOL flipped = [view isFlipped];
  NSRect bounds = [view bounds];
  NSView *previous = GnomeThemeSetMetricsView (view);
  CGFloat tabHeight = [self tabHeightForType: type];
  NSColor *headerFill = nil;
  NSColor *borderColor = nil;
  NSColor *textColor = nil;
  NSColor *accentColor = nil;
  NSFont *font = nil;
  NSEnumerator *enumerator = nil;
  NSTabViewItem *item = nil;
  CGFloat cursorX = NSMinX (bounds) + GnomeThemeTabStart;
  CGFloat underlineHeight;
  /* Where the tab row is, and which of a tab's edges meets the content
     (its line and the selected tab's underline): top tabs are above it,
     bottom tabs below. */
  BOOL top = (type == NSTopTabsBezelBorder);
  BOOL rowAtMinY = (top == flipped);
  BOOL contentAtMinY = (top != flipped);

  GnomeThemeSetMetricsView (previous);
  if ([view isKindOfClass: [NSTabView class]] == NO
    || GnomeThemeUsesFlatTabs (type) == NO)
    {
      [super drawTabViewRect: rect
                      inView: view
                   withItems: items
                selectedItem: selectedItem];
      return;
    }

  [self drawTabViewBezelRect: bounds tabViewType: type inView: view];

  headerFill = GnomeThemeColor (self, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  /* As -drawTabViewBezelRect:... draws it. */
  borderColor = GnomeThemeTabBorderColor (self, headerFill);
  textColor = GnomeThemeColor (self, @"controlTextColor", [NSColor controlTextColor]);
  accentColor = GnomeThemeColor (self, @"selectedControlColor", [NSColor selectedControlColor]);
  font = [tabView font];
  if (font == nil)
    {
      font = [[self settings] interfaceFont];
    }
  if (font == nil)
    {
      font = [NSFont systemFontOfSize: [NSFont systemFontSize]];
    }

  /* GNUstep's tab row in a nib window (17pt, #24) has no room for the
     4pt underline and the text clear of it and of the frame: there the
     underline is 2pt, and the label is centred above it. */
  underlineHeight = (tabHeight < GnomeThemeTabCompactHeight) ? 2.0 : GnomeThemeTabUnderline;

  enumerator = [items objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      NSString *label = [item label];
      NSSize labelSize = [item sizeOfLabel: truncate];
      CGFloat tabWidth = ceil (labelSize.width + 2.0 * GnomeThemeTabPadding);
      /* Inside the frame, up to (and over) the line between the tabs
         and the content. */
      NSRect tabRect = NSMakeRect (cursorX,
                                   rowAtMinY ? NSMinY (bounds) + 1.0 : NSMaxY (bounds) - tabHeight,
                                   tabWidth,
                                   tabHeight - 1.0);
      NSRect labelRect = tabRect;
      NSRect line = tabRect;

      /* NSTabViewItem records its hit rect while drawing its label; its
         own label is then painted over, the whole tab, and the line under
         the tabs drawn again (bits of GNUstep's label showed above and
         below the theme's in a short tab row). */
      [item drawLabel: truncate inRect: tabRect];
      [headerFill set];
      NSRectFill (tabRect);
      line.size.height = 1.0;
      if (contentAtMinY == NO)
        {
          line.origin.y = NSMaxY (tabRect) - 1.0;
        }
      [borderColor set];
      NSRectFill (line);
      if (underlineHeight < GnomeThemeTabUnderline)
        {
          labelRect.size.height -= underlineHeight + 1.0;
          if (contentAtMinY)
            {
              labelRect.origin.y += underlineHeight + 1.0;
            }
        }

      if (truncate
        && labelSize.width > NSWidth (tabRect) - 2.0 * GnomeThemeTabPadding
        && [item respondsToSelector: @selector(_truncatedLabel)])
        {
          label = [item _truncatedLabel];
        }
      GnomeThemeDrawTabLabel (label, labelRect, font, textColor);

      if (item == selectedItem)
        {
          NSRect underline = tabRect;

          underline.size.height = underlineHeight;
          if (contentAtMinY == NO)
            {
              underline.origin.y = NSMaxY (tabRect) - underlineHeight;
            }
          [accentColor set];
          NSRectFill (underline);
        }

      cursorX += tabWidth + GnomeThemeTabGap;
    }
}

@end

/* A level indicator's fill colour, as Cocoa picks it: from the critical
   value up libadwaita's error colour, from the warning value its warning
   colour, else the accent. With the critical value below the warning
   value, the values below them are the bad ones. With the two equal
   (neither set), the accent (GNUstep drew everything red then). */
static NSColor *
GnomeThemeLevelFillColor(GSTheme *theme, NSLevelIndicatorCell *cell, double value)
{
  double warning = [cell warningValue];
  double critical = [cell criticalValue];
  NSColor *accent = GnomeThemeColor (theme, @"selectedControlColor", [NSColor selectedControlColor]);
  NSColor *warningColor = GnomeThemeColor (theme, @"GnomeThemeWarningColor", [NSColor orangeColor]);
  NSColor *errorColor = GnomeThemeColor (theme, @"GnomeThemeErrorColor", [NSColor redColor]);

  /* Equal (both left at 0, say): no thresholds. */
  if (warning == critical)
    {
      return accent;
    }
  if (warning < critical)
    {
      if (value >= critical)
        {
          return errorColor;
        }
      return (value >= warning) ? warningColor : accent;
    }
  /* Low values are the bad ones: below the threshold, not at it (an
     empty level with the critical value left at 0 isn't an error). */
  if (value < critical)
    {
      return errorColor;
    }
  return (value < warning) ? warningColor : accent;
}

/* A pill of `rect` (the shorter side its diameter) in `color`. */
static void
GnomeThemeFillPill(NSRect rect, NSColor *color)
{
  CGFloat radius = MIN (NSWidth (rect), NSHeight (rect)) / 2.0;

  [color set];
  [[NSBezierPath bezierPathWithRoundedRect: rect xRadius: radius yRadius: radius] fill];
}

@implementation GnomeTheme (Overrides)

/* NSLevelIndicator as libadwaita's GtkLevelBar: an 8pt pill trough, the
   foreground at 15%, the level a pill in the accent (warning or error
   colour past those values); discrete, 8pt blocks 2pt apart, the ends
   rounded. A rating is GNOME's starred and non-starred icons. GNUstep's
   were bevelled green, yellow and red boxes, and its rating image is
   missing. Tick marks and the relevancy style keep GNUstep's drawing. */
- (void) _overrideNSLevelIndicatorCellMethod_drawInteriorWithFrame: (NSRect)cellFrame
                                                             inView: (NSView *)controlView
{
  typedef void (*DrawInteriorIMP)(id, SEL, NSRect, NSView *);
  DrawInteriorIMP originalIMP = (DrawInteriorIMP)GnomeThemeOriginalMethod (_cmd, self, [NSLevelIndicatorCell class]);
  NSLevelIndicatorCell *cell = (NSLevelIndicatorCell *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSLevelIndicatorStyle style = [cell style];
  double minimum = [cell minValue], maximum = [cell maxValue];
  double value = MAX (minimum, MIN (maximum, [cell doubleValue]));
  double fraction = (maximum > minimum) ? (value - minimum) / (maximum - minimum) : 0.0;
  BOOL vertical = NSHeight (cellFrame) > NSWidth (cellFrame);
  BOOL flipped = [controlView isFlipped];
  BOOL enabled = [cell isEnabled];
  NSColor *window = GnomeThemeColor (theme, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *foreground = GnomeThemeColor (theme, @"GnomeThemeForegroundColor", [NSColor controlTextColor]);
  /* High contrast (the theme's outline colour is set only there): the
     trough at 30% with the outline round its empty part, as libadwaita's
     base-hc.css. */
  NSColor *outline = GnomeThemeColor (theme, @"GnomeThemeOutlineColor", nil);
  NSColor *trough = GnomeThemeBlend (window, foreground, (outline != nil) ? 0.30 : 0.15);
  NSColor *fill = GnomeThemeLevelFillColor (theme, cell, value);
  NSRect bar;

  if (theme == nil || [cell numberOfTickMarks] != 0 || style == NSRelevancyLevelIndicatorStyle)
    {
      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd, cellFrame, controlView);
        }
      return;
    }
  /* Insensitive: half opacity. */
  if (enabled == NO)
    {
      trough = GnomeThemeBlend (trough, window, 0.5);
      fill = GnomeThemeBlend (fill, window, 0.5);
      foreground = GnomeThemeBlend (foreground, window, 0.5);
    }

  if (style == NSRatingLevelIndicatorStyle)
    {
      NSImage *starred = [NSImage imageNamed: @"GnomeThemeStarred-symbolic"];
      NSImage *empty = [NSImage imageNamed: @"GnomeThemeNonStarred-symbolic"];
      CGFloat side = MIN (16.0, vertical ? NSWidth (cellFrame) : NSHeight (cellFrame));
      NSInteger count = (NSInteger)floor (maximum - minimum + 0.5);
      NSInteger filled = (NSInteger)floor (value - minimum + 0.5);
      NSInteger i;

      if (starred == nil || empty == nil)
        {
          return;
        }
      starred = GnomeThemeTintedImage (starred, foreground);
      empty = GnomeThemeTintedImage (empty, GnomeThemeBlend (foreground, window, 0.5));
      for (i = 0; i < count; i++)
        {
          NSRect star;

          if (vertical)
            {
              star = NSMakeRect (NSMidX (cellFrame) - side / 2.0,
                                 flipped ? NSMaxY (cellFrame) - (i + 1) * (side + 2.0) + 2.0
                                         : NSMinY (cellFrame) + i * (side + 2.0),
                                 side, side);
            }
          else
            {
              star = NSMakeRect (NSMinX (cellFrame) + i * (side + 2.0), NSMidY (cellFrame) - side / 2.0,
                                 side, side);
            }
          if (NSMaxX (star) > NSMaxX (cellFrame) + 0.5 || NSMaxY (star) > NSMaxY (cellFrame) + 0.5
            || NSMinY (star) < NSMinY (cellFrame) - 0.5)
            {
              break;
            }
          [(i < filled ? starred : empty) drawInRect: NSIntegralRect (star)
                                            fromRect: NSZeroRect
                                           operation: NSCompositeSourceOver
                                            fraction: 1.0
                                      respectFlipped: YES
                                               hints: nil];
        }
      return;
    }

  /* The 8pt bar, centred across the frame. */
  if (vertical)
    {
      bar = NSMakeRect (floor (NSMidX (cellFrame) - 4.0), NSMinY (cellFrame), 8.0, NSHeight (cellFrame));
    }
  else
    {
      bar = NSMakeRect (NSMinX (cellFrame), floor (NSMidY (cellFrame) - 4.0), NSWidth (cellFrame), 8.0);
    }

  if (style == NSDiscreteCapacityLevelIndicatorStyle)
    {
      NSInteger segments = MAX (1, (NSInteger)floor (maximum - minimum + 0.5));
      NSInteger lit = (NSInteger)floor (fraction * segments + 0.5);
      CGFloat length = vertical ? NSHeight (bar) : NSWidth (bar);
      CGFloat step = (length + 2.0) / segments;
      NSInteger i;
      NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect: bar xRadius: 4.0 yRadius: 4.0];

      [NSGraphicsContext saveGraphicsState];
      [clip addClip];
      for (i = 0; i < segments; i++)
        {
          /* Counted from the start: the left, or the bottom on screen. */
          CGFloat start = floor (i * step);
          CGFloat end = floor ((i + 1) * step) - 2.0;
          NSRect block = bar;

          if (vertical)
            {
              block.origin.y = flipped ? NSMaxY (bar) - end : NSMinY (bar) + start;
              block.size.height = MAX (1.0, end - start);
            }
          else
            {
              block.origin.x = NSMinX (bar) + start;
              block.size.width = MAX (1.0, end - start);
            }
          [(i < lit ? fill : trough) set];
          NSRectFill (block);
          if (outline != nil && i >= lit)
            {
              [outline set];
              NSFrameRect (block);
            }
        }
      [NSGraphicsContext restoreGraphicsState];
      return;
    }

  /* Continuous (and anything else): a pill trough, the level a pill. */
  GnomeThemeFillPill (bar, trough);
  if (outline != nil)
    {
      [outline set];
      [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect (bar, 0.5, 0.5) xRadius: 3.5 yRadius: 3.5] stroke];
    }
  if (fraction > 0.0)
    {
      NSRect level = bar;

      if (vertical)
        {
          level.size.height = MAX (8.0, floor (NSHeight (bar) * fraction + 0.5));
          if (flipped)
            {
              level.origin.y = NSMaxY (bar) - NSHeight (level);
            }
        }
      else
        {
          level.size.width = MAX (8.0, floor (NSWidth (bar) * fraction + 0.5));
        }
      GnomeThemeFillPill (level, fill);
    }
}

/* Dark ink drawn over `background` in `source`, as a bitmap of `ink` at
   each pixel's coverage: how far the pixel is from the background towards
   black. For drawing that only comes in black (libs-gui's ruler). */
static NSBitmapImageRep *
GnomeThemeInkMask(NSBitmapImageRep *source, NSColor *background, NSColor *ink)
{
  NSColor *bg = [background colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSColor *rgb = [ink colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSInteger width = [source pixelsWide], height = [source pixelsHigh];
  CGFloat bgLevel, red, green, blue, alpha;
  BOOL clear;
  NSInteger samples = [source samplesPerPixel];
  NSInteger bits = [source bitsPerSample];
  NSUInteger maxValue = (bits >= 16) ? 65535 : ((1u << bits) - 1);
  BOOL alphaFirst = [source hasAlpha] && ([source bitmapFormat] & NSAlphaFirstBitmapFormat) != 0;
  NSInteger first = alphaFirst ? 1 : 0;
  NSInteger alphaIndex = [source hasAlpha] ? (alphaFirst ? 0 : samples - 1) : -1;
  NSBitmapImageRep *mask;
  unsigned char *data;
  NSInteger x, y, bytesPerRow;

  if (bg == nil || rgb == nil || width <= 0 || height <= 0
    || samples < 3 || samples > 5 || bits < 1 || bits > 16)
    {
      return nil;
    }
  bgLevel = ([bg redComponent] + [bg greenComponent] + [bg blueComponent]) / 3.0;
  /* A clear background: the coverage is the pixel's alpha. */
  clear = [bg alphaComponent] < 0.5;
  if (clear == NO && bgLevel <= 0.02)
    {
      return nil;
    }
  red = [rgb redComponent];
  green = [rgb greenComponent];
  blue = [rgb blueComponent];
  alpha = [rgb alphaComponent];
  mask = AUTORELEASE ([[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                              pixelsWide: width
                                                              pixelsHigh: height
                                                           bitsPerSample: 8
                                                         samplesPerPixel: 4
                                                                hasAlpha: YES
                                                                isPlanar: NO
                                                          colorSpaceName: NSCalibratedRGBColorSpace
                                                             bytesPerRow: 0
                                                            bitsPerPixel: 0]);
  data = [mask bitmapData];
  bytesPerRow = [mask bytesPerRow];
  if (data == NULL)
    {
      return nil;
    }
  for (y = 0; y < height; y++)
    {
      for (x = 0; x < width; x++)
        {
          NSUInteger raw[5];
          CGFloat level, a;
          unsigned char *pixel = data + y * bytesPerRow + x * 4;

          [source getPixel: raw atX: x y: y];
          level = ((CGFloat)raw[first] + raw[first + 1] + raw[first + 2]) / (3.0 * maxValue);
          a = clear
            ? (alphaIndex >= 0 ? (CGFloat)raw[alphaIndex] / maxValue : 1.0)
            : MAX (0.0, MIN (1.0, (bgLevel - level) / bgLevel));
          a *= alpha;

          pixel[0] = (unsigned char)floor (red * a * 255.0 + 0.5);
          pixel[1] = (unsigned char)floor (green * a * 255.0 + 0.5);
          pixel[2] = (unsigned char)floor (blue * a * 255.0 + 0.5);
          pixel[3] = (unsigned char)floor (a * 255.0 + 0.5);
        }
    }
  [mask setSize: [source size]];
  return mask;
}

/* NSRulerView (a text view's ruler) on the window's colour with a line
   along its edge, its marks, labels and markers in the foreground at 55%.
   libs-gui fills it with controlColor and draws the marks and labels in
   blackColor, which in the dark palette all but vanished. The marks are
   libs-gui's own: drawn in black on the window's colour, read back from
   the window (-initWithFocusedViewRect:), and drawn again as a mask in the
   theme's colour over a fresh background. */
- (void) _overrideNSRulerViewMethod_drawRect: (NSRect)aRect
{
  NSRulerView *ruler = (NSRulerView *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSColor *window = GnomeThemeColor (theme, @"windowBackgroundColor", [NSColor windowBackgroundColor]);
  NSColor *marks = GnomeThemeBlend (window, GnomeThemeColor (theme, @"GnomeThemeForegroundColor",
                                                             [NSColor controlTextColor]), 0.55);
  NSColor *line = GnomeThemeColor (theme, @"GnomeThemeSeparatorColor", [NSColor gridColor]);
  NSRect bounds = [ruler bounds];
  NSRect edge;
  NSBitmapImageRep *rep, *mask = nil;

  [window set];
  NSRectFill (aRect);
  [ruler drawHashMarksAndLabelsInRect: aRect];
  [ruler drawMarkersInRect: aRect];
  /* Only a screen has pixels to read back (not a print context). */
  if ([[NSGraphicsContext currentContext] isDrawingToScreen] == NO)
    {
      return;
    }
  /* The ruler has the focus here: read its pixels back once. */
  rep = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect: aRect]);
  if (rep != nil)
    {
      mask = GnomeThemeInkMask (rep, window, marks);
    }
  if (mask == nil)
    {
      /* Left as libs-gui drew it, on the window's colour. */
      return;
    }

  [window set];
  NSRectFill (aRect);
  /* The line between the ruler and the text. */
  edge = bounds;
  if ([ruler orientation] == NSHorizontalRuler)
    {
      edge.size.height = 1.0;
      if ([ruler isFlipped])
        {
          edge.origin.y = NSMaxY (bounds) - 1.0;
        }
    }
  else
    {
      edge.origin.x = NSMaxX (bounds) - 1.0;
      edge.size.width = 1.0;
    }
  [line set];
  NSRectFill (NSIntersectionRect (edge, aRect));
  {
    NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: aRect.size]);

    [image addRepresentation: mask];
    [image drawInRect: aRect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0
       respectFlipped: YES
                hints: nil];
  }
}

/* NSSplitView's dividers as GtkPaned's separators: a thin divider is a
   1pt line, the foreground at 15%; a thick or pane splitter divider (6pt)
   is GtkPaned's wide handle, a line at each edge with the window between.
   GNUstep drew NeXT's dimple in the middle of the thick ones, and the
   thin one in whatever colour was set. */
- (void) _overrideNSSplitViewMethod_drawDividerInRect: (NSRect)aRect
{
  NSSplitView *splitView = (NSSplitView *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSColor *line = GnomeThemeColor (theme, @"GnomeThemeSeparatorColor", [NSColor gridColor]);
  BOOL vertical = [splitView isVertical];

  [line set];
  if ([splitView dividerStyle] == NSSplitViewDividerStyleThin
    || (vertical ? NSWidth (aRect) : NSHeight (aRect)) <= 2.0)
    {
      NSRectFill (aRect);
      return;
    }
  if (vertical)
    {
      NSRectFill (NSMakeRect (NSMinX (aRect), NSMinY (aRect), 1.0, NSHeight (aRect)));
      NSRectFill (NSMakeRect (NSMaxX (aRect) - 1.0, NSMinY (aRect), 1.0, NSHeight (aRect)));
    }
  else
    {
      NSRectFill (NSMakeRect (NSMinX (aRect), NSMinY (aRect), NSWidth (aRect), 1.0));
      NSRectFill (NSMakeRect (NSMinX (aRect), NSMaxY (aRect) - 1.0, NSWidth (aRect), 1.0));
    }
}

- (void) _overrideNSScrollerMethod_drawRect: (NSRect)rect
{
  typedef void (*DrawRectIMP)(id, SEL, NSRect);
  DrawRectIMP originalIMP = (DrawRectIMP)GnomeThemeOriginalMethod (_cmd, self, [NSScroller class]);
  NSScroller *scroller = (NSScroller *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();

  if (theme == nil)
    {
      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd, rect);
        }
      return;
    }

  if ([scroller arrowsPosition] != NSScrollerArrowsNone)
    {
      [scroller setArrowsPosition: NSScrollerArrowsNone];
      return;
    }

  if (GnomeThemeDrawOverlayScrollerIfNeeded (scroller))
    {
      return;
    }

  if (GnomeThemeScrollerShowsOverflow (scroller) == NO)
    {
      GnomeThemeEraseScrollerRect (scroller, rect);
      return;
    }

  [theme drawScrollerRect: rect
                   inView: scroller
                  hitPart: [scroller hitPart]
             isHorizontal: GnomeThemeScrollerIsHorizontal (scroller)];
}

- (void) _overrideNSScrollerMethod_drawKnobSlotInRect: (NSRect)slotRect
                                             highlight: (BOOL)flag
{
  NSScroller *scroller = (NSScroller *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();

  (void)flag;

  if (theme == nil || GnomeThemeUsesOverlayScrollers ())
    {
      /* Overlay scrollers draw everything from -drawRect:. */
      return;
    }

  if (GnomeThemeScrollerShowsOverflow (scroller) == NO)
    {
      GnomeThemeEraseScrollerRect (scroller, slotRect);
      return;
    }

  GnomeThemeDrawModernScroller (theme,
                                scroller,
                                slotRect,
                                [scroller hitPart],
                                GnomeThemeScrollerIsHorizontal (scroller));
}

- (NSRect) _overrideNSTextFieldCellMethod_titleRectForBounds: (NSRect)aRect
{
  typedef NSRect (*TitleRectIMP)(id, SEL, NSRect);
  TitleRectIMP originalIMP = (TitleRectIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTextFieldCell class]);
  NSTextFieldCell *cell = (NSTextFieldCell *)self;
  /* Header cells skip the original method and the text-field insets below
     (they are bordered, so they would get the read-only field's 10pt); they
     get a small inset of their own so their titles line up with the rows'
     text. */
  BOOL headerCell = [cell isKindOfClass: [NSTableHeaderCell class]];
  NSRect titleRect = (originalIMP != NULL && headerCell == NO) ? originalIMP (self, _cmd, aRect) : aRect;
  NSFont *font = GnomeThemeResolvedEditorFont (cell);
  NSDictionary *attributes = nil;
  NSSize titleSize;

  attributes = [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName];
  titleSize = [@"Ag" sizeWithAttributes: attributes];

  /* Labels (text fields without a bezel) whose text needs more than one line
     (line breaks, or a wrapping cell too narrow for it) keep the full rect;
     centring them on one line showed only their first line, e.g. an NSAlert's
     informative text. Cells drawn by table and header views stay single-line. */
  if ([cell isBezeled] == NO && [cell isBordered] == NO
    && [[cell controlView] isKindOfClass: [NSTextField class]])
    {
      NSString *string = [cell stringValue];
      BOOL hasBreaks = [string rangeOfCharacterFromSet: [NSCharacterSet newlineCharacterSet]].location != NSNotFound;
      BOOL overflows = [cell wraps] && [[cell attributedStringValue] size].width > NSWidth (titleRect);

      /* Only when the frame has room for a second line; a one-line label that's
         too long keeps being centred (and clipped) as before. */
      if ((hasBreaks || overflows) && NSHeight (aRect) >= 2.0 * titleSize.height)
        {
          return titleRect;
        }
    }

  /* GTK list cells pad their text 6px from the column edge; headers match,
     less a sort indicator's room (GnomeThemeTableHeaderIndicatorRoom). */
  if (headerCell)
    {
      CGFloat room = GnomeThemeTableHeaderIndicatorRoom ();

      titleRect.origin.x += 4.0 + MAX (0.0, -room);
      titleRect.size.width = MAX (0.0, titleRect.size.width - 8.0 - fabs (room));
    }
  else if ([[cell controlView] isKindOfClass: [NSTableView class]])
    {
      titleRect.origin.x += 2.0;
      titleRect.size.width = MAX (0.0, titleRect.size.width - 4.0);
    }
  else if ([cell isBezeled] || [cell isBordered])
    {
      BOOL readonlyField = ([cell isEditable] == NO && [cell isSelectable] == NO);
      CGFloat horizontalInset = readonlyField ? 10.0 : 4.0;

      titleRect.origin.x += horizontalInset;
      titleRect.size.width -= (horizontalInset * 2.0);
    }

  titleRect.origin.y = aRect.origin.y + floor ((aRect.size.height - titleSize.height) / 2.0);
  titleRect.size.height = ceil (titleSize.height);
  /* 2px to spare below the line, inside the cell. In a field on a half
     pixel the field editor's clip view is offset half a pixel to put the
     text on the pixel grid, which hid the line's last half pixel: typing
     then scrolled to show it, and -[NSClipView constrainScrollPoint:]
     rounds in the clip view's current coordinates, so the scroll moved the
     text half a pixel off the grid and it went up and down a row as it was
     typed. The text's position doesn't change. */
  titleRect.size.height = MIN (titleRect.size.height + 2.0, NSMaxY (aRect) - NSMinY (titleRect));

  return titleRect;
}

- (NSText *) _overrideNSTextFieldCellMethod_setUpFieldEditorAttributes: (NSText *)textObject
{
  typedef NSText *(*SetUpFieldEditorAttributesIMP)(id, SEL, NSText *);
  SetUpFieldEditorAttributesIMP originalIMP
    = (SetUpFieldEditorAttributesIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTextFieldCell class]);
  NSTextFieldCell *cell = (NSTextFieldCell *)self;
  NSText *editor = textObject;
  NSView *controlView = [cell controlView];

  if (originalIMP != NULL)
    {
      editor = originalIMP (self, _cmd, textObject);
    }

  GnomeThemeApplyEditorFont (cell, editor);
  GnomeThemeSuppressEditorBackground (editor);

  if (controlView != nil)
    {
      GnomeThemeTrackFocusedEntryView (controlView);
    }

  return editor;
}

/* A form cell's text area (Gorm's "Title:" fields): the Adwaita entry
   beside the title. NSFormCell draws the border and then fills the area with
   plain textBackgroundColor, which covered the entry in white. */
- (void) _overrideNSFormCellMethod__drawBorderAndBackgroundWithFrame: (NSRect)cellFrame
                                                              inView: (NSView *)controlView
{
  NSFormCell *cell = (NSFormCell *)self;
  Ivar titleWidthIvar = class_getInstanceVariable ([NSFormCell class], "_displayedTitleWidth");
  CGFloat titleWidth = (titleWidthIvar != NULL)
    ? *(float *)((char *)cell + ivar_getOffset (titleWidthIvar))
    : [cell titleWidth];
  NSRect entryRect = cellFrame;
  BOOL enabled = [cell isEnabled] && GnomeThemeViewEnabled (controlView);
  BOOL focused = [cell _inEditing] && GnomeThemeViewHasFocus (controlView);

  if ([cell isBezeled] == NO && [cell isBordered] == NO)
    {
      return;
    }
  entryRect.origin.x += titleWidth + 3.0;
  entryRect.size.width -= titleWidth + 3.0;
  GnomeThemeDrawEntryChrome (GnomeThemeActiveTheme (), controlView, entryRect, enabled, focused,
                             [cell isEditable] == NO && [cell isSelectable] == NO);
}

- (void) _overrideNSTextFieldCellMethod__drawBackgroundWithFrame: (NSRect)cellFrame
                                                          inView: (NSView *)controlView
{
  typedef void (*DrawBackgroundIMP)(id, SEL, NSRect, NSView *);
  DrawBackgroundIMP originalIMP
    = (DrawBackgroundIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTextFieldCell class]);
  NSTextFieldCell *cell = (NSTextFieldCell *)self;

  if ([cell isBezeled] || [cell isBordered])
    {
      return;
    }

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, cellFrame, controlView);
    }
}

/* GTK's entries show their placeholder while they have focus and are
   empty, with the caret at its start; GNUstep's cell draws it only when it
   isn't editing, and the field editor draws no placeholder. The editor's
   background is clear (GnomeThemeSuppressEditorBackground()), so the cell
   draws it under the editor, in the colour it has unfocused (#67). */
static void
GnomeThemeDrawEditingPlaceholder(NSTextFieldCell *cell, NSRect titleRect, NSView *controlView)
{
  NSText *editor = [controlView isKindOfClass: [NSControl class]]
    ? [(NSControl *)controlView currentEditor] : nil;
  NSAttributedString *placeholder = [cell placeholderAttributedString];

  if (editor == nil || [[editor string] length] > 0)
    {
      return;
    }
  if ([[placeholder string] length] == 0)
    {
      NSString *string = [cell placeholderString];
      NSFont *font = [cell font];
      NSDictionary *attributes;

      if ([string length] == 0)
        {
          return;
        }
      attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                      (font != nil) ? font : [NSFont userFontOfSize: 0], NSFontAttributeName,
                      [NSColor disabledControlTextColor], NSForegroundColorAttributeName,
                      nil];
      placeholder = AUTORELEASE ([[NSAttributedString alloc] initWithString: string
                                                                 attributes: attributes]);
    }
  GnomeThemeDrawAttributedStringWithEditorLayout (cell, placeholder, titleRect, controlView);
}

/* The editor's text going from empty to not (or back) shows or hides the
   placeholder the cell draws under it: redraw the field, not only the
   editor's changed glyphs. */
- (void) _overrideNSTextFieldMethod_textDidChange: (NSNotification *)notification
{
  typedef void (*TextDidChangeIMP)(id, SEL, NSNotification *);
  TextDidChangeIMP originalIMP = (TextDidChangeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTextField class]);
  NSTextField *field = (NSTextField *)self;
  id cell = [field cell];

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, notification);
    }
  if ([cell isKindOfClass: [NSTextFieldCell class]]
    && ([[cell placeholderString] length] > 0
        || [[[cell placeholderAttributedString] string] length] > 0))
    {
      [field setNeedsDisplay: YES];
    }
}

/* While a secure field is edited, its field editor's glyphs: GTK's ●, as
   the field shows at rest (GnomeThemeSecureTextDisplayString), for
   libs-gui's •. A font without ● keeps libs-gui's. */
- (void) _overrideGSSimpleSecureGlyphGeneratorMethod_generateGlyphsForGlyphStorage: (id <NSGlyphStorage>)storage
                                                         desiredNumberOfCharacters: (NSUInteger)num
                                                                        glyphIndex: (NSUInteger *)glyph
                                                                    characterIndex: (NSUInteger *)index
{
  typedef void (*GenerateIMP)(id, SEL, id <NSGlyphStorage>, NSUInteger, NSUInteger *, NSUInteger *);
  GenerateIMP originalIMP = (GenerateIMP)GnomeThemeOriginalMethod (_cmd, self,
                                                                   NSClassFromString (@"GSSimpleSecureGlyphGenerator"));
  NSAttributedString *string = [storage attributedString];
  NSDictionary *attributes;
  GSFontInfo *info;
  NSGlyph circle = NSNullGlyph;
  NSGlyph *glyphs;
  NSUInteger i;

  if (num > 0 && *index < [string length])
    {
      attributes = [string attributesAtIndex: *index effectiveRange: NULL];
      info = [[(NSGlyphGenerator *)self fontForCharactersWithAttributes: attributes] fontInfo];
      if (info != nil)
        {
          circle = [info glyphForCharacter: GnomeThemeSecureCharacter];
        }
    }
  if (circle == NSNullGlyph || circle == 0)
    {
      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd, storage, num, glyph, index);
        }
      return;
    }
  glyphs = NSZoneMalloc (NSDefaultMallocZone (), num * sizeof (NSGlyph));
  for (i = 0; i < num; i++)
    {
      glyphs[i] = circle;
    }
  [storage insertGlyphs: glyphs
                 length: num
forStartingGlyphAtIndex: *glyph
         characterIndex: *index];
  NSZoneFree (NSDefaultMallocZone (), glyphs);
}

- (void) _overrideNSTextFieldCellMethod_drawInteriorWithFrame: (NSRect)cellFrame
                                                       inView: (NSView *)controlView
{
  NSTextFieldCell *cell = (NSTextFieldCell *)self;

  if ([cell _inEditing])
    {
      if ([cell isBezeled] || [cell isBordered])
        {
          GnomeTheme *theme = GnomeThemeActiveTheme ();
          BOOL enabled = [cell isEnabled] && GnomeThemeViewEnabled (controlView);
          BOOL focused = GnomeThemeViewHasFocus (controlView);
          BOOL readonlyField = ([cell isEditable] == NO && [cell isSelectable] == NO);

          GnomeThemeDrawEntryChrome (theme,
                                     controlView,
                                     cellFrame,
                                     enabled,
                                     focused,
                                     readonlyField);
        }

      if ([controlView isKindOfClass: [NSControl class]])
        {
          GnomeThemeSuppressEditorBackground ([(NSControl *)controlView currentEditor]);
        }

      GnomeThemeDrawEditingPlaceholder (cell, [cell titleRectForBounds: cellFrame], controlView);
      [cell _drawEditorWithFrame: cellFrame
                           inView: controlView];
      return;
    }

  GnomeThemeDrawAttributedStringWithEditorLayout (cell,
                                                  [cell _drawAttributedString],
                                                  [cell titleRectForBounds: cellFrame],
                                                  controlView);
}

/* libadwaita's search entry: 16px icons 8px in from each end, the text
   from 32px in (#59). */
- (NSRect) _overrideNSSearchFieldCellMethod_searchButtonRectForBounds: (NSRect)rect
{
  CGFloat iconSize = 16.0;
  CGFloat leftInset = 8.0;
  NSRect iconRect = NSMakeRect (NSMinX (rect) + leftInset,
                                NSMidY (rect) - (iconSize / 2.0),
                                iconSize,
                                iconSize);

  return iconRect;
}

- (NSRect) _overrideNSSearchFieldCellMethod_cancelButtonRectForBounds: (NSRect)rect
{
  CGFloat iconSize = 16.0;
  CGFloat rightInset = 8.0;
  NSRect iconRect = NSMakeRect (NSMaxX (rect) - rightInset - iconSize,
                                NSMidY (rect) - (iconSize / 2.0),
                                iconSize,
                                iconSize);

  return iconRect;
}

- (NSRect) _overrideNSSearchFieldCellMethod_searchTextRectForBounds: (NSRect)rect
{
  /* The title rect adds 13px: the text starts 32px in, after the icon. */
  CGFloat leftInset = 19.0;
  CGFloat rightInset = 19.0;
  NSRect textRect = rect;

  textRect.origin.x += leftInset;
  textRect.size.width = MAX (0.0, textRect.size.width - leftInset - rightInset);
  return textRect;
}

- (void) _overrideNSSearchFieldCellMethod_drawWithFrame: (NSRect)cellFrame
                                                 inView: (NSView *)controlView
{
  NSSearchFieldCell *cell = (NSSearchFieldCell *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  BOOL enabled = [cell isEnabled];
  BOOL focused = GnomeThemeViewHasFocus (controlView) && enabled;
  NSRect textRect = [cell searchTextRectForBounds: cellFrame];

  /* -[NSActionCell drawWithFrame:inView:], which this replaces, is where
     the cell learns its control view. Without it -stringValue doesn't take
     the field editor's text while editing, so a delegate's
     controlTextDidChange: read the text from before the key (#73). */
  if (controlView != nil)
    {
      [cell setControlView: controlView];
    }

  if (focused)
    {
      GnomeThemeTrackFocusedEntryView (controlView);
    }

  GnomeThemeDrawEntryChrome (theme, controlView, cellFrame, enabled, focused, NO);

  [[cell searchButtonCell] drawWithFrame: [cell searchButtonRectForBounds: cellFrame]
                                  inView: controlView];

  if ([cell _inEditing])
    {
      if ([controlView isKindOfClass: [NSControl class]])
        {
          GnomeThemeSuppressEditorBackground ([(NSControl *)controlView currentEditor]);
        }

      GnomeThemeDrawEditingPlaceholder (cell, [cell titleRectForBounds: textRect], controlView);
      [cell _drawEditorWithFrame: textRect
                           inView: controlView];
    }
  else
    {
      GnomeThemeDrawAttributedStringWithEditorLayout (cell,
                                                      [cell _drawAttributedString],
                                                      [cell titleRectForBounds: textRect],
                                                      controlView);
    }

  if ([[cell stringValue] length] > 0)
    {
      [[cell cancelButtonCell] drawWithFrame: [cell cancelButtonRectForBounds: cellFrame]
                                      inView: controlView];
    }
}

/* A disabled segment's label and symbolic images: libadwaita's
   insensitive half opacity, the enabled colour halfway to the window (the
   fill goes the same way), so the selected segment dims as much as the
   others. From the enabled text colour: libs-gui already greys a disabled
   cell's typing attributes. */
static NSColor *
GnomeThemeDisabledSegmentColor(GSTheme *theme, NSView *controlView)
{
  NSColor *color = GnomeThemeTemplateImageColorInView (controlView, NO,
                                                       GnomeThemeColor (theme, @"controlTextColor",
                                                                        [NSColor controlTextColor]));
  NSColor *window = GnomeThemeColor (theme, @"windowBackgroundColor", [NSColor windowBackgroundColor]);

  return GnomeThemeBlend (color, window, 0.5);
}

- (void) _overrideNSSegmentedCellMethod_drawSegment: (NSInteger)segmentIndex
                                            inFrame: (NSRect)frame
                                           withView: (NSView *)view
{
  typedef void (*DrawSegmentIMP)(id, SEL, NSInteger, NSRect, NSView *);
  DrawSegmentIMP originalIMP = (DrawSegmentIMP)GnomeThemeOriginalMethod (_cmd, self, [NSSegmentedCell class]);
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSSegmentedCell *cell = (NSSegmentedCell *)self;
  NSString *label = [cell labelForSegment: segmentIndex];
  NSImage *segmentImage = [cell imageForSegment: segmentIndex];
  BOOL selected = NO;
  GSThemeControlState state;
  BOOL roundedLeft = (segmentIndex == 0);
  BOOL roundedRight = (segmentIndex == ([cell segmentCount] - 1));
  NSView *controlView = [cell controlView];
  /* libadwaita draws an insensitive button at half opacity, the checked
     one too: the fill over the window, the label and image dimmed. */
  BOOL enabled = [cell isEnabled] && [cell isEnabledForSegment: segmentIndex]
    && ([controlView isKindOfClass: [NSControl class]] == NO || [(NSControl *)controlView isEnabled]);

  if ([cell trackingMode] == NSSegmentSwitchTrackingSelectOne)
    {
      selected = ([cell selectedSegment] == segmentIndex);
    }
  else
    {
      selected = [cell isSelectedForSegment: segmentIndex];
    }

  state = selected ? GSThemeSelectedState : GSThemeNormalState;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, segmentIndex, frame, view);
    }

  if (theme == nil)
    {
      return;
    }

  GnomeThemeSegmentBeingDrawnIsEnabled = enabled;
  if (segmentIndex > 0)
    {
      GnomeThemeSegmentBeingDrawnFollowsUnselected = ([cell trackingMode] == NSSegmentSwitchTrackingSelectOne)
        ? ([cell selectedSegment] != segmentIndex - 1)
        : ([cell isSelectedForSegment: segmentIndex - 1] == NO);
    }
  [theme drawSegmentedControlSegment: cell
                           withFrame: frame
                              inView: (controlView != nil) ? controlView : view
                               style: [cell segmentStyle]
                               state: state
                         roundedLeft: roundedLeft
                        roundedRight: roundedRight];
  GnomeThemeSegmentBeingDrawnIsEnabled = YES;
  GnomeThemeSegmentBeingDrawnFollowsUnselected = NO;

  if ([label length] > 0)
    {
      NSDictionary *cellAttributes = [cell _nonAutoreleasedTypingAttributes];
      NSMutableDictionary *attributes = [cellAttributes mutableCopy];
      NSFont *font = GnomeThemeEmphasizedFont ([attributes objectForKey: NSFontAttributeName], (NSCell *)self, view);
      NSSize textSize = [label sizeWithAttributes: attributes];
      CGFloat availableWidth = MAX (0.0, frame.size.width - 10.0);
      CGFloat drawWidth = MIN (availableWidth, ceil (textSize.width));
      NSRect textFrame = NSMakeRect (floor (NSMidX (frame) - (drawWidth / 2.0)),
                                     floor (NSMidY (frame) - (textSize.height / 2.0)),
                                     drawWidth,
                                     ceil (textSize.height));

      if (enabled == NO)
        {
          [attributes setObject: GnomeThemeDisabledSegmentColor (theme, (controlView != nil) ? controlView : view)
                         forKey: NSForegroundColorAttributeName];
        }
      if (font != nil)
        {
          [attributes setObject: font forKey: NSFontAttributeName];
          textSize = [label sizeWithAttributes: attributes];
          drawWidth = MIN (availableWidth, ceil (textSize.width));
          textFrame = NSMakeRect (floor (NSMidX (frame) - (drawWidth / 2.0)),
                                  floor (NSMidY (frame) - (textSize.height / 2.0)),
                                  drawWidth,
                                  ceil (textSize.height));
        }

      if (view != nil)
        {
          textFrame = [view centerScanRect: textFrame];
        }

      [label drawInRect: textFrame withAttributes: attributes];
      RELEASE (attributes);
      RELEASE (cellAttributes);
    }

  if (segmentImage != nil)
    {
      NSSize size = [segmentImage size];
      NSRect destinationRect = NSMakeRect (MAX (NSMidX (frame) - (size.width / 2.0), 0.0),
                                           MAX (NSMidY (frame) - (size.height / 2.0), 0.0),
                                           size.width,
                                           size.height);

      if (view != nil)
        {
          destinationRect = [view centerScanRect: destinationRect];
        }
      /* A template (symbolic) image in the segment's text colour, as a
         button's (plugins-themes-Adwaita#37). */
      if (GnomeThemeImageIsTemplate (segmentImage))
        {
          NSDictionary *cellAttributes = [cell _nonAutoreleasedTypingAttributes];
          NSColor *text = [cellAttributes objectForKey: NSForegroundColorAttributeName];

          segmentImage = GnomeThemeTintedImage (segmentImage, enabled
                                                ? GnomeThemeTemplateImageColorInView ((controlView != nil) ? controlView : view,
                                                                                      NO, text)
                                                : GnomeThemeDisabledSegmentColor (theme, (controlView != nil) ? controlView : view));
          RELEASE (cellAttributes);
        }

      [segmentImage drawInRect: destinationRect
                      fromRect: NSZeroRect
                     operation: NSCompositeSourceOver
                      fraction: (enabled || GnomeThemeImageIsTemplate ([cell imageForSegment: segmentIndex]))
                                  ? 1.0 : 0.5];
    }
}

/* A box's title is a GtkFrame's label: the interface font at its own size.
   GNUstep gives a new box the small system font. Boxes decoded from a nib
   or Gorm file keep their archived font (GnomeThemeNibMetrics sizes it). */
- (id) _overrideNSBoxMethod_initWithFrame: (NSRect)frameRect
{
  typedef id (*InitIMP)(id, SEL, NSRect);
  InitIMP originalIMP = (InitIMP)GnomeThemeOriginalMethod (_cmd, self, [NSBox class]);
  NSBox *box = nil;

  if (originalIMP != NULL)
    {
      box = originalIMP (self, _cmd, frameRect);
    }
  [box setTitleFont: [NSFont systemFontOfSize: 0.0]];
  return box;
}

/* A tab view's content sits on the view background, as a GtkNotebook's does.
   GNUstep starts tab views without a background (Cocoa's default is to draw
   one); apps that turn it off keep theirs off, and tab views decoded from a
   nib or Gorm file keep their archived setting. */
- (id) _overrideNSTabViewMethod_initWithFrame: (NSRect)frameRect
{
  typedef id (*InitIMP)(id, SEL, NSRect);
  InitIMP originalIMP = (InitIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTabView class]);
  NSTabView *tabView = nil;

  if (originalIMP != NULL)
    {
      tabView = originalIMP (self, _cmd, frameRect);
    }
  [tabView setDrawsBackground: YES];
  return tabView;
}

/* GNOME header bars show icon-only buttons with tool tips; GNUstep starts
   toolbars with icon and label. The first toolbar with an identifier starts
   icon-only; later ones copy it, as they copy any mode the app sets.
   -setDisplayMode: (the app, or the customisation palette) still switches
   modes, toolbars decoded from a nib or Gorm file keep their archived mode,
   and view switchers keep their labels (see -setDelegate:). */
- (id) _overrideNSToolbarMethod_initWithIdentifier: (NSString *)identifier
{
  typedef id (*InitIMP)(id, SEL, NSString *);
  InitIMP originalIMP = (InitIMP)GnomeThemeOriginalMethod (_cmd, self, [NSToolbar class]);
  Ivar displayMode = class_getInstanceVariable ([NSToolbar class], "_displayMode");
  NSToolbar *toolbar = nil;

  if (originalIMP != NULL)
    {
      toolbar = originalIMP (self, _cmd, identifier);
    }
  /* Set directly: -setDisplayMode: reloads the toolbar and tells its
     siblings. */
  if (toolbar != nil && displayMode != NULL
    && [toolbar displayMode] == NSToolbarDisplayModeIconAndLabel
    && [toolbar respondsToSelector: @selector(_toolbarModel)]
    && [toolbar performSelector: @selector(_toolbarModel)] == nil)
    {
      *(NSToolbarDisplayMode *)((char *)toolbar + ivar_getOffset (displayMode)) = NSToolbarDisplayModeIconOnly;
      objc_setAssociatedObject (toolbar, &GnomeThemeToolbarDefaultModeKey, [NSNumber numberWithBool: YES],
                                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  return toolbar;
}

/* The app chose a mode: it's no longer the theme's default. */
- (void) _overrideNSToolbarMethod_setDisplayMode: (NSToolbarDisplayMode)displayMode
{
  typedef void (*SetModeIMP)(id, SEL, NSToolbarDisplayMode);
  SetModeIMP originalIMP = (SetModeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSToolbar class]);

  objc_setAssociatedObject (self, &GnomeThemeToolbarDefaultModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, displayMode);
    }
}

/* A toolbar whose items select a view (its delegate lists selectable items,
   like Gorm's Objects/Images/Classes) is a view switcher; GNOME's
   AdwViewSwitcher shows icon and label, so it gets its labels back. The
   delegate arrives after -initWithIdentifier:, and the items are built from
   here on. */
- (void) _overrideNSToolbarMethod_setDelegate: (id)delegate
{
  typedef void (*SetDelegateIMP)(id, SEL, id);
  SetDelegateIMP originalIMP = (SetDelegateIMP)GnomeThemeOriginalMethod (_cmd, self, [NSToolbar class]);
  NSToolbar *toolbar = (NSToolbar *)self;
  Ivar displayMode = class_getInstanceVariable ([NSToolbar class], "_displayMode");

  if (displayMode != NULL
    && [objc_getAssociatedObject (toolbar, &GnomeThemeToolbarDefaultModeKey) boolValue]
    && [toolbar displayMode] == NSToolbarDisplayModeIconOnly
    && [delegate respondsToSelector: @selector(toolbarSelectableItemIdentifiers:)]
    && [[delegate toolbarSelectableItemIdentifiers: toolbar] count] > 0)
    {
      *(NSToolbarDisplayMode *)((char *)toolbar + ivar_getOffset (displayMode)) = NSToolbarDisplayModeIconAndLabel;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, delegate);
    }
}

/* Toolbar buttons get a flat hover highlight, like GNOME header bar buttons.
   GNUstep registers no tracking rects for them (-[NSButtonCell
   setShowsBorderOnlyWhileMouseInside:] is a FIXME), so add one whenever the
   button is laid out; the rect is in view coordinates, so only size changes
   need a new one. */
/* Toolbars (plugins-themes-Adwaita#8). libs-gui gives every item a fixed
   60pt (50pt small) slot with a label row even for empty labels, drops
   views taller than 32pt and makes images 32x32 (upstream item 9). Under
   GNOME's metrics the theme sizes items from their content instead, as GTK
   (and macOS) do:
   - icon only and label only: libadwaita's 46pt row, 34pt buttons with 6pt
     above and below and 3pt either side;
   - icon and label: the image over a caption-sized label, as in
     AdwViewSwitcher's narrow buttons, with 3pt above and below and no label
     row when the item has no label;
   - images keep their own size up to 24pt (16pt in small mode);
   - views stay however tall they are, and the row grows to fit them.
   Every item in a toolbar then gets the tallest one's height, so the row is
   even. Compact metrics (Gorm and nib-based apps) keep libs-gui's layout. */
static const CGFloat GnomeThemeToolbarRowHeight = 46.0;
static const CGFloat GnomeThemeToolbarButtonSize = 34.0;
static const CGFloat GnomeThemeToolbarSpacing = 3.0;
static const CGFloat GnomeThemeToolbarIconPadding = 5.0;
static const CGFloat GnomeThemeToolbarLabelPadding = 12.0;
static const CGFloat GnomeThemeToolbarLabelGap = 2.0;
/* On an item's image: its own size, before libs-gui first resized it. */
static char GnomeThemeToolbarImageSizeKey;

static BOOL
GnomeThemeLaysOutToolbar(NSToolbar *toolbar)
{
  return toolbar != nil && [[GnomeThemeActiveTheme () metrics] compact] == NO;
}

/* Spaces and separators: sized by libs-gui, given the row's height. */
static BOOL
GnomeThemeToolbarItemIsSpace(NSToolbarItem *item)
{
  NSString *identifier = [item itemIdentifier];

  return [identifier isEqualToString: NSToolbarSpaceItemIdentifier]
    || [identifier isEqualToString: NSToolbarFlexibleSpaceItemIdentifier]
    || [identifier isEqualToString: NSToolbarSeparatorItemIdentifier];
}

/* In the header bar, icons alone, as GNOME's header bar buttons; an item
   without an icon shows its label there (see GnomeThemeToolbarTextItem). */
static BOOL
GnomeThemeToolbarShowsLabels(NSToolbar *toolbar)
{
  return [toolbar displayMode] != NSToolbarDisplayModeIconOnly && GnomeThemeToolbarInHeaderBar (toolbar) == NO;
}

/* An item drawn as a text button: its label alone, in the label-only
   mode or, in the header bar, when it has neither icon nor view. */
static BOOL
GnomeThemeToolbarTextItem(NSToolbarItem *item)
{
  NSToolbar *toolbar = [item toolbar];

  return [toolbar displayMode] == NSToolbarDisplayModeLabelOnly
    || (GnomeThemeToolbarInHeaderBar (toolbar) && [item image] == nil && [item view] == nil);
}

/* The label's font: the interface font alone, or libadwaita's caption size
   (82%) under an icon. Kept: GSToolbarBackView doesn't retain its font. */
static NSFont *
GnomeThemeToolbarLabelFont(NSToolbar *toolbar)
{
  static NSFont *regular = nil;
  static NSFont *caption = nil;

  if (regular == nil || [regular pointSize] != [NSFont systemFontSize])
    {
      ASSIGN (regular, [NSFont systemFontOfSize: [NSFont systemFontSize]]);
      ASSIGN (caption, [NSFont systemFontOfSize: floor ([NSFont systemFontSize] * 0.82 + 0.5)]);
    }
  return ([toolbar displayMode] == NSToolbarDisplayModeLabelOnly || GnomeThemeToolbarInHeaderBar (toolbar))
    ? regular : caption;
}

static NSSize
GnomeThemeToolbarLabelSize(NSToolbarItem *item)
{
  NSToolbar *toolbar = [item toolbar];
  NSString *label = [item label];
  NSSize size;

  if ((GnomeThemeToolbarShowsLabels (toolbar) == NO && GnomeThemeToolbarTextItem (item) == NO)
    || [label length] == 0)
    {
      return NSZeroSize;
    }
  size = [label sizeWithAttributes: [NSDictionary dictionaryWithObject: GnomeThemeToolbarLabelFont (toolbar)
                                                                forKey: NSFontAttributeName]];
  return NSMakeSize (ceil (size.width), ceil (size.height));
}

/* The size an item's image is drawn at: its own, scaled down to fit 24pt
   (16pt in small mode). */
static NSSize
GnomeThemeToolbarImageSize(NSImage *image, NSToolbar *toolbar)
{
  NSValue *own;
  NSSize size;
  CGFloat limit = ([toolbar sizeMode] == NSToolbarSizeModeSmall) ? 16.0 : 24.0;

  if (image == nil)
    {
      return NSZeroSize;
    }
  own = objc_getAssociatedObject (image, &GnomeThemeToolbarImageSizeKey);
  if (own == nil)
    {
      own = [NSValue valueWithSize: [image size]];
      objc_setAssociatedObject (image, &GnomeThemeToolbarImageSizeKey, own, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  size = [own sizeValue];
  if (size.width > limit || size.height > limit)
    {
      CGFloat scale = limit / MAX (size.width, size.height);

      size = NSMakeSize (floor (size.width * scale), floor (size.height * scale));
    }
  return size;
}

/* A view item's view width: its own, kept within the item's minSize and
   maxSize when it has them. */
static CGFloat
GnomeThemeToolbarViewWidth(NSToolbarItem *item)
{
  CGFloat width = NSWidth ([[item view] frame]);
  CGFloat minWidth = [item minSize].width;
  CGFloat maxWidth = [item maxSize].width;

  if (minWidth > 0.0)
    {
      width = MAX (width, minWidth);
    }
  if (maxWidth > 0.0 && maxWidth >= minWidth)
    {
      width = MIN (width, maxWidth);
    }
  return width;
}

/* An item's content: the button an image item is drawn as, or a view item's
   view (with its label under it). */
static NSSize
GnomeThemeToolbarContentSize(NSToolbarItem *item)
{
  NSToolbar *toolbar = [item toolbar];
  NSSize label = GnomeThemeToolbarLabelSize (item);
  NSView *view = [item view];
  NSSize content;

  if (GnomeThemeToolbarTextItem (item))
    {
      return NSMakeSize (label.width + 2.0 * GnomeThemeToolbarLabelPadding, GnomeThemeToolbarButtonSize);
    }
  if (view != nil)
    {
      content = NSMakeSize (GnomeThemeToolbarViewWidth (item), NSHeight ([view frame]));
    }
  else
    {
      NSSize image = GnomeThemeToolbarImageSize ([item image], toolbar);

      content = NSMakeSize (image.width + 2.0 * GnomeThemeToolbarIconPadding,
                            image.height + 2.0 * GnomeThemeToolbarIconPadding);
      if (label.height == 0.0)
        {
          content.width = MAX (content.width, GnomeThemeToolbarButtonSize);
          content.height = MAX (content.height, GnomeThemeToolbarButtonSize);
        }
    }
  if (label.height > 0.0)
    {
      content.width = MAX (content.width, label.width + 2.0 * GnomeThemeToolbarSpacing);
      content.height += GnomeThemeToolbarLabelGap + label.height;
    }
  return content;
}

/* The height an item's slot needs. */
static CGFloat
GnomeThemeToolbarItemHeight(NSToolbarItem *item)
{
  NSSize content = GnomeThemeToolbarContentSize (item);
  CGFloat padding = (GnomeThemeToolbarLabelSize (item).height > 0.0
    && [[item toolbar] displayMode] != NSToolbarDisplayModeLabelOnly) ? 3.0 : 6.0;

  return MAX (GnomeThemeToolbarRowHeight, content.height + 2.0 * padding);
}

/* Where an item's content sits in its slot: centred. */
static NSRect
GnomeThemeToolbarContentRect(NSToolbarItem *item, NSRect slot)
{
  NSSize content = GnomeThemeToolbarContentSize (item);

  return NSMakeRect (floor (NSMidX (slot) - content.width / 2.0),
                     floor (NSMidY (slot) - content.height / 2.0),
                     content.width, content.height);
}

/* Puts a view item's view in its slot, above its label. */
static void
GnomeThemePlaceToolbarView(NSView *backView, NSToolbarItem *item)
{
  NSView *view = [item view];
  NSRect content;

  if (view == nil || [view superview] != backView)
    {
      return;
    }
  content = GnomeThemeToolbarContentRect (item, [backView bounds]);
  [view setFrameOrigin: NSMakePoint (floor (NSMidX (content) - NSWidth ([view frame]) / 2.0),
                                     NSMaxY (content) - NSHeight ([view frame]))];
}

- (void) _overrideGSToolbarBackViewMethod_layout
{
  typedef void (*LayoutIMP)(id, SEL);
  LayoutIMP originalIMP = (LayoutIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarBackView"));
  NSView *backView = (NSView *)self;
  NSToolbarItem *item = [(id<GnomeThemeToolbarButton>)backView toolbarItem];
  NSToolbar *toolbar = [item toolbar];
  NSView *view = [item view];
  NSSize content;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if (GnomeThemeLaysOutToolbar (toolbar) == NO)
    {
      return;
    }
  /* libs-gui drops a view taller than 32pt (24pt small): keep it. */
  if (view != nil && [view superview] == nil && [toolbar displayMode] != NSToolbarDisplayModeLabelOnly)
    {
      [backView addSubview: view];
    }
  content = GnomeThemeToolbarContentSize (item);
  [backView setFrameSize: NSMakeSize (content.width + 2.0 * GnomeThemeToolbarSpacing,
                                      GnomeThemeToolbarItemHeight (item))];
  GnomeThemePlaceToolbarView (backView, item);
}

/* A view item's label, under the view (or alone, centred), in the text
   colour: libs-gui draws it black, which is lost in the dark palette. */
- (void) _overrideGSToolbarBackViewMethod_drawRect: (NSRect)rect
{
  typedef void (*DrawIMP)(id, SEL, NSRect);
  DrawIMP originalIMP = (DrawIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarBackView"));
  NSView *backView = (NSView *)self;
  NSToolbarItem *item = [(id<GnomeThemeToolbarButton>)backView toolbarItem];
  NSToolbar *toolbar = [item toolbar];
  NSSize label;
  NSRect content, labelRect;
  NSMutableParagraphStyle *style;
  NSDictionary *attributes;

  if (GnomeThemeLaysOutToolbar (toolbar) == NO)
    {
      if (originalIMP != NULL)
        {
          originalIMP (self, _cmd, rect);
        }
      return;
    }
  label = GnomeThemeToolbarLabelSize (item);
  if (label.height == 0.0)
    {
      return;
    }
  content = GnomeThemeToolbarContentRect (item, [backView bounds]);
  labelRect = NSMakeRect (NSMinX ([backView bounds]), NSMinY (content), NSWidth ([backView bounds]), label.height);
  if ([toolbar displayMode] == NSToolbarDisplayModeLabelOnly)
    {
      labelRect.origin.y = floor (NSMidY (content) - label.height / 2.0);
    }
  style = AUTORELEASE ([[NSParagraphStyle defaultParagraphStyle] mutableCopy]);
  [style setAlignment: GnomeThemeCenterTextAlignment ()];
  attributes = [NSDictionary dictionaryWithObjectsAndKeys:
    GnomeThemeToolbarLabelFont (toolbar), NSFontAttributeName,
    ([item isEnabled] && [toolbar displayMode] != NSToolbarDisplayModeLabelOnly)
      ? [NSColor controlTextColor] : [NSColor disabledControlTextColor], NSForegroundColorAttributeName,
    style, NSParagraphStyleAttributeName, nil];
  [[item label] drawInRect: labelRect withAttributes: attributes];
}

/* After libs-gui places the items: every slot gets the row's height (the
   tallest item's), so the row is even and spaces don't set it. */
- (void) _overrideGSToolbarViewMethod__handleBackViewsFrame
{
  typedef void (*HandleIMP)(id, SEL);
  HandleIMP originalIMP = (HandleIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSToolbar *toolbar = [(id)self toolbar];
  NSEnumerator *enumerator;
  NSToolbarItem *item;
  CGFloat row = GnomeThemeToolbarRowHeight;
  Ivar heightIvar;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if (GnomeThemeLaysOutToolbar (toolbar) == NO)
    {
      return;
    }
  enumerator = [[toolbar items] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      if (GnomeThemeToolbarItemIsSpace (item) == NO)
        {
          row = MAX (row, GnomeThemeToolbarItemHeight (item));
        }
    }
  enumerator = [[toolbar items] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      NSView *backView = [item _backView];

      [backView setFrameSize: NSMakeSize (NSWidth ([backView frame]), row)];
      GnomeThemePlaceToolbarView (backView, item);
    }
  heightIvar = class_getInstanceVariable ([self class], "_heightFromLayout");
  if (heightIvar != NULL)
    {
      *(CGFloat *)((char *)self + ivar_getOffset (heightIvar)) = row;
    }
}

/* After libs-gui shares out the flexible width: it sets each view to its
   slot less its own 10pt insets, narrower than the slot this layout gives
   it (3pt insets), so views shrank on every layout down to nothing
   (plugins-themes-Adwaita#9). Each view gets its slot less the theme's
   insets instead, within its item's minSize and maxSize. */
- (void) _overrideGSToolbarViewMethod__takeInAccountFlexibleSpaces
{
  typedef void (*TakeIMP)(id, SEL);
  TakeIMP originalIMP = (TakeIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSToolbar *toolbar = [(id)self toolbar];
  NSEnumerator *enumerator;
  NSToolbarItem *item;

  GnomeThemeHeaderBarReserveTitleRoom ((NSView *)self);
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  GnomeThemeToolbarPlaceKeptItems ((NSView *)self);
  GnomeThemeHeaderBarGiveTitleRoom ((NSView *)self);
  if (GnomeThemeLaysOutToolbar (toolbar) == NO)
    {
      return;
    }
  enumerator = [[toolbar items] objectEnumerator];
  while ((item = [enumerator nextObject]) != nil)
    {
      NSView *backView = [item _backView];
      NSView *view = [item view];
      CGFloat width, minWidth, maxWidth;

      if (view == nil || [view superview] != backView)
        {
          continue;
        }
      width = NSWidth ([backView frame]) - 2.0 * GnomeThemeToolbarSpacing;
      minWidth = [item minSize].width;
      maxWidth = [item maxSize].width;
      if (maxWidth > 0.0 && maxWidth >= minWidth)
        {
          width = MIN (width, maxWidth);
        }
      width = MAX (width, MAX (minWidth, 0.0));
      [view setFrameSize: NSMakeSize (width, NSHeight ([view frame]))];
      GnomeThemePlaceToolbarView (backView, item);
    }
}

/* The items not in the » menu: those kept by visibilityPriority
   (GnomeThemeToolbarKeptItems), in their order. -[NSToolbar visibleItems],
   so the » menu, and the clip view's width follow; libs-gui's own when
   it drops items from the end anyway. */
- (NSArray *) _overrideGSToolbarViewMethod__visibleBackViews
{
  typedef NSArray *(*VisibleIMP)(id, SEL);
  VisibleIMP originalIMP = (VisibleIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSArray *items = [[(id)self toolbar] items];
  BOOL fromEnd = YES;
  NSIndexSet *keep = GnomeThemeToolbarKeptItems ((NSView *)self, &fromEnd);
  NSMutableArray *backViews;
  NSUInteger i;

  if (fromEnd && originalIMP != NULL)
    {
      return originalIMP (self, _cmd);
    }
  backViews = [NSMutableArray arrayWithCapacity: [keep count]];
  for (i = [keep firstIndex]; i != NSNotFound; i = [keep indexGreaterThanIndex: i])
    {
      [backViews addObject: [[items objectAtIndex: i] _backView]];
    }
  return backViews;
}

/* Where an item dragged while customising goes. libs-gui takes a
   position among -_visibleBackViews as the item's index in the toolbar,
   so with items kept by visibilityPriority (some before the end hidden)
   it moved the item to the wrong place. The same rule, by the kept items'
   own indexes: one dragged in goes before the first whose middle is
   right of the pointer, one in the row moves past a neighbour once the
   pointer crosses its middle, and one in the » menu goes where a new one
   would. */
- (int) _overrideGSToolbarViewMethod__insertionIndexAtPoint: (NSPoint)location
{
  typedef int (*InsertionIMP)(id, SEL, NSPoint);
  Class toolbarViewClass = NSClassFromString (@"GSToolbarView");
  InsertionIMP originalIMP = (InsertionIMP)GnomeThemeOriginalMethod (_cmd, self, toolbarViewClass);
  NSArray *items = [[(id)self toolbar] items];
  BOOL fromEnd = YES;
  NSIndexSet *keep = GnomeThemeToolbarKeptItems ((NSView *)self, &fromEnd);
  NSUInteger dragged = [toolbarViewClass draggedItemIndex];
  NSUInteger i, first = [keep firstIndex], last = [keep lastIndex];
  NSView *clipView;
  CGFloat x;

  if ((fromEnd && originalIMP != NULL) || first == NSNotFound)
    {
      return originalIMP != NULL ? originalIMP (self, _cmd, location) : (int)(dragged == NSNotFound ? 0 : dragged);
    }
  clipView = [[[items objectAtIndex: first] _backView] superview];
  x = [clipView convertPoint: location fromView: nil].x;
  if (dragged != NSNotFound && [keep containsIndex: dragged])
    {
      if (x < NSMidX ([[[items objectAtIndex: dragged] _backView] frame]))
        {
          for (i = first; i < dragged; i = [keep indexGreaterThanIndex: i])
            {
              if (x < NSMidX ([[[items objectAtIndex: i] _backView] frame]))
                {
                  return (int)i;
                }
            }
        }
      else
        {
          for (i = last; i > dragged; i = [keep indexLessThanIndex: i])
            {
              if (x > NSMidX ([[[items objectAtIndex: i] _backView] frame]))
                {
                  return (int)i;
                }
            }
        }
      return (int)dragged;
    }
  /* Before item i, or after the last kept; an item already in the
     toolbar is taken out first, so the indexes past it are one less. */
  for (i = first; i != NSNotFound; i = [keep indexGreaterThanIndex: i])
    {
      if (x < NSMidX ([[[items objectAtIndex: i] _backView] frame]))
        {
          return (int)(dragged != NSNotFound && dragged < i ? i - 1 : i);
        }
    }
  return (int)(dragged != NSNotFound && dragged < last ? last : last + 1);
}

- (void) _overrideGSToolbarButtonMethod_layout
{
  typedef void (*LayoutIMP)(id, SEL);
  LayoutIMP originalIMP = (LayoutIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarButton"));
  NSButton *button = (NSButton *)self;
  NSNumber *tag = objc_getAssociatedObject (button, &GnomeThemeToolbarButtonTrackingKey);

  NSToolbarItem *toolbarItem = [button respondsToSelector: @selector(toolbarItem)]
    ? [(id<GnomeThemeToolbarButton>)button toolbarItem] : nil;
  BOOL laysOut = GnomeThemeLaysOutToolbar ([toolbarItem toolbar]);

  /* Note the image's own size before libs-gui makes it 32x32. */
  if (laysOut)
    {
      GnomeThemeToolbarImageSize ([toolbarItem image], [toolbarItem toolbar]);
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if (laysOut)
    {
      NSToolbar *toolbar = [toolbarItem toolbar];

      if (GnomeThemeToolbarItemIsSpace (toolbarItem))
        {
          [button setFrameSize: NSMakeSize (NSWidth ([button frame]), GnomeThemeToolbarRowHeight)];
        }
      else
        {
          NSSize image = GnomeThemeToolbarImageSize ([toolbarItem image], toolbar);

          if (NSEqualSizes (image, NSZeroSize) == NO)
            {
              [[toolbarItem image] setSize: image];
            }
          [button setFont: GnomeThemeToolbarLabelFont (toolbar)];
          /* In the header bar libs-gui's layout still follows the
             toolbar's display mode: the icon alone, or the label alone
             for an item without one. */
          if (GnomeThemeToolbarInHeaderBar (toolbar))
            {
              [button setImagePosition: [toolbarItem image] != nil ? NSImageOnly : NSNoImage];
            }
          [button setFrameSize: NSMakeSize (GnomeThemeToolbarContentSize (toolbarItem).width
                                              + 2.0 * GnomeThemeToolbarSpacing,
                                            GnomeThemeToolbarItemHeight (toolbarItem))];
        }
    }
  /* The pressed state is the darker background drawn below; GNUstep's own
     highlight (NSChangeGrayCellMask) turned the label white on it. */
  [[button cell] setHighlightsBy: NSNoCellMask];
  /* Without its label, a button is named by its tool tip, as in GNOME. The
     item's own tool tip, when it has one, is already on the button. */
  if ([button respondsToSelector: @selector(toolbarItem)])
    {
      NSToolbarItem *item = [(id<GnomeThemeToolbarButton>)button toolbarItem];
      BOOL iconOnly = ([[item toolbar] displayMode] == NSToolbarDisplayModeIconOnly
                       || (GnomeThemeToolbarInHeaderBar ([item toolbar]) && [item image] != nil));

      if ([item toolTip] == nil)
        {
          [button setToolTip: iconOnly ? [item label] : nil];
        }
    }
  if (tag != nil)
    {
      [button removeTrackingRect: [tag integerValue]];
    }
  tag = [NSNumber numberWithInteger: [button addTrackingRect: [button bounds]
                                                      owner: [GnomeThemeToolbarHoverTracker sharedTracker]
                                                   userData: button
                                               assumeInside: NO]];
  objc_setAssociatedObject (button, &GnomeThemeToolbarButtonTrackingKey, tag,
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* The hover and pressed backgrounds: libadwaita's flat buttons, the text
   colour at 7% (hover) and 16% (pressed) over the toolbar, 6pt corners. */
- (void) _overrideGSToolbarButtonCellMethod_drawWithFrame: (NSRect)cellFrame
                                                   inView: (NSView *)controlView
{
  typedef void (*DrawIMP)(id, SEL, NSRect, NSView *);
  DrawIMP originalIMP = (DrawIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarButtonCell"));
  NSButtonCell *cell = (NSButtonCell *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSWindow *window = [controlView window];
  NSToolbarItem *toolbarItem = [controlView respondsToSelector: @selector(toolbarItem)]
    ? [(id<GnomeThemeToolbarButton>)controlView toolbarItem] : nil;
  NSRect buttonRect = NSInsetRect (cellFrame, 1.0, 1.0);

  /* With the theme's toolbar layout, the button is the item's content,
     centred in its slot, and its image and label are drawn there. */
  if (GnomeThemeLaysOutToolbar ([toolbarItem toolbar]) && GnomeThemeToolbarItemIsSpace (toolbarItem) == NO)
    {
      cellFrame = GnomeThemeToolbarContentRect (toolbarItem, cellFrame);
      buttonRect = cellFrame;
    }
  if (theme != nil && window != nil && [cell isEnabled])
    {
      BOOL pressed = [cell isHighlighted];
      BOOL hover = (objc_getAssociatedObject (controlView, &GnomeThemeToolbarButtonHoverKey) != nil);

      if (pressed || hover)
        {
          NSColor *background = [theme toolbarBackgroundColor];
          NSColor *textColor = GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor]);

          GnomeThemeFillAndStrokeRoundedRect (buttonRect,
                                              6.0,
                                              GnomeThemeBlend (background, textColor, pressed ? 0.16 : 0.07),
                                              nil,
                                              0.0);
        }
    }
  /* A label alone: libs-gui draws it at the top of the frame it's given
     (GSToolbarButtonCell's titleRect); give it a frame of the label's
     height, centred in the button. */
  if (GnomeThemeLaysOutToolbar ([toolbarItem toolbar]) && [cell imagePosition] == NSNoImage)
    {
      CGFloat height = GnomeThemeToolbarLabelSize (toolbarItem).height;

      if (height > 0.0 && height < NSHeight (cellFrame))
        {
          cellFrame = NSMakeRect (NSMinX (cellFrame), floor (NSMidY (cellFrame) - height / 2.0),
                                  NSWidth (cellFrame), height);
        }
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, cellFrame, controlView);
    }
}

/* GNUstep's arrow for this kind of cell (NSPopUpButtonCell's images): the
   nibble for a pop-up, a 3D arrow for a pull-down. Only that one, so an
   item that shows another of these images as its icon keeps it. */
static BOOL
GnomeThemeIsPopUpArrowImage(NSPopUpButtonCell *cell, NSImage *image)
{
  NSString *name = [image name];

  if ([cell pullsDown] == NO)
    {
      return [name isEqualToString: @"common_Nibble"];
    }
  return [name isEqualToString: @"common_3DArrowDown"] || [name isEqualToString: @"common_3DArrowRight"]
    || [name isEqualToString: @"common_3DArrowUp"];
}

- (void) _overrideNSPopUpButtonCellMethod_drawInteriorWithFrame: (NSRect)cellFrame
                                                         inView: (NSView *)controlView
{
  typedef void (*DrawInteriorIMP)(id, SEL, NSRect, NSView *);
  DrawInteriorIMP originalIMP = (DrawInteriorIMP)GnomeThemeOriginalMethod (_cmd, self, [NSPopUpButtonCell class]);
  NSPopUpButtonCell *cell = (NSPopUpButtonCell *)self;
  NSPopUpArrowPosition originalArrowPosition = [cell arrowPosition];
  NSMenuItem *item = [cell menuItem];
  NSImage *arrowImage = [cell _currentArrowImage];
  NSImage *savedImage = nil;
  NSRect contentFrame = cellFrame;
  NSFont *originalFont = [cell font];
  NSFont *popupFont = GnomeThemeEmphasizedFont (originalFont, (NSCell *)self, controlView);
  NSRect chevronFrame;

  /* The theme's -_currentArrowImage is nil, so only an image put on the
     item before the theme loaded can be the arrow: that one, or one of
     GNUstep's arrow images by name, as items archived in a Gorm file carry
     it (the Page Layout panel's empty Custom pop-up showed the nibble
     beside the chevron). */
  if (item != nil && [item image] != nil
    && ([item image] == arrowImage || GnomeThemeIsPopUpArrowImage (cell, [item image])))
    {
      savedImage = RETAIN ([item image]);
      [item setImage: nil];
    }

  [cell setArrowPosition: NSPopUpNoArrow];
  contentFrame.origin.x += 10.0;
  contentFrame.size.width = MAX (0.0, contentFrame.size.width - 16.0);
  chevronFrame = contentFrame;
  /* The title ends where the chevron's box starts; -drawTitleForMenuItemCell:
     cuts it short there (#67). It had the chevron's frame, and ran under the
     chevron. The chevron keeps its place, drawn below in the frame it has
     always had. */
  contentFrame.size.width = MAX (0.0, NSMinX (GnomeThemeComboBoxButtonRect (chevronFrame)) - NSMinX (contentFrame));
  if (popupFont != nil)
    {
      [cell setFont: popupFont];
    }

  if (originalIMP != NULL)
    {
      GnomeThemeDrawingPopUpTitle = YES;
      originalIMP (self, _cmd, contentFrame, controlView);
      GnomeThemeDrawingPopUpTitle = NO;
    }
  [GnomeThemeActiveTheme () drawPopUpButtonCellInteriorWithFrame: chevronFrame
                                                         withCell: cell
                                                           inView: controlView];

  [cell setArrowPosition: originalArrowPosition];
  if (popupFont != nil)
    {
      [cell setFont: originalFont];
    }

  if (item != nil && savedImage != nil)
    {
      [item setImage: savedImage];
      RELEASE (savedImage);
    }
}

/* No arrow image: the theme draws libadwaita's chevron. NSPopUpButtonCell
   puts its arrow image on the selected item when the item has none, and
   NSMenuView draws items' images in the open menu, so GNUstep's nibble
   showed at the right of the selected row, and stayed on rows selected
   earlier (#67). */
- (NSImage *) _overrideNSPopUpButtonCellMethod__currentArrowImage
{
  return nil;
}

/* Room for the theme's layout (the width the arrow image used to give):
   the widest title in the font it is drawn in, from 10pt in, then the
   chevron's box, which ends 8pt from the right edge. */
- (NSSize) _overrideNSPopUpButtonCellMethod_cellSize
{
  typedef NSSize (*CellSizeIMP)(id, SEL);
  CellSizeIMP originalIMP = (CellSizeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSPopUpButtonCell class]);
  NSPopUpButtonCell *cell = (NSPopUpButtonCell *)self;
  NSSize size = (originalIMP != NULL) ? originalIMP (self, _cmd) : NSZeroSize;
  NSFont *font = GnomeThemeEmphasizedFont ([cell font], (NSCell *)cell, [cell controlView]);
  NSDictionary *attributes = (font != nil)
    ? [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName] : nil;
  NSEnumerator *enumerator = [[cell itemArray] objectEnumerator];
  NSMenuItem *item;
  CGFloat titleWidth = 0.0;
  NSRect frame;

  /* As tall as a push button: GtkDropDown's 34pt (libs-gui's was about
     25, #86). The chevron's box, below, follows the height. */
  if ([cell isBordered])
    {
      size.height = MAX (size.height, GnomeThemeControlRowHeight (font));
    }
  frame = NSMakeRect (0.0, 0.0, size.width, MAX (size.height, NSHeight ([[cell controlView] bounds])));
  while ((item = [enumerator nextObject]) != nil)
    {
      titleWidth = MAX (titleWidth, [[item title] sizeWithAttributes: attributes].width);
    }
  size.width = MAX (size.width,
                    ceil (10.0 + titleWidth + GnomeThemeButtonTitleSlack
                          + NSWidth (GnomeThemeComboBoxButtonRect (frame)) + 8.0));
  return size;
}

/* A bezeled text field or combo box as tall as a push button: GtkEntry's
   34pt (libs-gui's were about 25, beside 34pt buttons and pop-ups in
   LinDirStat, #86). Labels, and the cells tables and headers draw, keep
   their size. One override for both: NSComboBoxCell's own would find
   this one as its original. */
- (NSSize) _overrideNSTextFieldCellMethod_cellSize
{
  typedef NSSize (*CellSizeIMP)(id, SEL);
  CellSizeIMP originalIMP = (CellSizeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSTextFieldCell class]);
  NSTextFieldCell *cell = (NSTextFieldCell *)self;
  NSSize size = (originalIMP != NULL) ? originalIMP (self, _cmd) : NSZeroSize;

  if ([cell isBezeled] && [cell isKindOfClass: [NSTableHeaderCell class]] == NO
    && [[cell controlView] isKindOfClass: [NSTableView class]] == NO)
    {
      size.height = MAX (size.height, GnomeThemeControlRowHeight ([cell font]));
    }
  return size;
}

- (void) _overrideNSComboBoxCellMethod_drawWithFrame: (NSRect)cellFrame
                                              inView: (NSView *)controlView
{
  NSComboBoxCell *cell = (NSComboBoxCell *)self;
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  BOOL enabled = [(NSCell *)cell isEnabled] && GnomeThemeViewEnabled (controlView);
  /* A drop-down's ring shows after a key press, as a button's. */
  BOOL focused = ((GnomeThemeIsDropDownComboBox (controlView)
                   ? GnomeThemeViewShowsFocusRing (controlView)
                   : GnomeThemeViewHasFocus (controlView))
    || [(NSCell *)cell isHighlighted]) && enabled;
  NSRect buttonRect = GnomeThemeComboBoxButtonRect (cellFrame);
  NSColor *fillColor = nil;
  NSColor *arrowColor = GnomeThemeColor (theme,
                                         enabled ? @"controlTextColor" : @"disabledControlTextColor",
                                         enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]);

  /* As for search fields: -[NSActionCell drawWithFrame:inView:], which this
     replaces, is where the cell learns its control view, which -stringValue
     needs to take the field editor's text while editing (#73). */
  if (controlView != nil)
    {
      [(NSCell *)cell setControlView: controlView];
    }

  if (focused)
    {
      GnomeThemeTrackFocusedEntryView (controlView);
    }

  GnomeThemeResolveEntryColors (theme,
                                controlView,
                                enabled,
                                focused,
                                NO,
                                &fillColor,
                                NULL,
                                NULL);
  GnomeThemeNeutralizeComboBoxButtonCell (cell);
  GnomeThemeDrawEntryChrome (theme, controlView, cellFrame, enabled, focused, NO);
  [cell drawInteriorWithFrame: cellFrame inView: controlView];

  if (fillColor != nil)
    {
      NSRect buttonFillRect = NSMakeRect (NSMinX (buttonRect) - 3.0,
                                          NSMinY (cellFrame) + 3.0,
                                          NSWidth (buttonRect) + 2.0,
                                          NSHeight (cellFrame) - 6.0);

      [fillColor set];
      NSRectFillUsingOperation (buttonFillRect, NSCompositeSourceOver);
      /* An editable combo box is libadwaita's entry linked to a button:
         where they overlap, 1px of the fill over itself (in GTK 6% of the
         way to the text colour) separates them. A drop-down has none. */
      if (GnomeThemeIsDropDownComboBox (controlView) == NO)
        {
          NSColor *text = GnomeThemeColor (theme, @"controlTextColor", [NSColor controlTextColor]);

          [GnomeThemeBlend (fillColor, text, 0.06) set];
          NSRectFillUsingOperation (NSMakeRect (NSMinX (buttonFillRect) - 1.0, NSMinY (cellFrame) + 0.5,
                                                1.0, NSHeight (cellFrame) - 1.0),
                                    NSCompositeSourceOver);
        }
    }

  GnomeThemeDrawPopupChevron (NSInsetRect (buttonRect, 6.0, 6.0),
                              arrowColor,
                              [controlView isFlipped]);
}

- (void) _overrideNSComboBoxCellMethod_drawInteriorWithFrame: (NSRect)cellFrame
                                                      inView: (NSView *)controlView
{
  typedef void (*DrawInteriorIMP)(id, SEL, NSRect, NSView *);
  DrawInteriorIMP originalIMP = (DrawInteriorIMP)GnomeThemeOriginalMethod (_cmd, self, [NSComboBoxCell class]);
  NSComboBoxCell *cell = (NSComboBoxCell *)self;
  NSRect buttonRect = GnomeThemeComboBoxButtonRect (cellFrame);
  NSRect textRect = GnomeThemeComboBoxTextRect (cell, cellFrame);
  BOOL enabled = [(NSCell *)self isEnabled];
  BOOL editing = ([controlView isKindOfClass: [NSControl class]]
    && [(NSControl *)controlView currentEditor] != nil);
  NSString *displayString = GnomeThemeComboBoxDisplayString (cell);
  NSMutableDictionary *attributes = nil;
  NSSize textSize = NSZeroSize;
  NSFont *font = nil;

  GnomeThemeNeutralizeComboBoxButtonCell (cell);
  GnomeThemeConfigureComboBoxPopupMetrics (cell);
  [cell setValue: [NSValue valueWithRect: cellFrame] forKey: @"_lastValidFrame"];

  if (editing)
    {
      if ([controlView isKindOfClass: [NSControl class]])
        {
          GnomeThemeSuppressEditorBackground ([(NSControl *)controlView currentEditor]);
        }
      [cell _drawEditorWithFrame: textRect
                           inView: controlView];
      (void)originalIMP;
      return;
    }

  if ([displayString length] > 0)
    {
      NSDictionary *cellAttributes = [cell _nonAutoreleasedTypingAttributes];

      attributes = [cellAttributes mutableCopy];
      RELEASE (cellAttributes);
      /* Bold is a drop-down's, a button's label; a combo box that can be
         edited is an entry, in the field editor's regular weight. */
      font = GnomeThemeIsDropDownComboBox (controlView)
        ? GnomeThemeEmphasizedFont ([attributes objectForKey: NSFontAttributeName], (NSCell *)self, controlView)
        : nil;
      if (font != nil)
        {
          [attributes setObject: font forKey: NSFontAttributeName];
        }
      [attributes setObject: enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]
                     forKey: NSForegroundColorAttributeName];

      textSize = [displayString sizeWithAttributes: attributes];
      textRect.origin.y = floor (NSMidY (cellFrame) - (textSize.height / 2.0));
      textRect.size.height = ceil (textSize.height);
      [displayString drawInRect: textRect withAttributes: attributes];
      RELEASE (attributes);
    }

  (void)buttonRect;
}

- (BOOL) _overrideNSComboBoxCellMethod_trackMouse: (NSEvent *)theEvent
                                           inRect: (NSRect)cellFrame
                                           ofView: (NSView *)controlView
                                     untilMouseUp: (BOOL)flag
{
  typedef BOOL (*TrackMouseIMP)(id, SEL, NSEvent *, NSRect, NSView *, BOOL);
  TrackMouseIMP originalIMP = (TrackMouseIMP)GnomeThemeOriginalMethod (_cmd, self, [NSComboBoxCell class]);
  NSPoint point = [controlView convertPoint: [theEvent locationInWindow] fromView: nil];
  BOOL nonEditableCombo = GnomeThemeIsDropDownComboBox (controlView);
  NSRect themedButtonRect = GnomeThemeComboBoxButtonRect (cellFrame);
  NSComboBoxCell *cell = (NSComboBoxCell *)self;

  GnomeThemeNeutralizeComboBoxButtonCell (cell);

  if ((nonEditableCombo && NSMouseInRect (point, cellFrame, [controlView isFlipped]))
    || NSMouseInRect (point, themedButtonRect, [controlView isFlipped]))
    {
      if ([(NSCell *)self isEnabled])
        {
          NS_DURING
            {
              [cell setValue: controlView forKey: @"_control_view"];
            }
          NS_HANDLER
            {
            }
          NS_ENDHANDLER

          [cell _didClickWithinButton: cell];
          [(NSCell *)cell setHighlighted: NO];
          GnomeThemeNeutralizeComboBoxButtonCell (cell);
          [controlView setNeedsDisplay: YES];
          [controlView displayIfNeededIgnoringOpacity];
          if ([controlView window] != nil)
            {
              [[controlView window] setViewsNeedDisplay: YES];
              [[controlView window] flushWindow];
              [[controlView window] performSelector: @selector(displayIfNeeded)
                                         withObject: nil
                                         afterDelay: 0.0];
            }
          return YES;
        }
    }

  if (originalIMP != NULL)
    {
      return originalIMP (self, _cmd, theEvent, cellFrame, controlView, flag);
    }

  return NO;
}

- (void) _overrideNSComboBoxCellMethod__performClickWithFrame: (NSRect)cellFrame
                                                       inView: (NSView *)controlView
{
  NSComboBoxCell *cell = (NSComboBoxCell *)self;

  if (controlView == nil || [(NSCell *)cell isEnabled] == NO)
    {
      return;
    }

  GnomeThemeNeutralizeComboBoxButtonCell (cell);

  NS_DURING
    {
      [cell setValue: controlView forKey: @"_control_view"];
    }
  NS_HANDLER
    {
    }
  NS_ENDHANDLER

  [cell _didClickWithinButton: cell];
  [(NSCell *)cell setHighlighted: NO];
  GnomeThemeNeutralizeComboBoxButtonCell (cell);
  [controlView setNeedsDisplay: YES];
  [controlView displayIfNeededIgnoringOpacity];

  (void)cellFrame;
}

/* A combo box that can't be edited is libadwaita's GtkDropDown: a button
   with a bold label, and no text cursor. GNUstep started the field editor
   when it took the focus (a click or Tab), which drew the text in the
   editor's regular weight over a lighter strip, or nothing at all when the
   cell had no string value yet (#70). It now keeps the focus itself, with
   a ring after a key press as a button does, and Space, Return or an
   arrow key opens its list. */
static BOOL
GnomeThemeIsDropDownComboBox(id view)
{
  return [view isKindOfClass: [NSComboBox class]] && [(NSComboBox *)view isEditable] == NO;
}

- (void) _overrideNSComboBoxMethod_selectText: (id)sender
{
  typedef void (*SelectTextIMP)(id, SEL, id);
  SelectTextIMP originalIMP = (SelectTextIMP)GnomeThemeOriginalMethod (_cmd, self, [NSComboBox class]);

  if (GnomeThemeIsDropDownComboBox (self))
    {
      [(NSView *)self setNeedsDisplay: YES];
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, sender);
    }
}

- (BOOL) _overrideNSComboBoxMethod_resignFirstResponder
{
  typedef BOOL (*ResignIMP)(id, SEL);
  ResignIMP originalIMP = (ResignIMP)GnomeThemeOriginalMethod (_cmd, self, [NSComboBox class]);
  BOOL resigned = (originalIMP != NULL) ? originalIMP (self, _cmd) : YES;

  if (resigned && GnomeThemeIsDropDownComboBox (self))
    {
      [(NSView *)self setNeedsDisplay: YES];
    }
  return resigned;
}

/* The frame it's given, as in Cocoa: libs-gui's -setFrame: makes every
   combo box 21pt high ("We shouldn't harcode the height value"), so one
   sized to fit (34pt, -cellSize) drew 21pt at the top of its row
   (LinDirStat's folder combo box, #86). */
- (void) _overrideNSComboBoxMethod_setFrame: (NSRect)frame
{
  typedef void (*SetFrameIMP)(id, SEL, NSRect);
  SetFrameIMP superIMP = (SetFrameIMP)[[NSComboBox superclass] instanceMethodForSelector: _cmd];

  if (superIMP != NULL)
    {
      superIMP (self, _cmd, frame);
    }
}

- (void) _overrideNSComboBoxMethod_keyDown: (NSEvent *)theEvent
{
  typedef void (*KeyDownIMP)(id, SEL, NSEvent *);
  KeyDownIMP originalIMP = (KeyDownIMP)GnomeThemeOriginalMethod (_cmd, self, [NSComboBox class]);
  NSComboBox *comboBox = (NSComboBox *)self;
  NSString *characters = [theEvent charactersIgnoringModifiers];
  unichar key = ([characters length] > 0) ? [characters characterAtIndex: 0] : 0;

  if (GnomeThemeIsDropDownComboBox (self) && [comboBox isEnabled]
    && ([theEvent modifierFlags] & (NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask)) == 0
    && (key == ' ' || key == NSCarriageReturnCharacter || key == NSEnterCharacter
      || key == NSDownArrowFunctionKey || key == NSUpArrowFunctionKey))
    {
      [[comboBox cell] _performClickWithFrame: [comboBox bounds] inView: comboBox];
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, theEvent);
    }
}

- (void) _overrideNSComboBoxCellMethod__didClickWithinButton: (id)sender
{
  NSComboBoxCell *cell = (NSComboBoxCell *)self;
  NSView *controlView = [cell controlView];
  NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  id popup = nil;

  (void)sender;

  if ([(NSCell *)cell isEnabled] == NO || controlView == nil)
    {
      return;
    }

  [notificationCenter postNotificationName: NSComboBoxWillPopUpNotification
                                    object: controlView
                                  userInfo: nil];
  /* Nothing to choose from, even once the app could fill the list for
     the notification: no list, not an empty box (#76). */
  if ([cell numberOfItems] == 0)
    {
      [notificationCenter postNotificationName: NSComboBoxWillDismissNotification
                                        object: controlView
                                      userInfo: nil];
      return;
    }

  GnomeThemeNeutralizeComboBoxButtonCell (cell);
  [(NSCell *)cell setHighlighted: YES];
  [controlView setNeedsDisplay: YES];
  [controlView displayIfNeededIgnoringOpacity];

  popup = [cell _popUp];
  [cell setValue: popup forKey: @"_popup"];
  GnomeThemeStyleComboBoxPopup (cell, GnomeThemeActiveTheme ());
  if ([popup respondsToSelector: @selector(popUpForComboBoxCell:)])
    {
      [popup popUpForComboBoxCell: cell];
    }
  [cell setValue: nil forKey: @"_popup"];

  [notificationCenter postNotificationName: NSComboBoxWillDismissNotification
                                    object: controlView
                                  userInfo: nil];

  [(NSCell *)cell setHighlighted: NO];
  GnomeThemeNeutralizeComboBoxButtonCell (cell);
  [controlView setNeedsDisplay: YES];
  [controlView displayIfNeededIgnoringOpacity];
}

- (void) _overrideNSComboBoxCellMethod_highlight: (BOOL)flag
                                        withFrame: (NSRect)cellFrame
                                           inView: (NSView *)controlView
{
  NSComboBoxCell *cell = (NSComboBoxCell *)self;

  GnomeThemeNeutralizeComboBoxButtonCell (cell);

  if ([(NSCell *)cell isHighlighted] != flag)
    {
      [(NSCell *)cell setHighlighted: flag];
      GnomeThemeNeutralizeComboBoxButtonCell (cell);
      [cell drawWithFrame: cellFrame inView: controlView];
    }
}

- (NSSize) _overrideNSButtonCellMethod_cellSize
{
  typedef NSSize (*CellSizeIMP)(id, SEL);
  CellSizeIMP originalIMP = (CellSizeIMP)GnomeThemeOriginalMethod (_cmd, self, [NSButtonCell class]);
  NSButtonCell *cell = (NSButtonCell *)self;
  NSSize size = (originalIMP != NULL) ? originalIMP (self, _cmd) : NSMakeSize (0.0, 0.0);
  BOOL checkbox = GnomeThemeButtonCellIsCheckbox (cell);
  BOOL radio = GnomeThemeButtonCellIsRadio (cell);
  /* Measure with the geometry the drawing code uses, on a generous probe frame:
     what the bezel takes (drawingRectForBounds:) plus the theme's own insets,
     and the slack that keeps "Sign In" from drawing as "Sign". */
  NSRect probe = NSMakeRect (0.0, 0.0, 600.0, MAX (size.height, 34.0));
  NSRect drawing = [cell drawingRectForBounds: probe];
  CGFloat bezel = probe.size.width - drawing.size.width;
  CGFloat slack = GnomeThemeButtonTitleSlack;

  if (checkbox || radio)
    {
      /* Mirrors drawInteriorWithFrame: an indicator of at least 18pt at +2,
         the label gap, then the title in the cell's own font. */
      NSAttributedString *title = [cell attributedTitle];
      CGFloat indicatorSize = MAX (GnomeThemeIndicatorMinimumSize (cell, nil), floor (drawing.size.height * 0.58));
      CGFloat labelWidth = [title length] > 0 ? ceil ([title size].width) : 0.0;
      CGFloat width = bezel + 2.0 + indicatorSize + (labelWidth > 0.0 ? GnomeThemeIndicatorLabelGap + labelWidth + slack : 2.0);

      size.width = MAX (size.width, ceil (width));
      size.height = MAX (size.height, indicatorSize + 4.0);
      return size;
    }

  if ([cell image] == nil)
    {
      NSSize labelSize = GnomeThemeButtonLabelSize (cell);
      NSRect titleRect = GnomeThemeButtonTitleRect (cell, probe);
      CGFloat insets = drawing.size.width - titleRect.size.width;
      CGFloat verticalPadding = ([cell isBordered] || [cell isBezeled]) ? 12.0 : 6.0;

      size.width = MAX (size.width, ceil (labelSize.width + bezel + insets + slack));
      size.height = MAX (size.height, ceil (labelSize.height + verticalPadding));

      if ([cell isBordered] || [cell isBezeled])
        {
          size.width = MAX (size.width, 86.0);
          size.height = MAX (size.height, 34.0);
        }
    }

  return size;
}

- (BOOL) _overrideNSSegmentedCellMethod_trackMouse: (NSEvent *)theEvent
                                            inRect: (NSRect)cellFrame
                                            ofView: (NSView *)controlView
                                      untilMouseUp: (BOOL)flag
{
  typedef BOOL (*TrackMouseIMP)(id, SEL, NSEvent *, NSRect, NSView *, BOOL);
  TrackMouseIMP originalIMP = (TrackMouseIMP)GnomeThemeOriginalMethod (_cmd, self, [NSSegmentedCell class]);
  GnomeTheme *theme = GnomeThemeActiveTheme ();
  NSSegmentedCell *cell = (NSSegmentedCell *)self;
  NSPoint point = [controlView convertPoint: [theEvent locationInWindow] fromView: nil];
  NSInteger hitIndex = NSNotFound;

  if (theme == nil || [cell trackingMode] != NSSegmentSwitchTrackingSelectOne)
    {
      if (originalIMP != NULL)
        {
          return originalIMP (self, _cmd, theEvent, cellFrame, controlView, flag);
        }
      return NO;
    }

  hitIndex = GnomeThemeSegmentIndexAtPoint (cell, cellFrame, point);
  if (hitIndex == NSNotFound || [cell isEnabledForSegment: hitIndex] == NO)
    {
      if (originalIMP != NULL)
        {
          return originalIMP (self, _cmd, theEvent, cellFrame, controlView, flag);
        }
      return NO;
    }

  if ([controlView respondsToSelector: @selector(setSelectedSegment:)])
    {
      [(id)controlView setSelectedSegment: hitIndex];
    }
  else
    {
      [cell setSelectedSegment: hitIndex];
    }

  [controlView setNeedsDisplayInRect: cellFrame];

  if ([controlView isKindOfClass: [NSControl class]])
    {
      [(NSControl *)controlView sendAction: [cell action] to: [cell target]];
    }
  else
    {
      [NSApp sendAction: [cell action] to: [cell target] from: controlView];
    }

  return YES;
}

- (void) _overrideNSButtonCellMethod_drawInteriorWithFrame: (NSRect)cellFrame
                                                    inView: (NSView *)controlView
{
  typedef void (*DrawInteriorIMP)(id, SEL, NSRect, NSView *);
  DrawInteriorIMP originalIMP = (DrawInteriorIMP)GnomeThemeOriginalMethod (_cmd, self, [NSButtonCell class]);
  NSButtonCell *cell = (NSButtonCell *)self;
  BOOL checkbox = GnomeThemeButtonCellIsCheckbox ((NSButtonCell *)self);
  BOOL radio = GnomeThemeButtonCellIsRadio ((NSButtonCell *)self);

  if (checkbox == NO && radio == NO)
    {
      BOOL defaultButton = NO;
      BOOL hasLegacyReturnImage = GnomeThemeButtonCellUsesLegacyReturnImage (cell);
      BOOL searchButton = GnomeThemeButtonCellUsesSearchImage (cell);
      BOOL cancelButton = GnomeThemeButtonCellUsesCancelImage (cell);
      BOOL hasCustomImage = ([cell image] != nil && hasLegacyReturnImage == NO);
      BOOL hasCustomAlternateImage = ([cell alternateImage] != nil
        && GnomeThemeImageHasName ([cell alternateImage], @"common_retH") == NO);
      BOOL enabled = [cell isEnabled];
      NSColor *textColor = enabled
        ? [NSColor controlTextColor]
        : [NSColor disabledControlTextColor];
      NSRect titleRect = GnomeThemeButtonTitleRect (cell, cellFrame);
      NSString *keyEquivalent = [cell keyEquivalent];

      if (searchButton || cancelButton)
        {
          GnomeTheme *theme = GnomeThemeActiveTheme ();
          NSColor *glyphColor = GnomeThemeColor (theme,
                                                 enabled ? @"controlTextColor" : @"disabledControlTextColor",
                                                 enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]);

          /* libadwaita dims an entry's icons: the text colour at 70% over
             the background (#59); full strength while pressed. */
          if (([cell isHighlighted] && enabled) == NO)
            {
              glyphColor = GnomeThemeBlend (glyphColor,
                                            GnomeThemeColor (theme,
                                                             @"windowBackgroundColor",
                                                             [NSColor windowBackgroundColor]),
                                            0.3);
            }

          if (searchButton)
            {
              GnomeThemeDrawSearchGlyph (cellFrame, glyphColor);
            }
          else
            {
              GnomeThemeDrawCancelGlyph (cellFrame, glyphColor, nil);
            }
          return;
        }

      if (hasCustomImage || hasCustomAlternateImage)
        {
          if (originalIMP != NULL)
            {
              originalIMP (self, _cmd, cellFrame, controlView);
            }
          return;
        }

      defaultButton = ([keyEquivalent isEqualToString: @"\r"]
        || [keyEquivalent isEqualToString: @"\n"]);
      if (defaultButton == NO && controlView != nil && [controlView window] != nil)
        {
          defaultButton = ([[controlView window] defaultButtonCell] == cell);
        }
      if (defaultButton && GnomeThemeWindowHasAccentButton ([controlView window]))
        {
          defaultButton = NO;
        }
      defaultButton = defaultButton || GnomeThemeButtonCellHasAccentStyle (cell);

      if (enabled && GnomeThemeButtonCellIsDestructive (cell, controlView))
        {
          /* As the bezel: destructive_color in an alert, white elsewhere. */
          textColor = GnomeThemeViewIsInAlert (controlView)
            ? GnomeThemeColor (GnomeThemeActiveTheme (), @"GnomeThemeDestructiveTextColor", [NSColor redColor])
            : [NSColor whiteColor];
        }
      else if (defaultButton && enabled)
        {
          textColor = [NSColor selectedControlTextColor];
        }
      else if (GnomeThemeButtonCellHasAccentStyle (cell))
        {
          textColor = [[NSColor selectedControlTextColor] colorWithAlphaComponent: 0.5];
        }

      if ([cell isHighlighted])
        {
          titleRect.origin.x += 1.0;
          titleRect.origin.y -= 1.0;
        }

      GnomeThemeDrawButtonLabel (cell, titleRect, controlView, textColor);
      return;
    }

  {
    GnomeTheme *theme = GnomeThemeActiveTheme ();
    BOOL enabled = [(NSButtonCell *)self isEnabled];
    BOOL highlighted = [(NSButtonCell *)self isHighlighted];
    NSInteger state = [(NSButtonCell *)self state];
    NSRect contentRect = [(NSButtonCell *)self drawingRectForBounds: cellFrame];
    CGFloat indicatorSize = MAX (GnomeThemeIndicatorMinimumSize ((NSCell *)self, controlView), floor (contentRect.size.height * 0.58));
    NSRect indicatorRect = GnomeThemeIndicatorRectInContent ((NSButtonCell *)self, contentRect, indicatorSize);
    NSRect titleRect = GnomeThemeIndicatorTitleRect ((NSButtonCell *)self, contentRect, indicatorRect);
    NSColor *fillColor = nil;
    NSColor *borderColor = nil;
    NSColor *markColor = nil;
    NSBezierPath *path = nil;
    BOOL checked = (state == NSOnState || state == NSMixedState);
    NSColor *windowColor = [NSColor windowBackgroundColor];
    NSColor *card = GnomeThemeColor (theme, @"GnomeThemeCardColor", [NSColor controlBackgroundColor]);
    BOOL highContrast = [[theme settings] highContrastEnabled];


    if (checked)
      {
        fillColor = [NSColor selectedControlColor];
        borderColor = GnomeThemeBlend (fillColor, [NSColor controlShadowColor], 0.25);
        markColor = [NSColor selectedControlTextColor];
      }
    else
      {
        /* libadwaita's unchecked check box and radio: no fill, a 2px ring
           of the foreground at 15% (the outline's 50% in high contrast).
           The text background and the border colour were the window's own
           in the dark palette, so the indicator didn't show (#57). */
        fillColor = nil;
        borderColor = GnomeThemeColor (theme, @"GnomeThemeOutlineColor",
                                              GnomeThemeColor (theme, @"GnomeThemeTroughColor",
                                                                      [NSColor controlShadowColor]));
        markColor = [NSColor controlTextColor];
      }

    if (highlighted && enabled)
      {
        fillColor = checked
          ? GnomeThemeBlend (fillColor, [NSColor controlShadowColor], 0.14)
          : GnomeThemeColor (theme, @"GnomeThemeButtonColor", nil);
      }
    if (enabled == NO)
      {
        fillColor = (fillColor != nil)
          ? GnomeThemeBlend (fillColor, card, 0.35)
          : nil;
        borderColor = checked
          ? GnomeThemeBlend (borderColor, card, 0.35)
          : GnomeThemeBlend (borderColor, windowColor, highContrast ? 0.6 : 0.5);
        markColor = [NSColor disabledControlTextColor];
      }

    if (GnomeThemeViewShowsFocusRing (controlView) && enabled)
      {
        NSRect focusRect = GnomeThemeIndicatorFocusRect (cell, cellFrame);
        CGFloat focusRadius = radio
          ? MIN (9.0, floor (focusRect.size.height / 2.0))
          : 7.0;

        GnomeThemeDrawFocusRing (theme, focusRect, focusRadius);
      }

    if (checked)
      {
        if (radio)
          {
            path = [NSBezierPath bezierPathWithOvalInRect: NSInsetRect (indicatorRect, 0.5, 0.5)];
          }
        else
          {
            path = GnomeThemeRoundedPath (NSInsetRect (indicatorRect, 0.5, 0.5), 5.0);
          }
        [fillColor set];
        [path fill];
        [borderColor set];
        [path setLineWidth: 1.0];
        [path stroke];
      }
    else
      {
        /* The ring inside the indicator's edge, 2px wide. */
        if (radio)
          {
            path = [NSBezierPath bezierPathWithOvalInRect: NSInsetRect (indicatorRect, 1.0, 1.0)];
          }
        else
          {
            path = GnomeThemeRoundedPath (NSInsetRect (indicatorRect, 1.0, 1.0), 4.0);
          }
        if (fillColor != nil)
          {
            [fillColor set];
            [path fill];
          }
        [borderColor set];
        [path setLineWidth: 2.0];
        [path stroke];
      }

    if (state == NSOnState)
      {
        if (radio)
          {
            NSRect dotRect = NSInsetRect (indicatorRect, indicatorSize * 0.28, indicatorSize * 0.28);
            NSBezierPath *dotPath = [NSBezierPath bezierPathWithOvalInRect: dotRect];

            [markColor set];
            [dotPath fill];
          }
        else
          {
            NSBezierPath *checkPath = [NSBezierPath bezierPath];
            CGFloat left = NSMinX (indicatorRect) + indicatorSize * 0.22;
            CGFloat midX = NSMinX (indicatorRect) + indicatorSize * 0.45;
            CGFloat right = NSMaxX (indicatorRect) - indicatorSize * 0.2;
            CGFloat top = NSMinY (indicatorRect) + indicatorSize * 0.28;
            CGFloat midY = NSMidY (indicatorRect) + indicatorSize * 0.08;
            CGFloat bottom = NSMaxY (indicatorRect) - indicatorSize * 0.24;

            [checkPath moveToPoint: NSMakePoint (left, midY)];
            [checkPath lineToPoint: NSMakePoint (midX, bottom)];
            [checkPath lineToPoint: NSMakePoint (right, top)];
            [checkPath setLineWidth: 2.1];
            [checkPath setLineCapStyle: NSRoundLineCapStyle];
            [checkPath setLineJoinStyle: NSRoundLineJoinStyle];
            [markColor set];
            [checkPath stroke];
          }
      }
    else if (state == NSMixedState)
      {
        NSRect dashRect = NSMakeRect (NSMinX (indicatorRect) + indicatorSize * 0.22,
                                      NSMidY (indicatorRect) - 1.5,
                                      indicatorSize * 0.56,
                                      3.0);

        GnomeThemeFillAndStrokeRoundedRect (dashRect, 1.5, markColor, nil, 0.0);
      }

    GnomeThemeDrawIndicatorLabel ((NSButtonCell *)self, titleRect, controlView, enabled);
  }
}

@end
