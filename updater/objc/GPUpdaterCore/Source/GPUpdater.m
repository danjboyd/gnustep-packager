#import "GPUpdater.h"

static NSString * const GPUpdaterErrorDomain = @"GPUpdaterErrorDomain";
static NSString * const GPUpdaterRuntimeConfigRelativePath = @"metadata/updates/gnustep-packager-update.json";
static NSString * const GPUpdaterAppImageRuntimeConfigRelativePath = @"usr/metadata/updates/gnustep-packager-update.json";

typedef NS_ENUM(NSInteger, GPUpdaterErrorCode) {
  GPUpdaterErrorInvalidConfiguration = 1,
  GPUpdaterErrorConfigurationNotFound = 2,
  GPUpdaterErrorFeedLoadFailed = 3,
  GPUpdaterErrorFeedParseFailed = 4
};

@interface GPUpdateAsset ()
@property (nonatomic, readwrite, copy) NSString *backend;
@property (nonatomic, readwrite, copy) NSString *platform;
@property (nonatomic, readwrite, copy) NSString *kind;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, retain) NSURL *URL;
@property (nonatomic, readwrite, copy) NSString *SHA256;
@property (nonatomic, readwrite) unsigned long long sizeBytes;
@property (nonatomic, readwrite, copy) NSString *installScope;
@property (nonatomic, readwrite, copy) NSString *installerVersion;
@property (nonatomic, readwrite, copy) NSString *updateInformation;
@property (nonatomic, readwrite, retain) NSURL *zsyncURL;
@end

@interface GPUpdateRelease ()
@property (nonatomic, readwrite, copy) NSString *version;
@property (nonatomic, readwrite, copy) NSString *tag;
@property (nonatomic, readwrite, retain) NSURL *releaseNotesURL;
@property (nonatomic, readwrite, retain) NSArray *assets;
@end

@interface GPUpdateCheckResult ()
@property (nonatomic, readwrite) GPUpdateCheckStatus status;
@property (nonatomic, readwrite, copy) NSString *currentVersion;
@property (nonatomic, readwrite, copy) NSString *latestVersion;
@property (nonatomic, readwrite, retain) GPUpdateRelease *release;
@property (nonatomic, readwrite, retain) GPUpdateAsset *asset;
@end

@interface GPUpdaterConfiguration ()
@property (nonatomic, readwrite, copy) NSString *packageIdentifier;
@property (nonatomic, readwrite, copy) NSString *packageName;
@property (nonatomic, readwrite, copy) NSString *displayName;
@property (nonatomic, readwrite, copy) NSString *currentVersion;
@property (nonatomic, readwrite, copy) NSString *backend;
@property (nonatomic, readwrite, copy) NSString *channel;
@property (nonatomic, readwrite, retain) NSURL *feedURL;
@property (nonatomic, readwrite) NSTimeInterval minimumCheckInterval;
@property (nonatomic, readwrite) NSTimeInterval startupDelay;
@end

@interface GPUpdaterDefaultsStore : NSObject {
  NSUserDefaults *_defaults;
  NSString *_prefix;
}
- (instancetype)initWithPackageIdentifier:(NSString *)packageIdentifier;
- (NSDate *)lastCheckDate;
- (void)setLastCheckDate:(NSDate *)date;
- (BOOL)automaticallyChecksForUpdates;
- (void)setAutomaticallyChecksForUpdates:(BOOL)enabled;
- (NSString *)skippedVersion;
- (void)setSkippedVersion:(NSString *)version;
@end

@interface GPUpdater ()
- (void)_performCheckInBackground;
- (void)_scheduledCheckFired:(NSTimer *)timer;
- (void)_deliverBackgroundPayload:(NSDictionary *)payload;
- (GPUpdateAsset *)_preferredAssetForRelease:(GPUpdateRelease *)release;
@end

static id GPDictionaryValue(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static id GPArrayValue(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSString *GPStringValue(id value) {
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSNumber *GPNumberValue(id value) {
  return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSURL *GPURLFromString(id value) {
  NSString *stringValue = GPStringValue(value);
  if (stringValue == nil || [stringValue length] == 0) {
    return nil;
  }

  return [NSURL URLWithString:stringValue];
}

static NSError *GPMakeUpdaterError(NSInteger code, NSString *description) {
  NSDictionary *userInfo = [NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
  return [NSError errorWithDomain:GPUpdaterErrorDomain code:code userInfo:userInfo];
}

static NSArray *GPSplitBaseVersion(NSString *version) {
  NSString *normalized = version != nil ? version : @"";
  NSRange plusRange = [normalized rangeOfString:@"+"];
  if (plusRange.location != NSNotFound) {
    normalized = [normalized substringToIndex:plusRange.location];
  }

  NSRange dashRange = [normalized rangeOfString:@"-"];
  NSString *baseVersion = dashRange.location == NSNotFound ? normalized : [normalized substringToIndex:dashRange.location];
  return [baseVersion componentsSeparatedByString:@"."];
}

static NSArray *GPSplitPreRelease(NSString *version) {
  NSString *normalized = version != nil ? version : @"";
  NSRange plusRange = [normalized rangeOfString:@"+"];
  if (plusRange.location != NSNotFound) {
    normalized = [normalized substringToIndex:plusRange.location];
  }

  NSRange dashRange = [normalized rangeOfString:@"-"];
  if (dashRange.location == NSNotFound) {
    return [NSArray array];
  }

  NSString *suffix = [normalized substringFromIndex:(dashRange.location + 1)];
  if ([suffix length] == 0) {
    return [NSArray array];
  }

  return [suffix componentsSeparatedByString:@"."];
}

static BOOL GPStringIsDigitsOnly(NSString *value) {
  if (value == nil || [value length] == 0) {
    return NO;
  }

  NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
  return [value rangeOfCharacterFromSet:nonDigits].location == NSNotFound;
}

static NSComparisonResult GPCompareVersionIdentifier(NSString *left, NSString *right) {
  BOOL leftNumeric = GPStringIsDigitsOnly(left);
  BOOL rightNumeric = GPStringIsDigitsOnly(right);

  if (leftNumeric && rightNumeric) {
    long long leftValue = [left longLongValue];
    long long rightValue = [right longLongValue];
    if (leftValue < rightValue) {
      return NSOrderedAscending;
    }
    if (leftValue > rightValue) {
      return NSOrderedDescending;
    }
    return NSOrderedSame;
  }

  if (leftNumeric && !rightNumeric) {
    return NSOrderedAscending;
  }

  if (!leftNumeric && rightNumeric) {
    return NSOrderedDescending;
  }

  return [left compare:right options:NSCaseInsensitiveSearch];
}

static NSComparisonResult GPCompareVersions(NSString *leftVersion, NSString *rightVersion) {
  NSArray *leftBase = GPSplitBaseVersion(leftVersion);
  NSArray *rightBase = GPSplitBaseVersion(rightVersion);
  NSUInteger maxBaseCount = MAX([leftBase count], [rightBase count]);
  NSUInteger index = 0;

  for (index = 0; index < maxBaseCount; index++) {
    long long leftValue = index < [leftBase count] ? [[leftBase objectAtIndex:index] longLongValue] : 0;
    long long rightValue = index < [rightBase count] ? [[rightBase objectAtIndex:index] longLongValue] : 0;
    if (leftValue < rightValue) {
      return NSOrderedAscending;
    }
    if (leftValue > rightValue) {
      return NSOrderedDescending;
    }
  }

  NSArray *leftPre = GPSplitPreRelease(leftVersion);
  NSArray *rightPre = GPSplitPreRelease(rightVersion);
  if ([leftPre count] == 0 && [rightPre count] == 0) {
    return NSOrderedSame;
  }
  if ([leftPre count] == 0) {
    return NSOrderedDescending;
  }
  if ([rightPre count] == 0) {
    return NSOrderedAscending;
  }

  NSUInteger maxPreCount = MAX([leftPre count], [rightPre count]);
  for (index = 0; index < maxPreCount; index++) {
    if (index >= [leftPre count]) {
      return NSOrderedAscending;
    }
    if (index >= [rightPre count]) {
      return NSOrderedDescending;
    }

    NSComparisonResult comparison = GPCompareVersionIdentifier([leftPre objectAtIndex:index], [rightPre objectAtIndex:index]);
    if (comparison != NSOrderedSame) {
      return comparison;
    }
  }

  return NSOrderedSame;
}

static GPUpdateAsset *GPUpdateAssetFromDictionary(NSDictionary *dictionary) {
  if (dictionary == nil) {
    return nil;
  }

  GPUpdateAsset *asset = [[[GPUpdateAsset alloc] init] autorelease];
  asset.backend = GPStringValue([dictionary objectForKey:@"backend"]);
  asset.platform = GPStringValue([dictionary objectForKey:@"platform"]);
  asset.kind = GPStringValue([dictionary objectForKey:@"kind"]);
  asset.name = GPStringValue([dictionary objectForKey:@"name"]);
  asset.URL = GPURLFromString([dictionary objectForKey:@"url"]);
  asset.SHA256 = GPStringValue([dictionary objectForKey:@"sha256"]);
  asset.installScope = GPStringValue([dictionary objectForKey:@"installScope"]);
  asset.installerVersion = GPStringValue([dictionary objectForKey:@"msiVersion"]);
  asset.updateInformation = GPStringValue([dictionary objectForKey:@"updateInformation"]);

  NSNumber *sizeValue = GPNumberValue([dictionary objectForKey:@"sizeBytes"]);
  asset.sizeBytes = sizeValue != nil ? [sizeValue unsignedLongLongValue] : 0ULL;

  NSDictionary *zsync = GPDictionaryValue([dictionary objectForKey:@"zsync"]);
  if (zsync != nil) {
    asset.zsyncURL = GPURLFromString([zsync objectForKey:@"url"]);
  }

  if ([asset.backend length] == 0 || [asset.name length] == 0 || asset.URL == nil) {
    return nil;
  }

  return asset;
}

static GPUpdateRelease *GPUpdateReleaseFromDictionary(NSDictionary *dictionary) {
  if (dictionary == nil) {
    return nil;
  }

  NSMutableArray *assets = [NSMutableArray array];
  NSArray *assetDictionaries = GPArrayValue([dictionary objectForKey:@"assets"]);
  NSEnumerator *assetEnumerator = [assetDictionaries objectEnumerator];
  NSDictionary *assetDictionary = nil;
  while ((assetDictionary = [assetEnumerator nextObject]) != nil) {
    GPUpdateAsset *asset = GPUpdateAssetFromDictionary(GPDictionaryValue(assetDictionary));
    if (asset != nil) {
      [assets addObject:asset];
    }
  }

  GPUpdateRelease *release = [[[GPUpdateRelease alloc] init] autorelease];
  release.version = GPStringValue([dictionary objectForKey:@"version"]);
  release.tag = GPStringValue([dictionary objectForKey:@"tag"]);
  release.releaseNotesURL = GPURLFromString([dictionary objectForKey:@"releaseNotesUrl"]);
  release.assets = [NSArray arrayWithArray:assets];

  if ([release.version length] == 0 || [[release assets] count] == 0) {
    return nil;
  }

  return release;
}

@implementation GPUpdateAsset

@synthesize backend = _backend;
@synthesize platform = _platform;
@synthesize kind = _kind;
@synthesize name = _name;
@synthesize URL = _URL;
@synthesize SHA256 = _SHA256;
@synthesize sizeBytes = _sizeBytes;
@synthesize installScope = _installScope;
@synthesize installerVersion = _installerVersion;
@synthesize updateInformation = _updateInformation;
@synthesize zsyncURL = _zsyncURL;

- (void)dealloc {
  [_backend release];
  [_platform release];
  [_kind release];
  [_name release];
  [_URL release];
  [_SHA256 release];
  [_installScope release];
  [_installerVersion release];
  [_updateInformation release];
  [_zsyncURL release];
  [super dealloc];
}

@end

@implementation GPUpdateRelease

@synthesize version = _version;
@synthesize tag = _tag;
@synthesize releaseNotesURL = _releaseNotesURL;
@synthesize assets = _assets;

- (void)dealloc {
  [_version release];
  [_tag release];
  [_releaseNotesURL release];
  [_assets release];
  [super dealloc];
}

@end

@implementation GPUpdateCheckResult

@synthesize status = _status;
@synthesize currentVersion = _currentVersion;
@synthesize latestVersion = _latestVersion;
@synthesize release = _release;
@synthesize asset = _asset;

- (BOOL)hasUpdate {
  return self.status == GPUpdateCheckStatusUpdateAvailable;
}

- (void)dealloc {
  [_currentVersion release];
  [_latestVersion release];
  [_release release];
  [_asset release];
  [super dealloc];
}

@end

@implementation GPUpdaterConfiguration

@synthesize packageIdentifier = _packageIdentifier;
@synthesize packageName = _packageName;
@synthesize displayName = _displayName;
@synthesize currentVersion = _currentVersion;
@synthesize backend = _backend;
@synthesize channel = _channel;
@synthesize feedURL = _feedURL;
@synthesize minimumCheckInterval = _minimumCheckInterval;
@synthesize startupDelay = _startupDelay;

+ (instancetype)configurationWithContentsOfFile:(NSString *)path error:(NSError **)error {
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    if (error != NULL) {
      *error = GPMakeUpdaterError(GPUpdaterErrorConfigurationNotFound, @"Updater runtime configuration file was not found.");
    }
    return nil;
  }

  NSError *jsonError = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (object == nil || ![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = jsonError != nil ? jsonError : GPMakeUpdaterError(GPUpdaterErrorFeedParseFailed, @"Updater runtime configuration could not be parsed as JSON.");
    }
    return nil;
  }

  return [self configurationWithDictionary:(NSDictionary *)object error:error];
}

+ (instancetype)configurationWithDictionary:(NSDictionary *)dictionary error:(NSError **)error {
  NSDictionary *package = GPDictionaryValue([dictionary objectForKey:@"package"]);
  NSDictionary *updates = GPDictionaryValue([dictionary objectForKey:@"updates"]);
  if (package == nil || updates == nil) {
    if (error != NULL) {
      *error = GPMakeUpdaterError(GPUpdaterErrorInvalidConfiguration, @"Updater runtime configuration must contain 'package' and 'updates' objects.");
    }
    return nil;
  }

  NSString *packageIdentifier = GPStringValue([package objectForKey:@"id"]);
  NSString *packageName = GPStringValue([package objectForKey:@"name"]);
  NSString *displayName = GPStringValue([package objectForKey:@"displayName"]);
  NSString *currentVersion = GPStringValue([package objectForKey:@"version"]);
  NSString *backend = GPStringValue([package objectForKey:@"backend"]);
  NSString *channel = GPStringValue([updates objectForKey:@"channel"]);
  NSURL *feedURL = GPURLFromString([updates objectForKey:@"feedUrl"]);
  NSNumber *minimumHours = GPNumberValue([updates objectForKey:@"minimumCheckIntervalHours"]);
  NSNumber *startupDelay = GPNumberValue([updates objectForKey:@"startupDelaySeconds"]);

  if ([packageIdentifier length] == 0 || [packageName length] == 0 || [currentVersion length] == 0 || [backend length] == 0 || feedURL == nil) {
    if (error != NULL) {
      *error = GPMakeUpdaterError(GPUpdaterErrorInvalidConfiguration, @"Updater runtime configuration is missing required package identity, backend, or feed URL values.");
    }
    return nil;
  }

  GPUpdaterConfiguration *configuration = [[[GPUpdaterConfiguration alloc] init] autorelease];
  configuration.packageIdentifier = packageIdentifier;
  configuration.packageName = packageName;
  configuration.displayName = [displayName length] > 0 ? displayName : packageName;
  configuration.currentVersion = currentVersion;
  configuration.backend = backend;
  configuration.channel = [channel length] > 0 ? channel : @"stable";
  configuration.feedURL = feedURL;
  configuration.minimumCheckInterval = (minimumHours != nil ? [minimumHours doubleValue] : 24.0) * 3600.0;
  configuration.startupDelay = startupDelay != nil ? [startupDelay doubleValue] : 15.0;
  return configuration;
}

+ (instancetype)packagedConfigurationWithError:(NSError **)error {
  NSBundle *mainBundle = [NSBundle mainBundle];
  NSString *executablePath = [mainBundle executablePath];
  if ([executablePath length] == 0) {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    executablePath = [arguments count] > 0 ? [arguments objectAtIndex:0] : nil;
  }

  if ([executablePath length] == 0) {
    if (error != NULL) {
      *error = GPMakeUpdaterError(GPUpdaterErrorConfigurationNotFound, @"The packaged updater configuration could not be located because the main executable path is unknown.");
    }
    return nil;
  }

  NSMutableArray *candidatePaths = [NSMutableArray array];
  NSString *currentDirectory = [executablePath stringByDeletingLastPathComponent];
  NSUInteger depth = 0;
  while ([currentDirectory length] > 1 && depth < 8) {
    [candidatePaths addObject:[currentDirectory stringByAppendingPathComponent:GPUpdaterRuntimeConfigRelativePath]];
    [candidatePaths addObject:[currentDirectory stringByAppendingPathComponent:GPUpdaterAppImageRuntimeConfigRelativePath]];

    NSString *parentDirectory = [currentDirectory stringByDeletingLastPathComponent];
    if ([parentDirectory isEqualToString:currentDirectory]) {
      break;
    }

    currentDirectory = parentDirectory;
    depth++;
  }

  NSEnumerator *enumerator = [candidatePaths objectEnumerator];
  NSString *candidatePath = nil;
  while ((candidatePath = [enumerator nextObject]) != nil) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidatePath]) {
      return [self configurationWithContentsOfFile:candidatePath error:error];
    }
  }

  if (error != NULL) {
    *error = GPMakeUpdaterError(GPUpdaterErrorConfigurationNotFound, @"No packaged updater configuration was found near the current executable.");
  }
  return nil;
}

- (void)dealloc {
  [_packageIdentifier release];
  [_packageName release];
  [_displayName release];
  [_currentVersion release];
  [_backend release];
  [_channel release];
  [_feedURL release];
  [super dealloc];
}

@end

@implementation GPUpdaterDefaultsStore

- (instancetype)initWithPackageIdentifier:(NSString *)packageIdentifier {
  self = [super init];
  if (self != nil) {
    _defaults = [[NSUserDefaults standardUserDefaults] retain];
    _prefix = [[NSString alloc] initWithFormat:@"GPUpdater.%@.", packageIdentifier];
  }
  return self;
}

- (NSString *)_key:(NSString *)suffix {
  return [NSString stringWithFormat:@"%@%@", _prefix, suffix];
}

- (NSDate *)lastCheckDate {
  return [_defaults objectForKey:[self _key:@"lastCheckDate"]];
}

- (void)setLastCheckDate:(NSDate *)date {
  if (date != nil) {
    [_defaults setObject:date forKey:[self _key:@"lastCheckDate"]];
  } else {
    [_defaults removeObjectForKey:[self _key:@"lastCheckDate"]];
  }
}

- (BOOL)automaticallyChecksForUpdates {
  NSString *configuredKey = [self _key:@"automaticChecksConfigured"];
  if (![_defaults boolForKey:configuredKey]) {
    return YES;
  }

  return [_defaults boolForKey:[self _key:@"automaticChecksEnabled"]];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)enabled {
  [_defaults setBool:YES forKey:[self _key:@"automaticChecksConfigured"]];
  [_defaults setBool:enabled forKey:[self _key:@"automaticChecksEnabled"]];
}

- (NSString *)skippedVersion {
  return [_defaults stringForKey:[self _key:@"skippedVersion"]];
}

- (void)setSkippedVersion:(NSString *)version {
  if ([version length] > 0) {
    [_defaults setObject:version forKey:[self _key:@"skippedVersion"]];
  } else {
    [_defaults removeObjectForKey:[self _key:@"skippedVersion"]];
  }
}

- (void)dealloc {
  [_defaults release];
  [_prefix release];
  [super dealloc];
}

@end

@implementation GPUpdater {
  GPUpdaterDefaultsStore *_store;
  NSTimer *_startupTimer;
  BOOL _checkInProgress;
}

@synthesize delegate = _delegate;
@synthesize configuration = _configuration;

- (instancetype)initWithConfiguration:(GPUpdaterConfiguration *)configuration {
  self = [super init];
  if (self != nil) {
    _configuration = [configuration retain];
    _store = [[GPUpdaterDefaultsStore alloc] initWithPackageIdentifier:[configuration packageIdentifier]];
    _startupTimer = nil;
    _checkInProgress = NO;
  }
  return self;
}

- (NSDate *)lastCheckDate {
  return [_store lastCheckDate];
}

- (BOOL)automaticallyChecksForUpdates {
  return [_store automaticallyChecksForUpdates];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)enabled {
  [_store setAutomaticallyChecksForUpdates:enabled];
}

- (NSString *)skippedVersion {
  return [_store skippedVersion];
}

- (void)skipVersion:(NSString *)version {
  [_store setSkippedVersion:version];
}

- (void)clearSkippedVersion {
  [_store setSkippedVersion:nil];
}

- (BOOL)shouldCheckNow {
  if (![self automaticallyChecksForUpdates]) {
    return NO;
  }

  NSDate *lastCheckDate = [self lastCheckDate];
  if (lastCheckDate == nil) {
    return YES;
  }

  NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
  return elapsed >= [[self configuration] minimumCheckInterval];
}

- (void)start {
  if (![self shouldCheckNow]) {
    return;
  }

  [_startupTimer invalidate];
  [_startupTimer release];
  _startupTimer = [[NSTimer scheduledTimerWithTimeInterval:[[self configuration] startupDelay]
                                                    target:self
                                                  selector:@selector(_scheduledCheckFired:)
                                                  userInfo:nil
                                                   repeats:NO] retain];
}

- (void)_scheduledCheckFired:(NSTimer *)timer {
  (void)timer;
  [self checkForUpdates];
}

- (void)checkForUpdates {
  @synchronized (self) {
    if (_checkInProgress) {
      return;
    }
    _checkInProgress = YES;
  }

  [NSThread detachNewThreadSelector:@selector(_performCheckInBackground) toTarget:self withObject:nil];
}

- (void)_performCheckInBackground {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *error = nil;
  GPUpdateCheckResult *result = [self checkForUpdatesSynchronously:&error];

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  if (result != nil) {
    [payload setObject:result forKey:@"result"];
  }
  if (error != nil) {
    [payload setObject:error forKey:@"error"];
  }

  [self performSelectorOnMainThread:@selector(_deliverBackgroundPayload:) withObject:payload waitUntilDone:NO];
  [pool release];
}

- (void)_deliverBackgroundPayload:(NSDictionary *)payload {
  @synchronized (self) {
    _checkInProgress = NO;
  }

  NSError *error = [payload objectForKey:@"error"];
  GPUpdateCheckResult *result = [payload objectForKey:@"result"];
  if (error != nil && [_delegate respondsToSelector:@selector(updater:didFailUpdateCheckWithError:)]) {
    [_delegate updater:self didFailUpdateCheckWithError:error];
    return;
  }

  if (result != nil && [_delegate respondsToSelector:@selector(updater:didFinishUpdateCheck:)]) {
    [_delegate updater:self didFinishUpdateCheck:result];
  }
}

- (GPUpdateAsset *)_preferredAssetForRelease:(GPUpdateRelease *)release {
  NSEnumerator *assetEnumerator = [[release assets] objectEnumerator];
  GPUpdateAsset *asset = nil;
  while ((asset = [assetEnumerator nextObject]) != nil) {
    if ([[asset backend] isEqualToString:[[self configuration] backend]]) {
      return asset;
    }
  }

  return nil;
}

- (GPUpdateCheckResult *)checkForUpdatesSynchronously:(NSError **)error {
  NSData *feedData = [NSData dataWithContentsOfURL:[[self configuration] feedURL]];
  if (feedData == nil) {
    if (error != NULL) {
      *error = GPMakeUpdaterError(GPUpdaterErrorFeedLoadFailed, @"The update feed could not be loaded from the configured URL.");
    }
    return nil;
  }

  NSError *jsonError = nil;
  id object = [NSJSONSerialization JSONObjectWithData:feedData options:0 error:&jsonError];
  if (object == nil || ![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = jsonError != nil ? jsonError : GPMakeUpdaterError(GPUpdaterErrorFeedParseFailed, @"The update feed could not be parsed as JSON.");
    }
    return nil;
  }

  NSDictionary *feed = (NSDictionary *)object;
  NSString *feedChannel = GPStringValue([feed objectForKey:@"channel"]);
  if ([feedChannel length] > 0 && ![feedChannel isEqualToString:[[self configuration] channel]]) {
    GPUpdateCheckResult *result = [[[GPUpdateCheckResult alloc] init] autorelease];
    result.status = GPUpdateCheckStatusUpToDate;
    result.currentVersion = [[self configuration] currentVersion];
    result.latestVersion = [[self configuration] currentVersion];
    [_store setLastCheckDate:[NSDate date]];
    return result;
  }

  NSArray *releaseDictionaries = GPArrayValue([feed objectForKey:@"releases"]);
  GPUpdateRelease *bestRelease = nil;
  GPUpdateAsset *bestAsset = nil;
  NSEnumerator *releaseEnumerator = [releaseDictionaries objectEnumerator];
  NSDictionary *releaseDictionary = nil;
  while ((releaseDictionary = [releaseEnumerator nextObject]) != nil) {
    GPUpdateRelease *release = GPUpdateReleaseFromDictionary(GPDictionaryValue(releaseDictionary));
    if (release == nil) {
      continue;
    }

    GPUpdateAsset *asset = [self _preferredAssetForRelease:release];
    if (asset == nil) {
      continue;
    }

    if (GPCompareVersions([release version], [[self configuration] currentVersion]) != NSOrderedDescending) {
      continue;
    }

    if (bestRelease == nil || GPCompareVersions([release version], [bestRelease version]) == NSOrderedDescending) {
      bestRelease = release;
      bestAsset = asset;
    }
  }

  [_store setLastCheckDate:[NSDate date]];

  GPUpdateCheckResult *result = [[[GPUpdateCheckResult alloc] init] autorelease];
  result.currentVersion = [[self configuration] currentVersion];

  if (bestRelease == nil || bestAsset == nil) {
    result.status = GPUpdateCheckStatusUpToDate;
    result.latestVersion = [[self configuration] currentVersion];
    return result;
  }

  result.latestVersion = [bestRelease version];
  result.release = bestRelease;
  result.asset = bestAsset;

  if ([[self skippedVersion] isEqualToString:[bestRelease version]]) {
    result.status = GPUpdateCheckStatusSkipped;
  } else {
    result.status = GPUpdateCheckStatusUpdateAvailable;
  }

  return result;
}

- (void)dealloc {
  [_configuration release];
  [_store release];
  [_startupTimer invalidate];
  [_startupTimer release];
  [super dealloc];
}

@end
