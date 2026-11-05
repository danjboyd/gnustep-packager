**Repository:** gnustep/libs-gui

**Title:** -displayIfNeeded draws a still-dirty opaque subview again after, and over, the siblings drawn above it

### Summary

When an opaque subview keeps its own dirty rect (an opaque view's
`-setNeedsDisplayInRect:` stores the rect in the view itself and only flags
its ancestors) and its parent's dirty rect covers only part of it,
`-displayIfNeededInRectIgnoringOpacity:` draws in two passes. The first
draws the parent's rect: the parent, then each subview in order inside that
rect, including the siblings above the opaque one. The opaque subview's own
rect isn't covered, so it stays dirty, and a second pass draws it again,
alone, over its whole dirty rect. That paints over the siblings drawn above
it in the first pass, and they aren't drawn again.

The visible case is a scroll view's scroller. With `copiesOnScroll` NO,
each scroll step marks the document view's whole visible rect; the
scroller's redraw marks only the scroller's strip in the scroll view, and a
vertical scroller stops where the horizontal one's strip begins. So the
scroll view's rect misses part of the document's, the document is drawn
again after the scroller, and an overlay scroller (drawn over the content)
vanishes, wholly or partly, while the content scrolls. Two GNUstep themes
hit this independently and worked round it (below).

### Steps to reproduce

Excerpt below; the complete program is `display_order.m`, to paste in or
attach. An opaque grey parent holds an opaque white "document" view the
size of the parent and, above it, a non-opaque red "strip" over the
document's right edge, stopping 20 points short of the bottom. Both are
marked dirty, as a scroll step and the scroller's redraw mark them, and the
window displays. The program logs each `-drawRect:` and reads a strip
pixel from the window's backing store.

```objc
[parent addSubview: document];          /* opaque, 0,0 200x200 */
[parent addSubview: strip];             /* not opaque, 180,20 20x180 */
...
[document setNeedsDisplay: YES];
[strip setNeedsDisplay: YES];
[window displayIfNeeded];
```

`./display_order -GSTheme GNUstep`, on master and on 0.32:

```
drawn: parent{x = 180; y = 20; width = 20; height = 180} document{x = 180; y = 20; width = 20; height = 180} strip{x = 0; y = 0; width = 20; height = 180} document{x = 0; y = 0; width = 200; height = 200}
strip pixel: r 1.00 g 1.00 b 1.00  FAIL (the document was drawn over the strip)
```

The first three draws are the first pass (the parent's rect, which is the
strip's); the last is the second pass, drawing the document over its whole
rect after the strip. The strip ends up white.

A real case, traced in an app (MarkdownViewer's preview: an NSScrollView
with an overlay vertical scroller, the horizontal scroller hidden), one
scroll step:

```
DRAW  NSScrollView          {0, 0, 735, 747}     <- the ancestors' rect: 13 px short
DRAW  OMDPreviewCanvasView  {0, 359, 735, 747}
DRAW  NSScroller            {0, 0, 13, 747}      <- the knob drawn
DRAW  OMDPreviewCanvasView  {0, 359, 735, 760}   <- second pass: the document over the scroller
```

### Expected

After `-displayIfNeeded`, views are drawn back to front: a subview isn't
drawn after a sibling that lies above it, or the sibling is drawn again
after it. The strip in the program stays red, and a scroller stays drawn
while the content scrolls.

### Cause

Source/NSView.m on master (lines 2589-2644), in
`-displayIfNeededInRectIgnoringOpacity:`. The first pass is limited to the
receiver's own dirty rect:

```objc
      rect = NSIntersectionRect(aRect, _invalidRect);
      [self displayRectIgnoringOpacity: rect];
```

`-displayRectIgnoringOpacity:inContext:` draws the receiver in that rect
and then every subview that intersects it, in order (lines 2738-2765,
`[subview displayRectIgnoringOpacity: isect inContext: context]` at 2752).
A subview's dirty state is cleared only if the drawn rect contains its own
`_invalidRect` (lines 2700-2710). An opaque subview's `_invalidRect` is its
own: `_setNeedsDisplayInRect_real:` (line 2975) keeps the rect in the view
when it is its own opaque ancestor and only sets `needs_display` on its
superviews (2997-3001), while a non-opaque view passes its rect up to its
opaque ancestor (2986-2990). So the opaque document stays dirty, and the
second pass (lines 2608-2641) draws it again:

```objc
              if (subview->_rFlags.needs_display)
                {
                  ...
                  isect = NSIntersectionRect(aRect, subviewFrame);
                  if (NSIsEmptyRect(isect) == NO)
                    {
                      isect = [subview convertRect: isect fromView: self];
                      [subview displayIfNeededInRectIgnoringOpacity: isect];
                    }
```

This draws the subview (and its own subviews), but not the siblings after
it in `_sub_views` that overlap what it drew; they were drawn in the first
pass and aren't dirty any more. This code hasn't changed since 2013.

### Suggested fix

Not tried; from reading the code. Either:

- **Before the first pass,** grow the rect to draw by the dirty rects of
  opaque subviews that keep their own (converted to the receiver's
  coordinates and clipped to `aRect`), so the first pass covers them and
  draws every subview back to front once. It draws no more than the second
  pass does today, since that area is drawn anyway.
- **Or, in the second pass,** after a subview redraws, redraw the siblings
  after it in `_sub_views` that intersect the rect it drew.

The first keeps a single back-to-front pass, which seems the simpler
invariant.

### Workarounds (in theme code)

Both GNUstep themes that draw overlay scrollers hit this and worked round
it from the scroll view's side:

- **plugins-themes-Adwaita** (#47): when the content scrolls, the scroll
  view invalidates the clip view's whole area itself, so the first pass
  covers the document's rect and the scrollers are drawn last
  (`GnomeThemeOverlayScrollers.m`). Measured: during a knob drag the
  scroller's column had no knob pixels before and the full knob after, in
  3 of 3 runs.
- **plugins-themes-winuitheme** (#87, PR #88): after libs-gui's pass, the
  scroll view redraws the scroller strips when the content was dirty
  (`WinUIThemeScrollers.m`). That project reports, in MarkdownViewer: the
  scroller missing in 3 of 8 scrolls and partly drawn in 1 before the fix,
  drawn in 8 of 8 after.

Any view that draws above an opaque sibling which redraws itself can show
the same overdraw, not only scrollers.

### Environment

- Reproduced 2026-10-08 with libs-gui master 549f639 (2026-10-02, unpatched,
  run uninstalled through `LD_LIBRARY_PATH`, confirmed with `ldd`) and with
  the installed gui (a Debian build of the master snapshot 7892137bd,
  2026-03-31, with two unrelated patches); libs-base 1.31.1 in both runs.
- Debian 13, clang 19, libobjc2 2.3 (gnustep-2.2 runtime), cairo/xlib
  backend, under Xvfb with no window manager, GNUstep's default theme.
- No existing issue or pull request found (searched "displayIfNeeded",
  "_invalidRect", "overdraw", "draws over", "scroller redraw",
  "needs_display subview", 2026-10-08).

---

Investigated, reproduced and written up with AI assistance (Claude).
