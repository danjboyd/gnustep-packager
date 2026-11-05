/* NSTableView's sort indicator: a table whose first column has a sort
 * descriptor prototype gets a click on that column's header, as a user
 * sorts it. Prints the table's sort descriptors, the column's indicator
 * image and highlighted column, and whether the header cell was asked to
 * draw a sort indicator (-drawSortIndicatorWithFrame:inView:ascending:
 * priority:) when the header drew.
 *
 * Build: clang `gnustep-config --objc-flags` sort_indicator.m \
 *          `gnustep-config --gui-libs` -o sort_indicator
 * Run:   ./sort_indicator -GSTheme GNUstep
 *        (fails: the descriptors change, but there is no indicator image
 *        and the header cell is never asked to draw one)
 */

#import <AppKit/AppKit.h>
#include <stdio.h>

static int indicatorDraws = 0;

@interface CountingHeaderCell : NSTableHeaderCell
@end

@implementation CountingHeaderCell
- (void) drawSortIndicatorWithFrame: (NSRect)cellFrame
                             inView: (NSView *)controlView
                          ascending: (BOOL)ascending
                           priority: (NSInteger)priority
{
  indicatorDraws++;
  [super drawSortIndicatorWithFrame: cellFrame
                             inView: controlView
                          ascending: ascending
                           priority: priority];
}
@end

@interface DataSource : NSObject
@end

@implementation DataSource
- (NSInteger) numberOfRowsInTableView: (NSTableView *)tableView
{
  return 3;
}

- (id) tableView: (NSTableView *)tableView
objectValueForTableColumn: (NSTableColumn *)column
             row: (NSInteger)row
{
  return [NSString stringWithFormat: @"row %ld", (long)row];
}
@end

static NSEvent *
mouseEvent(NSEventType type, NSPoint location, NSWindow *window)
{
  return [NSEvent mouseEventWithType: type
                            location: location
                       modifierFlags: 0
                           timestamp: 0
                        windowNumber: [window windowNumber]
                             context: nil
                         eventNumber: 0
                          clickCount: 1
                            pressure: 1.0];
}

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSWindow *window;
  NSScrollView *scroll;
  NSTableView *table;
  NSTableColumn *column;
  NSTableHeaderView *header;
  DataSource *source = [DataSource new];
  NSPoint click;
  NSImage *indicator;
  BOOL ok;

  [NSApplication sharedApplication];
  window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 320, 200)
                                       styleMask: NSTitledWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect (10, 10, 300, 180)];
  table = [[NSTableView alloc] initWithFrame: NSMakeRect (0, 0, 300, 180)];
  column = [[NSTableColumn alloc] initWithIdentifier: @"name"];
  [column setHeaderCell: [[CountingHeaderCell alloc] initTextCell: @"Name"]];
  [column setWidth: 150];
  [column setSortDescriptorPrototype:
    [[NSSortDescriptor alloc] initWithKey: @"name" ascending: YES]];
  [table addTableColumn: column];
  [table setDataSource: source];
  [scroll setDocumentView: table];
  [scroll setHasVerticalScroller: YES];
  [[window contentView] addSubview: scroll];
  [window orderFront: nil];
  [window display];
  header = [table headerView];

  /* A click on the column's header: the release is queued first, so the
     header view's tracking loop ends at once. */
  click = [header convertPoint: NSMakePoint (NSMidX ([header headerRectOfColumn: 0]),
                                             NSMidY ([header headerRectOfColumn: 0]))
                        toView: nil];
  [NSApp postEvent: mouseEvent (NSLeftMouseUp, click, window) atStart: NO];
  [header mouseDown: mouseEvent (NSLeftMouseDown, click, window)];
  indicatorDraws = 0;
  [window display];

  indicator = [table indicatorImageInTableColumn: column];
  printf ("sort descriptors: %s\n", [[[table sortDescriptors] description] UTF8String]);
  printf ("indicator image in the column: %s\n", indicator != nil ? [[indicator name] UTF8String] : "nil");
  printf ("highlighted column: %s\n", [table highlightedTableColumn] == column ? "the sorted one" : "none");
  printf ("header cell asked to draw a sort indicator: %d time(s)\n", indicatorDraws);
  ok = [[table sortDescriptors] count] > 0 && (indicator != nil || indicatorDraws > 0);
  printf ("%s\n", ok ? "PASS" : "FAIL");
  [pool release];
  return ok ? 0 : 1;
}
