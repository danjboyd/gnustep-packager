/* -displayIfNeeded draws a still-dirty opaque subview again after, and
 * over, a sibling drawn above it.
 *
 * An opaque parent (grey) holds an opaque "document" view (white, the
 * whole parent) and a non-opaque "strip" (red) over the document's right
 * edge, stopping 20 points short of the bottom, as an NSScrollView's
 * vertical scroller stops short of the horizontal one's strip.  Both are
 * marked dirty, as a scroll with copiesOnScroll NO and a scroller redraw
 * mark them: the document its whole bounds (it is opaque, so the rect
 * stays with it), the strip its bounds (passed up to the parent).  After
 * -displayIfNeeded the strip must be on top: its pixels red.
 *
 * Build: clang `gnustep-config --objc-flags` display_order.m \
 *          `gnustep-config --gui-libs` -o display_order
 * Run:   ./display_order -GSTheme GNUstep
 */

#import <AppKit/AppKit.h>
#include <stdio.h>

static NSMutableString *order = nil;

@interface FillView : NSView
{
  NSColor *color;
  NSString *label;
  BOOL opaque;
}
- (id) initWithFrame: (NSRect)frame
               color: (NSColor *)aColor
               label: (NSString *)aLabel
              opaque: (BOOL)flag;
@end

@implementation FillView
- (id) initWithFrame: (NSRect)frame
               color: (NSColor *)aColor
               label: (NSString *)aLabel
              opaque: (BOOL)flag
{
  if ((self = [super initWithFrame: frame]) != nil)
    {
      color = [aColor retain];
      label = [aLabel copy];
      opaque = flag;
    }
  return self;
}

- (void) dealloc
{
  [color release];
  [label release];
  [super dealloc];
}

- (BOOL) isOpaque
{
  return opaque;
}

- (void) drawRect: (NSRect)rect
{
  [order appendFormat: @" %@%@", label, NSStringFromRect (rect)];
  [color set];
  NSRectFill (rect);
}
@end

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSWindow *window;
  FillView *parent, *document, *strip;
  NSBitmapImageRep *rep;
  NSColor *pixel;
  BOOL red;

  [NSApplication sharedApplication];
  window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 200, 200)
                                       styleMask: NSTitledWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  parent = [[FillView alloc] initWithFrame: NSMakeRect (0, 0, 200, 200)
                                     color: [NSColor grayColor]
                                     label: @"parent"
                                    opaque: YES];
  document = [[FillView alloc] initWithFrame: NSMakeRect (0, 0, 200, 200)
                                       color: [NSColor whiteColor]
                                       label: @"document"
                                      opaque: YES];
  strip = [[FillView alloc] initWithFrame: NSMakeRect (180, 20, 20, 180)
                                    color: [NSColor redColor]
                                    label: @"strip"
                                   opaque: NO];
  [parent addSubview: document];
  [parent addSubview: strip];
  [[window contentView] addSubview: parent];
  [window orderFront: nil];
  [window display];

  /* As a scroll step and the scroller's redraw mark them. */
  [document setNeedsDisplay: YES];
  [strip setNeedsDisplay: YES];
  order = [NSMutableString new];
  [window displayIfNeeded];
  printf ("drawn:%s\n", [order UTF8String]);

  /* The strip's pixels, from the window's backing store. */
  [parent lockFocus];
  rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect: NSMakeRect (185, 100, 1, 1)];
  [parent unlockFocus];
  pixel = [rep colorAtX: 0 y: 0];
  red = [pixel redComponent] > 0.9 && [pixel greenComponent] < 0.1;
  printf ("strip pixel: r %.2f g %.2f b %.2f  %s\n", [pixel redComponent],
          [pixel greenComponent], [pixel blueComponent],
          red ? "PASS (the strip is on top)" : "FAIL (the document was drawn over the strip)");

  [rep release];
  [order release];
  [pool release];
  return red ? 0 : 1;
}
