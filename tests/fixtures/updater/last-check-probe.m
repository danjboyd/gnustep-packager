// For tests/shared/UpdaterDefaults.Tests.ps1. Each command is its own process, as app launches are:
//   last-check-probe set <epoch>      records a check at that time
//   last-check-probe legacy <epoch>   stores it as releases up to v0.1.7 did, an NSDate
//   last-check-probe rewrite          reads the defaults and writes them back, as any launch can
//   last-check-probe read             prints the stored time in epoch seconds, or "none"
//   last-check-probe due              prints whether an automatic check is due, "yes" or "no"
#import <Foundation/Foundation.h>
#import "GPUpdater.h"

// Private to GPUpdater.m.
@interface GPUpdaterDefaultsStore : NSObject
- (instancetype)initWithPackageIdentifier:(NSString *)packageIdentifier;
- (NSDate *)lastCheckDate;
- (void)setLastCheckDate:(NSDate *)date;
@end

static NSString *const kPackageIdentifier = @"com.example.LastCheckProbe";

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  GPUpdaterDefaultsStore *store = [[GPUpdaterDefaultsStore alloc] initWithPackageIdentifier:kPackageIdentifier];
  NSString *command = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
  int status = 0;

  if ([command isEqualToString:@"set"] && argc == 3) {
    [store setLastCheckDate:[NSDate dateWithTimeIntervalSince1970:atof(argv[2])]];
    [defaults synchronize];
  } else if ([command isEqualToString:@"legacy"] && argc == 3) {
    [defaults setObject:[NSDate dateWithTimeIntervalSince1970:atof(argv[2])]
                 forKey:[NSString stringWithFormat:@"GPUpdater.%@.lastCheckDate", kPackageIdentifier]];
    [defaults synchronize];
  } else if ([command isEqualToString:@"rewrite"]) {
    [defaults setObject:[[NSProcessInfo processInfo] globallyUniqueString] forKey:@"LastCheckProbeRewrite"];
    [defaults synchronize];
  } else if ([command isEqualToString:@"read"]) {
    NSDate *date = [store lastCheckDate];
    printf("%s\n", date != nil ? [[NSString stringWithFormat:@"%.0f", [date timeIntervalSince1970]] UTF8String] : "none");
  } else if ([command isEqualToString:@"due"]) {
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSDictionary dictionaryWithObjectsAndKeys:
        kPackageIdentifier, @"id", @"LastCheckProbe", @"name", @"1.0.0", @"version", @"appimage", @"backend", nil], @"package",
      [NSDictionary dictionaryWithObjectsAndKeys:@"https://example.invalid/feed.json", @"feedUrl", nil], @"updates",
      nil];
    GPUpdater *updater = [[GPUpdater alloc] initWithConfiguration:[GPUpdaterConfiguration configurationWithDictionary:dictionary error:NULL]];
    printf("%s\n", [updater shouldCheckNow] ? "yes" : "no");
  } else {
    fprintf(stderr, "usage: last-check-probe set <epoch> | legacy <epoch> | rewrite | read | due\n");
    status = 2;
  }
  [pool release];
  return status;
}
