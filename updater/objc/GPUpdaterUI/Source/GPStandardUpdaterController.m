#import "GPStandardUpdaterController.h"

static NSString * const GPUpdaterHelperPlanFormatVersion = @"1";
static NSString * const GPUpdaterHelperModePrepare = @"prepare";
static NSString * const GPUpdaterHelperModeApply = @"apply";
static NSString * const GPUpdaterHelperStatusPreparing = @"preparing";
static NSString * const GPUpdaterHelperStatusDownloading = @"downloading";
static NSString * const GPUpdaterHelperStatusReadyToApply = @"readyToApply";
static NSString * const GPUpdaterHelperStatusManualActionRequired = @"manualActionRequired";
static NSString * const GPUpdaterHelperStatusFailed = @"failed";

@interface GPStandardUpdaterController () {
  BOOL _manualCheckInProgress;
  BOOL _prepareInProgress;
  NSTimer *_helperPollTimer;
  NSPanel *_progressPanel;
  NSTextField *_progressLabel;
  NSProgressIndicator *_progressIndicator;
  NSString *_activePlanPath;
  NSString *_activeStatePath;
  GPUpdateCheckResult *_pendingInstallResult;
}
- (NSString *)_resolvedHelperPath;
- (NSString *)_helperStateRoot;
- (NSString *)_writeHelperPlanForResult:(GPUpdateCheckResult *)result statePath:(NSString *)statePath;
- (void)_presentUpdateAvailableForResult:(GPUpdateCheckResult *)result automaticCheck:(BOOL)automaticCheck;
- (void)_presentUpToDateDialog;
- (void)_presentError:(NSError *)error;
- (void)_openReleaseNotesURL:(NSURL *)releaseNotesURL;
- (void)_beginPrepareForResult:(GPUpdateCheckResult *)result;
- (void)_launchHelperMode:(NSString *)mode;
- (void)_beginPollingHelperState;
- (void)_pollHelperState:(NSTimer *)timer;
- (void)_stopPollingHelperState;
- (void)_showProgressPanelWithMessage:(NSString *)message;
- (void)_dismissProgressPanel;
- (NSDictionary *)_loadHelperState;
@end

static NSString *GPUpdaterUIStringValue(id value) {
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSNumber *GPUpdaterUINumberValue(id value) {
  return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSDictionary *GPUpdaterUIDictionaryValue(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static BOOL GPUpdaterUIWriteJSONObject(NSDictionary *dictionary, NSString *path) {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&error];
  if (data == nil || error != nil) {
    return NO;
  }

  NSString *directory = [path stringByDeletingLastPathComponent];
  if ([directory length] > 0) {
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  }

  return [data writeToFile:path atomically:YES];
}

static NSDictionary *GPUpdaterUILoadJSONObject(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    return nil;
  }

  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (object == nil || error != nil || ![object isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  return (NSDictionary *)object;
}

@implementation GPStandardUpdaterController

@synthesize delegate = _delegate;
@synthesize updater = _updater;
@synthesize parentWindow = _parentWindow;
@synthesize helperPath = _helperPath;
@synthesize helperStateDirectory = _helperStateDirectory;
@synthesize showsUpToDateAlerts = _showsUpToDateAlerts;

- (instancetype)initWithUpdater:(GPUpdater *)updater {
  self = [super init];
  if (self != nil) {
    _updater = [updater retain];
    [_updater setDelegate:self];
    _showsUpToDateAlerts = YES;
    _manualCheckInProgress = NO;
    _prepareInProgress = NO;
    _helperPollTimer = nil;
    _progressPanel = nil;
    _progressLabel = nil;
    _progressIndicator = nil;
    _activePlanPath = nil;
    _activeStatePath = nil;
    _pendingInstallResult = nil;
  }
  return self;
}

- (instancetype)initWithPackagedConfiguration:(NSError **)error {
  GPUpdaterConfiguration *configuration = [GPUpdaterConfiguration packagedConfigurationWithError:error];
  if (configuration == nil) {
    return nil;
  }

  GPUpdater *updater = [[[GPUpdater alloc] initWithConfiguration:configuration] autorelease];
  return [self initWithUpdater:updater];
}

- (void)start {
  [[self updater] start];
}

- (void)checkForUpdates:(id)sender {
  (void)sender;
  _manualCheckInProgress = YES;
  [[self updater] clearSkippedVersion];
  [[self updater] checkForUpdates];
}

- (void)updater:(GPUpdater *)updater didFinishUpdateCheck:(GPUpdateCheckResult *)result {
  (void)updater;
  BOOL automaticCheck = !_manualCheckInProgress;
  _manualCheckInProgress = NO;

  if ([[self delegate] respondsToSelector:@selector(standardUpdaterController:shouldPresentResult:automaticCheck:)]) {
    if (![[self delegate] standardUpdaterController:self shouldPresentResult:result automaticCheck:automaticCheck]) {
      return;
    }
  }

  if ([result hasUpdate]) {
    [self _presentUpdateAvailableForResult:result automaticCheck:automaticCheck];
    return;
  }

  if ([result status] == GPUpdateCheckStatusSkipped && automaticCheck) {
    return;
  }

  if (!automaticCheck && [self showsUpToDateAlerts]) {
    [self _presentUpToDateDialog];
  }
}

- (void)updater:(GPUpdater *)updater didFailUpdateCheckWithError:(NSError *)error {
  (void)updater;
  BOOL manualCheck = _manualCheckInProgress;
  _manualCheckInProgress = NO;
  if (manualCheck) {
    [self _presentError:error];
  }
}

- (NSString *)_resolvedHelperPath {
  if ([_helperPath length] > 0) {
    return _helperPath;
  }

  if ([[self delegate] respondsToSelector:@selector(helperPathForStandardUpdaterController:)]) {
    NSString *delegatePath = [[self delegate] helperPathForStandardUpdaterController:self];
    if ([delegatePath length] > 0) {
      return delegatePath;
    }
  }

  NSString *executablePath = [[NSBundle mainBundle] executablePath];
  if ([executablePath length] == 0) {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    executablePath = [arguments count] > 0 ? [arguments objectAtIndex:0] : nil;
  }

  if ([executablePath length] == 0) {
    return nil;
  }

  NSString *directory = [executablePath stringByDeletingLastPathComponent];
  NSArray *candidates = [NSArray arrayWithObjects:
    [directory stringByAppendingPathComponent:@"gp-update-helper"],
    [directory stringByAppendingPathComponent:@"gp-update-helper.exe"],
    [[directory stringByAppendingPathComponent:@"Helpers"] stringByAppendingPathComponent:@"gp-update-helper"],
    [[directory stringByAppendingPathComponent:@"Helpers"] stringByAppendingPathComponent:@"gp-update-helper.exe"],
    [[[directory stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Helpers"] stringByAppendingPathComponent:@"gp-update-helper"],
    [[[directory stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Helpers"] stringByAppendingPathComponent:@"gp-update-helper.exe"],
    nil
  ];

  NSEnumerator *enumerator = [candidates objectEnumerator];
  NSString *candidate = nil;
  while ((candidate = [enumerator nextObject]) != nil) {
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }

  return nil;
}

- (NSString *)_helperStateRoot {
  if ([_helperStateDirectory length] > 0) {
    return _helperStateDirectory;
  }

  NSString *packageIdentifier = [[[self updater] configuration] packageIdentifier];
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gnustep-packager-updater"];
  return [root stringByAppendingPathComponent:packageIdentifier];
}

- (NSString *)_writeHelperPlanForResult:(GPUpdateCheckResult *)result statePath:(NSString *)statePath {
  NSString *stateRoot = [self _helperStateRoot];
  [[NSFileManager defaultManager] createDirectoryAtPath:stateRoot withIntermediateDirectories:YES attributes:nil error:NULL];

  NSString *planPath = [stateRoot stringByAppendingPathComponent:@"update-plan.json"];
  GPUpdaterConfiguration *configuration = [[self updater] configuration];

  NSMutableDictionary *package = [NSMutableDictionary dictionary];
  [package setObject:[configuration packageIdentifier] forKey:@"id"];
  [package setObject:[configuration packageName] forKey:@"name"];
  [package setObject:[configuration displayName] forKey:@"displayName"];
  [package setObject:[configuration currentVersion] forKey:@"currentVersion"];
  [package setObject:[configuration backend] forKey:@"backend"];
  [package setObject:[configuration channel] forKey:@"channel"];

  NSMutableDictionary *release = [NSMutableDictionary dictionary];
  [release setObject:[result latestVersion] forKey:@"version"];
  if ([[result release] tag] != nil) {
    [release setObject:[[result release] tag] forKey:@"tag"];
  }
  if ([[result release] releaseNotesURL] != nil) {
    [release setObject:[[[result release] releaseNotesURL] absoluteString] forKey:@"releaseNotesUrl"];
  }

  GPUpdateAsset *asset = [result asset];
  NSMutableDictionary *assetDictionary = [NSMutableDictionary dictionary];
  [assetDictionary setObject:[asset backend] forKey:@"backend"];
  [assetDictionary setObject:[asset kind] forKey:@"kind"];
  [assetDictionary setObject:[asset name] forKey:@"name"];
  [assetDictionary setObject:[[asset URL] absoluteString] forKey:@"url"];
  [assetDictionary setObject:[NSNumber numberWithUnsignedLongLong:[asset sizeBytes]] forKey:@"sizeBytes"];
  if ([asset platform] != nil) {
    [assetDictionary setObject:[asset platform] forKey:@"platform"];
  }
  if ([asset SHA256] != nil) {
    [assetDictionary setObject:[asset SHA256] forKey:@"sha256"];
  }
  if ([asset installScope] != nil) {
    [assetDictionary setObject:[asset installScope] forKey:@"installScope"];
  }
  if ([asset installerVersion] != nil) {
    [assetDictionary setObject:[asset installerVersion] forKey:@"msiVersion"];
  }
  if ([asset updateInformation] != nil) {
    [assetDictionary setObject:[asset updateInformation] forKey:@"updateInformation"];
  }
  if ([asset zsyncURL] != nil) {
    NSDictionary *zsync = [NSDictionary dictionaryWithObject:[[asset zsyncURL] absoluteString] forKey:@"url"];
    [assetDictionary setObject:zsync forKey:@"zsync"];
  }

  NSString *executablePath = [[NSBundle mainBundle] executablePath];
  if ([executablePath length] == 0) {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    executablePath = [arguments count] > 0 ? [arguments objectAtIndex:0] : nil;
  }

  NSMutableDictionary *execution = [NSMutableDictionary dictionary];
  [execution setObject:statePath forKey:@"stateFile"];
  [execution setObject:stateRoot forKey:@"workingRoot"];
  if ([executablePath length] > 0) {
    [execution setObject:executablePath forKey:@"relaunchExecutablePath"];
  }

  NSMutableDictionary *linux = [NSMutableDictionary dictionary];
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *appImagePath = GPUpdaterUIStringValue([environment objectForKey:@"APPIMAGE"]);
  if ([appImagePath length] > 0) {
    [linux setObject:appImagePath forKey:@"currentAppImagePath"];
  }
  if ([linux count] > 0) {
    [execution setObject:linux forKey:@"linux"];
  }

  NSMutableDictionary *plan = [NSMutableDictionary dictionary];
  [plan setObject:[NSNumber numberWithInteger:[GPUpdaterHelperPlanFormatVersion integerValue]] forKey:@"formatVersion"];
  [plan setObject:package forKey:@"package"];
  [plan setObject:release forKey:@"release"];
  [plan setObject:assetDictionary forKey:@"asset"];
  [plan setObject:execution forKey:@"execution"];

  if ([executablePath length] > 0) {
    [plan setObject:executablePath forKey:@"currentExecutablePath"];
  }

  if (!GPUpdaterUIWriteJSONObject(plan, planPath)) {
    return nil;
  }

  return planPath;
}

- (void)_presentUpdateAvailableForResult:(GPUpdateCheckResult *)result automaticCheck:(BOOL)automaticCheck {
  NSString *title = nil;
  NSString *message = nil;

  if ([[self delegate] respondsToSelector:@selector(standardUpdaterController:titleForResult:automaticCheck:)]) {
    title = [[self delegate] standardUpdaterController:self titleForResult:result automaticCheck:automaticCheck];
  }
  if ([[self delegate] respondsToSelector:@selector(standardUpdaterController:messageForResult:automaticCheck:)]) {
    message = [[self delegate] standardUpdaterController:self messageForResult:result automaticCheck:automaticCheck];
  }

  if ([title length] == 0) {
    title = [NSString stringWithFormat:@"%@ %@ is available", [[[self updater] configuration] displayName], [result latestVersion]];
  }
  if ([message length] == 0) {
    message = [NSString stringWithFormat:@"You are currently running %@.", [result currentVersion]];
  }

  while (YES) {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"Install Update"];
    [alert addButtonWithTitle:@"Later"];
    [alert addButtonWithTitle:@"Skip This Version"];
    if ([[[result release] releaseNotesURL] absoluteString] != nil) {
      [alert addButtonWithTitle:@"View Changes"];
    }

    NSInteger response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
      [[self updater] clearSkippedVersion];
      [self _beginPrepareForResult:result];
      return;
    }

    if (response == NSAlertThirdButtonReturn) {
      [[self updater] skipVersion:[result latestVersion]];
      return;
    }

    if (response == NSAlertFirstButtonReturn + 3) {
      [self _openReleaseNotesURL:[[result release] releaseNotesURL]];
      continue;
    }

    return;
  }
}

- (void)_presentUpToDateDialog {
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:[NSString stringWithFormat:@"%@ is up to date", [[[self updater] configuration] displayName]]];
  [alert setInformativeText:[NSString stringWithFormat:@"You are already running %@.", [[[self updater] configuration] currentVersion]]];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

- (void)_presentError:(NSError *)error {
  NSString *message = error != nil ? [error localizedDescription] : @"The update check failed.";
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Update Check Failed"];
  [alert setInformativeText:message];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

- (void)_openReleaseNotesURL:(NSURL *)releaseNotesURL {
  if (releaseNotesURL == nil) {
    return;
  }

  if ([[self delegate] respondsToSelector:@selector(standardUpdaterController:openReleaseNotesURL:)]) {
    [[self delegate] standardUpdaterController:self openReleaseNotesURL:releaseNotesURL];
    return;
  }

  [[NSWorkspace sharedWorkspace] openURL:releaseNotesURL];
}

- (void)_beginPrepareForResult:(GPUpdateCheckResult *)result {
  NSString *helperPath = [self _resolvedHelperPath];
  if ([helperPath length] == 0) {
    NSError *error = [NSError errorWithDomain:@"GPUpdaterUIErrorDomain"
                                         code:1
                                     userInfo:[NSDictionary dictionaryWithObject:@"gp-update-helper was not found near the app bundle. Set GPStandardUpdaterController.helperPath or implement the delegate helper-path override." forKey:NSLocalizedDescriptionKey]];
    [self _presentError:error];
    return;
  }

  NSString *stateRoot = [self _helperStateRoot];
  [[NSFileManager defaultManager] createDirectoryAtPath:stateRoot withIntermediateDirectories:YES attributes:nil error:NULL];

  NSString *statePath = [stateRoot stringByAppendingPathComponent:@"update-state.json"];
  NSString *planPath = [self _writeHelperPlanForResult:result statePath:statePath];
  if ([planPath length] == 0) {
    NSError *error = [NSError errorWithDomain:@"GPUpdaterUIErrorDomain"
                                         code:2
                                     userInfo:[NSDictionary dictionaryWithObject:@"The helper plan could not be written to disk." forKey:NSLocalizedDescriptionKey]];
    [self _presentError:error];
    return;
  }

  [_pendingInstallResult release];
  _pendingInstallResult = [result retain];

  [_activePlanPath release];
  _activePlanPath = [planPath copy];
  [_activeStatePath release];
  _activeStatePath = [statePath copy];

  _prepareInProgress = YES;
  [self _showProgressPanelWithMessage:@"Preparing update..."];
  [self _launchHelperMode:GPUpdaterHelperModePrepare];
  [self _beginPollingHelperState];
}

- (void)_launchHelperMode:(NSString *)mode {
  NSString *helperPath = [self _resolvedHelperPath];
  if ([helperPath length] == 0) {
    return;
  }

  NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"--mode", mode, @"--plan", _activePlanPath, @"--state-file", _activeStatePath, nil];
  if ([mode isEqualToString:GPUpdaterHelperModeApply]) {
    [arguments addObject:@"--wait-pid"];
    [arguments addObject:[NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]]];
  }

  @try {
    [NSTask launchedTaskWithLaunchPath:helperPath arguments:arguments];
  } @catch (NSException *exception) {
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[exception reason] forKey:NSLocalizedDescriptionKey];
    NSError *error = [NSError errorWithDomain:@"GPUpdaterUIErrorDomain" code:3 userInfo:userInfo];
    [self _stopPollingHelperState];
    [self _dismissProgressPanel];
    [self _presentError:error];
  }
}

- (void)_beginPollingHelperState {
  [self _stopPollingHelperState];
  _helperPollTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(_pollHelperState:)
                                                     userInfo:nil
                                                      repeats:YES] retain];
}

- (void)_pollHelperState:(NSTimer *)timer {
  (void)timer;
  NSDictionary *state = [self _loadHelperState];
  if (state == nil) {
    return;
  }

  NSString *status = GPUpdaterUIStringValue([state objectForKey:@"status"]);
  NSString *message = GPUpdaterUIStringValue([state objectForKey:@"message"]);
  NSDictionary *progress = GPUpdaterUIDictionaryValue([state objectForKey:@"progress"]);
  NSNumber *fraction = GPUpdaterUINumberValue([progress objectForKey:@"fractionCompleted"]);

  if ([message length] > 0 && _progressLabel != nil) {
    [_progressLabel setStringValue:message];
  }

  if (fraction != nil && _progressIndicator != nil) {
    [_progressIndicator setIndeterminate:NO];
    [_progressIndicator setDoubleValue:([fraction doubleValue] * 100.0)];
  } else if (_progressIndicator != nil) {
    [_progressIndicator setIndeterminate:YES];
    [_progressIndicator startAnimation:self];
  }

  if ([status isEqualToString:GPUpdaterHelperStatusPreparing] || [status isEqualToString:GPUpdaterHelperStatusDownloading]) {
    return;
  }

  [self _stopPollingHelperState];
  [self _dismissProgressPanel];
  _prepareInProgress = NO;

  if ([status isEqualToString:GPUpdaterHelperStatusReadyToApply]) {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Restart to Finish Updating"];
    [alert setInformativeText:@"The update is ready to install. Restart the app now to apply it."];
    [alert addButtonWithTitle:@"Restart and Install"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
      [self _launchHelperMode:GPUpdaterHelperModeApply];
      [[NSApplication sharedApplication] terminate:nil];
    }
    return;
  }

  if ([status isEqualToString:GPUpdaterHelperStatusManualActionRequired]) {
    NSString *downloadedPath = GPUpdaterUIStringValue([state objectForKey:@"downloadedPath"]);
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Manual Update Required"];
    if ([message length] == 0) {
      message = @"The update was downloaded, but the current AppImage location is not writable.";
    }
    [alert setInformativeText:message];
    if ([downloadedPath length] > 0) {
      [alert addButtonWithTitle:@"Open Download"];
    }
    [alert addButtonWithTitle:@"OK"];
    if ([alert runModal] == NSAlertFirstButtonReturn && [downloadedPath length] > 0) {
      [[NSWorkspace sharedWorkspace] openFile:downloadedPath];
    }
    return;
  }

  NSString *errorMessage = message;
  NSDictionary *errorDictionary = GPUpdaterUIDictionaryValue([state objectForKey:@"error"]);
  if ([errorMessage length] == 0) {
    errorMessage = GPUpdaterUIStringValue([errorDictionary objectForKey:@"message"]);
  }
  if ([errorMessage length] == 0) {
    errorMessage = @"The update helper reported a failure.";
  }

  NSError *error = [NSError errorWithDomain:@"GPUpdaterUIErrorDomain"
                                       code:4
                                   userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
  [self _presentError:error];
}

- (void)_stopPollingHelperState {
  [_helperPollTimer invalidate];
  [_helperPollTimer release];
  _helperPollTimer = nil;
}

- (void)_showProgressPanelWithMessage:(NSString *)message {
  [self _dismissProgressPanel];

  NSRect frame = NSMakeRect(0, 0, 420, 120);
  _progressPanel = [[NSPanel alloc] initWithContentRect:frame
                                              styleMask:(NSTitledWindowMask)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  [_progressPanel setTitle:@"Installing Update"];

  NSView *contentView = [_progressPanel contentView];

  _progressLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 68, 380, 22)];
  [_progressLabel setEditable:NO];
  [_progressLabel setBordered:NO];
  [_progressLabel setDrawsBackground:NO];
  [_progressLabel setStringValue:message];
  [contentView addSubview:_progressLabel];

  _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 34, 380, 20)];
  [_progressIndicator setIndeterminate:YES];
  [_progressIndicator setMinValue:0.0];
  [_progressIndicator setMaxValue:100.0];
  [_progressIndicator startAnimation:self];
  [contentView addSubview:_progressIndicator];

  [_progressPanel center];
  [_progressPanel makeKeyAndOrderFront:nil];
}

- (void)_dismissProgressPanel {
  [_progressPanel orderOut:nil];
  [_progressIndicator stopAnimation:nil];
  [_progressIndicator release];
  [_progressLabel release];
  [_progressPanel release];
  _progressIndicator = nil;
  _progressLabel = nil;
  _progressPanel = nil;
}

- (NSDictionary *)_loadHelperState {
  if ([_activeStatePath length] == 0) {
    return nil;
  }

  return GPUpdaterUILoadJSONObject(_activeStatePath);
}

- (void)dealloc {
  [_updater release];
  [_helperPath release];
  [_helperStateDirectory release];
  [_helperPollTimer invalidate];
  [_helperPollTimer release];
  [_activePlanPath release];
  [_activeStatePath release];
  [_pendingInstallResult release];
  [self _dismissProgressPanel];
  [super dealloc];
}

@end
