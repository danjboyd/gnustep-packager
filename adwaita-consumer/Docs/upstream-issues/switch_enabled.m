/* A switch made in code should start enabled, as in Cocoa.
 *
 * Build: clang `gnustep-config --objc-flags` switch_enabled.m \
 *          `gnustep-config --gui-libs` -o switch_enabled
 * Run:   ./switch_enabled
 */

#import <AppKit/AppKit.h>
#include <stdio.h>

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSSwitch *aSwitch;
  BOOL enabled;

  [NSApplication sharedApplication];
  aSwitch = [[NSSwitch alloc] initWithFrame: NSMakeRect (0, 0, 48, 26)];
  enabled = [aSwitch isEnabled];
  printf ("new switch: isEnabled %s  %s\n", enabled ? "YES" : "NO",
          enabled ? "PASS" : "FAIL");
  [aSwitch release];
  [pool release];
  return enabled ? 0 : 1;
}
