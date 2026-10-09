#import "GPUpdaterDownload.h"

#if defined(_WIN32)
#include "GPUpdaterWinHTTP.h"
#endif

NSString *const GPUpdaterDownloadErrorDomain = @"GPUpdaterDownloadErrorDomain";

typedef NS_ENUM(NSInteger, GPUpdaterDownloadErrorCode) {
  GPUpdaterDownloadErrorInvalidURL = 1,
  GPUpdaterDownloadErrorNetwork = 2,
  GPUpdaterDownloadErrorHTTPStatus = 3,
  GPUpdaterDownloadErrorTooManyRedirects = 4,
  GPUpdaterDownloadErrorWriteFailed = 5,
};

static NSError *GPDownloadError(NSInteger code, NSString *description) {
  return [NSError errorWithDomain:GPUpdaterDownloadErrorDomain
                             code:code
                         userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

// Opens path for writing, empty. Returns nil if it can't.
static NSFileHandle *GPDownloadOpenForWriting(NSString *path) {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  [fileManager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
         withIntermediateDirectories:YES
                          attributes:nil
                               error:NULL];
  [fileManager removeItemAtPath:path error:NULL];
  if (![fileManager createFileAtPath:path contents:[NSData data] attributes:nil]) {
    return nil;
  }
  return [NSFileHandle fileHandleForWritingAtPath:path];
}

// Moves the finished download into place.
static BOOL GPDownloadMoveIntoPlace(NSString *partialPath, NSString *path, NSError **error) {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  [fileManager removeItemAtPath:path error:NULL];
  if (![fileManager moveItemAtPath:partialPath toPath:path error:NULL]) {
    [fileManager removeItemAtPath:partialPath error:NULL];
    if (error != NULL) {
      *error = GPDownloadError(GPUpdaterDownloadErrorWriteFailed, @"The download could not be moved into place.");
    }
    return NO;
  }
  return YES;
}

#if defined(_WIN32)

// Where the WinHTTP body goes: memory or an open file.
typedef struct {
  NSMutableData *data;
  NSFileHandle *handle;
  unsigned long long total;
  BOOL writeFailed;
} GPDownloadSink;

static int GPDownloadSinkWrite(void *context, const void *bytes, unsigned long length) {
  GPDownloadSink *sink = (GPDownloadSink *)context;
  NSData *chunk = [NSData dataWithBytesNoCopy:(void *)bytes length:length freeWhenDone:NO];

  if (sink->data != nil) {
    [sink->data appendData:chunk];
  } else {
    @try {
      [sink->handle writeData:chunk];
    } @catch (NSException *exception) {
      sink->writeFailed = YES;
      return 0;
    }
  }
  sink->total += length;
  return 1;
}

// GET through WinHTTP, with the body appended to data or written to handle.
static BOOL GPDownloadWinHTTP(NSURL *url, NSMutableData *data, NSFileHandle *handle,
                              unsigned long long *totalBytes, NSError **error) {
  NSString *string = [url absoluteString];
  NSUInteger length = [string length];
  NSMutableData *wideURL = [NSMutableData dataWithLength:(length + 1) * sizeof(wchar_t)];
  GPDownloadSink sink;
  unsigned long status = 0;
  unsigned long systemError = 0;

  [string getCharacters:(unichar *)[wideURL mutableBytes] range:NSMakeRange(0, length)];
  sink.data = data;
  sink.handle = handle;
  sink.total = 0;
  sink.writeFailed = NO;
  if (GPUpdaterWinHTTPGet([wideURL bytes], GPDownloadSinkWrite, &sink, &status, &systemError)) {
    if (totalBytes != NULL) {
      *totalBytes = sink.total;
    }
    return YES;
  }
  if (error != NULL) {
    if (sink.writeFailed) {
      *error = GPDownloadError(GPUpdaterDownloadErrorWriteFailed, @"The download could not be written to disk.");
    } else if (status != 0 && status != 200) {
      *error = GPDownloadError(GPUpdaterDownloadErrorHTTPStatus,
                               [NSString stringWithFormat:@"The server answered HTTP %lu.", status]);
    } else {
      *error = GPDownloadError(GPUpdaterDownloadErrorNetwork,
                               [NSString stringWithFormat:@"The download failed (Windows error %lu).", systemError]);
    }
  }
  return NO;
}

#else

// GET through NSURLHandle, following redirects ourselves.
static NSData *GPDownloadURLHandle(NSURL *url, NSError **error) {
  NSURL *current = url;
  NSUInteger redirects = 0;

  while (current != nil) {
    NSURLHandle *handle = [current URLHandleUsingCache:NO];
    NSData *body = [handle resourceData];
    NSInteger status = [[handle propertyForKeyIfAvailable:NSHTTPPropertyStatusCodeKey] integerValue];

    if (status >= 300 && status < 400) {
      NSString *location = [handle propertyForKeyIfAvailable:@"Location"];
      if (location == nil) {
        location = [handle propertyForKeyIfAvailable:@"location"];
      }
      if (location == nil) {
        break;
      }
      if (++redirects > 10) {
        if (error != NULL) {
          *error = GPDownloadError(GPUpdaterDownloadErrorTooManyRedirects, @"The download was redirected too many times.");
        }
        return nil;
      }
      current = [NSURL URLWithString:location relativeToURL:current];
      continue;
    }
    if (body == nil || (status != 0 && status != 200)) {
      if (error != NULL) {
        *error = status != 0
          ? GPDownloadError(GPUpdaterDownloadErrorHTTPStatus, [NSString stringWithFormat:@"The server answered HTTP %ld.", (long)status])
          : GPDownloadError(GPUpdaterDownloadErrorNetwork, @"The server could not be reached.");
      }
      return nil;
    }
    return body;
  }
  if (error != NULL) {
    *error = GPDownloadError(GPUpdaterDownloadErrorNetwork, @"The download URL could not be resolved.");
  }
  return nil;
}

#endif

NSData *GPUpdaterDownloadData(NSURL *url, NSError **error) {
  if (url == nil) {
    if (error != NULL) {
      *error = GPDownloadError(GPUpdaterDownloadErrorInvalidURL, @"The download URL is missing.");
    }
    return nil;
  }
  if ([url isFileURL]) {
    NSData *data = [NSData dataWithContentsOfFile:[url path]];
    if (data == nil && error != NULL) {
      *error = GPDownloadError(GPUpdaterDownloadErrorNetwork, @"The file could not be read.");
    }
    return data;
  }
#if defined(_WIN32)
  NSMutableData *data = [NSMutableData data];
  return GPDownloadWinHTTP(url, data, nil, NULL, error) ? data : nil;
#else
  return GPDownloadURLHandle(url, error);
#endif
}

BOOL GPUpdaterDownloadToFile(NSURL *url, NSString *path, unsigned long long *totalBytes, NSError **error) {
  NSString *partialPath = [path stringByAppendingString:@".part"];

  if (url == nil) {
    if (error != NULL) {
      *error = GPDownloadError(GPUpdaterDownloadErrorInvalidURL, @"The download URL is missing.");
    }
    return NO;
  }

#if defined(_WIN32)
  if (![url isFileURL]) {
    NSFileHandle *handle = GPDownloadOpenForWriting(partialPath);
    if (handle == nil) {
      if (error != NULL) {
        *error = GPDownloadError(GPUpdaterDownloadErrorWriteFailed, @"The download could not be written to disk.");
      }
      return NO;
    }
    BOOL ok = GPDownloadWinHTTP(url, nil, handle, totalBytes, error);
    [handle closeFile];
    if (!ok) {
      [[NSFileManager defaultManager] removeItemAtPath:partialPath error:NULL];
      return NO;
    }
    return GPDownloadMoveIntoPlace(partialPath, path, error);
  }
#endif

  NSData *data = GPUpdaterDownloadData(url, error);
  if (data == nil) {
    return NO;
  }
  NSFileHandle *handle = GPDownloadOpenForWriting(partialPath);
  BOOL written = NO;
  if (handle != nil) {
    @try {
      [handle writeData:data];
      written = YES;
    } @catch (NSException *exception) {
      written = NO;
    }
    [handle closeFile];
  }
  if (!written) {
    [[NSFileManager defaultManager] removeItemAtPath:partialPath error:NULL];
    if (error != NULL) {
      *error = GPDownloadError(GPUpdaterDownloadErrorWriteFailed, @"The download could not be written to disk.");
    }
    return NO;
  }
  if (totalBytes != NULL) {
    *totalBytes = [data length];
  }
  return GPDownloadMoveIntoPlace(partialPath, path, error);
}
