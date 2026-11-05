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

/* Template images tinted with the foreground colour, as GTK tints symbolic
   icons: an app ships one monochrome icon set and it reads right in light,
   dark and high contrast, in the header bar's backdrop state, on a
   suggested (blue) button and in menus. Only the image's alpha is used.

   An image is a template when -[NSImage isTemplate] says so (libs-gui
   after 0.32), or by its name: Cocoa's "…Template" or GNOME's
   "…-symbolic", for libs-gui 0.32, which has no -setTemplate:. Buttons,
   toolbar items and menu items all draw their image through
   -[NSButtonCell drawImage:withFrame:inView:]. */

#import "../GnomeTheme.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface NSImage (GnomeThemeSymbolicImages)
- (BOOL) isTemplate;
@end

static char GnomeThemeTintedImagesKey;

/* GNUstep images the theme replaces with GNOME symbolic icons, under
   their GNUstep names (Resources/ThemeImages): drawn as templates, in the
   text colour. GNUstep's own Open and Save panels' buttons: Home
   (user-home), Mount (drive-removable-media), Unmount (media-eject). */
static NSSet *
GnomeThemeSymbolicReplacements(void)
{
  static NSSet *names = nil;

  if (names == nil)
    {
      names = [[NSSet alloc] initWithObjects: @"common_Home", @"common_Mount", @"common_Unmount", nil];
    }
  return names;
}

BOOL
GnomeThemeImageIsTemplate(NSImage *image)
{
  NSString *name;

  if (image == nil)
    {
      return NO;
    }
  if ([image respondsToSelector: @selector(isTemplate)] && [image isTemplate])
    {
      return YES;
    }
  name = [image name];
  /* libs-gui's » for a toolbar's overflow is black on clear, a shape
     like a symbolic icon's: in the text colour, it shows on the dark
     style's header bar and toolbars (#83). */
  return [name hasSuffix: @"Template"] || [name hasSuffix: @"-symbolic"]
    || [name isEqualToString: @"common_ToolbarClippedItemsMark"]
    || [GnomeThemeSymbolicReplacements () containsObject: name];
}

/* A bitmap's shape in `rgb`: the same pixels and size, each pixel the
   colour at the source pixel's alpha (times the colour's). */
static NSBitmapImageRep *
GnomeThemeTintedBitmap(NSBitmapImageRep *source, NSColor *rgb)
{
  NSInteger width = [source pixelsWide];
  NSInteger height = [source pixelsHigh];
  NSInteger samples = [source samplesPerPixel];
  NSInteger bits = [source bitsPerSample];
  NSUInteger maxValue = (bits >= 16) ? 65535 : ((1u << bits) - 1);
  BOOL hasAlpha = [source hasAlpha];
  NSInteger alphaIndex = hasAlpha
    ? ((([source bitmapFormat] & NSAlphaFirstBitmapFormat) != 0) ? 0 : samples - 1) : -1;
  CGFloat red = [rgb redComponent], green = [rgb greenComponent], blue = [rgb blueComponent];
  CGFloat alpha = [rgb alphaComponent];
  NSBitmapImageRep *result;
  unsigned char *data;
  NSInteger bytesPerRow, x, y;
  NSUInteger pixel[5];

  if (width <= 0 || height <= 0 || samples < 1 || samples > 5 || bits < 1 || bits > 16)
    {
      return nil;
    }
  result = AUTORELEASE ([[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                pixelsWide: width
                                                                pixelsHigh: height
                                                             bitsPerSample: 8
                                                           samplesPerPixel: 4
                                                                  hasAlpha: YES
                                                                  isPlanar: NO
                                                            colorSpaceName: NSCalibratedRGBColorSpace
                                                               bytesPerRow: 0
                                                              bitsPerPixel: 0]);
  data = [result bitmapData];
  bytesPerRow = [result bytesPerRow];
  if (data == NULL)
    {
      return nil;
    }
  for (y = 0; y < height; y++)
    {
      unsigned char *row = data + y * bytesPerRow;

      for (x = 0; x < width; x++)
        {
          CGFloat a = 1.0;

          if (alphaIndex >= 0)
            {
              [source getPixel: pixel atX: x y: y];
              a = (CGFloat)pixel[alphaIndex] / (CGFloat)maxValue;
            }
          a *= alpha;
          /* Premultiplied, NSBitmapImageRep's default. */
          row[x * 4] = (unsigned char)floor (red * a * 255.0 + 0.5);
          row[x * 4 + 1] = (unsigned char)floor (green * a * 255.0 + 0.5);
          row[x * 4 + 2] = (unsigned char)floor (blue * a * 255.0 + 0.5);
          row[x * 4 + 3] = (unsigned char)floor (a * 255.0 + 0.5);
        }
    }
  [result setSize: [source size]];
  return result;
}

/* An image made only of bitmaps, tinted one by one, so it keeps each of
   them: drawn at 24pt, an icon with 24 and 32pt bitmaps still draws its
   24pt one, not the 32pt one scaled down (#68). libs-gui's caches of
   drawn bitmaps (NSCachedImageRep) are left out. Nil when the image has
   any other kind of representation (PDF, EPS, drawn into). */
static NSImage *
GnomeThemeTintedBitmapImage(NSImage *image, NSColor *rgb)
{
  NSEnumerator *enumerator = [[image representations] objectEnumerator];
  NSMutableArray *bitmaps = [NSMutableArray array];
  NSImageRep *rep;
  NSImage *result;

  while ((rep = [enumerator nextObject]) != nil)
    {
      if ([rep isKindOfClass: [NSBitmapImageRep class]])
        {
          [bitmaps addObject: rep];
        }
      else if ([rep isKindOfClass: [NSCachedImageRep class]] == NO)
        {
          return nil;
        }
    }
  if ([bitmaps count] == 0)
    {
      return nil;
    }
  result = AUTORELEASE ([[NSImage alloc] initWithSize: [image size]]);
  enumerator = [bitmaps objectEnumerator];
  while ((rep = [enumerator nextObject]) != nil)
    {
      NSBitmapImageRep *tinted = GnomeThemeTintedBitmap ((NSBitmapImageRep *)rep, rgb);

      if (tinted == nil)
        {
          return nil;
        }
      [result addRepresentation: tinted];
    }
  return result;
}

/* The image's shape in `color`, kept with the image for each colour it's
   drawn in (a few: the states of the palette in use). Bitmaps are tinted
   each at its own size; other images are drawn once, at the image's size,
   and filled. */
NSImage *
GnomeThemeTintedImage(NSImage *image, NSColor *color)
{
  NSMutableDictionary *tinted = objc_getAssociatedObject (image, &GnomeThemeTintedImagesKey);
  NSColor *rgb = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSString *key;
  NSImage *result;
  NSSize size = [image size];
  NSRect rect = NSMakeRect (0.0, 0.0, size.width, size.height);

  if (rgb == nil || size.width <= 0.0 || size.height <= 0.0)
    {
      return image;
    }
  key = [NSString stringWithFormat: @"%.4f %.4f %.4f %.4f", [rgb redComponent], [rgb greenComponent],
                  [rgb blueComponent], [rgb alphaComponent]];
  result = [tinted objectForKey: key];
  if (result != nil)
    {
      return result;
    }
  if (tinted == nil)
    {
      tinted = [NSMutableDictionary dictionary];
      objc_setAssociatedObject (image, &GnomeThemeTintedImagesKey, tinted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  result = GnomeThemeTintedBitmapImage (image, rgb);
  if (result == nil)
    {
      result = AUTORELEASE ([[NSImage alloc] initWithSize: size]);
      [result lockFocus];
      [image drawInRect: rect fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0];
      [rgb set];
      NSRectFillUsingOperation (rect, NSCompositeSourceIn);
      [result unlockFocus];
    }
  [tinted setObject: result forKey: key];
  return result;
}

/* Whether the control is in a toolbar shown in the header bar. */
static BOOL
GnomeThemeViewIsInHeaderBarToolbar(NSView *controlView)
{
  NSView *view;

  for (view = controlView; view != nil; view = [view superview])
    {
      if ([view respondsToSelector: @selector(toolbar)] && [view isKindOfClass: [NSControl class]] == NO)
        {
          NSToolbar *toolbar = [(id)view toolbar];

          return [toolbar isKindOfClass: [NSToolbar class]] && GnomeThemeToolbarInHeaderBar (toolbar);
        }
    }
  return NO;
}

/* A template image's colour in a control: the header bar's for one in a
   toolbar in the bar (dimmed in the backdrop state), the disabled text
   colour when `dimmed`, else `text`. For buttons and segmented controls. */
NSColor *
GnomeThemeTemplateImageColorInView(NSView *controlView, BOOL dimmed, NSColor *text)
{
  if (GnomeThemeViewIsInHeaderBarToolbar (controlView))
    {
      NSColor *color = GnomeThemeHeaderBarTextColor ([controlView window]);

      return dimmed ? [color colorWithAlphaComponent: [color alphaComponent] * 0.5] : color;
    }
  if (dimmed)
    {
      return [NSColor disabledControlTextColor];
    }
  return text != nil ? text : [NSColor controlTextColor];
}

@implementation GnomeTheme (SymbolicImages)

/* The colour the cell's title is drawn in: the header bar's for its
   toolbar items (dimmed in the backdrop state), white on a suggested
   button, the menu's text colour in menus. */
static NSColor *
GnomeThemeTemplateImageColor(NSButtonCell *cell, NSView *controlView)
{
  BOOL enabled = [cell isEnabled];
  /* A cell that dims its image itself (libs-gui draws it at half
     opacity) gets the enabled colour. */
  BOOL dimmed = enabled == NO && [cell imageDimsWhenDisabled] == NO;
  NSString *keyEquivalent = [cell keyEquivalent];

  if ([cell isKindOfClass: [NSMenuItemCell class]])
    {
      if (dimmed)
        {
          return [NSColor disabledControlTextColor];
        }
      /* Only the menu bar's accent pill has white content; a vertical
         menu's hovered row is neutral (#67). */
      return ([cell isHighlighted] && [[(NSMenuItemCell *)cell menuView] isHorizontal])
        ? [NSColor selectedMenuItemTextColor] : [NSColor controlTextColor];
    }
  /* White on an accent button's blue, in the header bar too; half
     opacity disabled. */
  if (GnomeThemeButtonCellHasAccentStyle (cell))
    {
      return dimmed ? [[NSColor selectedControlTextColor] colorWithAlphaComponent: 0.5]
        : [NSColor selectedControlTextColor];
    }
  if (dimmed || GnomeThemeViewIsInHeaderBarToolbar (controlView))
    {
      return GnomeThemeTemplateImageColorInView (controlView, dimmed, nil);
    }
  if (enabled && ([keyEquivalent isEqualToString: @"\r"] || [keyEquivalent isEqualToString: @"\n"]
                  || (controlView != nil && [[controlView window] defaultButtonCell] == cell))
      && GnomeThemeWindowHasAccentButton ([controlView window]) == NO)
    {
      return [NSColor selectedControlTextColor];
    }
  return [NSColor controlTextColor];
}

- (void) _overrideNSButtonCellMethod_drawImage: (NSImage *)image
                                     withFrame: (NSRect)frame
                                        inView: (NSView *)controlView
{
  typedef void (*DrawImageIMP)(id, SEL, NSImage *, NSRect, NSView *);
  DrawImageIMP originalIMP = (DrawImageIMP)GnomeThemeOriginalMethod (_cmd, self, [NSButtonCell class]);

  if (GnomeThemeImageIsTemplate (image))
    {
      image = GnomeThemeTintedImage (image, GnomeThemeTemplateImageColor ((NSButtonCell *)self, controlView));
    }
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd, image, frame, controlView);
    }
}

@end
