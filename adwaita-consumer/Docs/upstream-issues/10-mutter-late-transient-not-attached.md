**Repository:** GNOME/mutter (gitlab.gnome.org)

**Filed:** [GNOME/mutter#5106](https://gitlab.gnome.org/GNOME/mutter/-/issues/5106), 2026-10-06,
after Dan's sign-off (`Docs/UPSTREAM_SIGNOFF.md`); the body below plus a
link to the attached reproducer.

**Found for:** plugins-themes-Adwaita#44. Reproduced with the GTK 4
program below on 2026-10-06. Not already reported: searched 2026-10-06 in
GNOME/mutter's issues and merge requests, and in GNOME/nautilus's and
GNOME/xdg-desktop-portal-gnome's issues.

The issue's body is everything below the line; the reproducer,
`late_transient_attach.py`, is attached to it.

**Title:** Wayland: a modal dialog that gets its parent after it is mapped is never attached

---

### Affected version

- Mutter 48.7 (Debian 13, `48.7-0+deb13u1`), GNOME Shell 48.7, Nautilus
  48.3, xdg-desktop-portal-gnome 48.0, Wayland session. The same code is in
  49.0, 50.0 and `main` (checked 2026-10-06).

### Bug summary

With `attach-modal-dialogs` on, a Wayland modal dialog is attached to its
parent only if it has the parent when Mutter creates its window. If the
parent comes later, the dialog stays an ordinary window: it moves on its
own, the parent doesn't move with it, and the parent isn't dimmed.

This is always the case for the file chooser portal with an X11 parent
(`parent_window` = `x11:<xid>`, as every Xwayland app passes): Nautilus's
`external_window_wayland_set_parent_of()` waits until the chooser is
mapped, because `mutter_x11_interop.set_x11_parent` needs a `MetaWindow`, and
only then sets the parent. So a native GTK app's file chooser is attached,
while an Xwayland app's opens over its window but isn't.

### Steps to reproduce

`late_transient_attach.py` (GTK 4, about 30 lines): a modal dialog whose
parent is set 1 second after it is mapped.

1. On a GNOME Wayland session, `python3 late_transient_attach.py --early`:
   the dialog is attached.
2. `python3 late_transient_attach.py`: the dialog is not attached.

Or with an Xwayland app: call `org.freedesktop.portal.FileChooser.OpenFile`
with `parent_window` `x11:<xid>` and `modal` true.

### What happened

On GNOME Shell 48.7 (Wayland), `late_transient_attach.py`, screenshots taken
3s after start (6s for the third run):

| Run | Parent dimmed |
| --- | --- |
| `--early` (parent set before mapping) | yes: attached |
| parent set 1s after mapping | no |
| parent set 1s after mapping, then the dialog's modal flag turned off and on at 4s (a window type change) | yes |

The third run shows that once anything recomputes `attached` after the
parent is stored, the dialog is attached: only the computation in
`set_transient_for` gets it wrong.

Dimming can't tell the second run's state by itself: GNOME Shell re-checks
a parent's dimming only when a dialog maps, changes type or is unmanaged
(`_mapWindow()` in `js/ui/windowManager.js`), not when `attached`
changes. A toggle of `attach-modal-dialogs` therefore shows nothing either.
The dialog's behaviour shows it: dragging the dialog in the second run
moves it alone, while with `--early` the parent moves with it. An Xwayland
app's file chooser behaves like the second run.

### What did you expect to happen

The dialog is attached once it has a parent, whenever the parent is set.

### Cause

`meta_window_set_transient_for()` (`src/core/window.c`) calls the class's
`set_transient_for` before it stores the new parent:

```c
  if (!klass->set_transient_for (window, parent))
    return;
  ...
  g_set_object (&window->transient_for, parent);
```

`meta_window_wayland_set_transient_for()` (`src/wayland/meta-window-wayland.c`)
recomputes `attached` there:

```c
  if (window->attached != meta_window_should_attach_to_parent (window))
    {
      window->attached = meta_window_should_attach_to_parent (window);
      meta_window_recalc_features (window);
    }
```

and `meta_window_should_attach_to_parent()` reads the parent through
`meta_window_get_transient_for (window)`, which still returns the old
parent (none). So setting a parent on a mapped dialog leaves `attached`
FALSE. Nothing else recomputes it for a Wayland window except a change to
the `attach-modal-dialogs` setting (`prefs_changed_callback()`) and a change
of window type (`meta_window_type_changed()`), and both of those read the
stored parent.

### Possible fix

Recompute `attached` after `window->transient_for` is set: move the
recomputation from `meta_window_wayland_set_transient_for()` into
`meta_window_set_transient_for()`, after `g_set_object()`, for Wayland
windows. It has to stay after the `window->attached && parent == NULL`
check, which closes an attached dialog whose parent goes away and relies on
`attached` still describing the old parent.

GNOME Shell would then also need to re-check dimming when `attached`
changes (for example on a notification of it), or the parent stays
undimmed.

Investigated, reproduced and written up with AI assistance (Claude).
