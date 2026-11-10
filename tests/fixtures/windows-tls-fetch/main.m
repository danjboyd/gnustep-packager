/* gp-tls-fetch: fetch one https URL through gnustep-base and record the result.
 *
 * Usage: gp-tls-fetch <url> <result-file>
 *
 * Writes one line to <result-file>: "PASS <status> <bytes>" or
 * "FAIL <error>". The MSI launcher is a GUI program and has no console, so
 * the result goes to a file rather than to stdout. Exit status is 0 on PASS.
 * An Objective-C exception is recorded as "FAIL exception <name>: <reason>",
 * so a crash shows up as a result instead of a missing file.
 */
#import <Foundation/Foundation.h>
#include <stdio.h>

static int fetch(const char *urlArg, const char *resultArg);

static void writeRaw(const char *path, const char *line)
{
  FILE *f = fopen(path, "w");
  if (f != NULL)
    {
      fputs(line, f);
      fclose(f);
    }
}

int main(int argc, const char *argv[])
{
  if (argc < 3)
    {
      fprintf(stderr, "usage: gp-tls-fetch <url> <result-file>\n");
      return 2;
    }

  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int status = 1;
  @try
    {
      status = fetch(argv[1], argv[2]);
    }
  @catch (NSException *e)
    {
      NSString *reason = [NSString stringWithFormat: @"FAIL exception %@: %@\n",
        [e name], [e reason]];
      reason = [[reason componentsSeparatedByCharactersInSet:
        [NSCharacterSet newlineCharacterSet]] componentsJoinedByString: @" "];
      fprintf(stderr, "%s\n", [reason UTF8String]);
      writeRaw(argv[2], [[reason stringByAppendingString: @"\n"] UTF8String]);
      status = 1;
    }
  @catch (id other)
    {
      fprintf(stderr, "FAIL exception (not an NSException)\n");
      writeRaw(argv[2], "FAIL exception (not an NSException)\n");
      status = 1;
    }
  [pool release];
  return status;
}

static int fetch(const char *urlArg, const char *resultArg)
{
  int status = 2;
  NSString *urlString = [NSString stringWithUTF8String: urlArg];
  NSString *resultPath = [NSString stringWithUTF8String: resultArg];
  NSURL *url = [NSURL URLWithString: urlString];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url
    cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
    timeoutInterval: 60.0];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = [NSURLConnection sendSynchronousRequest: request
                                       returningResponse: &response
                                                   error: &error];
  NSString *line;

  if (data != nil && error == nil)
    {
      NSInteger code = 0;
      if ([response isKindOfClass: [NSHTTPURLResponse class]])
        {
          code = [(NSHTTPURLResponse *)response statusCode];
        }
      line = [NSString stringWithFormat: @"PASS %ld %lu\n",
        (long)code, (unsigned long)[data length]];
      status = 0;
    }
  else
    {
      NSString *reason = (error != nil) ? [error description] : @"no data and no error";
      reason = [[reason componentsSeparatedByCharactersInSet:
        [NSCharacterSet newlineCharacterSet]] componentsJoinedByString: @" "];
      line = [NSString stringWithFormat: @"FAIL %@\n", reason];
      status = 1;
    }

  if (![line writeToFile: resultPath atomically: YES encoding: NSUTF8StringEncoding error: NULL])
    {
      writeRaw(resultArg, [line UTF8String]);
    }
  return status;
}
