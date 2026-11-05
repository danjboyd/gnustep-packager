/* Tool tips show only once under GNOME Wayland (Mutter + Xwayland).
 *
 * Hover over the button until its tool tip appears, move away, and hover
 * again. Each time the tool tip panel is ordered front, this prints the X
 * window's _NET_WM_WINDOW_TYPE and _XWAYLAND_ALLOW_COMMITS. From the second
 * hover on, the panel is ordered front but nothing appears on screen, and
 * _XWAYLAND_ALLOW_COMMITS is 0.
 *
 * Build: clang `gnustep-config --objc-flags` tooltip_rehover.m \
 *          `gnustep-config --gui-libs` -lX11 -o tooltip_rehover
 */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

static Display *dpy;

static NSString *
atomProperty(Window w, const char *name)
{
  Atom type;
  int format;
  unsigned long n, after;
  unsigned char *data = NULL;
  NSString *result = @"(none)";

  if (XGetWindowProperty(dpy, w, XInternAtom(dpy, name, False), 0, 1, False,
                         AnyPropertyType, &type, &format, &n, &after,
                         &data) == Success && data != NULL && n == 1)
    {
      long v = *(long *)data;

      if (type == XA_ATOM)
        {
          char *s = XGetAtomName(dpy, (Atom)v);
          result = [NSString stringWithUTF8String: s];
          XFree(s);
        }
      else
        {
          result = [NSString stringWithFormat: @"%ld", v];
        }
    }
  if (data != NULL)
    XFree(data);
  return result;
}

@interface Controller : NSObject
{
  BOOL wasVisible;
  int shown;
}
@end

@implementation Controller

- (void) report: (NSWindow *)w
{
  Window xw = (Window)[GSServerForWindow(w) windowDevice: [w windowNumber]];

  NSLog(@"tool tip shown (%d): visible %@, frame %@, _NET_WM_WINDOW_TYPE %@,"
        @" _XWAYLAND_ALLOW_COMMITS %@", ++shown,
        [w isVisible] ? @"YES" : @"NO", NSStringFromRect([w frame]),
        atomProperty(xw, "_NET_WM_WINDOW_TYPE"),
        atomProperty(xw, "_XWAYLAND_ALLOW_COMMITS"));
}

- (void) check: (NSTimer *)timer
{
  NSEnumerator *e = [[NSApp windows] objectEnumerator];
  NSWindow *w;

  while ((w = [e nextObject]) != nil)
    {
      if (![NSStringFromClass([w class]) isEqual: @"GSTTPanel"])
        continue;
      if ([w isVisible] && !wasVisible)
        {
          /* Read the properties once Mutter has handled the new frame. */
          [self performSelector: @selector(report:)
                     withObject: w
                     afterDelay: 0.5];
        }
      wasVisible = [w isVisible];
    }
}

- (void) applicationDidFinishLaunching: (NSNotification *)n
{
  NSWindow *window;
  NSButton *button;

  window = [[NSWindow alloc]
             initWithContentRect: NSMakeRect(200, 200, 300, 160)
                       styleMask: NSTitledWindowMask
                         backing: NSBackingStoreBuffered
                           defer: NO];
  [window setTitle: @"Tool tip"];
  button = [[NSButton alloc] initWithFrame: NSMakeRect(50, 40, 200, 80)];
  [button setTitle: @"Hover here"];
  [button setToolTip: @"This is the tool tip"];
  [[window contentView] addSubview: button];
  [window makeKeyAndOrderFront: nil];

  /* Watch for the tool tip panel; a second connection (dpy) reads its
   * properties. */
  [NSTimer scheduledTimerWithTimeInterval: 0.2
                                   target: self
                                 selector: @selector(check:)
                                 userInfo: nil
                                  repeats: YES];
}

@end

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  dpy = XOpenDisplay(NULL);
  [NSApplication sharedApplication];
  [NSApp setDelegate: [Controller new]];
  [NSApp run];
  [pool release];
  return 0;
}
