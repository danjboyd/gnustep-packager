#import <AppKit/AppKit.h>
#import "GPUpdater.h"

@class GPStandardUpdaterController;

@protocol GPStandardUpdaterControllerDelegate <NSObject>
@optional
- (BOOL)standardUpdaterController:(GPStandardUpdaterController *)controller shouldPresentResult:(GPUpdateCheckResult *)result automaticCheck:(BOOL)automaticCheck;
- (NSString *)standardUpdaterController:(GPStandardUpdaterController *)controller titleForResult:(GPUpdateCheckResult *)result automaticCheck:(BOOL)automaticCheck;
- (NSString *)standardUpdaterController:(GPStandardUpdaterController *)controller messageForResult:(GPUpdateCheckResult *)result automaticCheck:(BOOL)automaticCheck;
- (void)standardUpdaterController:(GPStandardUpdaterController *)controller openReleaseNotesURL:(NSURL *)releaseNotesURL;
- (NSString *)helperPathForStandardUpdaterController:(GPStandardUpdaterController *)controller;
@end

@interface GPStandardUpdaterController : NSObject <GPUpdaterDelegate>
@property (nonatomic, assign) id<GPStandardUpdaterControllerDelegate> delegate;
@property (nonatomic, readonly, retain) GPUpdater *updater;
@property (nonatomic, assign) NSWindow *parentWindow;
@property (nonatomic, copy) NSString *helperPath;
@property (nonatomic, copy) NSString *helperStateDirectory;
@property (nonatomic) BOOL showsUpToDateAlerts;
- (instancetype)initWithUpdater:(GPUpdater *)updater;
- (instancetype)initWithPackagedConfiguration:(NSError **)error;
- (void)start;
- (void)checkForUpdates:(id)sender;
@end
