#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "GPUpdater.h"
#import "GPStandardUpdaterController.h"

@interface AppDelegate : NSObject <GPStandardUpdaterControllerDelegate> {
  GPStandardUpdaterController *_updaterController;
}
- (IBAction)checkForUpdates:(id)sender;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;

  NSError *error = nil;
  _updaterController = [[GPStandardUpdaterController alloc] initWithPackagedConfiguration:&error];
  if (_updaterController == nil) {
    NSLog(@"Updater disabled: %@", [error localizedDescription]);
    return;
  }

  [_updaterController setDelegate:self];
  [_updaterController start];
}

- (IBAction)checkForUpdates:(id)sender {
  [_updaterController checkForUpdates:sender];
}

- (void)dealloc {
  [_updaterController release];
  [super dealloc];
}

@end
