// For tests/shared/UpdaterDefaults.Tests.ps1:
//   skip-version-probe skip <version>   records the skip and exits at once,
//                                       as a killed app would (no -terminate:)
//   skip-version-probe read             prints the skipped version, or nothing
#import <Foundation/Foundation.h>
#import <unistd.h>
#import "GPUpdater.h"

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSDictionary dictionaryWithObjectsAndKeys:
      @"com.example.SkipProbe", @"id", @"SkipProbe", @"name", @"1.0.0", @"version", @"appimage", @"backend", nil], @"package",
    [NSDictionary dictionaryWithObjectsAndKeys:@"https://example.invalid/feed.json", @"feedUrl", nil], @"updates",
    nil];
  GPUpdater *updater = [[GPUpdater alloc] initWithConfiguration:[GPUpdaterConfiguration configurationWithDictionary:dictionary error:NULL]];
  NSString *command = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";

  if ([command isEqualToString:@"skip"] && argc == 3) {
    [updater skipVersion:[NSString stringWithUTF8String:argv[2]]];
    _exit(0);
  }
  if ([command isEqualToString:@"read"]) {
    NSString *skipped = [updater skippedVersion];
    printf("%s\n", skipped != nil ? [skipped UTF8String] : "");
    [pool release];
    return 0;
  }

  fprintf(stderr, "usage: skip-version-probe skip <version> | read\n");
  [pool release];
  return 2;
}
