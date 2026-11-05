#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

/* Text alignment in archived cells across the NSTextAlignment renumbering
 * (3237efda8, centre 1 and right 2 from then on). "write <dir>" archives a
 * centred and a right-aligned text field cell with NSArchiver (as Gorm
 * saves .gorm files) and with NSKeyedArchiver; "read <dir>" decodes both
 * and prints the alignment the running libs-gui gives each cell.
 *
 * Build against 0.32: clang `gnustep-config --objc-flags` align_archive.m \
 *          `gnustep-config --gui-libs` -o align_archive
 * Run:   ./align_archive write out           (with 0.32)
 *        ./align_archive read out            (with 0.32: both right)
 *        LD_LIBRARY_PATH=<master>/Source/obj ./align_archive read out
 *        (with master: the keyed cells come back swapped)
 * It needs a display (NSApplication); a private Xvfb will do.
 */

static NSString *
nameOf(NSTextAlignment a)
{
  /* The running library's numbering: NSParagraphStyle is version 4 from
     the commit that renumbered NSTextAlignment (centre 1, right 2). */
  BOOL renumbered = [NSParagraphStyle version] >= 4;

  if (a == 0) return @"left";
  if (a == (renumbered ? 1 : 2)) return @"centre";
  if (a == (renumbered ? 2 : 1)) return @"right";
  return [NSString stringWithFormat: @"%ld", (long)a];
}

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *dir;

  if (argc < 3)
    {
      fprintf(stderr, "usage: %s write|read dir\n", argv[0]);
      return 2;
    }
  [NSApplication sharedApplication];
  dir = [NSString stringWithUTF8String: argv[2]];
  if (strcmp(argv[1], "write") == 0)
    {
      NSTextFieldCell *centre = [[[NSTextFieldCell alloc] initTextCell: @"centre"] autorelease];
      NSTextFieldCell *right = [[[NSTextFieldCell alloc] initTextCell: @"right"] autorelease];
      NSArray *cells;

      [centre setAlignment: NSCenterTextAlignment];
      [right setAlignment: NSRightTextAlignment];
      cells = [NSArray arrayWithObjects: centre, right, nil];
      [NSArchiver archiveRootObject: cells
                             toFile: [dir stringByAppendingPathComponent: @"cells.archive"]];
      [NSKeyedArchiver archiveRootObject: cells
                                  toFile: [dir stringByAppendingPathComponent: @"cells.keyed"]];
      printf("wrote with NSParagraphStyle version %d: centre %ld, right %ld\n",
             (int)[NSParagraphStyle version], (long)NSCenterTextAlignment, (long)NSRightTextAlignment);
    }
  else
    {
      NSArray *plain = [NSUnarchiver unarchiveObjectWithFile:
        [dir stringByAppendingPathComponent: @"cells.archive"]];
      NSArray *keyed = [NSKeyedUnarchiver unarchiveObjectWithFile:
        [dir stringByAppendingPathComponent: @"cells.keyed"]];

      printf("read with NSParagraphStyle version %d\n", (int)[NSParagraphStyle version]);
      printf("NSArchiver:      \"centre\" cell is %s, \"right\" cell is %s\n",
             [nameOf([[plain objectAtIndex: 0] alignment]) UTF8String],
             [nameOf([[plain objectAtIndex: 1] alignment]) UTF8String]);
      printf("NSKeyedArchiver: \"centre\" cell is %s, \"right\" cell is %s\n",
             [nameOf([[keyed objectAtIndex: 0] alignment]) UTF8String],
             [nameOf([[keyed objectAtIndex: 1] alignment]) UTF8String]);
    }
  [pool release];
  return 0;
}
