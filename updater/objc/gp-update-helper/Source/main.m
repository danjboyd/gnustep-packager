#import <Foundation/Foundation.h>
#import "GPUpdaterDownload.h"
#import "monocypher/monocypher-ed25519.h"

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

// Windows names the variable "Path", and a process started by the MSI
// launcher keeps that spelling, so the lookup must ignore case there.
static NSString *GPHelperPathVariable(void) {
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
#if defined(_WIN32)
  NSEnumerator *keyEnumerator = [environment keyEnumerator];
  NSString *key = nil;
  while ((key = [keyEnumerator nextObject]) != nil) {
    if ([key caseInsensitiveCompare:@"PATH"] == NSOrderedSame) {
      return GPHelperStringValue([environment objectForKey:key]);
    }
  }
  return nil;
#else
  return GPHelperStringValue([environment objectForKey:@"PATH"]);
#endif
}

#if defined(_WIN32)
// System tools (certutil, msiexec) come from the system directory, never
// from PATH or the working directory.
static NSString *GPHelperSystemExecutable(NSString *name) {
  wchar_t directory[MAX_PATH];
  UINT length = GetSystemDirectoryW(directory, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return nil;
  }

  NSString *systemDirectory = [NSString stringWithCharacters:(const unichar *)directory length:length];
  NSString *path = [systemDirectory stringByAppendingPathComponent:name];
  return [[NSFileManager defaultManager] isExecutableFileAtPath:path] ? path : nil;
}
#endif

static NSString *GPHelperFindExecutable(NSArray *candidateNames) {
  NSString *pathVariable = GPHelperPathVariable();
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

    // A bare name is only looked up on PATH, never in the working directory.
    if ([candidateName isAbsolutePath] && [[NSFileManager defaultManager] isExecutableFileAtPath:candidateName]) {
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
  unsigned long long totalBytes = 0;
  NSError *downloadError = nil;
  if (!GPUpdaterDownloadToFile(url, destinationPath, &totalBytes, &downloadError)) {
    if (error != NULL) {
      NSString *reason = [downloadError localizedDescription];
      *error = GPHelperSimpleError(4, [reason length] > 0
        ? [NSString stringWithFormat:@"The update payload could not be downloaded: %@", reason]
        : @"The update payload could not be downloaded.");
    }
    return NO;
  }


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
  NSString *toolPath = GPHelperSystemExecutable(@"certutil.exe");
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

static NSData *GPHelperBase64Data(NSString *value) {
  if ([value length] == 0) {
    return nil;
  }
  return [[[NSData alloc] initWithBase64EncodedString:value
                                              options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
}

// Checks the Ed25519 signature (base64, over the file's bytes, as
// Sparkle's sign_update makes) against the public key (base64, 32 bytes).
static BOOL GPHelperVerifyEdSignature(NSString *path, NSString *signature, NSString *publicKey, NSError **error) {
  NSData *keyData = GPHelperBase64Data(publicKey);
  if ([keyData length] != 32) {
    if (error != NULL) {
      *error = GPHelperSimpleError(10, @"The app's update signing key is not valid.");
    }
    return NO;
  }

  NSData *signatureData = GPHelperBase64Data(signature);
  if ([signatureData length] != 64) {
    if (error != NULL) {
      *error = GPHelperSimpleError(11, [signature length] == 0 ? @"The update is not signed." : @"The update's signature is not valid.");
    }
    return NO;
  }

  NSData *fileData = [NSData dataWithContentsOfMappedFile:path];
  if (fileData == nil) {
    if (error != NULL) {
      *error = GPHelperSimpleError(12, @"The downloaded file could not be read to check its signature.");
    }
    return NO;
  }

  if (crypto_ed25519_check((const uint8_t *)[signatureData bytes],
                           (const uint8_t *)[keyData bytes],
                           (const uint8_t *)[fileData bytes],
                           (size_t)[fileData length]) != 0) {
    if (error != NULL) {
      *error = GPHelperSimpleError(13, @"The downloaded file's signature does not match: it was not signed by the app's publisher, or it was changed.");
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

// How long the helper waits for the app to quit before applying. The app
// may not quit at all: its user can cancel Quit (unsaved documents).
static const NSTimeInterval GPHelperQuitTimeout = 120.0;

// YES once the process has gone, NO if it is still running after the
// timeout.
static BOOL GPHelperWaitForPID(NSInteger pidValue, NSTimeInterval timeout) {
  if (pidValue <= 0) {
    return YES;
  }

#if defined(_WIN32)
  HANDLE processHandle = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)pidValue);
  if (processHandle == NULL) {
    return YES;
  }
  DWORD waited = WaitForSingleObject(processHandle, (DWORD)(timeout * 1000.0));
  CloseHandle(processHandle);
  return waited != WAIT_TIMEOUT;
#else
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (kill((pid_t)pidValue, 0) == 0 || errno == EPERM) {
    if ([deadline timeIntervalSinceNow] <= 0) {
      return NO;
    }
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

#if !defined(_WIN32)
// A single-quoted shell word.
static NSString *GPHelperShellQuote(NSString *value) {
  NSString *escaped = [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
  return [NSString stringWithFormat:@"'%@'", escaped];
}

// The script that applies an AppImage update once the app has quit, run
// with the system's /bin/sh. The helper and its libraries are inside the
// AppImage, whose mount goes when the app quits, so applying can't rely on
// anything there. The script waits for the app (giving up after two
// minutes, when quitting was cancelled), then either swaps the downloaded
// AppImage in (appimage-replace) or has appimageupdatetool overwrite the
// current one (appimage-update), and starts the AppImage at its path again.
static NSString *GPHelperWriteAppImageApplyScript(NSString *workingRoot,
                                                  NSString *mode,
                                                  NSString *currentAppImagePath,
                                                  NSString *downloadedPath,
                                                  NSString *toolPath,
                                                  NSString *statePath) {
  NSMutableString *script = [NSMutableString string];
  [script appendString:@"#!/bin/sh\n"
    "# Written by gp-update-helper; run as: sh apply-appimage.sh <app pid>\n"
    "unset LD_LIBRARY_PATH LD_PRELOAD APPDIR APPIMAGE ARGV0 OWD GNUSTEP_PATHPREFIX_LIST\n"];
  [script appendFormat:@"current=%@\n", GPHelperShellQuote(currentAppImagePath)];
  [script appendFormat:@"downloaded=%@\n", GPHelperShellQuote(downloadedPath != nil ? downloadedPath : @"")];
  [script appendFormat:@"tool=%@\n", GPHelperShellQuote(toolPath != nil ? toolPath : @"")];
  [script appendFormat:@"state=%@\n", GPHelperShellQuote(statePath)];
  [script appendFormat:@"mode=%@\n", GPHelperShellQuote(mode)];
  [script appendString:
    @"exec >>\"${state%/*}/apply-appimage.log\" 2>&1\n"
    "state() {\n"
    "  printf '{\"formatVersion\": 1, \"status\": \"%s\", \"message\": \"%s\"}\\n' \"$1\" \"$2\" >\"$state.tmp\" && mv \"$state.tmp\" \"$state\"\n"
    "}\n"
    "pid=\"$1\"\n"
    "waited=0\n"
    "while [ -n \"$pid\" ] && kill -0 \"$pid\" 2>/dev/null; do\n"
    "  if [ \"$waited\" -ge 240 ]; then\n"
    "    state readyToApply 'The app did not quit, so the update was not applied.'\n"
    "    exit 1\n"
    "  fi\n"
    "  sleep 0.5\n"
    "  waited=$((waited + 1))\n"
    "done\n"
    "state applying 'Applying update...'\n"
    "if [ \"$mode\" = appimage-update ]; then\n"
    "  if ! \"$tool\" -O \"$current\"; then\n"
    "    state failed 'appimageupdatetool could not update the AppImage.'\n"
    "    exit 1\n"
    "  fi\n"
    "else\n"
    "  # Copied next to the current file first, so the swap is a rename\n"
    "  # within one directory.\n"
    "  new=\"$current.gpupdate-new\"\n"
    "  backup=\"$current.gpupdate-backup\"\n"
    "  rm -f \"$new\" \"$backup\"\n"
    "  if ! cp \"$downloaded\" \"$new\" || ! chmod +x \"$new\"; then\n"
    "    rm -f \"$new\"\n"
    "    state failed 'The new AppImage could not be copied next to the current one.'\n"
    "    exit 1\n"
    "  fi\n"
    "  if ! mv \"$current\" \"$backup\"; then\n"
    "    rm -f \"$new\"\n"
    "    state failed 'The current AppImage could not be replaced.'\n"
    "    exit 1\n"
    "  fi\n"
    "  if ! mv \"$new\" \"$current\"; then\n"
    "    mv \"$backup\" \"$current\"\n"
    "    rm -f \"$new\"\n"
    "    state failed 'The current AppImage could not be replaced.'\n"
    "    exit 1\n"
    "  fi\n"
    "  rm -f \"$backup\" \"$downloaded\"\n"
    "fi\n"
    "state completed 'The AppImage update was applied.'\n"
    "nohup \"$current\" >/dev/null 2>&1 </dev/null &\n"
    "exit 0\n"];

  NSString *scriptPath = [workingRoot stringByAppendingPathComponent:@"apply-appimage.sh"];
  [[NSFileManager defaultManager] createDirectoryAtPath:workingRoot withIntermediateDirectories:YES attributes:nil error:NULL];
  if (![[script dataUsingEncoding:NSUTF8StringEncoding] writeToFile:scriptPath atomically:YES]) {
    return nil;
  }
  return scriptPath;
}
#endif

#if defined(_WIN32)
// GNUstep writes Windows paths with '/', and Windows Installer drops the
// drive from such a path (error 1619, package not found).
static NSString *GPHelperWindowsPath(NSString *path) {
  return [path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
}

// A value for set "NAME=value" in a .cmd file: only '%' is special there.
static NSString *GPHelperCmdValue(NSString *value) {
  return [GPHelperWindowsPath(value != nil ? value : @"") stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
}

// The script that installs an MSI update and starts the app again, run with
// the system's cmd.exe. The helper runs from the install folder and loads
// the runtime DLLs there, so Windows Installer's Restart Manager closes it
// partway through the install; the script uses nothing in that folder. It
// records the outcome in the state file, as the helper would, and starts
// the app (relaunchPath, the package's launcher) after an install, unless
// Windows is already restarting (1641). The paths are set with
// set "NAME=value" and always used quoted, so spaces, '&', '^' and '('
// in them are literal; '%' is doubled.
static NSString *GPHelperWriteMSIApplyScript(NSString *statePath,
                                             NSString *msiexecPath,
                                             NSString *packagePath,
                                             NSString *logPath,
                                             NSString *relaunchPath) {
  NSMutableString *script = [NSMutableString string];
  [script appendString:@"@echo off\r\n"
    "rem Written by gp-update-helper; run as: cmd.exe /d /c apply-msi.cmd\r\n"
    "chcp 65001 >nul\r\n"
    "setlocal\r\n"];
  [script appendFormat:@"set \"STATE=%@\"\r\n", GPHelperCmdValue(statePath)];
  [script appendFormat:@"set \"MSIEXEC=%@\"\r\n", GPHelperCmdValue(msiexecPath)];
  [script appendFormat:@"set \"PACKAGE=%@\"\r\n", GPHelperCmdValue(packagePath)];
  [script appendFormat:@"set \"LOG=%@\"\r\n", GPHelperCmdValue(logPath)];
  [script appendFormat:@"set \"APP=%@\"\r\n", GPHelperCmdValue(relaunchPath)];
  [script appendString:
    @"rem A progress window but no questions (/passive), no reboot by the\r\n"
    "rem installer (/norestart; 3010 and 1641 mean one is needed or under\r\n"
    "rem way, and the update is still installed), and a verbose log.\r\n"
    "\"%MSIEXEC%\" /i \"%PACKAGE%\" /passive /norestart /l*v \"%LOG%\"\r\n"
    "set \"CODE=%ERRORLEVEL%\"\r\n"
    "if \"%CODE%\"==\"0\" goto installed\r\n"
    "if \"%CODE%\"==\"3010\" goto installedRestart\r\n"
    "if \"%CODE%\"==\"1641\" goto installedRestarting\r\n"
    "if \"%CODE%\"==\"1602\" goto cancelled\r\n"
    "echo {\"formatVersion\": 1, \"status\": \"failed\", \"message\": \"MSI installation failed.\", \"error\": {\"message\": \"msiexec exit code %CODE%; see msiexec.log beside the state file\"}}>\"%STATE%.tmp\"\r\n"
    "goto finish\r\n"
    ":cancelled\r\n"
    "echo {\"formatVersion\": 1, \"status\": \"failed\", \"message\": \"The MSI installation was cancelled.\", \"error\": {\"message\": \"msiexec exit code 1602: cancelled by the user.\"}}>\"%STATE%.tmp\"\r\n"
    "goto finish\r\n"
    ":installedRestarting\r\n"
    "echo {\"formatVersion\": 1, \"status\": \"completed\", \"message\": \"MSI installation completed; Windows is restarting to finish it.\"}>\"%STATE%.tmp\"\r\n"
    "move /y \"%STATE%.tmp\" \"%STATE%\" >nul\r\n"
    "exit /b 0\r\n"
    ":installedRestart\r\n"
    "echo {\"formatVersion\": 1, \"status\": \"completed\", \"message\": \"MSI installation completed; Windows needs a restart to finish it.\"}>\"%STATE%.tmp\"\r\n"
    "goto relaunch\r\n"
    ":installed\r\n"
    "echo {\"formatVersion\": 1, \"status\": \"completed\", \"message\": \"MSI installation completed.\"}>\"%STATE%.tmp\"\r\n"
    ":relaunch\r\n"
    "move /y \"%STATE%.tmp\" \"%STATE%\" >nul\r\n"
    "if defined APP start \"\" \"%APP%\"\r\n"
    "exit /b 0\r\n"
    ":finish\r\n"
    "move /y \"%STATE%.tmp\" \"%STATE%\" >nul\r\n"
    "exit /b 1\r\n"];

  NSString *scriptPath = [[statePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"apply-msi.cmd"];
  if (![[script dataUsingEncoding:NSUTF8StringEncoding] writeToFile:scriptPath atomically:YES]) {
    return nil;
  }
  return scriptPath;
}

// Starts cmd.exe on the script with no window, no inherited handles and the
// script's directory as the working directory, so nothing it holds is in
// the install folder, and does not wait for it.
static BOOL GPHelperLaunchMSIApplyScript(NSString *scriptPath) {
  NSString *cmdPath = GPHelperSystemExecutable(@"cmd.exe");
  if ([cmdPath length] == 0) {
    return NO;
  }
  // GNUstep joins the system directory and the name with '/', and cmd.exe
  // reads "/system32/cmd.exe" in its own command line as /s and /c, so it
  // would never run the script.
  cmdPath = GPHelperWindowsPath(cmdPath);

  NSString *windowsScriptPath = GPHelperWindowsPath(scriptPath);
  NSString *workingDirectory = [windowsScriptPath stringByDeletingLastPathComponent];
  workingDirectory = GPHelperWindowsPath(workingDirectory);
  // cmd /c drops the outer quotes, leaving the quoted script path.
  NSString *commandLine = [NSString stringWithFormat:@"\"%@\" /d /c \"\"%@\"\"", cmdPath, windowsScriptPath];

  NSUInteger cmdLength = [cmdPath length];
  NSUInteger commandLength = [commandLine length];
  NSUInteger directoryLength = [workingDirectory length];
  unichar *cmdBuffer = calloc(cmdLength + 1, sizeof(unichar));
  unichar *commandBuffer = calloc(commandLength + 1, sizeof(unichar));
  unichar *directoryBuffer = calloc(directoryLength + 1, sizeof(unichar));
  if (cmdBuffer == NULL || commandBuffer == NULL || directoryBuffer == NULL) {
    free(cmdBuffer);
    free(commandBuffer);
    free(directoryBuffer);
    return NO;
  }
  [cmdPath getCharacters:cmdBuffer];
  [commandLine getCharacters:commandBuffer];
  [workingDirectory getCharacters:directoryBuffer];

  STARTUPINFOW startupInfo;
  PROCESS_INFORMATION processInfo;
  ZeroMemory(&startupInfo, sizeof(startupInfo));
  startupInfo.cb = sizeof(startupInfo);
  ZeroMemory(&processInfo, sizeof(processInfo));
  BOOL launched = CreateProcessW((LPCWSTR)cmdBuffer, (LPWSTR)commandBuffer, NULL, NULL, FALSE,
                                 CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP, NULL,
                                 (LPCWSTR)directoryBuffer, &startupInfo, &processInfo);
  free(cmdBuffer);
  free(commandBuffer);
  free(directoryBuffer);
  if (!launched) {
    return NO;
  }

  CloseHandle(processInfo.hThread);
  CloseHandle(processInfo.hProcess);
  return YES;
}
#endif

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
  NSDictionary *package = GPHelperDictionaryValue([plan objectForKey:@"package"]);
  NSDictionary *execution = GPHelperDictionaryValue([plan objectForKey:@"execution"]);
  NSDictionary *linuxInfo = GPHelperDictionaryValue([execution objectForKey:@"linux"]);
  NSString *backend = GPHelperStringValue([asset objectForKey:@"backend"]);
  NSString *assetName = GPHelperStringValue([asset objectForKey:@"name"]);
  NSString *assetURLString = GPHelperStringValue([asset objectForKey:@"url"]);
  NSString *sha256 = GPHelperStringValue([asset objectForKey:@"sha256"]);
  // With a public key, every payload must carry a valid signature; without
  // one (configs from before signing) the SHA-256 alone is checked.
  NSString *publicEDKey = GPHelperStringValue([package objectForKey:@"publicEDKey"]);
  NSString *edSignature = GPHelperStringValue([asset objectForKey:@"edSignature"]);
  NSString *workingRoot = GPHelperStringValue([execution objectForKey:@"workingRoot"]);
  NSString *currentAppImagePath = GPHelperStringValue([linuxInfo objectForKey:@"currentAppImagePath"]);
  NSString *downloadRoot = [workingRoot stringByAppendingPathComponent:@"downloads"];
  NSString *downloadedPath = [downloadRoot stringByAppendingPathComponent:assetName];

  GPHelperUpdateState(statePath, GPHelperStatusPreparing, @"Preparing update...", nil, nil, nil, nil);

  // appimageupdatetool checks only the .zsync file's hashes, so with a
  // signing key the helper downloads and checks the AppImage itself.
  if ([backend isEqualToString:@"appimage"] && [publicEDKey length] == 0) {
    // appimageupdatetool, not the AppImageUpdate GUI: run with -O it
    // overwrites the current AppImage, so starting it again starts the
    // new version.
    NSString *appImageUpdatePath = GPHelperFindExecutable([NSArray arrayWithObjects:@"appimageupdatetool", nil]);
    if ([appImageUpdatePath length] > 0 && [currentAppImagePath length] > 0 &&
        [[NSFileManager defaultManager] isWritableFileAtPath:[currentAppImagePath stringByDeletingLastPathComponent]]) {
      NSMutableDictionary *apply = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        @"appimage-update", @"mode",
        appImageUpdatePath, @"toolPath",
        currentAppImagePath, @"currentAppImagePath",
        nil
      ];
#if !defined(_WIN32)
      NSString *scriptPath = GPHelperWriteAppImageApplyScript(workingRoot, @"appimage-update", currentAppImagePath, nil, appImageUpdatePath, statePath);
      if ([scriptPath length] > 0) {
        [apply setObject:scriptPath forKey:@"script"];
      }
#endif
      GPHelperUpdateState(statePath, GPHelperStatusReadyToApply, @"Restart to let AppImageUpdate apply the new version.", nil, apply, nil, nil);
      return 0;
    }
  }

  if (dryRun) {
    NSString *applyMode = [backend isEqualToString:@"msi"] ? @"msi-install" : @"appimage-replace";
    if ([backend isEqualToString:@"appimage"] && ![[NSFileManager defaultManager] isWritableFileAtPath:[currentAppImagePath stringByDeletingLastPathComponent]]) {
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

  if ([publicEDKey length] > 0 && !GPHelperVerifyEdSignature(downloadedPath, edSignature, publicEDKey, &error)) {
    [[NSFileManager defaultManager] removeItemAtPath:downloadedPath error:NULL];
    NSDictionary *errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
      [error localizedDescription], @"message",
      nil
    ];
    GPHelperUpdateState(statePath, GPHelperStatusFailed, @"Downloaded update failed verification.", nil, nil, nil, errorDictionary);
    return 1;
  }

  if ([backend isEqualToString:@"appimage"]) {
    GPHelperSetExecutable(downloadedPath);

    // Replacing the AppImage renames files in its directory.
    if ([currentAppImagePath length] == 0 ||
        ![[NSFileManager defaultManager] isWritableFileAtPath:[currentAppImagePath stringByDeletingLastPathComponent]]) {
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

    NSMutableDictionary *apply = [NSMutableDictionary dictionaryWithObjectsAndKeys:
      @"appimage-replace", @"mode",
      currentAppImagePath, @"currentAppImagePath",
      nil
    ];
#if !defined(_WIN32)
    NSString *scriptPath = GPHelperWriteAppImageApplyScript(workingRoot, @"appimage-replace", currentAppImagePath, downloadedPath, nil, statePath);
    if ([scriptPath length] > 0) {
      [apply setObject:scriptPath forKey:@"script"];
    }
#endif
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

  if (!GPHelperWaitForPID(waitPID, GPHelperQuitTimeout)) {
    // Quit was cancelled: leave the update ready, as the AppImage apply
    // script does, rather than install under a running app.
    GPHelperUpdateState(statePath, GPHelperStatusReadyToApply, @"The app did not quit, so the update was not applied.", nil, apply, downloadedPath, nil);
    return 0;
  }

  if ([mode isEqualToString:@"manual-download"]) {
    GPHelperUpdateState(statePath, GPHelperStatusManualActionRequired, @"The downloaded update requires manual installation.", nil, apply, downloadedPath, nil);
    return 0;
  }

  if ([mode isEqualToString:@"msi-install"]) {
#if defined(_WIN32)
    NSString *msiexecPath = GPHelperSystemExecutable(@"msiexec.exe");
#else
    NSString *msiexecPath = GPHelperFindExecutable([NSArray arrayWithObjects:@"msiexec.exe", @"msiexec", nil]);
#endif
    if ([msiexecPath length] == 0) {
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"msiexec was not found.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:@"msiexec was not found." forKey:@"message"]);
      return 1;
    }

    // A progress window but no questions (/passive), no reboot by the
    // installer (/norestart; 3010 and 1641 mean one is needed or under
    // way, and the update is still installed), and a verbose log beside
    // the state file for when it fails.
    NSString *logPath = [[statePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"msiexec.log"];
#if defined(_WIN32)
    // Restart Manager would close this helper partway through the install
    // (it runs from the install folder), before it records the result and
    // starts the app again, so a script outside the folder does all three.
    NSString *scriptPath = GPHelperWriteMSIApplyScript(statePath, msiexecPath, downloadedPath, logPath, relaunchPath);
    if ([scriptPath length] == 0 || !GPHelperLaunchMSIApplyScript(scriptPath)) {
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"The MSI install could not be started.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:@"The apply-msi.cmd script could not be written or started." forKey:@"message"]);
      return 1;
    }
    return 0;
#else
    NSArray *arguments = [NSArray arrayWithObjects:@"/i", downloadedPath, @"/passive", @"/norestart", @"/l*v", logPath, nil];
    NSDictionary *result = GPHelperRunTask(msiexecPath, arguments);
    int exitCode = [[result objectForKey:@"exitCode"] intValue];
    if (exitCode == 1602) {
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"The MSI installation was cancelled.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:@"msiexec exit code 1602: cancelled by the user." forKey:@"message"]);
      return 1;
    }
    if (exitCode != 0 && exitCode != 3010 && exitCode != 1641) {
      NSString *message = [NSString stringWithFormat:@"msiexec exit code %d; see %@", exitCode, logPath];
      GPHelperUpdateState(statePath, GPHelperStatusFailed, @"MSI installation failed.", nil, apply, downloadedPath, [NSDictionary dictionaryWithObject:message forKey:@"message"]);
      return 1;
    }

    GPHelperUpdateState(statePath, GPHelperStatusCompleted,
      (exitCode == 0 ? @"MSI installation completed." : @"MSI installation completed; Windows needs a restart to finish it."),
      nil, apply, downloadedPath, nil);
    GPHelperLaunchProcess(relaunchPath, [NSArray array]);
    return 0;
#endif
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
    if (!GPHelperReplaceFile(downloadedPath, currentAppImagePath, &error)) {
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
