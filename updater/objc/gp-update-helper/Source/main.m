#import <Foundation/Foundation.h>

#if defined(_WIN32)
#import <windows.h>
#else
#import <errno.h>
#import <signal.h>
#import <unistd.h>
#endif

static NSString * const GPHelperStatusPreparing = @"preparing";
static NSString * const GPHelperStatusDownloading = @"downloading";
static NSString * const GPHelperStatusReadyToApply = @"readyToApply";
static NSString * const GPHelperStatusApplying = @"applying";
static NSString * const GPHelperStatusCompleted = @"completed";
static NSString * const GPHelperStatusManualActionRequired = @"manualActionRequired";
static NSString * const GPHelperStatusFailed = @"failed";

static NSString *GPHelperStringValue(id value) {
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSDictionary *GPHelperDictionaryValue(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSNumber *GPHelperNumberValue(id value) {
  return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSError *GPHelperSimpleError(NSInteger code, NSString *message);

static NSDictionary *GPHelperLoadJSONFile(NSString *path, NSError **error) {
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    if (error != NULL) {
      NSString *message = [NSString stringWithFormat:@"JSON file not found: %@", path];
      *error = [NSError errorWithDomain:@"GPUpdateHelperErrorDomain"
                                   code:1
                               userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
    }
    return nil;
  }

  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (object == nil || ![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL && *error == nil) {
      *error = [NSError errorWithDomain:@"GPUpdateHelperErrorDomain"
                                   code:2
                               userInfo:[NSDictionary dictionaryWithObject:@"The JSON document is not an object." forKey:NSLocalizedDescriptionKey]];
    }
    return nil;
  }

  return (NSDictionary *)object;
}

static BOOL GPHelperWriteJSONFile(NSDictionary *dictionary, NSString *path, NSError **error) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:error];
  if (data == nil) {
    return NO;
  }

  NSString *directory = [path stringByDeletingLastPathComponent];
  if ([directory length] > 0) {
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  }

  if ([data writeToFile:path atomically:YES]) {
    return YES;
  }

  if (error != NULL) {
    *error = GPHelperSimpleError(8, @"The JSON file could not be written.");
  }
  return NO;
}

static BOOL GPHelperUpdateState(NSString *statePath,
                                NSString *status,
                                NSString *message,
                                NSDictionary *progress,
                                NSDictionary *apply,
                                NSString *downloadedPath,
                                NSDictionary *errorDictionary) {
  NSError *error = nil;
  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  NSDictionary *existing = GPHelperLoadJSONFile(statePath, NULL);
  if (existing != nil) {
    [state addEntriesFromDictionary:existing];
  }

  [state setObject:[NSNumber numberWithInt:1] forKey:@"formatVersion"];
  [state setObject:status forKey:@"status"];
  [state setObject:[[NSDate date] descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%SZ"
                                                      timeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]
                                                        locale:nil] forKey:@"updatedAt"];

  if ([message length] > 0) {
    [state setObject:message forKey:@"message"];
  } else {
    [state removeObjectForKey:@"message"];
  }

  if (progress != nil) {
    [state setObject:progress forKey:@"progress"];
  } else {
    [state removeObjectForKey:@"progress"];
  }

  if (apply != nil) {
    [state setObject:apply forKey:@"apply"];
  } else {
    [state removeObjectForKey:@"apply"];
  }

  if ([downloadedPath length] > 0) {
    [state setObject:downloadedPath forKey:@"downloadedPath"];
  } else {
    [state removeObjectForKey:@"downloadedPath"];
  }

  if (errorDictionary != nil) {
    [state setObject:errorDictionary forKey:@"error"];
  } else {
    [state removeObjectForKey:@"error"];
  }

  return GPHelperWriteJSONFile(state, statePath, &error);
}

static NSString *GPHelperFindExecutable(NSArray *candidateNames) {
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *pathVariable = GPHelperStringValue([environment objectForKey:@"PATH"]);
#if defined(_WIN32)
  NSString *separator = @";";
#else
  NSString *separator = @":";
#endif
  NSArray *pathEntries = [pathVariable componentsSeparatedByString:separator];

  NSEnumerator *candidateEnumerator = [candidateNames objectEnumerator];
  NSString *candidateName = nil;
  while ((candidateName = [candidateEnumerator nextObject]) != nil) {
    if ([candidateName length] == 0) {
      continue;
    }

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidateName]) {
      return candidateName;
    }

    NSEnumerator *pathEnumerator = [pathEntries objectEnumerator];
    NSString *pathEntry = nil;
    while ((pathEntry = [pathEnumerator nextObject]) != nil) {
      NSString *candidatePath = [pathEntry stringByAppendingPathComponent:candidateName];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidatePath]) {
        return candidatePath;
      }
    }
  }

  return nil;
}

static NSDictionary *GPHelperRunTask(NSString *launchPath, NSArray *arguments) {
  NSTask *task = [[[NSTask alloc] init] autorelease];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  [task setLaunchPath:launchPath];
  [task setArguments:arguments];
  [task setStandardOutput:stdoutPipe];
  [task setStandardError:stderrPipe];

  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    return [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt:255], @"exitCode",
      [exception reason], @"stderr",
      @"", @"stdout",
      nil
    ];
  }

  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  NSString *stdoutText = [[[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] autorelease];
  NSString *stderrText = [[[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] autorelease];
  if (stdoutText == nil) {
    stdoutText = @"";
  }
  if (stderrText == nil) {
    stderrText = @"";
  }

  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt:[task terminationStatus]], @"exitCode",
    stdoutText, @"stdout",
    stderrText, @"stderr",
    nil
  ];
}

static NSError *GPHelperSimpleError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:@"GPUpdateHelperErrorDomain"
                             code:code
                         userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

static BOOL GPHelperCopyURLToPath(NSURL *url, NSString *destinationPath, NSString *statePath, NSError **error) {
  if (url == nil) {
    if (error != NULL) {
      *error = GPHelperSimpleError(3, @"The update asset URL is missing.");
    }
    return NO;
  }

  GPHelperUpdateState(statePath, GPHelperStatusDownloading, @"Downloading update...", nil, nil, nil, nil);
  NSData *data = [NSData dataWithContentsOfURL:url];
  if (data == nil) {
    if (error != NULL) {
      *error = GPHelperSimpleError(4, @"The update payload could not be downloaded.");
    }
    return NO;
  }

  NSString *directory = [destinationPath stringByDeletingLastPathComponent];
  [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
  if (![data writeToFile:destinationPath atomically:YES]) {
    if (error != NULL) {
      *error = GPHelperSimpleError(9, @"The downloaded payload could not be written to disk.");
    }
    return NO;
  }

  unsigned long long totalBytes = [data length];
  NSDictionary *progress = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithDouble:1.0], @"fractionCompleted",
    [NSNumber numberWithUnsignedLongLong:totalBytes], @"bytesReceived",
    [NSNumber numberWithUnsignedLongLong:totalBytes], @"bytesExpected",
    nil
  ];
  GPHelperUpdateState(statePath, GPHelperStatusDownloading, @"Download complete.", progress, nil, destinationPath, nil);
  return YES;
}

static NSString *GPHelperSHA256ForFile(NSString *path) {
#if defined(_WIN32)
  NSString *toolPath = GPHelperFindExecutable([NSArray arrayWithObjects:@"certutil.exe", @"certutil", nil]);
  if ([toolPath length] == 0) {
    return nil;
  }

  NSDictionary *result = GPHelperRunTask(toolPath, [NSArray arrayWithObjects:@"-hashfile", path, @"SHA256", nil]);
  NSString *stdoutText = GPHelperStringValue([result objectForKey:@"stdout"]);
  NSArray *lines = [stdoutText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSEnumerator *enumerator = [lines objectEnumerator];
  NSString *line = nil;
  while ((line = [enumerator nextObject]) != nil) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 64) {
      return [trimmed lowercaseString];
    }
  }
#else
  NSString *toolPath = GPHelperFindExecutable([NSArray arrayWithObjects:@"sha256sum", @"shasum", nil]);
  if ([toolPath length] == 0) {
    return nil;
  }

  NSArray *arguments = nil;
  if ([[toolPath lastPathComponent] isEqualToString:@"shasum"]) {
    arguments = [NSArray arrayWithObjects:@"-a", @"256", path, nil];
  } else {
    arguments = [NSArray arrayWithObjects:path, nil];
  }

  NSDictionary *result = GPHelperRunTask(toolPath, arguments);
  NSString *stdoutText = GPHelperStringValue([result objectForKey:@"stdout"]);
  NSArray *parts = [stdoutText componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([parts count] > 0) {
    NSString *value = [[parts objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value length] == 64) {
      return [value lowercaseString];
    }
  }
#endif

  return nil;
}

static BOOL GPHelperVerifySHA256(NSString *path, NSString *expectedSHA256, NSError **error) {
  if ([expectedSHA256 length] == 0) {
    return YES;
  }

  NSString *actual = GPHelperSHA256ForFile(path);
  if ([actual length] == 0) {
    if (error != NULL) {
      *error = GPHelperSimpleError(5, @"The downloaded file could not be hashed for SHA-256 verification.");
    }
    return NO;
  }

  if (![[actual lowercaseString] isEqualToString:[expectedSHA256 lowercaseString]]) {
    if (error != NULL) {
      *error = GPHelperSimpleError(6, @"The downloaded file failed SHA-256 verification.");
    }
    return NO;
  }

  return YES;
}

static BOOL GPHelperSetExecutable(NSString *path) {
#if defined(_WIN32)
  (void)path;
  return YES;
#else
  NSDictionary *result = GPHelperRunTask(@"/bin/chmod", [NSArray arrayWithObjects:@"+x", path, nil]);
  return [[result objectForKey:@"exitCode"] intValue] == 0;
#endif
}

static BOOL GPHelperWaitForPID(NSInteger pidValue) {
  if (pidValue <= 0) {
    return YES;
  }

#if defined(_WIN32)
  HANDLE processHandle = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)pidValue);
  if (processHandle == NULL) {
    return YES;
  }
  WaitForSingleObject(processHandle, INFINITE);
  CloseHandle(processHandle);
  return YES;
#else
  while (kill((pid_t)pidValue, 0) == 0 || errno == EPERM) {
    [NSThread sleepForTimeInterval:0.5];
    errno = 0;
  }
  return YES;
#endif
}

static BOOL GPHelperReplaceFile(NSString *sourcePath, NSString *destinationPath, NSError **error) {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *backupPath = [destinationPath stringByAppendingString:@".gpupdate-backup"];
  [fileManager removeItemAtPath:backupPath error:NULL];

  if ([fileManager fileExistsAtPath:destinationPath]) {
    if (![fileManager moveItemAtPath:destinationPath toPath:backupPath error:error]) {
      return NO;
    }
  }

  if (![fileManager moveItemAtPath:sourcePath toPath:destinationPath error:error]) {
    if ([fileManager fileExistsAtPath:backupPath]) {
      [fileManager moveItemAtPath:backupPath toPath:destinationPath error:NULL];
    }
    return NO;
  }

  [fileManager removeItemAtPath:backupPath error:NULL];
  return YES;
}

static BOOL GPHelperLaunchProcess(NSString *launchPath, NSArray *arguments) {
  if ([launchPath length] == 0) {
    return YES;
  }

  @try {
    [NSTask launchedTaskWithLaunchPath:launchPath arguments:arguments];
  } @catch (NSException *exception) {
    NSLog(@"Failed to relaunch %@: %@", launchPath, [exception reason]);
    return NO;
  }

  return YES;
}

static NSDictionary *GPHelperLoadApplyState(NSString *statePath, NSError **error) {
  NSDictionary *state = GPHelperLoadJSONFile(statePath, error);
  if (state == nil) {
    return nil;
  }

  NSDictionary *apply = GPHelperDictionaryValue([state objectForKey:@"apply"]);
  if (apply == nil) {
    if (error != NULL) {
      *error = GPHelperSimpleError(7, @"The state file does not include an apply plan.");
    }
    return nil;
  }

  return state;
}

static int GPHelperPrepare(NSDictionary *plan, NSString *statePath, BOOL dryRun) {
  NSDictionary *asset = GPHelperDictionaryValue([plan objectForKey:@"asset"]);
  NSDictionary *execution = GPHelperDictionaryValue([plan objectForKey:@"execution"]);
  NSDictionary *linux = GPHelperDictionaryValue([execution objectForKey:@"linux"]);
  NSString *backend = GPHelperStringValue([asset objectForKey:@"backend"]);
  NSString *assetName = GPHelperStringValue([asset objectForKey:@"name"]);
  NSString *assetURLString = GPHelperStringValue([asset objectForKey:@"url"]);
  NSString *sha256 = GPHelperStringValue([asset objectForKey:@"sha256"]);
  NSString *workingRoot = GPHelperStringValue([execution objectForKey:@"workingRoot"]);
  NSString *currentAppImagePath = GPHelperStringValue([linux objectForKey:@"currentAppImagePath"]);
  NSString *downloadRoot = [workingRoot stringByAppendingPathComponent:@"downloads"];
  NSString *downloadedPath = [downloadRoot stringByAppendingPathComponent:assetName];

  GPHelperUpdateState(statePath, GPHelperStatusPreparing, @"Preparing update...", nil, nil, nil, nil);

  if ([backend isEqualToString:@"appimage"]) {
    NSString *appImageUpdatePath = GPHelperFindExecutable([NSArray arrayWithObjects:@"AppImageUpdate", @"appimageupdatetool", nil]);
    if ([appImageUpdatePath length] > 0 && [currentAppImagePath length] > 0) {
      NSDictionary *apply = [NSDictionary dictionaryWithObjectsAndKeys:
        @"appimage-update", @"mode",
        appImageUpdatePath, @"toolPath",
        currentAppImagePath, @"currentAppImagePath",
        nil
      ];
      GPHelperUpdateState(statePath, GPHelperStatusReadyToApply, @"Restart to let AppImageUpdate apply the new version.", nil, apply, nil, nil);
      return 0;
    }
  }

  if (dryRun) {
    NSString *applyMode = [backend isEqualToString:@"msi"] ? @"msi-install" : @"appimage-replace";
    if ([backend isEqualToString:@"appimage"] && ![[NSFileManager defaultManager] isWritableFileAtPath:currentAppImagePath]) {
      applyMode = @"manual-download";
    }

    NSMutableDictionary *apply = [NSMutableDictionary dictionary];
    [apply setObject:applyMode forKey:@"mode"];
    if ([currentAppImagePath length] > 0) {
      [apply setObject:currentAppImagePath forKey:@"currentAppImagePath"];
    }
    GPHelperUpdateState(statePath,
                        [applyMode isEqualToString:@"manual-download"] ? GPHelperStatusManualActionRequired : GPHelperStatusReadyToApply,
                        dryRun ? @"Dry-run helper plan generated." : @"Update prepared.",
                        nil,
                        apply,
                        downloadedPath,
                        nil);
    return 0;
  }

  NSError *error = nil;
  if (!GPHelperCopyURLToPath([NSURL URLWithString:assetURLString], downloadedPath, statePath, &error)) {
    NSDictionary *errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
      [error localizedDescription], @"message",
      nil
    ];
    GPHelperUpdateState(statePath, GPHelperStatusFailed, @"Update download failed.", nil, nil, nil, errorDictionary);
    return 1;
  }

  if (!GPHelperVerifySHA256(downloadedPath, sha256, &error)) {
    NSDictionary *errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
      [error localizedDescription], @"message",
      nil
    ];
    GPHelperUpdateState(statePath, GPHelperStatusFailed, @"Downloaded update failed verification.", nil, nil, downloadedPath, errorDictionary);
    return 1;
  }

  if ([backend isEqualToString:@"appimage"]) {
    GPHelperSetExecutable(downloadedPath);

    if ([currentAppImagePath length] == 0 || ![[NSFileManager defaultManager] isWritableFileAtPath:currentAppImagePath]) {
      NSDictionary *apply = [NSDictionary dictionaryWithObjectsAndKeys:
        @"manual-download", @"mode",
        nil
      ];
      GPHelperUpdateState(statePath,
                          GPHelperStatusManualActionRequired,
                          @"The new AppImage was downloaded, but the current location is not writable. Install the downloaded file manually.",
                          nil,
                          apply,
                          downloadedPath,
                          nil);
      return 0;
    }

    NSDictionary *apply = [NSDictionary dictionaryWithObjectsAndKeys:
      @"appimage-replace", @"mode",
      currentAppImagePath, @"currentAppImagePath",
      nil
    ];
    GPHelperUpdateState(statePath, GPHelperStatusReadyToApply, @"Restart to finish applying the new AppImage.", nil, apply, downloadedPath, nil);
    return 0;
  }

  NSDictionary *apply = [NSDictionary dictionaryWithObjectsAndKeys:
    @"msi-install", @"mode",
    nil
  ];
  GPHelperUpdateState(statePath, GPHelperStatusReadyToApply, @"Restart to launch the MSI installer.", nil, apply, downloadedPath, nil);
  return 0;
}

static int GPHelperApply(NSDictionary *plan, NSString *statePath, NSInteger waitPID, BOOL dryRun) {
  NSError *error = nil;
  NSDictionary *state = GPHelperLoadApplyState(statePath, &error);
  if (state == nil) {
    NSDictionary *errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
      [error localizedDescription], @"message",
      nil
    ];
    GPHelperUpdateState(statePath, GPHelperStatusFailed, @"Prepared state could not be loaded.", nil, nil, nil, errorDictionary);
    return 1;
  }

  NSDictionary *apply = GPHelperDictionaryValue([state objectForKey:@"apply"]);
  NSDictionary *execution = GPHelperDictionaryValue([plan objectForKey:@"execution"]);
  NSString *relaunchPath = GPHelperStringValue([execution objectForKey:@"relaunchExecutablePath"]);
  NSString *downloadedPath = GPHelperStringValue([state objectForKey:@"downloadedPath"]);
  NSString *mode = GPHelperStringValue([apply objectForKey:@"mode"]);

  GPHelperUpdateState(statePath, GPHelperStatusApplying, @"Applying update...", nil, apply, downloadedPath, nil);

  if (dryRun) {
    GPHelperUpdateState(statePath, GPHelperStatusCompleted, @"Dry-run apply completed.", nil, apply, downloadedPath, nil);
    return 0;
  }

  GPHelperWaitForPID(waitPID);

  if ([mode isEqualToString:@"manual-download"]) {
    GPHelperUpdateState(statePath, GPHelperStatusManualActionRequired, @"The downloaded update requires manual installation.", nil, apply, downloadedPath, nil);
    return 0;
  }

  if ([mode isEqualToString:@"msi-install"]) {
    NSString *msiexecPath = GPHelperFindExecutable([NSArray arrayWithObjects:@"msiexec.exe", @"msiexec", nil]);
    if ([msiexecPath length] == 0) {
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"msiexec was not found.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:@"msiexec was not found." forKey:@"message"]);
      return 1;
    }

    NSDictionary *result = GPHelperRunTask(msiexecPath, [NSArray arrayWithObjects:@"/i", downloadedPath, nil]);
    if ([[result objectForKey:@"exitCode"] intValue] != 0) {
      NSString *stderrText = GPHelperStringValue([result objectForKey:@"stderr"]);
      if ([stderrText length] == 0) {
        stderrText = @"msiexec returned a failure exit code.";
      }
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"MSI installation failed.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:stderrText forKey:@"message"]);
      return 1;
    }

    GPHelperUpdateState(statePath, GPHelperStatusCompleted, @"MSI installation completed.", nil, apply, downloadedPath, nil);
    GPHelperLaunchProcess(relaunchPath, [NSArray array]);
    return 0;
  }

  if ([mode isEqualToString:@"appimage-update"]) {
    NSString *toolPath = GPHelperStringValue([apply objectForKey:@"toolPath"]);
    NSString *currentAppImagePath = GPHelperStringValue([apply objectForKey:@"currentAppImagePath"]);
    NSDictionary *result = GPHelperRunTask(toolPath, [NSArray arrayWithObjects:currentAppImagePath, nil]);
    if ([[result objectForKey:@"exitCode"] intValue] != 0) {
      NSString *stderrText = GPHelperStringValue([result objectForKey:@"stderr"]);
      if ([stderrText length] == 0) {
        stderrText = @"AppImageUpdate returned a failure exit code.";
      }
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"AppImageUpdate failed.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:stderrText forKey:@"message"]);
      return 1;
    }

    GPHelperUpdateState(statePath, GPHelperStatusCompleted, @"AppImageUpdate completed.", nil, apply, downloadedPath, nil);
    GPHelperLaunchProcess(relaunchPath, [NSArray array]);
    return 0;
  }

  if ([mode isEqualToString:@"appimage-replace"]) {
    NSString *currentAppImagePath = GPHelperStringValue([apply objectForKey:@"currentAppImagePath"]);
    if (![GPHelperReplaceFile(downloadedPath, currentAppImagePath, &error)]) {
      NSDictionary *errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
        [error localizedDescription], @"message",
        nil
      ];
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"The current AppImage could not be replaced.", nil, apply, downloadedPath, errorDictionary);
      return 1;
    }

    GPHelperSetExecutable(currentAppImagePath);
    GPHelperUpdateState(statePath, GPHelperStatusCompleted, @"The AppImage update was applied.", nil, apply, currentAppImagePath, nil);
    GPHelperLaunchProcess(currentAppImagePath, [NSArray array]);
    return 0;
  }

  GPHelperUpdateState(statePath, GPHelperStatusFailed, @"The helper received an unknown apply mode.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:@"Unknown apply mode." forKey:@"message"]);
  return 1;
}

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSString *mode = nil;
  NSString *planPath = nil;
  NSString *statePath = nil;
  NSInteger waitPID = 0;
  BOOL dryRun = NO;

  int index = 1;
  while (index < argc) {
    NSString *argument = [NSString stringWithUTF8String:argv[index]];
    if ([argument isEqualToString:@"--mode"] && (index + 1) < argc) {
      mode = [NSString stringWithUTF8String:argv[index + 1]];
      index += 2;
      continue;
    }
    if ([argument isEqualToString:@"--plan"] && (index + 1) < argc) {
      planPath = [NSString stringWithUTF8String:argv[index + 1]];
      index += 2;
      continue;
    }
    if ([argument isEqualToString:@"--state-file"] && (index + 1) < argc) {
      statePath = [NSString stringWithUTF8String:argv[index + 1]];
      index += 2;
      continue;
    }
    if ([argument isEqualToString:@"--wait-pid"] && (index + 1) < argc) {
      waitPID = [[NSString stringWithUTF8String:argv[index + 1]] integerValue];
      index += 2;
      continue;
    }
    if ([argument isEqualToString:@"--dry-run"]) {
      dryRun = YES;
      index += 1;
      continue;
    }

    fprintf(stderr, "Unknown argument: %s\n", argv[index]);
    [pool release];
    return 2;
  }

  if ([mode length] == 0 || [planPath length] == 0 || [statePath length] == 0) {
    fprintf(stderr, "Usage: gp-update-helper --mode <prepare|apply> --plan <path> --state-file <path> [--wait-pid <pid>] [--dry-run]\n");
    [pool release];
    return 2;
  }

  NSError *error = nil;
  NSDictionary *plan = GPHelperLoadJSONFile(planPath, &error);
  if (plan == nil) {
    NSDictionary *errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
      [error localizedDescription], @"message",
      nil
    ];
    GPHelperUpdateState(statePath, GPHelperStatusFailed, @"The helper plan could not be loaded.", nil, nil, nil, errorDictionary);
    [pool release];
    return 1;
  }

  int exitCode = 0;
  if ([mode isEqualToString:@"prepare"]) {
    exitCode = GPHelperPrepare(plan, statePath, dryRun);
  } else if ([mode isEqualToString:@"apply"]) {
    exitCode = GPHelperApply(plan, statePath, waitPID, dryRun);
  } else {
    GPHelperUpdateState(statePath, GPHelperStatusFailed, @"Unknown helper mode.", nil, nil, nil, [NSDictionary dictionaryWithObject:@"Unknown helper mode." forKey:@"message"]);
    exitCode = 2;
  }

  [pool release];
  return exitCode;
}
