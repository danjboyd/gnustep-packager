// For tests/shared/UpdaterDefaults.Tests.ps1: starts the updater with a check due and a short startup
// delay, checks by hand at once, as File > Check for Updates does, runs past the delay, and prints how
// many checks finished. The feed doesn't exist, so each ends in a failure.
#import <Foundation/Foundation.h>
#import "GPUpdater.h"

@interface StartupCheckProbeDelegate : NSObject <GPUpdaterDelegate> {
@public
  int finished;
}
@end

@implementation StartupCheckProbeDelegate
- (void)updater:(GPUpdater *)updater didFinishUpdateCheck:(GPUpdateCheckResult *)result {
  finished++;
}
- (void)updater:(GPUpdater *)updater didFailUpdateCheckWithError:(NSError *)error {
  finished++;
}
@end

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSDictionary dictionaryWithObjectsAndKeys:
      @"com.example.StartupCheckProbe", @"id", @"StartupCheckProbe", @"name", @"1.0.0", @"version", @"appimage", @"backend", nil], @"package",
    [NSDictionary dictionaryWithObjectsAndKeys:
      @"https://example.invalid/feed.json", @"feedUrl", [NSNumber numberWithInt:3], @"startupDelaySeconds", nil], @"updates",
    nil];
  GPUpdater *updater = [[GPUpdater alloc] initWithConfiguration:[GPUpdaterConfiguration configurationWithDictionary:dictionary error:NULL]];
  StartupCheckProbeDelegate *delegate = [[StartupCheckProbeDelegate alloc] init];
  [updater setDelegate:delegate];

  [updater start];
  [updater checkForUpdates];

  // Past the delay, and long enough for any check to fail on a slow resolver.
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:20.0]];
  printf("%d\n", delegate->finished);
  [pool release];
  return 0;
}
