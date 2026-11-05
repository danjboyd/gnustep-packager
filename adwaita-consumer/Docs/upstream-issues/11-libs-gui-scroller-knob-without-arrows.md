**Repository:** gnustep/libs-gui

**Filed:** [gnustep/libs-gui#989](https://github.com/gnustep/libs-gui/issues/989), 2026-10-08, the version signed off (draft 6c51be2, reproducer 94f62df), with the reproducer's source attached.

**Title:** NSScroller: with no arrows, the knob is offset by one arrow unless GSScrollerArrowsSameEnd is set

### Summary

A scroller whose arrows are `NSScrollerArrowsNone` has a knob slot that
fills the scroller, but `-rectForPart: NSScrollerKnob` still moves the knob
one arrow's height down the slot when the arrows are not "at the same end"
(`GSScrollerArrowsSameEnd NO`, or a theme returning NO from
`-scrollerArrowsSameEndForScroller:`). At 0.0 the knob starts one arrow
below the top of the slot, and at 1.0 it runs one arrow past the end, out
of the scroller.

### Steps to reproduce

Excerpt below; the complete program is `scroller_knob_offset.m`, to paste
in or attach. It makes a 15x200 vertical scroller with no arrows and
compares the knob's rect at 0.0 and 1.0 with the knob slot's.

```objc
scroller = [[NSScroller alloc] initWithFrame: NSMakeRect (0, 0, 15, 200)];
[scroller setArrowsPosition: NSScrollerArrowsNone];
[scroller setEnabled: YES];
[scroller setKnobProportion: 0.1];
slot = [scroller rectForPart: NSScrollerKnobSlot];
[scroller setDoubleValue: 0.0];   /* then 1.0 */
knob = [scroller rectForPart: NSScrollerKnob];
```

`./scroller_knob_offset -GSTheme GNUstep -GSScrollerArrowsSameEnd NO`:

```
value 0.0: knob y 18 to 37, slot y 1 to 199  FAIL
value 1.0: knob y 197 to 216, slot y 1 to 199  FAIL
```

`./scroller_knob_offset -GSTheme GNUstep -GSScrollerArrowsSameEnd YES`:

```
value 0.0: knob y 1 to 20, slot y 1 to 199  PASS
value 1.0: knob y 180 to 199, slot y 1 to 199  PASS
```

### Expected

With no arrows, the knob covers the slot from end to end whatever
`GSScrollerArrowsSameEnd` says, as it does with `YES`.

### Cause

Source/NSScroller.m, `-rectForPart:`, the `NSScrollerKnob` case (line 846
on master). The knob's travel already leaves out the arrows when there are
none (`slotHeight` and the overshoot), but its start doesn't:

```objc
if (arrowsSameEnd)
  {
    if (_arrowsPosition == NSScrollerArrowsMinEnd)
      {
        y += buttonsSize;
      }
  }
else
  {
    y += buttonsWidth + buttonsOffset;
  }
```

The `else` branch adds the top arrow's height without checking
`_arrowsPosition`. The `NSScrollerKnobSlot` case just below returns before
this for `NSScrollerArrowsNone`, which is why the slot is right and the
knob isn't.

### Suggested fix

Skip the offset when there are no arrows: make the `else` an
`else if (_arrowsPosition != NSScrollerArrowsNone)`.

### Workaround (in theme code)

Return YES from `-scrollerArrowsSameEndForScroller:` for scrollers whose
arrows are `NSScrollerArrowsNone`.

### Environment

- Reproduced 2026-10-07 with libs-gui master 549f639 (2026-10-02, unpatched,
  run uninstalled through `LD_LIBRARY_PATH`) and with the installed gui
  (a Debian build of the master snapshot 7892137bd, 2026-03-31, with two
  unrelated patches); libs-base 1.31.1 in both runs.
- Debian 13, clang 19, libobjc2 2.3 (gnustep-2.2 runtime), cairo/xlib
  backend, under Xvfb with no window manager.
- No existing issue or pull request found (searched "scroller knob",
  "NSScrollerArrowsNone", "knob arrows", 2026-10-07).

---

Investigated, reproduced and written up with AI assistance (Claude).
