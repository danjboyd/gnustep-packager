// Prints the feed URL of the updater configuration packaged next to it, for
// tests/shared/UpdaterFeedOverride.Tests.ps1. Put the configuration at
// metadata/updates/gnustep-packager-update.json beside the probe.
#import <Foundation/Foundation.h>
#import "GPUpdater.h"

int main(int argc, const char *argv[]) {
  (void)argc;
  (void)argv;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *error = nil;
  GPUpdaterConfiguration *configuration = [GPUpdaterConfiguration packagedConfigurationWithError:&error];
  int status = 0;
  if (configuration == nil) {
    fprintf(stderr, "no configuration: %s\n", [[error localizedDescription] UTF8String]);
    status = 1;
  } else {
    printf("%s\n", [[[configuration feedURL] absoluteString] UTF8String]);
  }
  [pool release];
  return status;
}
