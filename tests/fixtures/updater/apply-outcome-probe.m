// Drives GPUpdaterApplyOutcome for tests/shared/UpdaterHelperRuntime.Tests.ps1:
//   apply-outcome-probe record <directory> <version> <backend> <url>
//   apply-outcome-probe outcome <directory>    (prints JSON, or null)
//   apply-outcome-probe clear <directory>
//   apply-outcome-probe describe <msiexec exit code>
#import <Foundation/Foundation.h>
#import "GPUpdaterApplyOutcome.h"

static void GPProbePrint(NSString *text) {
  printf("%s\n", [text UTF8String]);
}

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int status = 0;
  NSString *command = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
  NSString *argument = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"";

  if ([command isEqualToString:@"record"] && argc == 6) {
    BOOL recorded = [GPUpdaterApplyOutcome recordRequestInDirectory:argument
                                                            version:[NSString stringWithUTF8String:argv[3]]
                                                            backend:[NSString stringWithUTF8String:argv[4]]
                                                        downloadURL:[NSURL URLWithString:[NSString stringWithUTF8String:argv[5]]]];
    status = recorded ? 0 : 1;
  } else if ([command isEqualToString:@"outcome"] && argc == 3) {
    GPUpdaterApplyOutcome *outcome = [GPUpdaterApplyOutcome outcomeInDirectory:argument];
    if (outcome == nil) {
      GPProbePrint(@"null");
    } else {
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      [result setObject:[outcome status] forKey:@"status"];
      [result setObject:[NSNumber numberWithBool:[outcome failed]] forKey:@"failed"];
      [result setObject:[NSNumber numberWithInteger:[outcome installerExitCode]] forKey:@"installerExitCode"];
      if ([outcome version] != nil) {
        [result setObject:[outcome version] forKey:@"version"];
      }
      if ([outcome backend] != nil) {
        [result setObject:[outcome backend] forKey:@"backend"];
      }
      if ([outcome failureReason] != nil) {
        [result setObject:[outcome failureReason] forKey:@"failureReason"];
      }
      if ([outcome downloadURL] != nil) {
        [result setObject:[[outcome downloadURL] absoluteString] forKey:@"downloadUrl"];
      }
      if ([outcome logPath] != nil) {
        [result setObject:[outcome logPath] forKey:@"logPath"];
      }
      NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
      GPProbePrint([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
    }
  } else if ([command isEqualToString:@"clear"] && argc == 3) {
    [GPUpdaterApplyOutcome clearDirectory:argument];
  } else if ([command isEqualToString:@"describe"] && argc == 3) {
    GPProbePrint(GPUpdaterDescribeMSIExitCode([argument integerValue]));
  } else {
    fprintf(stderr, "usage: apply-outcome-probe record|outcome|clear|describe ...\n");
    status = 2;
  }

  [pool release];
  return status;
}
