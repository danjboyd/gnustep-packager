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
+ (instancetype)configurationWithContentsOfFile:(NSString *)path error:(NSError **)error;
+ (instancetype)configurationWithDictionary:(NSDictionary *)dictionary error:(NSError **)error;
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
