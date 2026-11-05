/* NSScroller's knob without arrows: a vertical scroller with no arrows
 * (NSScrollerArrowsNone), its knob at the start (0.0) and the end (1.0).
 * Prints the knob's rect against the knob slot's: at 0.0 the knob should
 * start where the slot starts, and at 1.0 end where the slot ends.
 *
 * Build: clang `gnustep-config --objc-flags` scroller_knob_offset.m \
 *          `gnustep-config --gui-libs` -o scroller_knob_offset
 * Run:   ./scroller_knob_offset -GSTheme GNUstep -GSScrollerArrowsSameEnd NO
 *        (fails: the knob is one arrow lower than the slot)
 *        ./scroller_knob_offset -GSTheme GNUstep -GSScrollerArrowsSameEnd YES
 *        (passes)
 */

#import <AppKit/AppKit.h>
#include <stdio.h>

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSScroller *scroller;
  NSRect slot, knob;
  double values[2] = { 0.0, 1.0 };
  int i, failures = 0;

  [NSApplication sharedApplication];
  scroller = [[NSScroller alloc] initWithFrame: NSMakeRect (0, 0, 15, 200)];
  [scroller setArrowsPosition: NSScrollerArrowsNone];
  [scroller setEnabled: YES];
  [scroller setKnobProportion: 0.1];
  slot = [scroller rectForPart: NSScrollerKnobSlot];
  for (i = 0; i < 2; i++)
    {
      BOOL inside;

      [scroller setDoubleValue: values[i]];
      knob = [scroller rectForPart: NSScrollerKnob];
      inside = NSMinY (knob) >= NSMinY (slot) && NSMaxY (knob) <= NSMaxY (slot)
        && (values[i] > 0.0 || NSMinY (knob) == NSMinY (slot))
        && (values[i] < 1.0 || NSMaxY (knob) == NSMaxY (slot));
      if (inside == NO)
        {
          failures++;
        }
      printf ("value %.1f: knob y %g to %g, slot y %g to %g  %s\n",
              values[i], NSMinY (knob), NSMaxY (knob),
              NSMinY (slot), NSMaxY (slot), inside ? "PASS" : "FAIL");
    }
  [scroller release];
  [pool release];
  return failures;
}
