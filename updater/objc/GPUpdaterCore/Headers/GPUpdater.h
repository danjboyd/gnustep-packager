#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GPUpdateCheckStatus) {
  GPUpdateCheckStatusUpToDate = 0,
  GPUpdateCheckStatusUpdateAvailable = 1,
  GPUpdateCheckStatusSkipped = 2
};

@class GPUpdateAsset;
@class GPUpdateCheckResult;
@class GPUpdateRelease;
@class GPUpdater;
@class GPUpdaterConfiguration;

@protocol GPUpdaterDelegate <NSObject>
@optional
- (void)updater:(GPUpdater *)updater didFinishUpdateCheck:(GPUpdateCheckResult *)result;
- (void)updater:(GPUpdater *)updater didFailUpdateCheckWithError:(NSError *)error;
@end

@interface GPUpdateAsset : NSObject
@property (nonatomic, readonly, copy) NSString *backend;
@property (nonatomic, readonly, copy) NSString *platform;
@property (nonatomic, readonly, copy) NSString *kind;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, retain) NSURL *URL;
@property (nonatomic, readonly, copy) NSString *SHA256;
@property (nonatomic, readonly) unsigned long long sizeBytes;
@property (nonatomic, readonly, copy) NSString *installScope;
@property (nonatomic, readonly, copy) NSString *installerVersion;
@property (nonatomic, readonly, copy) NSString *updateInformation;
@property (nonatomic, readonly, retain) NSURL *zsyncURL;
// The Ed25519 signature of the asset's bytes, base64 (the feed's
// "edSignature").
@property (nonatomic, readonly, copy) NSString *edSignature;
// The Ed25519 signature, base64, of GPUpdaterVersionSignatureMessage() for
// this asset (the feed's "versionSignature"). It ties the asset's SHA-256 to
// the package, release version, channel and platform, so a feed can't offer
// an older signed payload as a newer version, or one platform's as another's.
@property (nonatomic, readonly, copy) NSString *versionSignature;
@end

@interface GPUpdateRelease : NSObject
@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly, copy) NSString *tag;
@property (nonatomic, readonly, retain) NSURL *releaseNotesURL;
@property (nonatomic, readonly, retain) NSArray *assets;
@end

@interface GPUpdateCheckResult : NSObject
@property (nonatomic, readonly) GPUpdateCheckStatus status;
@property (nonatomic, readonly, copy) NSString *currentVersion;
@property (nonatomic, readonly, copy) NSString *latestVersion;
@property (nonatomic, readonly, retain) GPUpdateRelease *release;
@property (nonatomic, readonly, retain) GPUpdateAsset *asset;
- (BOOL)hasUpdate;
@end

@interface GPUpdaterConfiguration : NSObject
@property (nonatomic, readonly, copy) NSString *packageIdentifier;
@property (nonatomic, readonly, copy) NSString *packageName;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSString *currentVersion;
@property (nonatomic, readonly, copy) NSString *backend;
@property (nonatomic, readonly, copy) NSString *channel;
@property (nonatomic, readonly, retain) NSURL *feedURL;
@property (nonatomic, readonly) NSTimeInterval minimumCheckInterval;
@property (nonatomic, readonly) NSTimeInterval startupDelay;
// The Ed25519 public key update payloads must be signed with, base64
// ("updates.publicEDKey"). When set, an asset without a valid signature
// is refused.
@property (nonatomic, readonly, copy) NSString *publicEDKey;
// The package's launcher relative to its install root
// ("package.launcherRelativePath"), and, for a packaged configuration
// whose launcher exists, its full path: what to relaunch after an update.
@property (nonatomic, readonly, copy) NSString *launcherRelativePath;
@property (nonatomic, readonly, copy) NSString *relaunchExecutablePath;
+ (instancetype)configurationWithContentsOfFile:(NSString *)path error:(NSError **)error;
+ (instancetype)configurationWithDictionary:(NSDictionary *)dictionary error:(NSError **)error;
// The configuration packaged next to the executable. Its feed URL can be
// overridden for testing by the GP_UPDATER_FEED_URL environment variable,
// or else the GPUpdaterFeedURL user default: an https URL, an http URL to
// localhost or 127.0.0.1, or a file URL. Its use is logged; any other URL
// is ignored (and logged).
+ (instancetype)packagedConfigurationWithError:(NSError **)error;
@end

@interface GPUpdater : NSObject
@property (nonatomic, assign) id<GPUpdaterDelegate> delegate;
@property (nonatomic, readonly, retain) GPUpdaterConfiguration *configuration;
@property (nonatomic, readonly, retain) NSDate *lastCheckDate;
- (instancetype)initWithConfiguration:(GPUpdaterConfiguration *)configuration;
- (void)start;
- (void)checkForUpdates;
- (GPUpdateCheckResult *)checkForUpdatesSynchronously:(NSError **)error;
- (BOOL)shouldCheckNow;
- (BOOL)automaticallyChecksForUpdates;
- (void)setAutomaticallyChecksForUpdates:(BOOL)enabled;
- (NSString *)skippedVersion;
- (void)skipVersion:(NSString *)version;
- (void)clearSkippedVersion;
@end

// The platform token of the running build, as feeds name asset platforms:
// linux-x64, linux-arm64, windows-x64, windows-arm64 or macos.
extern NSString *GPUpdaterCurrentPlatform(void);

// The asset in assets (GPUpdateAsset objects) for backend and platform, or
// nil. An asset with no platform, as feeds before v0.1.9 wrote, counts as
// x64 only, so an arm64 machine never installs it.
extern GPUpdateAsset *GPUpdaterPreferredAsset(NSArray *assets, NSString *backend, NSString *platform);

// A feed release (an element of the feed's "releases") as the updater reads
// it, or nil when it isn't one.
extern GPUpdateRelease *GPUpdaterReleaseFromDictionary(NSDictionary *dictionary);

// Orders two version strings the way the updater decides what is newer:
// numeric dotted base versions, then pre-release identifiers (1.2.3-beta.1).
extern NSComparisonResult GPUpdaterCompareVersions(NSString *leftVersion, NSString *rightVersion);

// The UTF-8 message a feed's versionSignature signs, with lines joined by
// "\n" and no trailing newline:
//   gnustep-packager-update-v1
//   <package id>
//   <release version>
//   <channel>
//   <asset platform, such as linux-x64>
//   <asset SHA-256, lowercase hex>
// Returns nil when any part is empty or contains a line break.
extern NSData *GPUpdaterVersionSignatureMessage(NSString *packageIdentifier, NSString *version, NSString *channel, NSString *platform, NSString *SHA256);
