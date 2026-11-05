/* NSComboBox's string value after -selectItemAtIndex:: a combo box with
 * two items selects the second, as an app does to show a choice at
 * launch. Prints the selected index, the selected item and the string
 * value: Cocoa shows the selected item's text in the field.
 *
 * Build: clang `gnustep-config --objc-flags` combo_select_string.m \
 *          `gnustep-config --gui-libs` -o combo_select_string
 * Run:   ./combo_select_string -GSTheme GNUstep
 *        (fails: the string value stays empty)
 */

#import <AppKit/AppKit.h>
#include <stdio.h>

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSComboBox *combo;
  BOOL ok;

  [NSApplication sharedApplication];
  combo = [[NSComboBox alloc] initWithFrame: NSMakeRect (0, 0, 200, 26)];
  [combo addItemsWithObjectValues:
    [NSArray arrayWithObjects: @"Largest files", @"Duplicates", nil]];
  [combo selectItemAtIndex: 1];

  printf ("selected index: %ld\n", (long)[combo indexOfSelectedItem]);
  printf ("selected item: %s\n", [[[combo objectValueOfSelectedItem] description] UTF8String]);
  printf ("string value: \"%s\"\n", [[combo stringValue] UTF8String]);
  ok = [[combo stringValue] isEqualToString: @"Duplicates"];
  printf ("%s\n", ok ? "PASS" : "FAIL");
  [combo release];
  [pool release];
  return ok ? 0 : 1;
}
