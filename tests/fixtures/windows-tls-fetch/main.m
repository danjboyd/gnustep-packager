/* gp-tls-fetch: fetch one https URL through gnustep-base and record the result.
 *
 * Usage: gp-tls-fetch <url> <result-file>
 *
 * Writes one line to <result-file>: "PASS <status> <bytes>" or
 * "FAIL <error>". The MSI launcher is a GUI program and has no console, so
 * the result goes to a file rather than to stdout. Exit status is 0 on PASS.
 */
#import <Foundation/Foundation.h>

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int status = 2;

  if (argc < 3)
    {
      fprintf(stderr, "usage: gp-tls-fetch <url> <result-file>\n");
      [pool release];
      return 2;
    }

  NSString *urlString = [NSString stringWithUTF8String: argv[1]];
  NSString *resultPath = [NSString stringWithUTF8String: argv[2]];
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

  [line writeToFile: resultPath atomically: YES encoding: NSUTF8StringEncoding error: NULL];
  [pool release];
  return status;
}
