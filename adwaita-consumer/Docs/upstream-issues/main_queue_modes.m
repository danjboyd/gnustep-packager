/* Foundation only. Build with -fblocks and link libdispatch. */
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

static BOOL
drainsInMode(NSString *mode)
{
  __block BOOL ran = NO;
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: 1.0];
  /* Keep the mode alive: a mode with no input sources returns at once. */
  NSTimer *keepAlive = [NSTimer timerWithTimeInterval: 0.1 target: loop
                                             selector: @selector(description)
                                             userInfo: nil repeats: YES];

  [loop addTimer: keepAlive forMode: mode];
  dispatch_async(dispatch_get_main_queue(), ^{ ran = YES; });
  while (ran == NO && [limit timeIntervalSinceNow] > 0)
    {
      [loop runMode: mode beforeDate: limit];
    }
  [keepAlive invalidate];
  /* Let anything left over run before the next test. */
  while (ran == NO)
    {
      [loop runMode: NSDefaultRunLoopMode
         beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
    }
  return ran && [limit timeIntervalSinceNow] > 0;
}

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    NSArray *modes = [NSArray arrayWithObjects: NSDefaultRunLoopMode,
      @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode", nil];
    NSEnumerator *e = [modes objectEnumerator];
    NSString *mode;

    while ((mode = [e nextObject]) != nil)
      {
        BOOL ok = drainsInMode(mode);
        NSLog(@"main-queue block runs within 1s in %@: %@", mode, ok ? @"yes" : @"NO");
      }
  }
  return 0;
}
