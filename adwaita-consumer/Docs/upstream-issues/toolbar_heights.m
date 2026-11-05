/* Toolbar heights in libs-gui: an icon-only toolbar whose items are an
 * image and a 34pt button, and the same items in icon-and-label mode with
 * empty labels. Prints the toolbar view's height, whether the button view
 * is shown, and the image item's image size.
 *
 * Build: clang `gnustep-config --objc-flags` toolbar_heights.m \
 *          `gnustep-config --gui-libs` -o toolbar_heights
 * Run:   ./toolbar_heights -GSTheme GNUstep
 */

#import <AppKit/AppKit.h>

@interface Tester : NSObject
@end

@implementation Tester

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
  BOOL emptyLabels = [[toolbar identifier] hasSuffix: @"Empty"];

  [item setLabel: emptyLabels ? @"" : identifier];
  if ([identifier isEqualToString: @"Image"])
    {
      NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize (16, 16)] autorelease];

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
      NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect (0, 0, 34, 34)] autorelease];

      [button setTitle: @"B"];
      [item setView: button];
      [item setMinSize: NSMakeSize (34, 34)];
      [item setMaxSize: NSMakeSize (34, 34)];
    }
  return item;
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects: @"Image", @"Button", nil];
}

- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{
  return [self toolbarAllowedItemIdentifiers: toolbar];
}

- (void) measure: (NSString *)identifier mode: (NSToolbarDisplayMode)mode name: (NSString *)name
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 300, 100)
                                                 styleMask: NSTitledWindowMask
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
  NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier: identifier] autorelease];
  NSView *frameView, *buttonView;
  NSRect contentFrame;

  [toolbar setDelegate: self];
  [toolbar setDisplayMode: mode];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  [window display];
  frameView = [[window contentView] superview];
  contentFrame = [[window contentView] frame];
  buttonView = [[[toolbar items] lastObject] view];
  /* The toolbar sits between the content view and the top of the frame
     view (no title bar is drawn by GNUstep here). */
  printf ("%s: toolbar %g pt high, 34pt button view %s, image item's image %gx%g\n",
          [name UTF8String], NSHeight ([frameView bounds]) - NSMaxY (contentFrame),
          [buttonView window] == window ? "shown" : "removed",
          [[[[toolbar items] objectAtIndex: 0] image] size].width,
          [[[[toolbar items] objectAtIndex: 0] image] size].height);
  [window orderOut: nil];
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  [self measure: @"IconOnly" mode: NSToolbarDisplayModeIconOnly name: @"icon only"];
  [self measure: @"LabelsEmpty" mode: NSToolbarDisplayModeIconAndLabel name: @"icon and label, empty labels"];
  [NSApp terminate: nil];
}

@end

int
main (int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  [NSApplication sharedApplication];
  [NSApp setDelegate: [Tester new]];
  [NSApp run];
  [pool release];
  return 0;
}
