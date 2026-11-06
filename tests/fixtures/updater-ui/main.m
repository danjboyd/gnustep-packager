// Updater dialog fixture: a GNUstep app with GPStandardUpdaterController and
// nothing else. Every alert it shows, and the button that closed it, goes to
// the marker file, so a driver can press real keys and check what happened.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "GPStandardUpdaterController.h"

static NSString *gMarker = nil;
static void Mark(NSString *line) {
  NSString *text = [line stringByAppendingString:@"\n"];
  NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:gMarker];
  if (h == nil) {
    [text writeToFile:gMarker atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    return;
  }
  [h seekToEndOfFile];
  [h writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
  [h closeFile];
}

static IMP gRunModal = NULL;
static NSInteger LoggedRunModal(id self, SEL _cmd) {
  NSMutableArray *titles = [NSMutableArray array];
  for (NSButton *b in [self buttons]) { [titles addObject:[b title]]; }
  Mark([NSString stringWithFormat:@"ALERT %@ | %@ | %@", [self messageText], [self informativeText], [titles componentsJoinedByString:@","]]);
  NSInteger r = ((NSInteger (*)(id, SEL))gRunModal)(self, _cmd);
  Mark([NSString stringWithFormat:@"RESPONSE %ld", (long)(r - NSAlertFirstButtonReturn + 1)]);
  return r;
}

@interface Fixture : NSObject <GPStandardUpdaterControllerDelegate>
@property (retain) GPStandardUpdaterController *controller;
@end

@implementation Fixture
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSError *error = nil;
  GPUpdaterConfiguration *config = [GPUpdaterConfiguration configurationWithContentsOfFile:[env objectForKey:@"GPUI_CONFIG"] error:&error];
  if (config == nil) { Mark([NSString stringWithFormat:@"CONFIG-ERROR %@", error]); [NSApp terminate:nil]; return; }
  GPUpdater *updater = [[[GPUpdater alloc] initWithConfiguration:config] autorelease];
  if ([[env objectForKey:@"GPUI_RESET"] isEqualToString:@"1"]) {
    [updater clearSkippedVersion];
  }
  self.controller = [[[GPStandardUpdaterController alloc] initWithUpdater:updater] autorelease];
  self.controller.delegate = self;
  self.controller.helperPath = [env objectForKey:@"GPUI_HELPER"];
  self.controller.helperStateDirectory = [env objectForKey:@"GPUI_STATE"];
  Mark([NSString stringWithFormat:@"LAUNCHED %@ skipped=%@", [config currentVersion], [updater skippedVersion]]);
  if ([[env objectForKey:@"GPUI_MODE"] isEqualToString:@"manual"]) {
    [self.controller checkForUpdates:nil];
  } else {
    [self.controller start];
  }
}
- (BOOL)standardUpdaterController:(GPStandardUpdaterController *)c shouldPresentResult:(GPUpdateCheckResult *)result automaticCheck:(BOOL)automatic {
  Mark([NSString stringWithFormat:@"RESULT status=%ld latest=%@ automatic=%d", (long)[result status], [result latestVersion], automatic]);
  return YES;
}
- (void)applicationWillTerminate:(NSNotification *)n { Mark(@"QUIT"); }
@end

int main(int argc, const char **argv) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  gMarker = [[[[NSProcessInfo processInfo] environment] objectForKey:@"GPUI_MARKER"] retain];
  Method m = class_getInstanceMethod([NSAlert class], @selector(runModal));
  gRunModal = method_setImplementation(m, (IMP)LoggedRunModal);
  [NSApplication sharedApplication];
  Fixture *f = [Fixture new];
  [NSApp setDelegate:f];
  [NSApp run];
  [pool release];
  return 0;
}
