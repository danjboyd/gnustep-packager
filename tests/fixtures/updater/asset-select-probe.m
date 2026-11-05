// Asset selection, for tests/shared/UpdaterPlatform.Tests.ps1.
//   asset-select-probe select <backend> <platform> <release.json>
//     prints the name of the asset GPUpdaterPreferredAsset picks, or "none"
//   asset-select-probe check
//     checks the feed in GP_UPDATER_FEED_URL with the packaged configuration
//     beside the probe, on this machine's platform, and prints
//     "update <asset name>", "up-to-date" or "error <message>"
//   asset-select-probe platform
//     prints GPUpdaterCurrentPlatform()
#import <Foundation/Foundation.h>
#import "GPUpdater.h"

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int status = 0;
  NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";

  if ([mode isEqualToString:@"platform"]) {
    printf("%s\n", [GPUpdaterCurrentPlatform() UTF8String]);
  } else if ([mode isEqualToString:@"select"] && argc == 5) {
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[4]]];
    id release = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    GPUpdateRelease *parsed = GPUpdaterReleaseFromDictionary(release);
    GPUpdateAsset *asset = GPUpdaterPreferredAsset([parsed assets],
                                                   [NSString stringWithUTF8String:argv[2]],
                                                   [NSString stringWithUTF8String:argv[3]]);
    printf("%s\n", asset ? [[asset name] UTF8String] : "none");
  } else if ([mode isEqualToString:@"check"]) {
    NSError *error = nil;
    GPUpdaterConfiguration *configuration = [GPUpdaterConfiguration packagedConfigurationWithError:&error];
    GPUpdater *updater = configuration ? [[[GPUpdater alloc] initWithConfiguration:configuration] autorelease] : nil;
    GPUpdateCheckResult *result = updater ? [updater checkForUpdatesSynchronously:&error] : nil;
    if (result == nil) {
      printf("error %s\n", [[error localizedDescription] UTF8String]);
    } else if ([result status] == GPUpdateCheckStatusUpdateAvailable) {
      printf("update %s\n", [[[result asset] name] UTF8String]);
    } else {
      printf("up-to-date\n");
    }
  } else {
    fprintf(stderr, "usage: asset-select-probe platform | select <backend> <platform> <release.json> | check\n");
    status = 2;
  }

  [pool release];
  return status;
}
