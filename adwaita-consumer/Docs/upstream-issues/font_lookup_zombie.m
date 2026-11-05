/* A font lookup after the autorelease pool that ran the first one drains.
 * The first lookup sets up the font roles' default names; the second one
 * reads them again.
 *
 * Build: clang `gnustep-config --objc-flags` font_lookup_zombie.m \
 *          `gnustep-config --gui-libs` -o font_lookup_zombie
 * Run:   NSZombieEnabled=YES ./font_lookup_zombie
 *        with empty user defaults (no NSFont or NSBoldFont), so the font
 *        roles fall back to the backend's default names. The bug shows as
 *        "message sent to deallocated instance" on stderr, and the second
 *        lookup getting the regular face instead of the bold one; with
 *        zombies off it can crash instead.
 */

#import <AppKit/AppKit.h>
#include <stdio.h>

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *outer = [NSAutoreleasePool new];
  NSAutoreleasePool *pool;
  NSFont *font;

  [NSApplication sharedApplication];

  pool = [NSAutoreleasePool new];
  font = [NSFont systemFontOfSize: 0];
  printf ("first lookup:  %s\n", [[font fontName] UTF8String]);
  [pool release];

  pool = [NSAutoreleasePool new];
  font = [NSFont boldSystemFontOfSize: 0];
  printf ("second lookup: %s\n", [[font fontName] UTF8String]);
  [pool release];

  printf ("PASS\n");
  [outer release];
  return 0;
}
