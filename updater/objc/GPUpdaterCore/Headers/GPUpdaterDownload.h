#import <Foundation/Foundation.h>

// Downloads for the updater: the feed and the update payload.
//
// GNUstep's -[NSData dataWithContentsOfURL:] doesn't follow HTTP redirects,
// and GitHub serves release assets through a redirect to another host. On
// Windows it also verifies TLS against gnustep-base's bundled certificate
// list, which can be older than the certificates a host uses. So:
//
// - On Windows, downloads go through WinHTTP: the system's certificate store
//   and proxy settings, redirects followed, the body streamed to its
//   destination.
// - Elsewhere, through NSURLHandle, following up to ten redirects.
// - file: URLs are read directly (tests point feeds at local files).
//
// An HTTP status other than 200 fails the download.

extern NSString *const GPUpdaterDownloadErrorDomain;

// The body of a small resource, such as the feed, or nil and *error.
NSData *GPUpdaterDownloadData(NSURL *url, NSError **error);

// Writes the resource to path (replacing it), streaming where it can.
// totalBytes, when not NULL, receives the size written.
BOOL GPUpdaterDownloadToFile(NSURL *url, NSString *path, unsigned long long *totalBytes, NSError **error);
