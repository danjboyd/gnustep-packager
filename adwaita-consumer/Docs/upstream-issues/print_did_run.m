/* NSPrintOperation's didRunSelector: what the delegate receives.
 *
 * Cocoa's callback is
 *   - (void) printOperationDidRun: (NSPrintOperation *)printOperation
 *                         success: (BOOL)success
 *                     contextInfo: (void *)contextInfo;
 * This runs an operation with -runOperationModalForWindow:delegate:
 * didRunSelector:contextInfo: and prints the three arguments the delegate
 * got. The print panel is a stand-in whose sheet ends at once with
 * NSCancelButton, calling its didEndSelector the way -[NSApplication
 * beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:]
 * does (as if Cancel was clicked), so nothing is printed and no printer
 * is asked.
 *
 * Build: clang `gnustep-config --objc-flags` print_did_run.m \
 *          `gnustep-config --gui-libs` -o print_did_run
 * Run:   ./print_did_run -GSTheme GNUstep -GSPrinting GSLPR
 */

#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static NSPrintOperation *theOperation = nil;
static int expectedContext = 42;
static int failures = 0;

/* A print panel whose sheet ends at once with Cancel. NSPrintPanel's
   +allocWithZone: returns the printing bundle's panel class, so this
   allocates itself. */
@interface ReproPanel : NSPrintPanel
@end

@implementation ReproPanel
+ (id) allocWithZone: (NSZone *)zone
{
  return NSAllocateObject (self, 0, zone);
}

- (void) beginSheetWithPrintInfo: (NSPrintInfo *)printInfo
                  modalForWindow: (NSWindow *)docWindow
                        delegate: (id)delegate
                  didEndSelector: (SEL)didEndSelector
                     contextInfo: (void *)contextInfo
{
  void (*didEnd)(id, SEL, id, NSInteger, void *);

  didEnd = (void (*)(id, SEL, id, NSInteger, void *))
    [delegate methodForSelector: didEndSelector];
  didEnd (delegate, didEndSelector, self, NSCancelButton, contextInfo);
}
@end

@interface Delegate : NSObject
@end

@implementation Delegate
- (void) printOperationDidRun: (NSPrintOperation *)printOperation
                      success: (BOOL)success
                  contextInfo: (void *)contextInfo
{
  BOOL opOK = (printOperation == theOperation);
  BOOL successOK = (success == NO);
  BOOL contextOK = (contextInfo == &expectedContext);

  printf ("printOperation: %p (the operation is %p)  %s\n",
          (void *)printOperation, (void *)theOperation, opOK ? "PASS" : "FAIL");
  printf ("success:        %d (want 0, the sheet was cancelled)  %s\n",
          (int)success, successOK ? "PASS" : "FAIL");
  printf ("contextInfo:    %p (passed %p)  %s\n",
          contextInfo, (void *)&expectedContext, contextOK ? "PASS" : "FAIL");
  failures = (opOK ? 0 : 1) + (successOK ? 0 : 1) + (contextOK ? 0 : 1);
}
@end

int
main (int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSWindow *window;
  NSView *view;
  Delegate *delegate;
  ReproPanel *panel;

  [NSApplication sharedApplication];
  window = [[NSWindow alloc] initWithContentRect: NSMakeRect (100, 100, 300, 200)
                                       styleMask: NSTitledWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  view = [[NSView alloc] initWithFrame: NSMakeRect (0, 0, 300, 200)];
  [window setContentView: view];
  [window orderFront: nil];
  delegate = [Delegate new];

  theOperation = [NSPrintOperation printOperationWithView: view];
  [theOperation setShowsPrintPanel: NO];
  [theOperation setShowsProgressPanel: NO];
  panel = [[ReproPanel alloc] init];
  [theOperation setPrintPanel: panel];
  [theOperation runOperationModalForWindow: window
                                  delegate: delegate
                            didRunSelector: @selector(printOperationDidRun:success:contextInfo:)
                               contextInfo: &expectedContext];

  fflush (stdout);
  [panel release];
  [pool release];
  return failures;
}
