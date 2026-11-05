**Repository:** gnustep/libs-gui

**Filed:** [gnustep/libs-gui#964](https://github.com/gnustep/libs-gui/issues/964), 2026-09-25

**Title:** Tool tips and drag images show only once under GNOME Wayland: they are shrunk to NSZeroRect while visible, then ordered out

### Summary

Under GNOME on Wayland (Mutter + Xwayland), a tool tip appears the first time
and never again: hovering the same control, or another control with a tool
tip of the same size, shows nothing. With tool tips of different sizes it
comes and goes, so it looks intermittent.

The tool tip panel is still ordered front each time, with the right frame,
and X reports it mapped. Mutter is holding back its content: to hide the
tool tip, `-[GSToolTips _endDisplay:]` shrinks the still-visible panel to
`NSZeroRect` and then orders it out. Mutter freezes a window's commits when
it is resized, and thaws them only after it next paints the window. That
paint never happens, because the window is unmapped straight away. The
Mutter side is reported as [GNOME/mutter#5080](https://gitlab.gnome.org/GNOME/mutter/-/issues/5080), with a plain Xlib reproducer.

### Related

#404 reported the same tool tip symptom and attached the tool tip panel to
its owner window (0b29e9ce0). That is on master, and tool tips still show
only once there; the cause turned out to be this one.

### Steps to reproduce

The complete program is `tooltip_rehover.m`: a window with one button that
has a tool tip. Half a second after each time the tool tip panel is ordered
front, it prints the X window's `_XWAYLAND_ALLOW_COMMITS`.

1. Build: ``clang `gnustep-config --objc-flags` tooltip_rehover.m `gnustep-config --gui-libs` -lX11 -o tooltip_rehover``
2. Run it in a GNOME Wayland session (the X11 backend runs under Xwayland).
3. Hover over the button until the tool tip appears, move away, and repeat
   twice.

Output on master:

```
tool tip shown (1): visible YES, ..., _XWAYLAND_ALLOW_COMMITS (none)
tool tip shown (2): visible YES, ..., _XWAYLAND_ALLOW_COMMITS 0
tool tip shown (3): visible YES, ..., _XWAYLAND_ALLOW_COMMITS 0
```

The tool tip is on screen only the first time. `0` means Mutter has told
Xwayland not to show the window's updates.

### Expected

The tool tip appears every time.

### Cause

`-[GSToolTips _endDisplay:]` (Source/GSToolTips.m, line 596 on master):

```objc
if (window != nil)
  {
    [window setFrame: NSZeroRect display: NO];
    [window orderOut:self];
    GSDetachToolTipParentWindow(window);
  }
```

The shrink was added in f3d8072b0 (2012); its ChangeLog entry says "This prevents ugly rectangles in
some desktops." `-[GSDragView _clearupWindow]` (Source/GSDragView.m, line
419) got the same change, and drag images are affected the same way.

### Drag images

A view that starts a drag with a solid 60x60 image, dragged three times.
Screenshots in the middle of each drag, counting the image's pixels (5625 at
1.25x scale):

| | drag 1 | drag 2 | drag 3 |
| --- | --- | --- | --- |
| 0.32.0 (two runs) | 5625 | 0 | 0 |
| master (two runs) | 5625 | 0 or 5625 | 0 |
| shrink removed, 0.32.0 (two runs) and master | 5625 | 5625 | 5625 |

During the drags that show nothing, the drag window (the X11 backend's
`XGRawWindow`) is mapped at the right place with
`_XWAYLAND_ALLOW_COMMITS = 0`.

### Suggested fix

Order the tool tip panel and the drag window out without shrinking them.
Screenshots in the middle of each tool tip showing, with the shrink removed
at runtime (the panel's `setFrame:display:` ignores empty rects):

| | tool tip visible |
| --- | --- |
| master, same tool tip, 3 hovers | 1 of 3 (also on 0.32.0, several runs) |
| shrink removed, same tool tip, 3 hovers | 3 of 3 (master and 0.32.0) |
| master, alternating short and long tool tips, 6 hovers | 5 of 6 |
| shrink removed, alternating short and long tool tips, 6 hovers | 6 of 6 |

Ordering out first and shrinking afterwards is not enough: it showed the
tool tip 2 times out of 3.

If the shrink is still needed for the desktops it was added for, skipping it
where `_XWAYLAND_ALLOW_COMMITS` is used (Xwayland under Mutter) would keep it
there.

### Workaround

An application or theme can replace `-setFrame:display:` on the private
`GSTTPanel` and `XGRawWindow` classes at runtime (`class_replaceMethod`) with
one that ignores empty rects and calls the original otherwise.

### Environment

- libs-gui master ff49ac8 (2026-09-22), libs-back master 5db2ae7
  (2026-09-11), libs-base 1.31.1. Also seen with the released gui 0.32.0 and
  back 0.32.0. (Building master needed `-Wno-error=format-security` for
  `NSApplication.m:986`, unrelated.)
- Debian 13, GNOME Shell / Mutter 48.7, Xwayland 24.1.6, clang 19, libobjc2,
  cairo/xlib backend, default theme.
