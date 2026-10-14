#import "GPUpdaterApplyOutcome.h"

static NSString * const GPApplyOutcomeRequestFileName = @"apply-request.json";
static NSString * const GPApplyOutcomeStateFileName = @"update-state.json";
static NSString * const GPApplyOutcomePlanFileName = @"update-plan.json";

static NSString *GPApplyOutcomeStringValue(id value) {
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSDictionary *GPApplyOutcomeDictionaryValue(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSDictionary *GPApplyOutcomeLoadJSON(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    return nil;
  }
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  return GPApplyOutcomeDictionaryValue(object);
}

NSString *GPUpdaterDescribeMSIExitCode(NSInteger code) {
  switch (code) {
    case 1260:
      return @"Windows blocked the installer: a software restriction policy on this computer does not allow it";
    case 1601:
      return @"the Windows Installer service could not be reached";
    case 1602:
      return @"the installation was cancelled";
    case 1603:
      return @"Windows Installer hit a fatal error during the installation";
    case 1618:
      return @"another installation was already in progress";
    case 1619:
    case 1620:
      return @"Windows Installer could not open the downloaded installer";
    case 1622:
      return @"Windows Installer could not write its log file";
    case 1625:
      return @"Windows Installer is turned off on this computer by policy (an administrator may have to install it)";
    case 1633:
      return @"the installer does not support this version of Windows or this processor";
    case 1638:
      return @"another version of the app is already installed";
    case 1639:
      return @"Windows Installer rejected the command line it was given";
    case 1730:
      return @"an administrator has to install it";
    default:
      return [NSString stringWithFormat:@"Windows Installer reported error %ld", (long)code];
  }
}

@interface GPUpdaterApplyOutcome ()
@property (nonatomic, readwrite, copy) NSString *status;
@property (nonatomic, readwrite, copy) NSString *version;
@property (nonatomic, readwrite, copy) NSString *backend;
@property (nonatomic, readwrite, copy) NSString *failureReason;
@property (nonatomic, readwrite) NSInteger installerExitCode;
@property (nonatomic, readwrite, retain) NSURL *downloadURL;
@property (nonatomic, readwrite, copy) NSString *logPath;
@end

@implementation GPUpdaterApplyOutcome

@synthesize status = _status;
@synthesize version = _version;
@synthesize backend = _backend;
@synthesize failureReason = _failureReason;
@synthesize installerExitCode = _installerExitCode;
@synthesize downloadURL = _downloadURL;
@synthesize logPath = _logPath;

- (BOOL)failed {
  return [[self status] isEqualToString:@"failed"];
}

+ (BOOL)recordRequestInDirectory:(NSString *)directory
                         version:(NSString *)version
                         backend:(NSString *)backend
                     downloadURL:(NSURL *)downloadURL {
  if ([directory length] == 0) {
    return NO;
  }

  NSMutableDictionary *request = [NSMutableDictionary dictionary];
  [request setObject:[NSNumber numberWithInt:1] forKey:@"formatVersion"];
  if ([version length] > 0) {
    [request setObject:version forKey:@"version"];
  }
  if ([backend length] > 0) {
    [request setObject:backend forKey:@"backend"];
  }
  if ([[downloadURL absoluteString] length] > 0) {
    [request setObject:[downloadURL absoluteString] forKey:@"downloadUrl"];
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:request options:NSJSONWritingPrettyPrinted error:NULL];
  if (data == nil) {
    return NO;
  }
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  return [data writeToFile:[directory stringByAppendingPathComponent:GPApplyOutcomeRequestFileName] atomically:YES];
}

+ (void)removeRequestInDirectory:(NSString *)directory {
  if ([directory length] > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:GPApplyOutcomeRequestFileName] error:NULL];
  }
}

+ (instancetype)outcomeInDirectory:(NSString *)directory {
  if ([directory length] == 0) {
    return nil;
  }

  NSDictionary *request = GPApplyOutcomeLoadJSON([directory stringByAppendingPathComponent:GPApplyOutcomeRequestFileName]);
  if (request == nil) {
    return nil;
  }

  NSDictionary *state = GPApplyOutcomeLoadJSON([directory stringByAppendingPathComponent:GPApplyOutcomeStateFileName]);
  NSString *status = GPApplyOutcomeStringValue([state objectForKey:@"status"]);
  // Still being applied: the installer may be running now.
  if ([status isEqualToString:@"applying"]) {
    return nil;
  }
  if ([status length] == 0) {
    status = @"unknown";
  }

  GPUpdaterApplyOutcome *outcome = [[[self alloc] init] autorelease];
  [outcome setStatus:status];
  [outcome setVersion:GPApplyOutcomeStringValue([request objectForKey:@"version"])];
  [outcome setBackend:GPApplyOutcomeStringValue([request objectForKey:@"backend"])];
  NSString *downloadURLString = GPApplyOutcomeStringValue([request objectForKey:@"downloadUrl"]);
  if ([downloadURLString length] > 0) {
    [outcome setDownloadURL:[NSURL URLWithString:downloadURLString]];
  }

  if (![outcome failed]) {
    return outcome;
  }

  NSDictionary *errorDictionary = GPApplyOutcomeDictionaryValue([state objectForKey:@"error"]);
  id exitCode = [errorDictionary objectForKey:@"exitCode"];
  NSString *reason = nil;
  if ([exitCode isKindOfClass:[NSNumber class]] && [exitCode integerValue] != 0) {
    [outcome setInstallerExitCode:[exitCode integerValue]];
    reason = GPUpdaterDescribeMSIExitCode([exitCode integerValue]);
  } else {
    // The helper's own words: its message, then the error's details.
    NSString *message = GPApplyOutcomeStringValue([state objectForKey:@"message"]);
    NSString *detail = GPApplyOutcomeStringValue([errorDictionary objectForKey:@"message"]);
    if ([message length] > 0 && [detail length] > 0) {
      reason = [NSString stringWithFormat:@"%@ (%@)", message, detail];
    } else if ([message length] > 0) {
      reason = message;
    } else if ([detail length] > 0) {
      reason = detail;
    } else {
      reason = @"the update helper reported a failure";
    }
  }
  [outcome setFailureReason:reason];

  NSEnumerator *enumerator = [[NSArray arrayWithObjects:@"msiexec.log", @"apply-appimage.log", nil] objectEnumerator];
  NSString *logName = nil;
  while ((logName = [enumerator nextObject]) != nil) {
    NSString *logPath = [directory stringByAppendingPathComponent:logName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
      [outcome setLogPath:logPath];
      break;
    }
  }

  return outcome;
}

+ (void)clearDirectory:(NSString *)directory {
  if ([directory length] == 0) {
    return;
  }

  NSEnumerator *enumerator = [[NSArray arrayWithObjects:GPApplyOutcomeRequestFileName, GPApplyOutcomeStateFileName, GPApplyOutcomePlanFileName, nil] objectEnumerator];
  NSString *name = nil;
  while ((name = [enumerator nextObject]) != nil) {
    [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:name] error:NULL];
  }
}

- (void)dealloc {
  [_status release];
  [_version release];
  [_backend release];
  [_failureReason release];
  [_downloadURL release];
  [_logPath release];
  [super dealloc];
}

@end
