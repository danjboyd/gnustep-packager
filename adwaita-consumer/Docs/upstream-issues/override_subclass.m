#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>

/* A theme that overrides -[NSActionCell tag]. */
@interface ReproTheme : GSTheme
@end

@implementation ReproTheme
- (NSInteger) _overrideNSActionCellMethod_tag
{
  typedef NSInteger (*TagIMP)(id, SEL);
  TagIMP original = (TagIMP)[[GSTheme theme] overriddenMethod: _cmd for: self];

  NSLog(@"  override called for %@: original IMP %p",
        NSStringFromClass([(id)self class]), original);
  return original ? original(self, _cmd) : -1;
}
@end

/* A subclass that inherits -tag unchanged. */
@interface MyCell : NSActionCell
@end
@implementation MyCell
@end

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  {
    NSActionCell *base;
    MyCell *sub;

    [NSApplication sharedApplication];
    [GSTheme setTheme: [[ReproTheme alloc] initWithBundle: nil]];

    base = [NSActionCell new];
    [base setTag: 7];
    sub = [MyCell new];
    [sub setTag: 7];

    NSLog(@"NSActionCell tag = %ld", (long)[base tag]);
    NSLog(@"MyCell tag       = %ld  (%@)", (long)[sub tag], [sub tag] == 7 ? @"PASS" : @"FAIL");
  }
  [pool release];
  return 0;
}
