#import <Foundation/Foundation.h>

// What became of the last update the app quit to install. The update is
// applied after the app has quit (by gp-update-helper, apply-msi.cmd or
// apply-appimage.sh), and when that fails the app is not started again, so
// the app learns of it at its next launch, from the helper's state file.
//
// Before quitting to install, the app records the request beside the
// state file (apply-request.json). At launch, an outcome exists only when
// such a request does, so a failure the app already showed while preparing
// is not shown twice.
@interface GPUpdaterApplyOutcome : NSObject
// The helper status: "completed", "failed", "readyToApply" (the app did
// not quit) and so on.
@property (nonatomic, readonly, copy) NSString *status;
@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly, copy) NSString *backend;
// Why the update was not installed, in plain words; nil unless it failed.
@property (nonatomic, readonly, copy) NSString *failureReason;
// msiexec's exit code when the MSI install failed, else 0.
@property (nonatomic, readonly) NSInteger installerExitCode;
// Where to download the update by hand, and the installer's log, if any.
@property (nonatomic, readonly, retain) NSURL *downloadURL;
@property (nonatomic, readonly, copy) NSString *logPath;
- (BOOL)failed;

// Records, in the helper's state directory, that the app is quitting to
// install this update.
+ (BOOL)recordRequestInDirectory:(NSString *)directory
                         version:(NSString *)version
                         backend:(NSString *)backend
                     downloadURL:(NSURL *)downloadURL;

// Forgets the request, when the app did not quit after all.
+ (void)removeRequestInDirectory:(NSString *)directory;

// The outcome of the recorded request, or nil when there is none or the
// update is still being applied.
+ (instancetype)outcomeInDirectory:(NSString *)directory;

// Forgets the request and the helper's state, once the outcome is dealt
// with.
+ (void)clearDirectory:(NSString *)directory;
@end

// An msiexec exit code in plain words, such as "Windows Installer is
// turned off on this computer by policy" for 1625.
NSString *GPUpdaterDescribeMSIExitCode(NSInteger code);
