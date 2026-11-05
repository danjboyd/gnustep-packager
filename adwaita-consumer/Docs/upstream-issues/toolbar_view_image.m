#import <AppKit/AppKit.h>

@interface Delegate : NSObject <NSToolbarDelegate>
{ NSButton *button; NSWindow *window; }
@end

@implementation Delegate
- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar
      itemForItemIdentifier: (NSString *)identifier
  willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: identifier];
  NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(24, 24)];

  [image lockFocus];
  NSRectFill(NSMakeRect(4, 4, 16, 16));
  [image unlockFocus];

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 36, 32)];
  [button setImage: image];
  [button setImagePosition: NSImageOnly];
  [item setView: button];
  [item setLabel: @"Item"];
  NSLog(@"button image after setView: %@", [button image] ? @"set" : @"nil");
  return item;
}
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *)toolbar
{ return [NSArray arrayWithObject: @"Item"]; }
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *)toolbar
{ return [NSArray arrayWithObject: @"Item"]; }

- (void) check: (NSTimer *)timer
{
  NSLog(@"button image after layout:  %@  (%@)", [button image] ? @"set" : @"nil",
        [button image] ? @"PASS" : @"FAIL");
  [NSApp terminate: nil];
}
- (void) applicationDidFinishLaunching: (NSNotification *)n
{
  NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: @"repro"];

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 150)
                                       styleMask: NSTitledWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  [toolbar setDelegate: self];
  [window setToolbar: toolbar];
  [window orderFront: nil];
  [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self
                                 selector: @selector(check:)
                                 userInfo: nil repeats: NO];
}
@end

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setDelegate: [Delegate new]];
    [NSApp run];
  }
  return 0;
}
