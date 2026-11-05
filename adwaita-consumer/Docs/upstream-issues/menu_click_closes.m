/* A click (press and release) on a menu bar title should leave its menu
   open; since libs-gui 0.32 the release closes it.

   Build as a GNUstep app (APP_NAME = MenuClick) and run with
   -NSMenuInterfaceStyle NSWindows95InterfaceStyle -GSTheme GNUstep.
   The click goes through the event queue, but menu tracking follows the
   real pointer, so the program moves the pointer onto the title: run it
   on a spare display (Xvfb :1) rather than a desktop in use. */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>

static BOOL checked = NO;
static BOOL openAfterRelease = NO;

@interface Tester : NSObject
{
  NSWindow *window;
}
@end

@implementation Tester

- (void) applicationDidFinishLaunching: (NSNotification *)n
{
  NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
  NSMenu *file = [[NSMenu alloc] initWithTitle: @"File"];
  NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle: @"File" action: NULL keyEquivalent: @""];

  [file addItemWithTitle: @"Open" action: NULL keyEquivalent: @""];
  [fileItem setSubmenu: file];
  [main addItem: fileItem];
  [NSApp setMainMenu: main];

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 400, 200)
                                       styleMask: NSTitledWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  [window setMenu: main];
  [window makeKeyAndOrderFront: nil];
  [self performSelector: @selector(click) withObject: nil afterDelay: 1.0];
}

/* While tracking: is the File menu showing? Then close it with a click
   outside. */
- (void) inspect: (NSTimer *)timer
{
  NSEnumerator *e = [[NSApp windows] objectEnumerator];
  NSWindow *w;
  NSEvent *down, *up;

  checked = YES;
  while ((w = [e nextObject]) != nil)
    {
      NSView *content = [w contentView];

      /* A menu's window holds its NSMenuView as the content view or in
         it. */
      if (w != window && [w isVisible]
        && ([content isKindOfClass: [NSMenuView class]]
            || ([[content subviews] count] > 0
                && [[[content subviews] objectAtIndex: 0] isKindOfClass: [NSMenuView class]])))
        {
          openAfterRelease = YES;
        }
    }
  down = [NSEvent mouseEventWithType: NSLeftMouseDown location: NSMakePoint (-50, -50) modifierFlags: 0
                           timestamp: 0 windowNumber: 0 context: nil eventNumber: 0 clickCount: 1 pressure: 1];
  up = [NSEvent mouseEventWithType: NSLeftMouseUp location: NSMakePoint (-50, -50) modifierFlags: 0
                         timestamp: 0 windowNumber: 0 context: nil eventNumber: 0 clickCount: 1 pressure: 0];
  [NSApp postEvent: down atStart: NO];
  [NSApp postEvent: up atStart: NO];
}

- (NSMenuView *) menuBarIn: (NSView *)view
{
  NSEnumerator *e = [[view subviews] objectEnumerator];
  NSView *v;

  if ([view isKindOfClass: [NSMenuView class]] && [(NSMenuView *)view isHorizontal])
    {
      return (NSMenuView *)view;
    }
  while ((v = [e nextObject]) != nil)
    {
      NSMenuView *found = [self menuBarIn: v];

      if (found != nil)
        {
          return found;
        }
    }
  return nil;
}

- (void) click
{
  NSMenuView *bar = [self menuBarIn: [[window contentView] superview]];
  NSRect title = [bar convertRect: [bar rectOfItemAtIndex: 0] toView: nil];
  NSPoint p = NSMakePoint (NSMidX (title), NSMidY (title));
  NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: p modifierFlags: 0
                                    timestamp: 0 windowNumber: [window windowNumber] context: nil
                                  eventNumber: 0 clickCount: 1 pressure: 1];
  NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: p modifierFlags: 0
                                  timestamp: 0 windowNumber: [window windowNumber] context: nil
                                eventNumber: 0 clickCount: 1 pressure: 0];

  if (bar == nil)
    {
      printf ("no menu bar in the window (run with -NSMenuInterfaceStyle NSWindows95InterfaceStyle)\n");
      [NSApp terminate: nil];
      return;
    }
  [GSCurrentServer () setMouseLocation: [window convertBaseToScreen: p]
                               onScreen: [[window screen] screenNumber]];
  /* The click's release is already queued when tracking starts. */
  [NSApp postEvent: up atStart: NO];
  [[NSRunLoop currentRunLoop] addTimer: [NSTimer timerWithTimeInterval: 0.3 target: self
                                                              selector: @selector(inspect:)
                                                              userInfo: nil repeats: NO]
                               forMode: NSEventTrackingRunLoopMode];
  [bar mouseDown: down];

  printf ("after a click on \"File\": menu %s\n",
          openAfterRelease ? "still open 0.3s later"
          : (checked ? "closed" : "closed on the release (tracking had ended before 0.3s)"));
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
