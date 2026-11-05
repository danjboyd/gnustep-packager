/* Run with: ./win95_late_window_menu -GSTheme GNUstep -NSMenuInterfaceStyle NSWindows95InterfaceStyle */
#import <AppKit/AppKit.h>

@interface Delegate : NSObject
{ NSWindow *early, *late; }
@end

@implementation Delegate
- (NSWindow *) windowAt: (CGFloat)x title: (NSString *)title
{
  NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(x, 100, 250, 120)
                                            styleMask: NSTitledWindowMask
                                              backing: NSBackingStoreBuffered
                                                defer: NO];
  [w setTitle: title];
  [w orderFront: nil];
  return w;
}
- (void) openLate: (NSTimer *)t
{
  late = [self windowAt: 400 title: @"Late"];
  [late makeKeyAndOrderFront: nil];
}
- (void) check: (NSTimer *)t
{
  NSLog(@"window created at launch: menu %@", [early menu] ? @"attached" : @"none");
  NSLog(@"window created later:     menu %@  (%@)", [late menu] ? @"attached" : @"none",
        [late menu] ? @"PASS" : @"FAIL");
  [NSApp terminate: nil];
}
- (void) applicationDidFinishLaunching: (NSNotification *)n
{
  early = [self windowAt: 100 title: @"Early"];
  [early makeKeyAndOrderFront: nil];
  [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self
                                 selector: @selector(openLate:) userInfo: nil repeats: NO];
  [NSTimer scheduledTimerWithTimeInterval: 2.0 target: self
                                 selector: @selector(check:) userInfo: nil repeats: NO];
}
@end

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  {
    NSMenu *menu;
    NSMenu *fileMenu;
    NSMenuItem *fileItem;

    [NSApplication sharedApplication];
    menu = [[NSMenu alloc] initWithTitle: @"Repro"];
    fileMenu = [[NSMenu alloc] initWithTitle: @"File"];
    [fileMenu addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];
    fileItem = [menu addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
    [menu setSubmenu: fileMenu forItem: fileItem];
    [NSApp setMainMenu: menu];
    [NSApp setDelegate: [Delegate new]];
    [NSApp run];
  }
  [pool release];
  return 0;
}
