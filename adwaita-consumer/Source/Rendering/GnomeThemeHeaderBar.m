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

/* libadwaita's header bar as the window's title bar, when GNUstep draws the
   window decorations itself (GSX11HandlesWindowDecorations NO; the theme
   can't ask for that, the backend reads it before the theme loads). The
   window's top row is a 46px bar with the bold title centred and round
   window buttons in the order of GNOME's button-layout; the window can be
   moved by the bar and resized from every edge and corner.

   Sizes and colours are measured from libadwaita 1.7 renders
   (Reference/HeaderBar/headerbar_reference.py). */

#import "../GnomeTheme.h"
#import "../Settings/GnomeThemeSettings.h"
#import "../Adapters/GnomeThemeWindowManager.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <GNUstepGUI/GSToolbarView.h>
#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSWindowDecorationView.h>

/* The bar, and the 1px border round the window (GTK's border for windows
   without a compositor shadow). As in GTK, the border is drawn over the
   bar's outermost pixels: the bar is 46px including it, and the buttons'
   margins are measured from the window's edge. */
static const CGFloat GnomeThemeHeaderBarHeight = 46.0;
static const CGFloat GnomeThemeWindowBorderWidth = 1.0;
/* Window buttons: 34px, 6px from the bar's edges, 3px apart, a 24px circle
   round a 16px icon. */
static const CGFloat GnomeThemeWindowButtonSize = 34.0;
static const CGFloat GnomeThemeWindowButtonMargin = 6.0;
static const CGFloat GnomeThemeWindowButtonSpacing = 3.0;
static const CGFloat GnomeThemeWindowButtonCircle = 24.0;
/* Title: kept this far from the buttons at either end. */
static const CGFloat GnomeThemeHeaderBarTitleSpacing = 6.0;
/* With the toolbar in the bar, the title's flexible space keeps this much
   room: a short title, or a long one shortened with "…". Toolbar items go
   into the » menu first. */
static const CGFloat GnomeThemeHeaderBarMinimumTitleWidth = 100.0;

/* rect grown to whole device pixels. At a fractional scale a window's edges
   fall inside a pixel: clearing and filling them there covers that pixel only
   partly, and what's under it (black, in an X window) shows as a dark line. */
static NSRect
GnomeThemeRectOutwardToPixels(NSRect rect, CGFloat factor)
{
  CGFloat minX, minY, maxX, maxY;

  if (factor <= 0.0)
    {
      return rect;
    }
  minX = floor (NSMinX (rect) * factor) / factor;
  minY = floor (NSMinY (rect) * factor) / factor;
  maxX = ceil (NSMaxX (rect) * factor) / factor;
  maxY = ceil (NSMaxY (rect) * factor) / factor;
  return NSMakeRect (minX, minY, maxX - minX, maxY - minY);
}
/* libs-gui's » button and the inset on each side of an item's view
   (ClippedItemsViewWidth and InsetItemViewX in GSToolbarView.m). */
static const CGFloat GnomeThemeToolbarClippedItemsWidth = 28.0;
static const CGFloat GnomeThemeToolbarItemViewInset = 10.0;
/* The theme's inset on each side of an item's view
   (GnomeThemeToolbarSpacing in GnomeThemeControls.m). */
static const CGFloat GnomeThemeToolbarItemSpacing = 3.0;
/* Resizing: a strip this wide inside each edge (there's no shadow margin
   outside the window to put it in), and corners this long. */
static const CGFloat GnomeThemeResizeEdge = 5.0;
static const CGFloat GnomeThemeResizeCorner = 16.0;
/* With a shadow, as GTK 4 under Mutter: the edges are a band outside the
   visible window, in the shadow, and none inside. */
static const CGFloat GnomeThemeResizeBand = 12.0;
/* How far the pointer moves before a press on the bar becomes a move
   (GTK's gtk-dnd-drag-threshold). */
static const CGFloat GnomeThemeDragThreshold = 8.0;

/* The text colour's share of the circle behind a window button: normal,
   under the pointer, pressed. */
static const CGFloat GnomeThemeWindowButtonFill = 0.10;
static const CGFloat GnomeThemeWindowButtonHoverFill = 0.15;
static const CGFloat GnomeThemeWindowButtonPressedFill = 0.30;
/* The text colour's share of the title and icons in a window that isn't
   focused (GTK's backdrop state), and of the border. */
static const CGFloat GnomeThemeBackdropText = 0.60;
static const CGFloat GnomeThemeWindowBorderShade = 0.125;
/* High contrast (libadwaita's, measured the same way): a 1px ring round
   each button's circle, and a darker border. */
static const CGFloat GnomeThemeHighContrastRing = 0.36;
static const CGFloat GnomeThemeHighContrastBorderShade = 0.40;

enum
{
  GnomeThemeResizeLeft = 1,
  GnomeThemeResizeRight = 2,
  GnomeThemeResizeBottom = 4,
  GnomeThemeResizeTop = 8
};

@interface GSStandardWindowDecorationView (GnomeThemeHeaderBarPrivate)
- (NSPoint) mouseLocationOnScreenOutsideOfEventStream;
- (void) moveWindowStartingWithEvent: (NSEvent *)event;
@end

/* The header bar's, for its maximise button's icon. */
@interface NSView (GnomeThemeHeaderBarState)
- (BOOL) isMaximized;
@end

@interface NSWindow (GnomeThemeHeaderBarPrivate)
- (void) _captureMouse: (id)sender;
- (void) _releaseMouse: (id)sender;
- (BOOL) _hasTitleWithRepresentedFilename;
@end

@interface NSToolbar (GnomeThemeHeaderBarPrivate)
- (NSView *) _toolbarView;
@end

@interface NSToolbarItem (GnomeThemeHeaderBarPrivate)
- (NSView *) _backView;
- (BOOL) _isFlexibleSpace;
@end

@interface NSView (GnomeThemeHeaderBarToolbarView)
- (void) _reload;
- (void) setBorderMask: (unsigned int)borderMask;
- (unsigned int) borderMask;
- (CGFloat) _heightFromLayout;
- (NSToolbar *) toolbar;
- (NSToolbarItem *) toolbarItem;
- (BOOL) holdsToolbarInBar;
@end

/* GSWindowDecorationView's (ToolbarPrivate) methods, overridden below. */
@interface GSWindowDecorationView (GnomeThemeHeaderBarToolbar)
- (void) addToolbarView: (NSView *)toolbarView;
- (void) removeToolbarView: (NSView *)toolbarView;
- (void) adjustToolbarView: (NSView *)toolbarView;
@end

/* The app shows its toolbar in the header bar row, as a GNOME app packs
   its buttons there, instead of as a row of its own. Asked in order: the
   user for this app (its defaults, or -GnomeThemeHeaderBarToolbar on the
   command line); the app, when its Info.plist says its toolbar doesn't suit
   the bar (NO); the user for all apps (NSGlobalDomain); the app's own
   default (its Info.plist, or registered defaults). Off otherwise, as the
   toolbar has to suit it (a few icons, a flexible space between those at
   the start and those at the end). */
BOOL
GnomeThemeHeaderBarToolbarEnabled(void)
{
  NSString *key = @"GnomeThemeHeaderBarToolbar";
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSEnumerator *enumerator = [[defaults searchList] objectEnumerator];
  NSString *domain;
  id global = nil;
  id registered = nil;
  id declared = [[[NSBundle mainBundle] infoDictionary] objectForKey: key];

  while ((domain = [enumerator nextObject]) != nil)
    {
      NSDictionary *values = [defaults persistentDomainForName: domain] ?: [defaults volatileDomainForName: domain];
      id value = [values objectForKey: key];

      if ([value respondsToSelector: @selector(boolValue)] == NO)
        {
          continue;
        }
      if ([domain isEqualToString: NSGlobalDomain])
        {
          global = global ?: value;
        }
      else if ([domain isEqualToString: NSRegistrationDomain])
        {
          registered = registered ?: value;
        }
      else
        {
          return [value boolValue];
        }
    }
  if ([declared respondsToSelector: @selector(boolValue)] == NO)
    {
      declared = nil;
    }
  if (declared != nil && [declared boolValue] == NO)
    {
      return NO;
    }
  if (global != nil)
    {
      return [global boolValue];
    }
  return [(declared ?: registered) boolValue];
}

BOOL
GnomeThemeToolbarInHeaderBar(NSToolbar *toolbar)
{
  NSView *superview = [[toolbar _toolbarView] superview];

  return [superview respondsToSelector: @selector(holdsToolbarInBar)] && [superview holdsToolbarInBar];
}

static BOOL
GnomeThemeToolbarItemIsSpace(NSToolbarItem *item)
{
  NSString *identifier = [item itemIdentifier];

  return [identifier isEqualToString: NSToolbarSpaceItemIdentifier]
    || [identifier isEqualToString: NSToolbarFlexibleSpaceItemIdentifier]
    || [identifier isEqualToString: NSToolbarSeparatorItemIdentifier];
}

BOOL
GnomeThemeUsesRightToLeft(void)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray *languages;

  /* Cocoa's switch for trying a right-to-left layout. */
  if ([defaults objectForKey: @"NSForceRightToLeftWritingDirection"] != nil)
    {
      return [defaults boolForKey: @"NSForceRightToLeftWritingDirection"];
    }
  languages = [NSLocale preferredLanguages];
  return [languages count] > 0
    && [NSLocale characterDirectionForLanguage: [languages objectAtIndex: 0]] == NSLocaleLanguageDirectionRightToLeft;
}

BOOL
GnomeThemeUsesHeaderBar(void)
{
  GSDisplayServer *server = GSCurrentServer ();

  return server != nil && [server handlesWindowDecorations] == NO;
}

static GnomeThemeSettings *
GnomeThemeCurrentSettings(void)
{
  GSTheme *theme = [GSTheme theme];

  return [theme isKindOfClass: [GnomeTheme class]] ? [(GnomeTheme *)theme settings] : nil;
}

/* GTK's backdrop state follows the keyboard focus: a main window behind
   a key panel is drawn as not focused. */
static BOOL
GnomeThemeWindowIsFocused(NSWindow *window)
{
  return [window isKeyWindow];
}

NSColor *
GnomeThemeHeaderBarTextColor(NSWindow *window)
{
  NSColor *text = [NSColor controlTextColor];

  if (GnomeThemeWindowIsFocused (window))
    {
      return text;
    }
  return [[NSColor windowBackgroundColor] blendedColorWithFraction: GnomeThemeBackdropText ofColor: text];
}

/* button-layout's two sides, keeping the buttons GNUstep has: close,
   minimize and maximize. Without a colon everything is at the start, as in
   GTK. */
static void
GnomeThemeParseButtonLayout(NSString *layout, NSArray **startOut, NSArray **endOut)
{
  NSArray *sides = [layout componentsSeparatedByString: @":"];
  NSArray *known = [NSArray arrayWithObjects: @"close", @"minimize", @"maximize", nil];
  NSMutableArray *result[2];
  NSUInteger side;

  for (side = 0; side < 2; side++)
    {
      NSEnumerator *enumerator;
      NSString *name;

      result[side] = [NSMutableArray array];
      if (side >= [sides count])
        {
          continue;
        }
      enumerator = [[[sides objectAtIndex: side] componentsSeparatedByString: @","] objectEnumerator];
      while ((name = [enumerator nextObject]) != nil)
        {
          name = [name stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
          if ([known containsObject: name] && [result[0] containsObject: name] == NO
            && [result[1] containsObject: name] == NO)
            {
              [result[side] addObject: name];
            }
        }
    }
  *startOut = result[0];
  *endOut = result[1];
}

static GnomeThemeMoveResizeDirection
GnomeThemeMoveResizeDirectionForEdges(NSUInteger edges)
{
  BOOL left = (edges & GnomeThemeResizeLeft) != 0;
  BOOL right = (edges & GnomeThemeResizeRight) != 0;
  BOOL top = (edges & GnomeThemeResizeTop) != 0;
  BOOL bottom = (edges & GnomeThemeResizeBottom) != 0;

  if (top)
    {
      return left ? GnomeThemeMoveResizeTopLeft : (right ? GnomeThemeMoveResizeTopRight : GnomeThemeMoveResizeTop);
    }
  if (bottom)
    {
      return left ? GnomeThemeMoveResizeBottomLeft
        : (right ? GnomeThemeMoveResizeBottomRight : GnomeThemeMoveResizeBottom);
    }
  return left ? GnomeThemeMoveResizeLeft : GnomeThemeMoveResizeRight;
}

static NSCursor *
GnomeThemeResizeCursor(NSUInteger edges)
{
  static NSCursor *diagonal[2];
  BOOL horizontal = (edges & (GnomeThemeResizeLeft | GnomeThemeResizeRight)) != 0;
  BOOL vertical = (edges & (GnomeThemeResizeTop | GnomeThemeResizeBottom)) != 0;
  NSUInteger index;

  if (horizontal && vertical == NO)
    {
      return [NSCursor resizeLeftRightCursor];
    }
  if (vertical && horizontal == NO)
    {
      return [NSCursor resizeUpDownCursor];
    }
  /* Top-left and bottom-right share one diagonal, the other two the
     other. */
  index = ((edges & GnomeThemeResizeLeft) != 0) == ((edges & GnomeThemeResizeTop) != 0) ? 0 : 1;
  if (diagonal[index] == nil)
    {
      NSImage *image = [NSImage imageNamed: index == 0 ? @"GSFrameResizeNWSECursor" : @"GSFrameResizeNESWCursor"];
      NSSize size = [image size];

      diagonal[index] = image != nil
        ? [[NSCursor alloc] initWithImage: image hotSpot: NSMakePoint (floor (size.width / 2.0), floor (size.height / 2.0))]
        : RETAIN ([NSCursor arrowCursor]);
    }
  return diagonal[index];
}

/* A round libadwaita window button. The action comes from GSTheme
   (-performClose:, -miniaturize:, -zoom:); the images GNUstep sets on the
   close button are ignored. */
@interface GnomeThemeWindowButton : NSButton
{
  NSTrackingRectTag _tracking;
  BOOL _hover;
}
@end

@implementation GnomeThemeWindowButton

- (void) updateTracking
{
  if (_tracking != 0)
    {
      [self removeTrackingRect: _tracking];
      _tracking = 0;
    }
  if ([self window] != nil)
    {
      _tracking = [self addTrackingRect: [self bounds] owner: self userData: NULL assumeInside: NO];
    }
}

- (void) viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self updateTracking];
}

- (void) setFrame: (NSRect)frame
{
  [super setFrame: frame];
  [self updateTracking];
}

- (void) mouseEntered: (NSEvent *)event
{
  _hover = YES;
  [self setNeedsDisplay: YES];
}

- (void) mouseExited: (NSEvent *)event
{
  _hover = NO;
  [self setNeedsDisplay: YES];
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

/* A point of a 16px icon, in the icon file's coordinates (origin at the
   top left). */
- (NSPoint) iconPoint: (NSRect)icon x: (CGFloat)x y: (CGFloat)y
{
  return NSMakePoint (NSMinX (icon) + x, [self isFlipped] ? NSMinY (icon) + y : NSMaxY (icon) - y);
}

/* A square outline of the given size and stroke, as the maximize and
   restore icons draw it. */
- (void) fillSquareOutline: (NSRect)icon at: (CGFloat)origin size: (CGFloat)size stroke: (CGFloat)stroke
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  NSPoint a = [self iconPoint: icon x: origin y: origin];
  NSPoint b = [self iconPoint: icon x: origin + size y: origin + size];
  NSPoint c = [self iconPoint: icon x: origin + stroke y: origin + stroke];
  NSPoint d = [self iconPoint: icon x: origin + size - stroke y: origin + size - stroke];

  [path appendBezierPathWithRect: NSMakeRect (MIN (a.x, b.x), MIN (a.y, b.y), fabs (b.x - a.x), fabs (b.y - a.y))];
  [path appendBezierPathWithRect: NSMakeRect (MIN (c.x, d.x), MIN (c.y, d.y), fabs (d.x - c.x), fabs (d.y - c.y))];
  [path setWindingRule: NSEvenOddWindingRule];
  [path fill];
}

/* The icons, from Adwaita's window-close-symbolic, window-minimize-symbolic,
   window-maximize-symbolic and window-restore-symbolic. */
- (void) drawIconInRect: (NSRect)icon
{
  switch ([self tag])
    {
      case NSWindowCloseButton:
        {
          /* The X, with the icon's square ends and rounded joins: lines
             (a point) and curves (two control points and a point). */
          static const struct { char op; CGFloat v[6]; } steps[] = {
            {'M', {4, 4}}, {'L', {5.03125, 4}},
            {'C', {5.285156, 4.011719, 5.542969, 4.128906, 5.71875, 4.3125}},
            {'L', {8, 6.59375}}, {'L', {10.3125, 4.3125}},
            {'C', {10.578125, 4.082031, 10.757812, 4.007812, 11, 4}},
            {'L', {12, 4}}, {'L', {12, 5}},
            {'C', {12, 5.285156, 11.964844, 5.550781, 11.75, 5.75}},
            {'L', {9.46875, 8.03125}}, {'L', {11.71875, 10.28125}},
            {'C', {11.90625, 10.46875, 12, 10.734375, 12, 11}},
            {'L', {12, 12}}, {'L', {11, 12}},
            {'C', {10.734375, 12, 10.46875, 11.90625, 10.28125, 11.71875}},
            {'L', {8, 9.4375}}, {'L', {5.71875, 11.71875}},
            {'C', {5.53125, 11.90625, 5.265625, 12, 5, 12}},
            {'L', {4, 12}}, {'L', {4, 11}},
            {'C', {4, 10.734375, 4.09375, 10.46875, 4.28125, 10.28125}},
            {'L', {6.5625, 8.03125}}, {'L', {4.28125, 5.75}},
            {'C', {4.070312, 5.554688, 3.976562, 5.28125, 4, 5}}
          };
          NSBezierPath *path = [NSBezierPath bezierPath];
          NSUInteger i;

          for (i = 0; i < sizeof (steps) / sizeof (steps[0]); i++)
            {
              const CGFloat *v = steps[i].v;

              switch (steps[i].op)
                {
                  case 'M':
                    [path moveToPoint: [self iconPoint: icon x: v[0] y: v[1]]];
                    break;
                  case 'L':
                    [path lineToPoint: [self iconPoint: icon x: v[0] y: v[1]]];
                    break;
                  default:
                    [path curveToPoint: [self iconPoint: icon x: v[4] y: v[5]]
                         controlPoint1: [self iconPoint: icon x: v[0] y: v[1]]
                         controlPoint2: [self iconPoint: icon x: v[2] y: v[3]]];
                    break;
                }
            }
          [path closePath];
          [path fill];
          break;
        }
      case NSWindowMiniaturizeButton:
        {
          NSPoint a = [self iconPoint: icon x: 4.0 y: 10.0];
          NSPoint b = [self iconPoint: icon x: 12.0 y: 12.0];

          NSRectFill (NSMakeRect (a.x, MIN (a.y, b.y), b.x - a.x, 2.0));
          break;
        }
      case NSWindowZoomButton:
        if ([[self superview] respondsToSelector: @selector(isMaximized)]
            ? [[self superview] isMaximized] : [[self window] isZoomed])
          {
            [self fillSquareOutline: icon at: 5.0 size: 6.0 stroke: 2.0];
          }
        else
          {
            [self fillSquareOutline: icon at: 4.0 size: 8.0 stroke: 2.0];
          }
        break;
      default:
        break;
    }
}

- (void) drawRect: (NSRect)rect
{
  NSRect bounds = [self bounds];
  NSColor *background = [NSColor windowBackgroundColor];
  NSColor *text = GnomeThemeHeaderBarTextColor ([self window]);
  CGFloat fill = GnomeThemeWindowButtonFill;
  NSRect circle = NSMakeRect (floor (NSMidX (bounds) - GnomeThemeWindowButtonCircle / 2.0),
                              floor (NSMidY (bounds) - GnomeThemeWindowButtonCircle / 2.0),
                              GnomeThemeWindowButtonCircle, GnomeThemeWindowButtonCircle);

  if ([[self cell] isHighlighted])
    {
      fill = GnomeThemeWindowButtonPressedFill;
    }
  else if (_hover)
    {
      fill = GnomeThemeWindowButtonHoverFill;
    }
  [[background blendedColorWithFraction: fill ofColor: text] set];
  [[NSBezierPath bezierPathWithOvalInRect: circle] fill];
  if ([GnomeThemeCurrentSettings () highContrastEnabled])
    {
      NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect: NSInsetRect (circle, 0.5, 0.5)];

      [ring setLineWidth: 1.0];
      [[background blendedColorWithFraction: GnomeThemeHighContrastRing ofColor: text] set];
      [ring stroke];
    }

  [text set];
  [self drawIconInRect: NSInsetRect (circle, 4.0, 4.0)];
}

@end

@interface GnomeThemeHeaderBarDecorationView : GSStandardWindowDecorationView
{
  NSButton *_zoomButton;
  /* The primary menu's ☰, when the app uses it. */
  NSView *_menuButton;
  /* The frame to go back to from maximised. GNUstep's -zoom: only goes
     back to a frame saved under the window's autosave name. */
  NSRect _restoreFrame;
  BOOL _hasRestoreFrame;
  /* The backend draws a shadow round the window (and its outline): no
     border of our own then. */
  BOOL _hasShadow;
  /* The resize band outside each edge (left, right, top, bottom), while
     the shadow shows; all 0 otherwise, and the edges are inside. */
  CGFloat _resizeBand[4];
  /* The ends of the buttons at the bar's start and end, for the title. */
  CGFloat _startLimit;
  CGFloat _endLimit;
  /* The window's toolbar is in the bar (rather than in a row of its own):
     where it was put, whatever the setting says now. */
  BOOL _toolbarInBar;
  /* A document window's folder, shown on hover over its title, and where
     the title was drawn. */
  NSString *_titleFolder;
  NSRect _titleFolderRect;
}
- (void) placeToolbarForSetting;
- (void) layoutWindowButtons;
@end

@implementation GnomeThemeHeaderBarDecorationView

/* NSDocModalWindowMask marks a dialog drawn as libadwaita's alert
   dialogs are: a border and no bar (see -initWithContentRect:... for
   GSAlertPanel below). */
+ (void) offsets: (float *)l : (float *)r : (float *)t : (float *)b
    forStyleMask: (NSUInteger)style
{
  *l = *r = *t = *b = 0.0;
  /* Fullscreen: neither bar nor border. (GNUstep has no -setStyleMask:,
     so a window is created fullscreen or not at all.) */
  if (style & NSFullScreenWindowMask)
    {
      return;
    }
  if (style & (NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
               | NSDocModalWindowMask))
    {
      *l = *r = *t = *b = GnomeThemeWindowBorderWidth;
    }
  if (style & (NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask))
    {
      *t = GnomeThemeHeaderBarHeight;
    }
  /* Offsets are in device pixels; the bar is drawn in points. */
  if ((style & NSUnscaledWindowMask) == 0)
    {
      CGFloat factor = [[NSScreen mainScreen] userSpaceScaleFactor];

      *l *= factor;
      *r *= factor;
      *t *= factor;
      *b *= factor;
    }
}

+ (CGFloat) minFrameWidthWithTitle: (NSString *)aTitle
                         styleMask: (NSUInteger)aStyle
{
  /* Room for the buttons (in device pixels, as the offsets); the title is
     shortened to fit. */
  CGFloat factor = (aStyle & NSUnscaledWindowMask) ? 1.0 : [[NSScreen mainScreen] userSpaceScaleFactor];

  return factor * (2.0 * GnomeThemeWindowButtonMargin
                   + 3.0 * GnomeThemeWindowButtonSize + 2.0 * GnomeThemeWindowButtonSpacing);
}

- (id) initWithFrame: (NSRect)frame
              window: (NSWindow *)w
{
  self = [super initWithFrame: frame window: w];
  if (self != nil && ([w styleMask] & NSFullScreenWindowMask))
    {
      [closeButton removeFromSuperview];
      [miniaturizeButton removeFromSuperview];
      closeButton = miniaturizeButton = nil;
      hasTitleBar = isTitled = NO;
      titleBarRect = NSZeroRect;
      return self;
    }
  if (self != nil && ([w styleMask] & NSResizableWindowMask) && hasTitleBar)
    {
      _zoomButton = [NSWindow standardWindowButton: NSWindowZoomButton forStyleMask: [w styleMask]];
      [_zoomButton setTarget: self];
      [_zoomButton setAction: @selector(toggleMaximized:)];
      [self addSubview: _zoomButton];
      [self updateRects];
    }
  return self;
}

/* The title shows the unsaved-changes dot. */
- (void) setDocumentEdited: (BOOL)flag
{
  [super setDocumentEdited: flag];
  if (hasTitleBar)
    {
      [self setNeedsDisplayInRect: titleBarRect];
    }
}

- (void) dealloc
{
  if (_titleFolder != nil)
    {
      [self removeAllToolTips];
    }
  RELEASE (_titleFolder);
  RELEASE (_menuButton);
  [super dealloc];
}

- (NSButton *) buttonNamed: (NSString *)name
{
  if ([name isEqualToString: @"close"])
    {
      return closeButton;
    }
  if ([name isEqualToString: @"minimize"])
    {
      return miniaturizeButton;
    }
  if ([name isEqualToString: @"maximize"])
    {
      return _zoomButton;
    }
  return nil;
}

- (void) layoutWindowButtons
{
  NSRect bounds = [self bounds];
  NSArray *start = nil;
  NSArray *end = nil;
  NSArray *all = [NSArray arrayWithObjects: @"close", @"minimize", @"maximize", nil];
  CGFloat y = NSMaxY (bounds) - GnomeThemeWindowButtonMargin - GnomeThemeWindowButtonSize;
  CGFloat x;
  NSEnumerator *enumerator;
  NSString *name;

  GnomeThemeParseButtonLayout ([GnomeThemeCurrentSettings () buttonLayout] ?: @"appmenu:close", &start, &end);

  enumerator = [all objectEnumerator];
  while ((name = [enumerator nextObject]) != nil)
    {
      [[self buttonNamed: name] setHidden: [start containsObject: name] == NO && [end containsObject: name] == NO];
    }

  x = NSMinX (bounds) + GnomeThemeWindowButtonMargin;
  _startLimit = x - GnomeThemeWindowButtonMargin;
  enumerator = [start objectEnumerator];
  while ((name = [enumerator nextObject]) != nil)
    {
      NSButton *button = [self buttonNamed: name];

      if (button != nil)
        {
          [button setFrame: NSMakeRect (x, y, GnomeThemeWindowButtonSize, GnomeThemeWindowButtonSize)];
          _startLimit = x + GnomeThemeWindowButtonSize;
          x += GnomeThemeWindowButtonSize + GnomeThemeWindowButtonSpacing;
        }
    }

  x = NSMaxX (bounds) - GnomeThemeWindowButtonMargin - GnomeThemeWindowButtonSize;
  _endLimit = x + GnomeThemeWindowButtonSize + GnomeThemeWindowButtonMargin;
  enumerator = [end reverseObjectEnumerator];
  while ((name = [enumerator nextObject]) != nil)
    {
      NSButton *button = [self buttonNamed: name];

      if (button != nil)
        {
          [button setFrame: NSMakeRect (x, y, GnomeThemeWindowButtonSize, GnomeThemeWindowButtonSize)];
          _endLimit = x;
          x -= GnomeThemeWindowButtonSize + GnomeThemeWindowButtonSpacing;
        }
    }

  /* The primary menu's ☰ goes before the buttons at the end, 6px from
     them (or from the window's edge), as libadwaita packs it. The button
     view keeps a 6px margin at its right. */
  if (GnomeThemeUsesPrimaryMenu () && [window menu] != nil)
    {
      CGFloat width = GnomeThemeWindowButtonSize + GnomeThemeWindowButtonMargin;

      if (_menuButton == nil)
        {
          _menuButton = GnomeThemeNewHeaderBarMenuButton ();
          [self addSubview: _menuButton];
        }
      [_menuButton setFrame: NSMakeRect (_endLimit - width, NSMaxY (bounds) - GnomeThemeHeaderBarHeight,
                                         width, GnomeThemeHeaderBarHeight)];
      _endLimit -= width;
    }
  else if (_menuButton != nil)
    {
      [_menuButton removeFromSuperview];
      DESTROY (_menuButton);
    }

  if (GnomeThemeUsesRightToLeft ())
    {
      [self mirrorBarLayout];
    }
  [self layoutToolbarInBar];
}

/* Whether the window's toolbar is in the bar: where -addToolbarView: put
   it, not what the setting says now (it can change while the toolbar is
   shown). */
- (BOOL) holdsToolbarInBar
{
  return _toolbarInBar && [window toolbar] != nil;
}

/* The setting changed: move a shown toolbar into or out of the bar,
   keeping the window's frame (the content gives up or takes the toolbar's
   row). */
- (void) placeToolbarForSetting
{
  NSToolbar *toolbar = [window toolbar];
  NSView *toolbarView = [toolbar _toolbarView];
  NSRect frame = [window frame];

  if (hasTitleBar == NO || toolbar == nil || [toolbar isVisible] == NO || [toolbarView superview] != self
    || _toolbarInBar == GnomeThemeHeaderBarToolbarEnabled ())
    {
      return;
    }
  RETAIN (toolbarView);
  [self removeToolbarView: toolbarView];
  [self addToolbarView: toolbarView];
  RELEASE (toolbarView);
  [window setFrame: frame display: YES];
}

/* The toolbar between the buttons at the bar's start and end, 6pt from
   them (its items keep 3pt at each side), as libadwaita spaces a header
   bar's children. */
- (void) layoutToolbarInBar
{
  NSView *toolbarView = [[window toolbar] _toolbarView];
  NSRect frame;

  if ([self holdsToolbarInBar] == NO || [toolbarView superview] != self)
    {
      return;
    }
  frame = NSMakeRect (_startLimit + 3.0, NSMaxY ([self bounds]) - GnomeThemeHeaderBarHeight,
                      MAX (0.0, _endLimit - _startLimit - 6.0), GnomeThemeHeaderBarHeight);
  /* No bottom line in the bar: without it libs-gui doesn't keep a point
     for one, which put the items 1pt high and » 1pt taller. */
  if ([toolbarView borderMask] != 0)
    {
      [toolbarView setBorderMask: 0];
      [toolbarView _reload];
    }
  if (NSWidth (frame) != NSWidth ([toolbarView frame]))
    {
      /* libs-gui lays the items out again for a new width. */
      [toolbarView setFrameSize: NSMakeSize (NSWidth (frame), 100.0)];
      [toolbarView _reload];
    }
  [toolbarView setFrame: frame];
}

/* The toolbar's row of its own is gone: the content keeps the window's
   height, and the window doesn't grow or shrink with the toolbar. */
- (NSRect) contentRectForFrameRect: (NSRect)aRect
                         styleMask: (NSUInteger)aStyle
{
  NSRect content = [super contentRectForFrameRect: aRect styleMask: aStyle];

  if ([self holdsToolbarInBar])
    {
      content.size.height += [[[window toolbar] _toolbarView] _heightFromLayout];
    }
  return content;
}

- (NSRect) frameRectForContentRect: (NSRect)aRect
                         styleMask: (NSUInteger)aStyle
{
  NSRect frame = [super frameRectForContentRect: aRect styleMask: aStyle];

  if ([self holdsToolbarInBar])
    {
      frame.size.height -= [[[window toolbar] _toolbarView] _heightFromLayout];
    }
  return frame;
}

- (void) addToolbarView: (NSView *)toolbarView
{
  if (hasTitleBar == NO || GnomeThemeHeaderBarToolbarEnabled () == NO)
    {
      NSToolbar *toolbar = [window toolbar];

      _toolbarInBar = NO;
      /* Back from the bar: its row's bottom line, as libs-gui sets it. */
      if ([toolbarView borderMask] == 0 && [toolbar showsBaselineSeparator])
        {
          [toolbarView setBorderMask: GSToolbarViewBottomBorder];
        }
      [super addToolbarView: toolbarView];
      return;
    }
  _toolbarInBar = YES;
  hasToolbar = YES;
  /* In the bar before its items are laid out: they lay out for it. */
  [self addSubview: toolbarView];
  [toolbarView setFrameSize: NSMakeSize (MAX (0.0, _endLimit - _startLimit - 6.0), 100.0)];
  [toolbarView _reload];
  [self layoutToolbarInBar];
  [self setNeedsDisplayInRect: titleBarRect];
}

- (void) removeToolbarView: (NSView *)toolbarView
{
  if (_toolbarInBar == NO || [toolbarView superview] != self)
    {
      [super removeToolbarView: toolbarView];
      return;
    }
  _toolbarInBar = NO;
  hasToolbar = NO;
  [toolbarView removeFromSuperviewWithoutNeedingDisplay];
  [self setNeedsDisplayInRect: titleBarRect];
}

- (void) adjustToolbarView: (NSView *)toolbarView
{
  if ([self holdsToolbarInBar])
    {
      [self layoutToolbarInBar];
      [self setNeedsDisplayInRect: titleBarRect];
      return;
    }
  [super adjustToolbarView: toolbarView];
}

/* Where the title goes when the toolbar is in the bar: in its widest
   flexible space (the items before it are the bar's start, those after
   it its end), else after the items; never under the » of the items that
   don't fit. Only what the toolbar's clip view shows counts: when even
   the title's space doesn't fit, libs-gui clips it with the items after
   it, and the title was drawn in its whole frame, under the » (alpha13,
   ScreenshotTool's toolbar at 720pt). */
- (void) titleLimitsWithToolbar: (CGFloat *)minX : (CGFloat *)maxX
{
  NSView *toolbarView = [[window toolbar] _toolbarView];
  NSEnumerator *enumerator = [[[window toolbar] items] objectEnumerator];
  NSToolbarItem *item;
  NSView *subview;
  NSRect widest = NSZeroRect;
  CGFloat itemsEnd = *minX;

  if ([self holdsToolbarInBar] == NO)
    {
      return;
    }
  while ((item = [enumerator nextObject]) != nil)
    {
      NSView *backView = [item _backView];
      NSRect visible, frame;

      if ([backView superview] == nil || [backView isHiddenOrHasHiddenAncestor])
        {
          continue;
        }
      visible = [backView visibleRect];
      if (NSIsEmptyRect (visible))
        {
          continue;
        }
      frame = [self convertRect: visible fromView: backView];
      if ([[item itemIdentifier] isEqualToString: NSToolbarFlexibleSpaceItemIdentifier])
        {
          if (NSWidth (frame) > NSWidth (widest))
            {
              widest = frame;
            }
        }
      else
        {
          itemsEnd = MAX (itemsEnd, NSMaxX (frame) + GnomeThemeHeaderBarTitleSpacing);
        }
    }
  if (NSWidth (widest) > 0.0)
    {
      *minX = MAX (*minX, NSMinX (widest));
      *maxX = MIN (*maxX, NSMaxX (widest));
    }
  else
    {
      *minX = MAX (*minX, itemsEnd);
    }
  /* The » is the toolbar view's only subview besides its clip view; it's
     at the toolbar's end, or its start in a right-to-left window. */
  enumerator = [[toolbarView subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      NSRect frame;

      if ([subview isKindOfClass: [NSClipView class]] || [subview isHidden])
        {
          continue;
        }
      frame = [self convertRect: [subview bounds] fromView: subview];
      if (NSMidX (frame) > (*minX + *maxX) / 2.0)
        {
          *maxX = MIN (*maxX, NSMinX (frame) - GnomeThemeHeaderBarTitleSpacing);
        }
      else
        {
          *minX = MAX (*minX, NSMaxX (frame) + GnomeThemeHeaderBarTitleSpacing);
        }
    }
}

/* In a right-to-left language GTK mirrors the header bar: button-layout's
   start is at the right, the buttons at its end are at the left (close
   outermost), and the ☰ is 6px to their right. The layout above is made
   left to right; this turns it over. */
- (void) mirrorBarLayout
{
  NSRect bounds = [self bounds];
  NSArray *views = [NSArray arrayWithObjects: closeButton ?: (id)[NSNull null],
                                              miniaturizeButton ?: (id)[NSNull null],
                                              _zoomButton ?: (id)[NSNull null], nil];
  NSEnumerator *enumerator = [views objectEnumerator];
  id view;
  CGFloat start = _startLimit;

  while ((view = [enumerator nextObject]) != nil)
    {
      if (view != [NSNull null])
        {
          NSRect frame = [view frame];

          frame.origin.x = NSMinX (bounds) + NSMaxX (bounds) - NSMaxX (frame);
          [view setFrame: frame];
        }
    }
  if (_menuButton != nil)
    {
      /* The ☰ view keeps its margin at its right: mirror the button, not
         the view. */
      NSRect frame = [_menuButton frame];

      frame.origin.x = NSMinX (bounds) + NSMaxX (bounds) - NSMaxX (frame) + GnomeThemeWindowButtonMargin;
      [_menuButton setFrame: frame];
    }
  _startLimit = NSMinX (bounds) + NSMaxX (bounds) - _endLimit;
  _endLimit = NSMinX (bounds) + NSMaxX (bounds) - start;
}

/* GSWindowDecorationView puts a menu bar 1pt above the content area, over
   the border it expects there; here that would be the header bar's last
   row. */
/* GSWindowDecorationView's +contentRectForFrameRect:styleMask: scales the
   content's size to points but not its origin, so with a scale factor
   other than 1 the content, and the menu bar and toolbar laid out from
   it, sit the border's width in pixels, taken as points, from the edges:
   a gap at the left and bottom, and an overlap under the bar. (GNUstep's
   own title bar has the same offset.) Moves them back. */
- (void) scaleContentOrigin
{
  NSUInteger style = [window styleMask];
  CGFloat factor = [[NSScreen mainScreen] userSpaceScaleFactor];
  NSEnumerator *enumerator;
  NSView *subview;
  float l, r, t, b;
  NSPoint shift;

  if ((style & NSUnscaledWindowMask) || factor == 1.0)
    {
      return;
    }
  [object_getClass (self) offsets: &l : &r : &t : &b forStyleMask: style];
  shift = NSMakePoint (l / factor - l, b / factor - b);
  contentRect.origin = NSMakePoint (l / factor, b / factor);
  enumerator = [[self subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      if (subview != closeButton && subview != miniaturizeButton && subview != _zoomButton
        && subview != _menuButton
        && ([self holdsToolbarInBar] == NO || subview != [[window toolbar] _toolbarView]))
        {
          NSPoint origin = [subview frame].origin;

          [subview setFrameOrigin: NSMakePoint (origin.x + shift.x, origin.y + shift.y)];
        }
    }
}

- (void) layout
{
  NSEnumerator *enumerator;
  NSView *subview;
  BOOL inBar = [self holdsToolbarInBar];

  /* GSWindowDecorationView would give the toolbar a row above the
     content: in the bar, it has none. */
  if (inBar)
    {
      hasToolbar = NO;
    }
  [super layout];
  if (inBar)
    {
      hasToolbar = YES;
    }
  [self scaleContentOrigin];
  [self layoutToolbarInBar];
  enumerator = [[self subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      if ([subview isKindOfClass: [NSMenuView class]] && NSMaxY ([subview frame]) > NSMaxY (contentRect))
        {
          NSRect frame = [subview frame];

          /* An empty one (the primary menu's) moves down instead. */
          frame.origin.y = MIN (NSMinY (frame), NSMaxY (contentRect));
          frame.size.height = NSMaxY (contentRect) - NSMinY (frame);
          [subview setFrame: frame];
        }
    }
}

- (void) updateRects
{
  NSRect bounds = [self bounds];

  if (hasTitleBar)
    {
      titleBarRect = NSMakeRect (NSMinX (bounds), NSMaxY (bounds) - GnomeThemeHeaderBarHeight,
                                 NSWidth (bounds), GnomeThemeHeaderBarHeight);
      [self layoutWindowButtons];
    }
  resizeBarRect = NSZeroRect;
  /* The shadow comes and goes with the window manager's state
     (maximised, tiled), which also changes the frame. */
  [self updateShadow];
  [[self window] invalidateCursorRectsForView: self];
}

/* The title, shortened with an ellipsis to fit between the buttons. */
- (NSString *) fittedTitle: (NSString *)title
                attributes: (NSDictionary *)attributes
                     width: (CGFloat)width
{
  NSString *ellipsis = [NSString stringWithFormat: @"%C", (unichar)0x2026];
  NSUInteger length = [title length];

  if ([title sizeWithAttributes: attributes].width <= width)
    {
      return title;
    }
  while (length > 0)
    {
      NSString *shortened;

      length--;
      shortened = [[[title substringToIndex: length]
                     stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]
                    stringByAppendingString: ellipsis];
      if ([shortened sizeWithAttributes: attributes].width <= width)
        {
          return shortened;
        }
    }
  return @"";
}

/* GNUstep titles a document window "name  --  ~/folder"
   (-setTitleWithRepresentedFilename:). GNOME shows the file's name, with
   the folder as AdwWindowTitle's subtitle; here the folder shows on hover
   over the title. Other titles are left as they are, but for the
   unsaved-changes dot. */
static NSString *
GnomeThemeHeaderBarTitle(NSWindow *window, NSString **folder)
{
  NSString *path = [window representedFilename];
  NSString *title = [window title];

  *folder = nil;
  if ([path length] > 0 && [window respondsToSelector: @selector(_hasTitleWithRepresentedFilename)]
    && [window _hasTitleWithRepresentedFilename])
    {
      *folder = [[path stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];
      title = [[NSFileManager defaultManager] displayNameAtPath: path];
    }
  /* Unsaved changes (-setDocumentEdited:): a dot before the title, as
     GNOME's document apps mark them (plugins-themes-Adwaita#39). */
  if ([title length] > 0 && [window isDocumentEdited])
    {
      title = [@"\u2022 " stringByAppendingString: title];
    }
  return title;
}

- (NSString *) view: (NSView *)view
   stringForToolTip: (NSToolTipTag)tag
              point: (NSPoint)point
           userData: (void *)data
{
  return _titleFolder;
}

/* The folder's tool tip over the drawn title, moved when the title is. */
- (void) setTitleFolder: (NSString *)folder inRect: (NSRect)rect
{
  if ((folder == _titleFolder || [folder isEqualToString: _titleFolder])
    && NSEqualRects (rect, _titleFolderRect))
    {
      return;
    }
  if (_titleFolder != nil)
    {
      [self removeAllToolTips];
    }
  ASSIGN (_titleFolder, folder);
  _titleFolderRect = rect;
  if (folder != nil)
    {
      [self addToolTipRect: rect owner: self userData: NULL];
    }
}

- (void) drawTitleInRect: (NSRect)bar
{
  NSString *folder = nil;
  NSString *title = GnomeThemeHeaderBarTitle (window, &folder);
  NSFont *font = [GnomeThemeCurrentSettings () boldInterfaceFont] ?: [NSFont boldSystemFontOfSize: 0.0];
  NSDictionary *attributes;
  CGFloat minX = _startLimit + GnomeThemeHeaderBarTitleSpacing;
  CGFloat maxX = _endLimit - GnomeThemeHeaderBarTitleSpacing;
  NSSize size;
  CGFloat x;
  CGFloat baseline;

  [self titleLimitsWithToolbar: &minX : &maxX];
  if (isTitled == NO || [title length] == 0 || maxX <= minX)
    {
      [self setTitleFolder: nil inRect: NSZeroRect];
      return;
    }
  attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                               font, NSFontAttributeName,
                               GnomeThemeHeaderBarTextColor (window), NSForegroundColorAttributeName,
                               nil];
  title = [self fittedTitle: title attributes: attributes width: maxX - minX];
  size = [title sizeWithAttributes: attributes];

  /* Centred on the window, as GTK centres it, unless the buttons at one
     end are in the way. Vertically GTK centres the font's ascent and
     descent, not the line with its leading. */
  x = floor (NSMidX (bar) - size.width / 2.0);
  x = MAX (minX, MIN (x, maxX - size.width));
  baseline = NSMaxY (bar) - floor ((NSHeight (bar) - ([font ascender] - [font descender])) / 2.0 + [font ascender]);
  [title drawAtPoint: NSMakePoint (x, baseline + [font descender] - (size.height - ([font ascender] - [font descender])))
      withAttributes: attributes];
  [self setTitleFolder: folder inRect: NSMakeRect (x, NSMinY (bar), size.width, NSHeight (bar))];
}

- (void) drawRect: (NSRect)rect
{
  NSRect bounds = [self bounds];
  NSColor *background = [NSColor windowBackgroundColor];

  if (hasTitleBar && NSIntersectsRect (rect, titleBarRect))
    {
      [background set];
      NSRectFill (titleBarRect);
      [self drawTitleInRect: titleBarRect];
    }
  if (NSEqualRects (contentRect, bounds) == NO && _hasShadow)
    {
      /* The border area takes the window's background: the shadow's
         outline is the edge, as in libadwaita. */
      [background set];
      NSFrameRectWithWidth (bounds, GnomeThemeWindowBorderWidth);
    }
  else if (NSEqualRects (contentRect, bounds) == NO)
    {
      CGFloat shade = [GnomeThemeCurrentSettings () highContrastEnabled]
        ? GnomeThemeHighContrastBorderShade : GnomeThemeWindowBorderShade;

      [[background blendedColorWithFraction: shade ofColor: [NSColor controlTextColor]] set];
      NSFrameRectWithWidth (bounds, GnomeThemeWindowBorderWidth);
    }
  if (NSIntersectsRect (rect, contentRect))
    {
      /* As GSWindowDecorationView: the outermost view clears the content
         area in case the window's background isn't opaque. */
      NSRect fill = GnomeThemeRectOutwardToPixels (contentRect, [window userSpaceScaleFactor]);

      NSRectFillUsingOperation (fill, NSCompositeClear);
      [[GSTheme theme] drawWindowBackground: fill view: self];
    }
}

/* The backend window exists now: let the window manager move, maximise,
   minimise and close it. */
- (void) setWindowNumber: (int)number
{
  [super setWindowNumber: number];
  if (number > 0)
    {
      GnomeThemeWindowManagerAllowFunctions (window);
      [self updateShadow];
    }
}

- (void) setInputState: (int)state
{
  [super setInputState: state];
  /* The buttons dim with the title. */
  [closeButton setNeedsDisplay: YES];
  [miniaturizeButton setNeedsDisplay: YES];
  [_zoomButton setNeedsDisplay: YES];
  [_menuButton setNeedsDisplay: YES];
}

/* Maximised, as the window manager has it when it can tell (it maximises
   and tiles on its own: a drag to the top, Super+Up), otherwise as
   GNUstep's -isZoomed has it. */
- (BOOL) isMaximized
{
  BOOL known;
  BOOL maximized = GnomeThemeWindowManagerIsMaximized (window, &known);

  return known ? maximized : [window isZoomed];
}

/* Whether the backend draws the shadow, and the resize band it leaves
   outside each edge (the input shape takes presses there). */
- (void) updateShadow
{
  CGFloat extents[4];
  CGFloat factor = [window userSpaceScaleFactor];
  int i;

  _hasShadow = GnomeThemeWindowManagerShadowExtents (window, extents);
  for (i = 0; i < 4; i++)
    {
      _resizeBand[i] = MIN (GnomeThemeResizeBand, extents[i] / (factor > 0.0 ? factor : 1.0));
    }
}

- (BOOL) resizesOutside
{
  return _resizeBand[0] > 0.0 || _resizeBand[1] > 0.0 || _resizeBand[2] > 0.0 || _resizeBand[3] > 0.0;
}

/* Where the edges are: the bounds, or the bounds with the band outside. */
- (NSRect) resizeArea
{
  NSRect bounds = [self bounds];

  return NSMakeRect (NSMinX (bounds) - _resizeBand[0], NSMinY (bounds) - _resizeBand[3],
                     NSWidth (bounds) + _resizeBand[0] + _resizeBand[1],
                     NSHeight (bounds) + _resizeBand[2] + _resizeBand[3]);
}

/* Resizable from the edges: not while maximised or fullscreen. */
- (BOOL) resizable
{
  NSUInteger style = [window styleMask];

  return (style & NSResizableWindowMask) && (style & NSFullScreenWindowMask) == 0 && [self isMaximized] == NO;
}

/* The edges a point is on, for resizing. */
- (NSUInteger) resizeEdgesForPoint: (NSPoint)point
{
  /* An event's location is its pixel's top edge (the pixel row just
     below the window is at y 0): test the pixel's centre. */
  NSPoint p = NSMakePoint (point.x + 0.5, point.y - 0.5);
  NSRect bounds = [self bounds];
  NSRect area = [self resizeArea];
  BOOL outside = [self resizesOutside];
  CGFloat edge = outside ? 0.0 : GnomeThemeResizeEdge;
  BOOL left = p.x < NSMinX (bounds) + edge;
  BOOL right = p.x >= NSMaxX (bounds) - edge;
  BOOL bottom = p.y < NSMinY (bounds) + edge;
  BOOL top = p.y >= NSMaxY (bounds) - edge;
  NSUInteger edges = 0;

  /* With a shadow, presses inside the window are the content's. */
  if ([self resizable] == NO || NSPointInRect (p, area) == NO || (outside && NSPointInRect (p, bounds)))
    {
      return 0;
    }
  if (left || right)
    {
      edges |= left ? GnomeThemeResizeLeft : GnomeThemeResizeRight;
      if (p.y < NSMinY (area) + GnomeThemeResizeCorner)
        {
          edges |= GnomeThemeResizeBottom;
        }
      else if (p.y >= NSMaxY (area) - GnomeThemeResizeCorner)
        {
          edges |= GnomeThemeResizeTop;
        }
    }
  if (top || bottom)
    {
      edges |= bottom ? GnomeThemeResizeBottom : GnomeThemeResizeTop;
      if (p.x < NSMinX (area) + GnomeThemeResizeCorner)
        {
          edges |= GnomeThemeResizeLeft;
        }
      else if (p.x >= NSMaxX (area) - GnomeThemeResizeCorner)
        {
          edges |= GnomeThemeResizeRight;
        }
    }
  return edges;
}

/* The edges are over the content view's edge, or outside the bounds in
   the shadow: take clicks there before the content does. */
- (NSView *) hitTest: (NSPoint)point
{
  NSPoint p = [self convertPoint: point fromView: nil];

  if ([self resizeEdgesForPoint: p] != 0)
    {
      return self;
    }
  return [super hitTest: point];
}

- (void) resetCursorRects
{
  NSRect bounds = [self bounds];
  CGFloat edge = GnomeThemeResizeEdge;
  CGFloat corner = GnomeThemeResizeCorner;
  CGFloat minX = NSMinX (bounds), maxX = NSMaxX (bounds);
  CGFloat minY = NSMinY (bounds), maxY = NSMaxY (bounds);

  [super resetCursorRects];
  if ([self resizable] == NO)
    {
      return;
    }
  if ([self resizesOutside])
    {
      /* The band outside the edges; each corner is the band's two arms. */
      NSRect area = [self resizeArea];
      CGFloat l = _resizeBand[0], r = _resizeBand[1], t = _resizeBand[2], b = _resizeBand[3];
      CGFloat aMinX = NSMinX (area), aMaxX = NSMaxX (area), aMinY = NSMinY (area), aMaxY = NSMaxY (area);
      NSCursor *bottomLeft = GnomeThemeResizeCursor (GnomeThemeResizeLeft | GnomeThemeResizeBottom);
      NSCursor *bottomRight = GnomeThemeResizeCursor (GnomeThemeResizeRight | GnomeThemeResizeBottom);
      NSCursor *topLeft = GnomeThemeResizeCursor (GnomeThemeResizeLeft | GnomeThemeResizeTop);
      NSCursor *topRight = GnomeThemeResizeCursor (GnomeThemeResizeRight | GnomeThemeResizeTop);

      [self addCursorRect: NSMakeRect (aMinX, aMinY + corner, l, NSHeight (area) - 2.0 * corner)
                   cursor: GnomeThemeResizeCursor (GnomeThemeResizeLeft)];
      [self addCursorRect: NSMakeRect (maxX, aMinY + corner, r, NSHeight (area) - 2.0 * corner)
                   cursor: GnomeThemeResizeCursor (GnomeThemeResizeRight)];
      [self addCursorRect: NSMakeRect (aMinX + corner, aMinY, NSWidth (area) - 2.0 * corner, b)
                   cursor: GnomeThemeResizeCursor (GnomeThemeResizeBottom)];
      [self addCursorRect: NSMakeRect (aMinX + corner, maxY, NSWidth (area) - 2.0 * corner, t)
                   cursor: GnomeThemeResizeCursor (GnomeThemeResizeTop)];
      [self addCursorRect: NSMakeRect (aMinX, aMinY, l, corner) cursor: bottomLeft];
      [self addCursorRect: NSMakeRect (aMinX, aMinY, corner, b) cursor: bottomLeft];
      [self addCursorRect: NSMakeRect (maxX, aMinY, r, corner) cursor: bottomRight];
      [self addCursorRect: NSMakeRect (aMaxX - corner, aMinY, corner, b) cursor: bottomRight];
      [self addCursorRect: NSMakeRect (aMinX, aMaxY - corner, l, corner) cursor: topLeft];
      [self addCursorRect: NSMakeRect (aMinX, maxY, corner, t) cursor: topLeft];
      [self addCursorRect: NSMakeRect (maxX, aMaxY - corner, r, corner) cursor: topRight];
      [self addCursorRect: NSMakeRect (aMaxX - corner, maxY, corner, t) cursor: topRight];
      return;
    }
  [self addCursorRect: NSMakeRect (minX, minY + corner, edge, NSHeight (bounds) - 2.0 * corner)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeLeft)];
  [self addCursorRect: NSMakeRect (maxX - edge, minY + corner, edge, NSHeight (bounds) - 2.0 * corner)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeRight)];
  [self addCursorRect: NSMakeRect (minX + corner, minY, NSWidth (bounds) - 2.0 * corner, edge)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeBottom)];
  [self addCursorRect: NSMakeRect (minX + corner, maxY - edge, NSWidth (bounds) - 2.0 * corner, edge)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeTop)];
  [self addCursorRect: NSMakeRect (minX, minY, corner, corner)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeLeft | GnomeThemeResizeBottom)];
  [self addCursorRect: NSMakeRect (maxX - corner, minY, corner, corner)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeRight | GnomeThemeResizeBottom)];
  [self addCursorRect: NSMakeRect (minX, maxY - corner, corner, corner)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeLeft | GnomeThemeResizeTop)];
  [self addCursorRect: NSMakeRect (maxX - corner, maxY - corner, corner, corner)
               cursor: GnomeThemeResizeCursor (GnomeThemeResizeRight | GnomeThemeResizeTop)];
}

static NSRect
GnomeThemeResizedFrame(NSRect frame, NSUInteger edges, NSPoint delta, NSSize minSize, NSSize maxSize)
{
  NSRect result = frame;

  if (maxSize.width <= 0.0)
    {
      maxSize.width = 1e7;
    }
  if (maxSize.height <= 0.0)
    {
      maxSize.height = 1e7;
    }
  if (edges & GnomeThemeResizeLeft)
    {
      result.size.width = MAX (minSize.width, MIN (maxSize.width, NSWidth (frame) - delta.x));
      result.origin.x = NSMaxX (frame) - NSWidth (result);
    }
  else if (edges & GnomeThemeResizeRight)
    {
      result.size.width = MAX (minSize.width, MIN (maxSize.width, NSWidth (frame) + delta.x));
    }
  if (edges & GnomeThemeResizeBottom)
    {
      result.size.height = MAX (minSize.height, MIN (maxSize.height, NSHeight (frame) - delta.y));
      result.origin.y = NSMaxY (frame) - NSHeight (result);
    }
  else if (edges & GnomeThemeResizeTop)
    {
      result.size.height = MAX (minSize.height, MIN (maxSize.height, NSHeight (frame) + delta.y));
    }
  return result;
}

- (void) resizeWindowFromEdges: (NSUInteger)edges event: (NSEvent *)event
{
  NSUInteger mask = NSLeftMouseDraggedMask | NSLeftMouseUpMask;
  NSEvent *current = event;
  NSPoint start = [self mouseLocationOnScreenOutsideOfEventStream];
  NSRect frame = [window frame];
  NSSize minSize = [window minSize];
  NSSize maxSize = [window maxSize];
  NSCursor *cursor = GnomeThemeResizeCursor (edges);

  [cursor push];
  [window _captureMouse: nil];
  while (current != nil && [current type] != NSLeftMouseUp)
    {
      NSPoint point;

      /* Only the latest drag matters. */
      current = [window nextEventMatchingMask: mask
                                    untilDate: [NSDate distantFuture]
                                       inMode: NSEventTrackingRunLoopMode
                                      dequeue: YES];
      while ([current type] == NSLeftMouseDragged)
        {
          NSEvent *next = [window nextEventMatchingMask: mask
                                              untilDate: [NSDate distantPast]
                                                 inMode: NSEventTrackingRunLoopMode
                                                dequeue: YES];
          if (next == nil)
            {
              break;
            }
          current = next;
        }
      point = [self mouseLocationOnScreenOutsideOfEventStream];
      [window setFrame: GnomeThemeResizedFrame (frame, edges, NSMakePoint (point.x - start.x, point.y - start.y),
                                                minSize, maxSize)
               display: YES];
    }
  [window _releaseMouse: nil];
  [cursor pop];
}

/* Maximise, or go back to the frame the window had before. */
- (void) toggleMaximized: (id)sender
{
  /* The window manager maximises and restores, and knows the window is
     maximised (restore on drag, tiling). */
  if (GnomeThemeWindowManagerToggleMaximized (window))
    {
      return;
    }
  if ([window isZoomed] && _hasRestoreFrame)
    {
      _hasRestoreFrame = NO;
      [window setFrame: _restoreFrame display: YES];
    }
  else if ([window isZoomed] == NO)
    {
      _restoreFrame = [window frame];
      _hasRestoreFrame = YES;
      [window zoom: sender];
    }
  /* The maximise button shows restore, and resizing is off. */
  [self setNeedsDisplay: YES];
  [window invalidateCursorRectsForView: self];
}

- (void) toggleAlwaysOnTop: (id)sender
{
  [window setLevel: [window level] > NSNormalWindowLevel ? NSNormalWindowLevel : NSFloatingWindowLevel];
}

/* The window menu, with the entries of Mutter's that GNUstep can carry
   out. (Mutter's own needs the window manager: see
   Docs/PROPOSAL_LIBS_BACK_CSD.md.) */
- (NSMenu *) windowMenu
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @""]);
  NSUInteger style = [window styleMask];
  id <NSMenuItem> item;

  if (style & NSMiniaturizableWindowMask)
    {
      item = [menu addItemWithTitle: @"Hide" action: @selector(miniaturize:) keyEquivalent: @""];
      [item setTarget: window];
    }
  if (style & NSResizableWindowMask)
    {
      item = [menu addItemWithTitle: [self isMaximized] ? @"Restore" : @"Maximize"
                             action: @selector(toggleMaximized:)
                      keyEquivalent: @""];
      [item setTarget: self];
    }
  if ([menu numberOfItems] > 0)
    {
      [menu addItem: [NSMenuItem separatorItem]];
    }
  item = [menu addItemWithTitle: @"Always on Top" action: @selector(toggleAlwaysOnTop:) keyEquivalent: @""];
  [item setTarget: self];
  [item setState: [window level] > NSNormalWindowLevel ? NSOnState : NSOffState];
  if (style & NSClosableWindowMask)
    {
      [menu addItem: [NSMenuItem separatorItem]];
      item = [menu addItemWithTitle: @"Close" action: @selector(performClose:) keyEquivalent: @""];
      [item setTarget: window];
    }
  return menu;
}

/* The title bar actions GNOME's settings name: "toggle-maximize" (and its
   horizontal and vertical forms, which GNUstep can't do separately),
   "minimize", "lower", "menu" and "none". A menu opens when the press
   that asked for it is released (`release` is that button's up event), so
   that it stays open. */
- (void) performTitleBarAction: (NSString *)action release: (NSEventType)release
{
  NSUInteger style = [window styleMask];

  if ([action hasPrefix: @"toggle-maximize"] && (style & NSResizableWindowMask))
    {
      [self toggleMaximized: self];
    }
  else if ([action isEqualToString: @"minimize"] && (style & NSMiniaturizableWindowMask))
    {
      [window miniaturize: self];
    }
  else if ([action isEqualToString: @"lower"])
    {
      [window orderBack: self];
    }
  else if ([action isEqualToString: @"menu"] && GnomeThemeWindowManagerShowWindowMenu (window))
    {
      /* Mutter's window menu, shown on the press as GTK shows it. */
    }
  else if ([action isEqualToString: @"menu"])
    {
      NSUInteger mask = NSLeftMouseDraggedMask | NSRightMouseDraggedMask | NSOtherMouseDraggedMask
        | NSLeftMouseUpMask | NSRightMouseUpMask | NSOtherMouseUpMask;
      NSEvent *event;

      do
        {
          event = [window nextEventMatchingMask: mask
                                      untilDate: [NSDate distantFuture]
                                         inMode: NSEventTrackingRunLoopMode
                                        dequeue: YES];
        }
      while ([event type] != release);
      GnomeThemeTrackMenu ([self windowMenu], [NSEvent mouseLocation], NO);
    }
}

/* Right and middle clicks on the bar run GNOME's actions for them (the
   window menu and nothing, by default). */
- (void) rightMouseDown: (NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];

  if (hasTitleBar && NSPointInRect (p, titleBarRect) && [self resizeEdgesForPoint: p] == 0)
    {
      [self performTitleBarAction: [GnomeThemeCurrentSettings () titlebarRightClickAction] ?: @"menu"
                          release: NSRightMouseUp];
      return;
    }
  [super rightMouseDown: event];
}

- (void) otherMouseDown: (NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];

  if (hasTitleBar && NSPointInRect (p, titleBarRect) && [self resizeEdgesForPoint: p] == 0
    && [event buttonNumber] == 2)
    {
      [self performTitleBarAction: [GnomeThemeCurrentSettings () titlebarMiddleClickAction] ?: @"none"
                          release: NSOtherMouseUp];
      return;
    }
  [super otherMouseDown: event];
}

/* Waits until the pointer moves past GTK's drag threshold (YES: a move)
   or the button is released (NO: a click, which leaves a double-click
   to come). */
- (BOOL) pointerDraggedFrom: (NSEvent *)event
{
  return [self pointerDraggedFrom: event release: NULL];
}

/* As above, and hands back the release when there was one. */
- (BOOL) pointerDraggedFrom: (NSEvent *)event release: (NSEvent **)release
{
  NSPoint start = [event locationInWindow];
  NSEvent *current;

  while (YES)
    {
      current = [window nextEventMatchingMask: NSLeftMouseDraggedMask | NSLeftMouseUpMask
                                    untilDate: [NSDate distantFuture]
                                       inMode: NSEventTrackingRunLoopMode
                                      dequeue: YES];
      if ([current type] == NSLeftMouseUp)
        {
          if (release != NULL)
            {
              *release = current;
            }
          return NO;
        }
      if (fabs ([current locationInWindow].x - start.x) > GnomeThemeDragThreshold
        || fabs ([current locationInWindow].y - start.y) > GnomeThemeDragThreshold)
        {
          return YES;
        }
    }
}

- (void) mouseDown: (NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSUInteger edges = [self resizeEdgesForPoint: p];
  NSView *pressed = [self hitTest: [event locationInWindow]];

  if (edges != 0)
    {
      if (GnomeThemeWindowManagerMoveResize (window, GnomeThemeMoveResizeDirectionForEdges (edges)) == NO)
        {
          [self resizeWindowFromEdges: edges event: event];
        }
      return;
    }
  /* A press that a toolbar item's view passed on: a container, an empty
     part of the item, a view that acts only on the release. As a GTK
     header bar (a GtkWindowHandle round its children), a drag from it
     moves the window; a click gives its release back to the item, which
     libs-gui sends it to (plugins-themes-Adwaita#33, #36). Controls take
     their presses themselves and never get here. */
  if (pressed != self && [pressed isDescendantOf: [[window toolbar] _toolbarView]])
    {
      NSEvent *release = nil;

      if ([self pointerDraggedFrom: event release: &release])
        {
          if (GnomeThemeWindowManagerMoveResize (window, GnomeThemeMoveResizeMove) == NO)
            {
              [self moveWindowStartingWithEvent: event];
            }
        }
      else if (release != nil)
        {
          [NSApp postEvent: release atStart: YES];
        }
      return;
    }
  /* At the pixel's centre, as for the edges: the bar's top row too. */
  if (hasTitleBar && NSPointInRect (NSMakePoint (p.x + 0.5, p.y - 0.5), titleBarRect))
    {
      if ([event clickCount] == 2)
        {
          [self performTitleBarAction: [GnomeThemeCurrentSettings () titlebarDoubleClickAction] ?: @"toggle-maximize"
                              release: NSLeftMouseUp];
        }
      else if ([self pointerDraggedFrom: event])
        {
          /* The window manager moves the window: snapping, tiling, off
             the screen's edge, a drag to the top to maximise. */
          if (GnomeThemeWindowManagerMoveResize (window, GnomeThemeMoveResizeMove) == NO)
            {
              [self moveWindowStartingWithEvent: event];
            }
        }
      return;
    }
  [super mouseDown: event];
}

/* A press while the app waits for a modal dialog outside it: a drag from
   the bar's draggable parts moves the window; the bar's buttons, the
   edges, clicks and double-clicks do nothing (plugins-themes-Adwaita#43).
   NO when the press isn't the bar's to move with. */
- (BOOL) moveWindowFromModalPress: (NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSView *pressed;

  if (hasTitleBar == NO || NSPointInRect (NSMakePoint (p.x + 0.5, p.y - 0.5), titleBarRect) == NO
    || [self resizeEdgesForPoint: p] != 0)
    {
      return NO;
    }
  pressed = [self hitTest: [event locationInWindow]];
  if (pressed != self
    && ([pressed isDescendantOf: [[window toolbar] _toolbarView]] == NO || [pressed isKindOfClass: [NSControl class]]))
    {
      return NO;
    }
  if ([self pointerDraggedFrom: event]
    && GnomeThemeWindowManagerMoveResize (window, GnomeThemeMoveResizeMove) == NO)
    {
      [self moveWindowStartingWithEvent: event];
    }
  return YES;
}

@end

BOOL
GnomeThemeHeaderBarMoveWindowFromModalPress(NSEvent *event)
{
  NSView *frameView = [[[event window] contentView] superview];

  if ([event type] != NSLeftMouseDown || [frameView isKindOfClass: [GnomeThemeHeaderBarDecorationView class]] == NO)
    {
      return NO;
    }
  return [(GnomeThemeHeaderBarDecorationView *)frameView moveWindowFromModalPress: event];
}

/* The header bar toolbar setting may have changed (NSUserDefaults
   noticed): move shown toolbars into or out of the bar. */
void
GnomeThemeHeaderBarToolbarSettingChanged(void)
{
  static int enabled = -1;
  BOOL now = GnomeThemeHeaderBarToolbarEnabled ();
  NSEnumerator *enumerator;
  NSWindow *window;

  if (enabled == (int)now)
    {
      return;
    }
  enabled = now;
  enumerator = [[NSApp windows] objectEnumerator];
  while ((window = [enumerator nextObject]) != nil)
    {
      NSView *frameView = [[window contentView] superview];

      if ([frameView isKindOfClass: [GnomeThemeHeaderBarDecorationView class]])
        {
          [(GnomeThemeHeaderBarDecorationView *)frameView placeToolbarForSetting];
        }
    }
}

void
GnomeThemeHeaderBarDesktopSettingsChanged(void)
{
  NSEnumerator *enumerator = [[NSApp windows] objectEnumerator];
  NSWindow *window;

  while ((window = [enumerator nextObject]) != nil)
    {
      NSView *frameView = [[window contentView] superview];

      if ([frameView isKindOfClass: [GnomeThemeHeaderBarDecorationView class]])
        {
          [(GnomeThemeHeaderBarDecorationView *)frameView layoutWindowButtons];
          [frameView setNeedsDisplay: YES];
        }
    }
}

@implementation GnomeTheme (HeaderBar)

/* For apps: a toolbar's » menu takes items by visibilityPriority
   (GnomeThemeToolbarKeptItems), so an app needn't widen its window to keep
   its important items. Asked of [GSTheme theme], as WinUITheme answers it
   too; it goes with the theme when another is chosen. */
- (BOOL) toolbarHonoursVisibilityPriority
{
  return YES;
}

/* In the header bar the toolbar is part of the bar: no background or
   bottom line of its own (the bar's shows, with the title), and presses
   on its empty parts and spaces are the bar's (moves, double-click). */
- (void) _overrideGSToolbarViewMethod_drawRect: (NSRect)rect
{
  typedef void (*DrawIMP)(id, SEL, NSRect);
  DrawIMP originalIMP = (DrawIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSView *superview = [(NSView *)self superview];

  if ([superview respondsToSelector: @selector(holdsToolbarInBar)] && [superview holdsToolbarInBar])
    {
      return;
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, rect);
    }
}

- (BOOL) _overrideGSToolbarViewMethod_isOpaque
{
  typedef BOOL (*OpaqueIMP)(id, SEL);
  OpaqueIMP originalIMP = (OpaqueIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSView *superview = [(NSView *)self superview];

  if ([superview respondsToSelector: @selector(holdsToolbarInBar)] && [superview holdsToolbarInBar])
    {
      return NO;
    }
  return originalIMP != NULL ? originalIMP (self, _cmd) : NO;
}

/* libs-gui lays the toolbar out left to right at every reload; in the bar of
   a right-to-left window, as GTK mirrors its header bar, the items go from
   the right (those before the flexible space at the bar's start, now its
   right), and the » of the items that don't fit goes to the left. */
- (void) _overrideGSToolbarViewMethod__reload
{
  typedef void (*ReloadIMP)(id, SEL);
  ReloadIMP originalIMP = (ReloadIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSView *toolbarView = (NSView *)self;
  NSView *superview = [toolbarView superview];
  CGFloat width = NSWidth ([toolbarView frame]);
  NSEnumerator *enumerator;
  NSView *subview;

  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
  if (GnomeThemeUsesRightToLeft () == NO || [superview respondsToSelector: @selector(holdsToolbarInBar)] == NO
    || [superview holdsToolbarInBar] == NO)
    {
      return;
    }
  enumerator = [[toolbarView subviews] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      NSRect frame = [subview frame];

      if ([subview isKindOfClass: [NSClipView class]])
        {
          CGFloat clipWidth = NSWidth (frame);
          NSEnumerator *items = [[subview subviews] objectEnumerator];
          NSView *backView;

          frame.origin.x = width - clipWidth;
          [subview setFrame: frame];
          while ((backView = [items nextObject]) != nil)
            {
              NSRect itemFrame = [backView frame];

              itemFrame.origin.x = clipWidth - NSMaxX (itemFrame);
              [backView setFrame: itemFrame];
            }
        }
      else
        {
          frame.origin.x = 0.0;
          [subview setFrame: frame];
        }
    }
}

/* The width libs-gui counts for an item when it decides which items fit
   (-_visibleBackViews in GSToolbarView.m); a flexible space counts as
   `space`. */
static CGFloat
GnomeThemeToolbarItemCountedWidth(NSToolbarItem *item, CGFloat space)
{
  if ([item _isFlexibleSpace])
    {
      return space;
    }
  if ([item view] != nil)
    {
      return [item minSize].width + 2.0 * GnomeThemeToolbarItemViewInset;
    }
  return NSWidth ([[item _backView] frame]);
}

/* In the bar, the title is drawn in the toolbar's widest flexible space.
   libs-gui shrinks the flexible spaces to nothing before it moves items
   into the » menu, and the title went with them (ScreenshotTool's toolbar
   at 860pt). Around libs-gui's share-out of the flexible width
   (GnomeThemeControls.m's -_takeInAccountFlexibleSpaces): the first
   flexible space counts as GnomeThemeHeaderBarMinimumTitleWidth when
   libs-gui decides which items fit, so the items at the end go into the »
   menu first, and gets back the room left at the end afterwards. */
static NSToolbarItem *
GnomeThemeHeaderBarTitleSpace(NSView *toolbarView, NSUInteger *index)
{
  NSView *superview = [toolbarView superview];
  NSArray *items;
  NSUInteger i, n;

  if ([superview respondsToSelector: @selector(holdsToolbarInBar)] == NO || [superview holdsToolbarInBar] == NO)
    {
      return nil;
    }
  items = [[toolbarView toolbar] items];
  n = [items count];
  for (i = 0; i < n; i++)
    {
      if ([[items objectAtIndex: i] _isFlexibleSpace])
        {
          *index = i;
          return [items objectAtIndex: i];
        }
    }
  return nil;
}

/* Which items stay in the row when they don't all fit: libs-gui keeps the
   longest run from the start, so the » menu took the items at the end
   whatever their visibilityPriority. Items go by ascending priority
   instead, right to left within one, until the rest and the » fit; a run
   of separators and spaces goes with the item on its left (a leading run
   with the item on its right), and flexible spaces stay. The last item to
   go can leave room for some that went before it with the same priority:
   those come back, leftmost first (ScreenshotTool's Copy and Colour, which
   went before its wide Tools). When that order is right to left anyway
   (every item Standard) and nothing comes back, or every item has the
   same priority, the items kept are libs-gui's run, as it counts it:
   *fromEnd is then YES and nothing changes. The same rule as
   WinUITheme's. */
NSIndexSet *
GnomeThemeToolbarKeptItems(NSView *toolbarView, BOOL *fromEnd)
{
  NSUInteger titleIndex = NSNotFound;
  NSToolbarItem *titleSpace = GnomeThemeHeaderBarTitleSpace (toolbarView, &titleIndex);
  NSArray *items = [[toolbarView toolbar] items];
  NSUInteger i, j, n = [items count], kept = 0, candidates = 0, gone, returned = 0;
  NSMutableIndexSet *keep = [NSMutableIndexSet indexSet];
  NSMutableData *data = [NSMutableData dataWithLength: MAX (n, 1) * (sizeof (CGFloat) + 2 * sizeof (NSUInteger))];
  CGFloat *counted = [data mutableBytes];
  NSUInteger *owner = (NSUInteger *)(counted + MAX (n, 1));
  NSUInteger *order = owner + MAX (n, 1);
  CGFloat width = NSWidth ([toolbarView frame]), total = 0.0, sum = 0.0;
  NSInteger previous = NSIntegerMax, last;
  BOOL rightToLeft = YES, samePriority = YES;

  for (i = 0; i < n; i++)
    {
      NSToolbarItem *item = [items objectAtIndex: i];

      counted[i] = GnomeThemeToolbarItemCountedWidth (item, item == titleSpace
                                                      ? GnomeThemeHeaderBarMinimumTitleWidth : 0.0);
      total += counted[i];
      owner[i] = NSNotFound;
      if (GnomeThemeToolbarItemIsSpace (item) == NO)
        {
          NSInteger priority = [item visibilityPriority];

          rightToLeft = rightToLeft && priority <= previous;
          samePriority = samePriority && (previous == NSIntegerMax || priority == previous);
          previous = priority;
          owner[i] = i;
          /* The drop order: ascending priority, right to left within one. */
          for (j = candidates; j > 0
                 && [[items objectAtIndex: order[j - 1]] visibilityPriority] >= priority; j--)
            {
              order[j] = order[j - 1];
            }
          order[j] = i;
          candidates++;
        }
    }
  if (fromEnd != NULL)
    {
      *fromEnd = YES;
    }
  if (total <= width)
    {
      [keep addIndexesInRange: NSMakeRange (0, n)];
      return keep;
    }
  /* A separator or space belongs to the nearest item on its left that
     isn't a space, else (at the start, or after a flexible space) to the
     nearest on its right; a flexible space to none. */
  for (i = 0; i < n; i++)
    {
      NSToolbarItem *item = [items objectAtIndex: i];

      if (owner[i] != NSNotFound || [item _isFlexibleSpace])
        {
          continue;
        }
      for (j = i; j > 0 && owner[i] == NSNotFound; j--)
        {
          if ([[items objectAtIndex: j - 1] _isFlexibleSpace])
            {
              break;
            }
          if (GnomeThemeToolbarItemIsSpace ([items objectAtIndex: j - 1]) == NO)
            {
              owner[i] = j - 1;
            }
        }
      for (j = i + 1; j < n && owner[i] == NSNotFound; j++)
        {
          if ([[items objectAtIndex: j] _isFlexibleSpace])
            {
              break;
            }
          if (GnomeThemeToolbarItemIsSpace ([items objectAtIndex: j]) == NO)
            {
              owner[i] = j;
            }
        }
    }
  [keep addIndexesInRange: NSMakeRange (0, n)];
  sum = total;
  for (gone = 0; gone < candidates && sum + GnomeThemeToolbarClippedItemsWidth > width; gone++)
    {
      for (j = 0; j < n; j++)
        {
          if (owner[j] == order[gone])
            {
              [keep removeIndex: j];
              sum -= counted[j];
            }
        }
    }
  /* Those that went before the last with its priority, in the reverse
     order, come back where they fit; lower ones stay in the » menu, so no
     item is kept while one above it isn't. */
  last = gone > 0 ? [[items objectAtIndex: order[gone - 1]] visibilityPriority] : 0;
  for (i = gone > 0 ? gone - 1 : 0; i > 0
         && [[items objectAtIndex: order[i - 1]] visibilityPriority] == last; i--)
    {
      CGFloat group = 0.0;

      for (j = 0; j < n; j++)
        {
          group += owner[j] == order[i - 1] ? counted[j] : 0.0;
        }
      if (sum + group + GnomeThemeToolbarClippedItemsWidth <= width)
        {
          for (j = 0; j < n; j++)
            {
              if (owner[j] == order[i - 1])
                {
                  [keep addIndex: j];
                }
            }
          sum += group;
          returned++;
        }
    }
  if (rightToLeft && (returned == 0 || samePriority))
    {
      [keep removeAllIndexes];
      for (i = 0, sum = 0.0; i < n; i++)
        {
          sum += counted[i];
          if (sum + GnomeThemeToolbarClippedItemsWidth > width && (i < n - 1 || sum > width))
            {
              break;
            }
          kept = i + 1;
        }
      [keep addIndexesInRange: NSMakeRange (0, kept)];
      return keep;
    }
  if (fromEnd != NULL)
    {
      *fromEnd = NO;
    }
  return keep;
}

/* After libs-gui places the items, when the items kept aren't the run
   from the start: those go contiguously from the start, a view item at
   its minimum width and the theme's insets, the others are hidden (not
   left past the clip view's end), and the width left over is shared by
   the flexible spaces kept (else left at the end). In the header bar,
   GnomeThemeHeaderBarGiveTitleRoom places them again. */
void
GnomeThemeToolbarPlaceKeptItems(NSView *toolbarView)
{
  NSArray *items = [[toolbarView toolbar] items];
  BOOL fromEnd = YES;
  NSIndexSet *keep = GnomeThemeToolbarKeptItems (toolbarView, &fromEnd);
  NSUInteger i, n = [items count], flexible = 0;
  CGFloat left = NSWidth ([toolbarView frame]) - GnomeThemeToolbarClippedItemsWidth, x = 0.0;

  for (i = 0; i < n; i++)
    {
      NSToolbarItem *item = [items objectAtIndex: i];

      [[item _backView] setHidden: (fromEnd == NO && [keep containsIndex: i] == NO)];
      if (fromEnd == NO && [keep containsIndex: i])
        {
          left -= [item view] != nil ? [item minSize].width + 2.0 * GnomeThemeToolbarItemSpacing
            : GnomeThemeToolbarItemCountedWidth (item, 0.0);
          flexible += [item _isFlexibleSpace] ? 1 : 0;
        }
    }
  if (fromEnd)
    {
      return;
    }
  left = MAX (0.0, left);
  for (i = 0; i < n; i++)
    {
      NSToolbarItem *item = [items objectAtIndex: i];
      NSView *backView = [item _backView];
      NSRect frame = [backView frame];

      if ([keep containsIndex: i] == NO)
        {
          continue;
        }
      frame.origin.x = x;
      if ([item _isFlexibleSpace])
        {
          frame.size.width = floor (left / flexible);
        }
      else if ([item view] != nil)
        {
          frame.size.width = [item minSize].width + 2.0 * GnomeThemeToolbarItemSpacing;
        }
      [backView setFrame: frame];
      x += NSWidth (frame);
    }
}

void
GnomeThemeHeaderBarReserveTitleRoom(NSView *toolbarView)
{
  NSUInteger index;
  NSToolbarItem *space = GnomeThemeHeaderBarTitleSpace (toolbarView, &index);
  NSView *backView = [space _backView];
  NSRect frame;

  if (space == nil)
    {
      return;
    }
  frame = [backView frame];
  frame.size.width = GnomeThemeHeaderBarMinimumTitleWidth;
  [backView setFrame: frame];
}

void
GnomeThemeHeaderBarGiveTitleRoom(NSView *toolbarView)
{
  NSUInteger titleIndex = 0;
  NSToolbarItem *titleSpace = GnomeThemeHeaderBarTitleSpace (toolbarView, &titleIndex);
  NSArray *items = [[toolbarView toolbar] items];
  NSToolbarItem *item;
  NSView *backView;
  CGFloat width = NSWidth ([toolbarView frame]);
  CGFloat others = 0.0, trailing = 0.0, end, x = 0.0;
  NSUInteger i, n = [items count];
  NSIndexSet *keep;
  BOOL fromEnd = YES, placedTrailing = NO;

  if (titleSpace == nil)
    {
      return;
    }
  /* The items kept (GnomeThemeToolbarKeptItems), as libs-gui counts them:
     the others as it counts them again afterwards (-_visibleBackViews),
     and the width the kept ones after the title take. An item with a
     view counts with libs-gui's insets, wider than the theme lays it out
     (-_takeInAccountFlexibleSpaces in GnomeThemeControls.m); giving the
     title what they really leave pushed the last item into the » menu at
     any width (ScreenshotTool's Copy). */
  keep = GnomeThemeToolbarKeptItems (toolbarView, &fromEnd);
  if ([keep containsIndex: titleIndex] == NO)
    {
      return;
    }
  for (i = 0; i < n; i++)
    {
      item = [items objectAtIndex: i];
      if ([keep containsIndex: i] == NO)
        {
          continue;
        }
      if (item != titleSpace)
        {
          others += GnomeThemeToolbarItemCountedWidth (item, 0.0);
        }
      if (i > titleIndex)
        {
          trailing += NSWidth ([[item _backView] frame]);
        }
    }
  /* The title's space takes what libs-gui will count as left; the items
     before it follow one another from the start, those after it end at
     the end (libs-gui leaves items where they were when no width is left
     to share out). Hidden items keep no place. */
  end = [keep count] < n ? width - GnomeThemeToolbarClippedItemsWidth : width;
  for (i = 0; i < n; i++)
    {
      NSRect frame;

      if (fromEnd == NO && [keep containsIndex: i] == NO)
        {
          continue;
        }
      backView = [[items objectAtIndex: i] _backView];
      frame = [backView frame];
      if (i > titleIndex && placedTrailing == NO)
        {
          x = MAX (x, end - trailing);
          placedTrailing = YES;
        }
      frame.origin.x = x;
      if (i == titleIndex)
        {
          frame.size.width = MAX (0.0, floor (end - others));
        }
      [backView setFrame: frame];
      x += NSWidth (frame);
    }
}

- (NSView *) _overrideGSToolbarViewMethod_hitTest: (NSPoint)point
{
  typedef NSView *(*HitIMP)(id, SEL, NSPoint);
  HitIMP originalIMP = (HitIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSToolbarView"));
  NSView *toolbarView = (NSView *)self;
  NSView *superview = [toolbarView superview];
  NSView *hit = originalIMP != NULL ? originalIMP (self, _cmd, point) : nil;

  if ([superview respondsToSelector: @selector(holdsToolbarInBar)] == NO || [superview holdsToolbarInBar] == NO)
    {
      return hit;
    }
  /* The toolbar view and its clip view are background; so are spaces, and
     labels (a text field that can be neither edited nor selected), which
     would otherwise take the press and never drag. */
  if (hit == toolbarView || [hit isKindOfClass: [NSClipView class]]
    || ([hit respondsToSelector: @selector(toolbarItem)] && GnomeThemeToolbarItemIsSpace ([hit toolbarItem]))
    || ([hit isKindOfClass: [NSTextField class]] && [(NSTextField *)hit isEditable] == NO
        && [(NSTextField *)hit isSelectable] == NO))
    {
      return nil;
    }
  return hit;
}

/* Alerts have no header bar, as AdwAlertDialog, whether shown alone or as
   a sheet: GSAlertPanel's title bar becomes a border. An NSPanel can
   become key without a title bar, so Return and Escape still work. */
- (id) _overrideGSAlertPanelMethod_initWithContentRect: (NSRect)contentRect
                                             styleMask: (NSUInteger)style
                                               backing: (NSBackingStoreType)backing
                                                 defer: (BOOL)flag
{
  typedef id (*InitIMP)(id, SEL, NSRect, NSUInteger, NSBackingStoreType, BOOL);
  InitIMP originalIMP = (InitIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSAlertPanel"));

  if (GnomeThemeUsesHeaderBar () && (style & NSTitledWindowMask))
    {
      style = (style & ~(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask))
        | NSDocModalWindowMask;
    }
  return originalIMP != NULL ? originalIMP (self, _cmd, contentRect, style, backing, flag) : self;
}

- (id<GSWindowDecorator>) windowDecorator
{
  if (GnomeThemeUsesHeaderBar ())
    {
      return [GnomeThemeHeaderBarDecorationView self];
    }
  return [super windowDecorator];
}

- (NSButton *) standardWindowButton: (NSWindowButton)button
                       forStyleMask: (NSUInteger)mask
{
  NSButton *newButton;

  if (GnomeThemeUsesHeaderBar () == NO
    || (button != NSWindowCloseButton && button != NSWindowMiniaturizeButton && button != NSWindowZoomButton))
    {
      return [super standardWindowButton: button forStyleMask: mask];
    }
  newButton = AUTORELEASE ([[GnomeThemeWindowButton alloc] initWithFrame: NSZeroRect]);
  [newButton setRefusesFirstResponder: YES];
  [newButton setButtonType: NSMomentaryChangeButton];
  [newButton setBordered: NO];
  [newButton setTag: button];
  switch (button)
    {
      case NSWindowCloseButton:
        [newButton setAction: @selector(performClose:)];
        [newButton setToolTip: @"Close"];
        break;
      case NSWindowMiniaturizeButton:
        [newButton setAction: @selector(miniaturize:)];
        [newButton setToolTip: @"Minimize"];
        break;
      default:
        [newButton setAction: @selector(zoom:)];
        [newButton setToolTip: @"Maximize"];
        break;
    }
  return newButton;
}

@end
