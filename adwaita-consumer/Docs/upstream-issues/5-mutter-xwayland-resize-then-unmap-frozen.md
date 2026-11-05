**Repository:** GNOME/mutter (gitlab.gnome.org)

**Filed:** [GNOME/mutter#5080](https://gitlab.gnome.org/GNOME/mutter/-/issues/5080), 2026-09-25

**Title:** Xwayland: a window resized and then unmapped stays frozen (_XWAYLAND_ALLOW_COMMITS = 0) and is blank when mapped again

### Affected version

- Mutter 48.7 (Debian 13, `48.7-0+deb13u1`), GNOME Shell 48.7, Xwayland 24.1.6,
  Wayland session. The same code is on `main` (888a7b7d, 2026-09-17).
- Does not apply to an Xorg session (commit freezing is Xwayland-only).

### Bug summary

If an X11 client resizes a mapped window and unmaps it straight away, Mutter
freezes the window's commits for the resize and never thaws them. The next
time the window is mapped, Xwayland is still holding back its content, so the
window is invisible even though it is mapped and viewable.

GNUstep hits this every time it hides a tool tip or a drag image: it
shrinks the window to 1x1 and then unmaps it. Tool tips and drag images then
show once per application and, most of the time, never again.

### Steps to reproduce

The complete program is `xwayland_resize_unmap.c` (about 110 lines, Xlib
only). It maps a small undecorated window three times, 2 seconds apart, and
hides it in between with:

```c
XResizeWindow(dpy, w, 1, 1);
XUnmapWindow(dpy, w);
```

1. `cc xwayland_resize_unmap.c -o xwayland_resize_unmap -lX11`
2. `./xwayland_resize_unmap` and watch the blue window at (300, 300).
3. Compare with `./xwayland_resize_unmap --no-resize`, which only unmaps.

### What happened

With the resize, the window appears for the first showing only. The program
prints:

```
showing 1: _XWAYLAND_ALLOW_COMMITS = -1     (property not set yet)
showing 2: _XWAYLAND_ALLOW_COMMITS = 0
showing 3: _XWAYLAND_ALLOW_COMMITS = 0
```

Screenshots taken in the middle of each showing, counting the window's
pixels (160x40 at 1.25x scale is 10000):

| | 1st showing | 2nd | 3rd |
| --- | --- | --- | --- |
| resize, then unmap | 10000 | 0 | 0 |
| unmap only (`--no-resize`) | 10000 | 10000 | 10000 |

This happened on each of three runs.

### What did you expect to happen

The window is visible every time it is mapped, whether or not it was resized
before it was last unmapped.

### Cause

`meta_window_x11_move_resize_internal()` freezes commits when a mapped
window is resized, and asks for a thaw after the next paint
(`src/x11/window-x11.c`, line 1425 on main):

```c
/* If resizing, freeze commits - This is for Xwayland, and a no-op on Xorg */
if (need_resize_client || need_resize_frame)
  {
    if (meta_window_x11_can_freeze_commits (window) &&
        !meta_window_x11_should_thaw_after_paint (window))
      {
        meta_window_x11_set_thaw_after_paint (window, TRUE);
        meta_window_x11_freeze_commits (window);
      }
  }
```

The only thaw is in `meta_window_actor_x11_after_paint()`
(`src/compositor/meta-window-actor-x11.c`, line 1209 on main). The client
unmaps the window before it is painted at the new size, so that thaw never
runs. `_XWAYLAND_ALLOW_COMMITS` stays 0 and `thaw_after_paint` stays TRUE.
When the window is mapped again, Xwayland doesn't commit the client's
drawing, and nothing is painted that would thaw it.

### Suggested fix

Thaw a pending `thaw_after_paint` freeze when the window is unmapped or its
actor hidden (and clear the flag), since no paint will follow. Thawing when
the window is mapped again would also do.

### Workaround for clients

Unmap without resizing first. Resizing after unmapping is not enough in
practice: in GNUstep, ordering the tool tip out and then shrinking it showed
it only two times out of three, likely because the actor is still mapped for
a moment after the unmap.

### Environment

- Debian 13, GNOME 48 Wayland session, 1.25 fractional scaling, Intel
  Arrow Lake-U graphics (Lenovo ThinkPad T14 Gen 6).
- Found through GNUstep (libs-gui master ff49ac8, libs-back master 5db2ae7,
  and the released gui 0.32.0 / back 0.32.0), then reproduced with the plain
  Xlib program above.
