# Review: libs-back patch 1

**Item:** libs-back 0001, "x11: keep the window manager functions of windows the gui decorates"
**Commit:** `dbfbe5397bc18895ef3e49951574e312603b03fa`
**Base:** libs-back master `9731f15`
**Where:** branch `ai-policy/csd-series` in `~/git/gnustep/libs-back-series`; patch file `Docs/upstream-patches/libs-back/0001-x11-keep-the-window-manager-functions-of-windows-the.patch`
**Files:** `Source/x11/XGServerWindow.m` (+14 −2), `ChangeLog` (+11), `Tests/x11/motifhints.m` (new, 180 lines)

This is the version to sign off on. It replaces `813163e`, which had three inaccurate statements in its commit message. The code and the test are byte-for-byte the same as in `813163e` (the commits' trees are identical), so the results below, run on `813163e` and master, apply to this commit unchanged.

Prepared under `Docs/UPSTREAM_POLICY.md`. Nothing has been sent.

## The problem

When GNUstep draws a window's title bar itself (`GSBackHandlesWindowDecorations NO`, which the Adwaita theme needs), libs-back puts a `_MOTIF_WM_HINTS` property on each window. That property has two fields that matter here:

- `decorations`: what the window manager should draw (its title bar and borders);
- `functions`: what the window manager may do to the window (move, resize, minimize, maximize, close).

libs-back set both to 0 for every window it decorates, as it does for borderless windows. "Draw no frame" is right. "Allow no functions" is the bug: GNOME's window manager then refuses to move, minimize, maximize or close the window, however it is asked (double-click on the title bar, Super-drag, its window menu, the requests a theme sends). GNUstep's own title bar didn't notice, because it moves the window itself (`-setFrameOrigin:`, carried out with `XMoveResizeWindow`), which the hints don't restrict.

## The fix, hunk by hunk

The function is `setWindowHintsForStyle()` in `Source/x11/XGServerWindow.m`. It is quoted whole below the patch.

1. **The first branch (line 344).** It read `if (styleMask == NSBorderlessWindowMask || !handlesWindowDecorations)`, which gave every window GNUstep decorates the borderless treatment: decorations 0, functions 0. The patch removes `|| !handlesWindowDecorations`; only borderless windows take that branch now.
2. **The new block (line 388).** Styled windows go through the existing per-style branches, which add a function for each part of the style: titled gives move, closable gives close (and move), miniaturizable gives minimize, resizable gives resize and maximize. These branches also ask for decorations (title, border and so on). The new block runs after them when the gui draws the decorations: it sets `decorations = 0`, keeps the functions the style earned, and adds move.
3. **What doesn't change:**
   - The icon window and mini window branches come after the new block and still set everything to 0, so those windows stay locked.
   - When the window manager draws the decorations (`handlesWindowDecorations` YES), the new block doesn't run, so nothing changes in that mode.
   - Borderless windows (menus, tool tips) still allow nothing.

## Who this affects

Everyone who runs GNUstep with the gui drawing the decorations (`GSBackHandlesWindowDecorations` or `GSX11HandlesWindowDecorations` NO), not only the Adwaita theme. Every styled window, sheets and utility panels included, now lets the window manager move it, and resize, minimize, maximize or close it as its style allows. Before, it allowed nothing. The commit message says so.

**To weigh:** a sheet can now be moved by the window manager on its own, for example with Super-drag, away from the window it belongs to. The commit message names sheets among the windows that change, but not this case.

## The test: `Tests/x11/motifhints.m`

- **What it does:** turns GNUstep-drawn decorations on for its own process only (in the argument domain, so nothing is written to the user's defaults), creates windows of four styles, and reads back each window's `_MOTIF_WM_HINTS` as "flags functions decorations", compared exactly:

  | Style | Expected | Meaning |
  |---|---|---|
  | titled, closable, miniaturizable, resizable | `3 62 0` | no decorations; move, resize, minimize, maximize, close |
  | titled, closable | `3 36 0` | no decorations; move, close |
  | titled | `3 4 0` | no decorations; move |
  | borderless | `3 0 0` | no decorations; nothing |

  It also checks that the backend reports the gui as drawing the decorations, so the test can't pass by running in the wrong mode.
- **Why that is enough:** the exact comparison catches both halves of the bug (functions missing, or decorations asked for). The borderless case guards against the fix spreading to windows that must stay locked.
- **A detail you may be asked about:** it flushes the backend's own X connection before reading. Without that, the property can still be in the backend's buffer and the read finds nothing.
- **What it needs:** a display; no particular window manager, since it only reads what the backend sets.
- **Not covered:** the icon and mini window branches; window managers other than Mutter.

## Results, each run on 2026-10-06

| Check | Without the patch (master `9731f15`) | With the patch |
|---|---|---|
| `Tests/x11/motifhints.m` | 3 of 5 fail (each reads `3 0 0`) | 5 of 5 pass |
| GNOME Shell 48.7 (X11), GNUstep theme, gui drawing the decorations: Mutter's `_NET_WM_ALLOWED_ACTIONS` | resize, fullscreen, change desktop, above, below (no move, maximize, minimize or close) | includes move, maximize and close |
| `gcc-syntax-check.sh` on this commit | — | clean (canary rejected) |
| This commit alone: build, whole `Tests/x11` | — | builds; 54 passed, 0 failed |

The GNOME Shell run used the GNUstep theme on purpose: the Adwaita theme works around this bug itself (`GnomeThemeWindowManagerAllowFunctions`), which would hide it. Minimize isn't in what that check looks for.

## What changed since the first packet (`813163e` → `dbfbe53`)

Only the commit message:

1. "Mutter's `_NET_WM_ALLOWED_ACTIONS` lists none of them" became "lists resize, but not move, minimize, maximize or close", as the run shows.
2. "moves the window with `XMoveWindow`" became "`-setFrameOrigin:`, which `-placewindow::` carries out with `XMoveResizeWindow`", as the code shows.
3. "as GTK's client-side decorated windows do" was dropped: nobody checked what GTK puts in that property.
4. The Testing section gained the GNOME Shell result, so the claim about Mutter rests on a run.

## Questions to be able to answer

- Why not leave the functions field out entirely (no `MWM_HINTS_FUNCTIONS` flag), as the window manager then allows everything? *The style's limits still mean something: a window that isn't resizable shouldn't be resized by the window manager either. Leaving the field out would allow everything.*
- Why add move to every styled window? *Every styled window can be moved with GNUstep's own title bar. Without move, the window manager can't do the same thing for it: drag-to-move handed to it, Super-drag, keyboard moves.*
- Does anything change when the window manager draws the decorations? *No. The new block only runs when the gui draws them, and the first branch changes only for that mode.*

## To check it yourself

```
cd ~/git/gnustep/libs-back-series
git show dbfbe53                                   # the whole commit
git show dbfbe53:Source/x11/XGServerWindow.m | sed -n 312,427p   # the function
```

The test needs a private display; the packet's results came from `run-back-tests.sh` in the session's scratch directory. Ask Claude to run it with you watching if you want to see it.

## Sign-off

If you approve this exact version, say so in the chat ("I approve libs-back-0001") and Claude records it, or add this row to `Docs/UPSTREAM_SIGNOFF.md` yourself:

```
| 2026-10-06 | libs-back 0001 | dbfbe5397bc18895ef3e49951574e312603b03fa | | |
```

## The patch, as it would be sent

```diff
From dbfbe5397bc18895ef3e49951574e312603b03fa Mon Sep 17 00:00:00 2001
From: Daniel Boyd <danieljboyd@icloud.com>
Date: Tue, 6 Oct 2026 11:19:03 -0500
Subject: [PATCH 1/5] x11: keep the window manager functions of windows the gui
 decorates

With GSBackHandlesWindowDecorations (or GSX11HandlesWindowDecorations)
NO, setWindowHintsForStyle() gave every window the borderless window's
Motif hints: no decorations, which is right, but also functions 0, which
tells the window manager that the window may not be moved, resized,
minimized, maximized or closed.  Mutter follows that for all but resize:
the _NET_WM_ALLOWED_ACTIONS it sets on the window lists resize, but not
move, minimize, maximize or close, so it won't do those for the window,
whether asked through _NET_WM_MOVERESIZE, _NET_WM_STATE, Super-drag or
its window menu.  GNUstep's own title bar moves the window itself
(-setFrameOrigin:, which -placewindow:: carries out with
XMoveResizeWindow), and the hints don't restrict that, so this went
unnoticed.

A styled window the gui decorates now asks for no decorations but keeps
the functions its style allows, plus move.  Borderless windows keep
functions 0.

This changes behaviour for everyone who uses GNUstep-drawn decorations
today: every styled window, sheets and utility panels included, now lets
the window manager move it (and resize, minimize, maximize or close it as
its style allows), where before it allowed nothing.

Testing: Tests/x11/motifhints.m creates windows of four styles with the
gui drawing the decorations and reads back their _MOTIF_WM_HINTS: the
flags, the functions and the decorations, compared exactly.  Exact
comparison catches both halves of the bug (functions missing, or
decorations asked for), and the borderless case guards against the fix
spreading to windows that must stay fixed.  It reads only the property
the backend sets, so it needs a display but no particular window manager.
Without this change the three styled checks fail ("3 0 0", nothing
allowed); with it all five checks pass.

Under GNOME Shell 48.7 (X11), with the GNUstep theme and the gui drawing
the decorations, Mutter's _NET_WM_ALLOWED_ACTIONS for a fully styled
window lists resize, fullscreen, change desktop, above and below without
this change, and includes move, maximize and close with it.

AI assistance: this change, its test and this description were written
with Claude (Anthropic's Claude Code).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
---
 ChangeLog                   |  11 +++
 Source/x11/XGServerWindow.m |  16 +++-
 Tests/x11/motifhints.m      | 180 ++++++++++++++++++++++++++++++++++++
 3 files changed, 205 insertions(+), 2 deletions(-)
 create mode 100644 Tests/x11/motifhints.m

diff --git a/ChangeLog b/ChangeLog
index 2b1b779..47ed8d1 100644
--- a/ChangeLog
+++ b/ChangeLog
@@ -1,3 +1,14 @@
+2026-10-06 Daniel Boyd <danieljboyd@icloud.com>
+
+	* Source/x11/XGServerWindow.m (setWindowHintsForStyle): For a styled
+	window whose decorations the gui draws (GSBackHandlesWindowDecorations
+	or GSX11HandlesWindowDecorations NO), ask for no decorations but keep
+	the functions the style allows, plus move.  With functions 0, window
+	managers such as Mutter refused to move, resize, maximize, minimize
+	or close the window, even when asked with _NET_WM_MOVERESIZE or
+	_NET_WM_STATE.  Borderless windows still allow no functions.
+	* Tests/x11/motifhints.m: New test.
+
 2026-07-22 Richard Frith-Macdonald <rfm@gnu.org>
 
 	* Source/x11/XGServerEvent.m:
diff --git a/Source/x11/XGServerWindow.m b/Source/x11/XGServerWindow.m
index 19c5e9e..b491681 100644
--- a/Source/x11/XGServerWindow.m
+++ b/Source/x11/XGServerWindow.m
@@ -341,8 +341,7 @@ static void setWindowHintsForStyle (Display *dpy, Window window,
   hints->functions = 0;
 
   /* Now add to the hints from the styleMask */
-  if (styleMask == NSBorderlessWindowMask
-      || !handlesWindowDecorations)
+  if (styleMask == NSBorderlessWindowMask)
     {
       hints->flags |= MWM_HINTS_DECORATIONS;
       hints->flags |= MWM_HINTS_FUNCTIONS;
@@ -386,6 +385,19 @@ static void setWindowHintsForStyle (Display *dpy, Window window,
 	  hints->functions |= MWM_FUNC_MAXIMIZE;
 	  hints->functions |= MWM_FUNC_MOVE;
         }
+      if (!handlesWindowDecorations)
+	{
+	  /* The gui library draws the decorations: ask for none, but keep
+	     the functions, so that the window manager still moves,
+	     resizes, maximizes, minimizes and closes the window when the
+	     user or the decorations ask it to (_NET_WM_MOVERESIZE, its
+	     window menu, keyboard shortcuts). With functions 0 a window
+	     manager such as Mutter refuses all of them. */
+	  hints->flags |= MWM_HINTS_DECORATIONS;
+	  hints->flags |= MWM_HINTS_FUNCTIONS;
+	  hints->decorations = 0;
+	  hints->functions |= MWM_FUNC_MOVE;
+	}
       if (styleMask & NSIconWindowMask)
 	{
 	  // FIXME
diff --git a/Tests/x11/motifhints.m b/Tests/x11/motifhints.m
new file mode 100644
index 0000000..c768d7f
--- /dev/null
+++ b/Tests/x11/motifhints.m
@@ -0,0 +1,180 @@
+/* The _MOTIF_WM_HINTS of windows whose decorations the gui library draws
+ * (GSBackHandlesWindowDecorations NO): they ask the window manager for no
+ * decorations, but keep the functions their style allows, plus move, so
+ * that the window manager still moves, resizes, minimizes, maximizes and
+ * closes them when asked to (_NET_WM_MOVERESIZE, _NET_WM_STATE, its window
+ * menu and keyboard shortcuts).  With functions 0 Mutter refuses all of
+ * these.  A borderless window still allows nothing.
+ *
+ * Only the property the backend sets is read, so the test works with or
+ * without a window manager on the display.
+ */
+#import <Foundation/Foundation.h>
+#import "Testing.h"
+#include "config.h"
+
+#if defined(BUILD_SERVER) && defined(SERVER_x11) && BUILD_SERVER == SERVER_x11
+
+#import <AppKit/AppKit.h>
+#import <GNUstepGUI/GSDisplayServer.h>
+#include <X11/Xlib.h>
+#include <X11/Xatom.h>
+
+/* From the Motif window manager hints (XGServerWindow.m). */
+#define HINTS_FUNCTIONS		(1L << 0)
+#define HINTS_DECORATIONS	(1L << 1)
+#define FUNC_RESIZE		(1L << 1)
+#define FUNC_MOVE		(1L << 2)
+#define FUNC_MINIMIZE		(1L << 3)
+#define FUNC_MAXIMIZE		(1L << 4)
+#define FUNC_CLOSE		(1L << 5)
+
+/* Sets a default for this process only, in the argument domain. */
+static void
+setDefault(id value, NSString *key)
+{
+  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
+  NSMutableDictionary	*args;
+
+  args = [[defs volatileDomainForName: NSArgumentDomain] mutableCopy];
+  if (args == nil)
+    {
+      args = [NSMutableDictionary new];
+    }
+  [args setObject: value forKey: key];
+  [defs removeVolatileDomainForName: NSArgumentDomain];
+  [defs setVolatileDomain: args forName: NSArgumentDomain];
+  [args release];
+}
+
+/* The window's Motif hints as "flags functions decorations", or "none".
+ * The backend's own connection is flushed first: what it set may still be
+ * in its buffer.
+ */
+static NSString *
+motifHints(GSDisplayServer *srv, Display *dpy, int win)
+{
+  Window	w = (Window)[srv windowDevice: win];
+  Atom		type;
+  int		format;
+  unsigned long	n, after;
+  unsigned char	*data = NULL;
+  NSString	*s = @"none";
+
+  XSync((Display *)[srv serverDevice], False);
+  if (XGetWindowProperty(dpy, w, XInternAtom(dpy, "_MOTIF_WM_HINTS", False),
+      0, 5, False, AnyPropertyType, &type, &format, &n, &after, &data)
+    == Success && data != NULL)
+    {
+      unsigned long *v = (unsigned long *)data;
+
+      if (n >= 3)
+	{
+	  s = [NSString stringWithFormat: @"%lu %lu %lu", v[0], v[1], v[2]];
+	}
+      XFree(data);
+    }
+  return s;
+}
+
+static NSString *
+expected(unsigned long functions)
+{
+  return [NSString stringWithFormat: @"%lu %lu %lu",
+    (unsigned long)(HINTS_FUNCTIONS | HINTS_DECORATIONS), functions, 0UL];
+}
+
+int
+main(int argc, const char **argv)
+{
+  START_SET("motif hints")
+
+  extern void	initialize_gnustep_backend(void);
+  GSDisplayServer	*srv = nil;
+  Display		*dpy;
+  int			win;
+
+  if (getenv("DISPLAY") == NULL || *getenv("DISPLAY") == '\0')
+    {
+      SKIP("no window server available")
+    }
+  dpy = XOpenDisplay(NULL);
+  if (dpy == NULL)
+    {
+      SKIP("no window server available")
+    }
+
+  setDefault(@"NO", @"GSBackHandlesWindowDecorations");
+  NS_DURING
+    {
+      initialize_gnustep_backend();
+      srv = [GSDisplayServer serverWithAttributes: nil];
+    }
+  NS_HANDLER
+    {
+      NSLog(@"the display server did not start: %@", localException);
+      SKIP("It looks like the GNUstep backend is not installed")
+    }
+  NS_ENDHANDLER
+  if (srv == nil || [srv isMemberOfClass: [GSDisplayServer class]])
+    {
+      SKIP("no concrete display server")
+    }
+  [GSDisplayServer setCurrentServer: srv];
+
+  PASS([srv handlesWindowDecorations] == NO,
+    "with GSBackHandlesWindowDecorations NO the gui draws the decorations");
+
+  win = [srv window: NSMakeRect(100, 100, 400, 300)
+		   : NSBackingStoreBuffered
+		   : NSTitledWindowMask | NSClosableWindowMask
+		     | NSMiniaturizableWindowMask | NSResizableWindowMask
+		   : 0];
+  PASS_EQUAL(motifHints(srv, dpy, win),
+    expected(FUNC_MOVE | FUNC_CLOSE | FUNC_MINIMIZE | FUNC_RESIZE
+      | FUNC_MAXIMIZE),
+    "a fully styled window asks for no decorations and allows every function");
+  [srv termwindow: win];
+
+  win = [srv window: NSMakeRect(100, 100, 400, 300)
+		   : NSBackingStoreBuffered
+		   : NSTitledWindowMask | NSClosableWindowMask
+		   : 0];
+  PASS_EQUAL(motifHints(srv, dpy, win),
+    expected(FUNC_MOVE | FUNC_CLOSE),
+    "a closable window that isn't resizable allows move and close only");
+  [srv termwindow: win];
+
+  win = [srv window: NSMakeRect(100, 100, 400, 300)
+		   : NSBackingStoreBuffered : NSTitledWindowMask : 0];
+  PASS_EQUAL(motifHints(srv, dpy, win),
+    expected(FUNC_MOVE),
+    "a titled window allows move");
+  [srv termwindow: win];
+
+  win = [srv window: NSMakeRect(100, 100, 200, 100)
+		   : NSBackingStoreBuffered : NSBorderlessWindowMask : 0];
+  PASS_EQUAL(motifHints(srv, dpy, win),
+    expected(0),
+    "a borderless window asks for no decorations and allows no functions");
+  [srv termwindow: win];
+
+  XCloseDisplay(dpy);
+
+  END_SET("motif hints")
+
+  return 0;
+}
+
+#else
+
+int
+main(int argc, const char **argv)
+{
+  START_SET("motif hints")
+    SKIP("back is not built with the x11 server")
+  END_SET("motif hints")
+  return 0;
+}
+
+#endif
-- 
2.47.3

```

## The function after the patch

`Source/x11/XGServerWindow.m`, lines 312–427:

```objc
static void setWindowHintsForStyle (Display *dpy, Window window,
                                    unsigned int styleMask, Atom mwhints_atom)
{
  MwmHints *hints;
  BOOL needToFreeHints = YES;
  Atom type_ret;
  int format_ret, success;
  unsigned long nitems_ret;
  unsigned long bytes_after_ret;

  /* Get the already-set window hints */
  success = XGetWindowProperty (dpy, window, mwhints_atom, 0,
		      sizeof (MwmHints) / sizeof (unsigned long),
		      False, AnyPropertyType, &type_ret, &format_ret,
		      &nitems_ret, &bytes_after_ret,
		      (unsigned char **)&hints);

  /* If no window hints were set, create new hints to 0 */
  if (success != Success || type_ret == None)
    {
      needToFreeHints = NO;
      hints = alloca (sizeof (MwmHints));
      memset (hints, 0, sizeof (MwmHints));
    }

  /* Remove the hints we want to change */
  hints->flags &= ~MWM_HINTS_DECORATIONS;
  hints->flags &= ~MWM_HINTS_FUNCTIONS;
  hints->decorations = 0;
  hints->functions = 0;

  /* Now add to the hints from the styleMask */
  if (styleMask == NSBorderlessWindowMask)
    {
      hints->flags |= MWM_HINTS_DECORATIONS;
      hints->flags |= MWM_HINTS_FUNCTIONS;
      hints->decorations = 0;
      hints->functions = 0;
    }
  else
    {
      /* These need to be on all windows except mini and icon windows,
	 where they are specifically set to 0 (see below) */
      hints->flags |= MWM_HINTS_DECORATIONS;
      hints->decorations |= (MWM_DECOR_TITLE | MWM_DECOR_BORDER);
      if (styleMask & NSTitledWindowMask)
	{
	  // Without this, iceWM does not let you move the window!
	  // [idem below]
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->functions |= MWM_FUNC_MOVE;
	}
      if (styleMask & NSClosableWindowMask)
	{
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->functions |= MWM_FUNC_CLOSE;
	  hints->functions |= MWM_FUNC_MOVE;
	}
      if (styleMask & NSMiniaturizableWindowMask)
	{
	  hints->flags |= MWM_HINTS_DECORATIONS;
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->decorations |= MWM_DECOR_MINIMIZE;
	  hints->functions |= MWM_FUNC_MINIMIZE;
	  hints->functions |= MWM_FUNC_MOVE;
	}
      if (styleMask & NSResizableWindowMask)
	{
	  hints->flags |= MWM_HINTS_DECORATIONS;
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->decorations |= MWM_DECOR_RESIZEH;
	  hints->decorations |= MWM_DECOR_MAXIMIZE;
	  hints->functions |= MWM_FUNC_RESIZE;
	  hints->functions |= MWM_FUNC_MAXIMIZE;
	  hints->functions |= MWM_FUNC_MOVE;
        }
      if (!handlesWindowDecorations)
	{
	  /* The gui library draws the decorations: ask for none, but keep
	     the functions, so that the window manager still moves,
	     resizes, maximizes, minimizes and closes the window when the
	     user or the decorations ask it to (_NET_WM_MOVERESIZE, its
	     window menu, keyboard shortcuts). With functions 0 a window
	     manager such as Mutter refuses all of them. */
	  hints->flags |= MWM_HINTS_DECORATIONS;
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->decorations = 0;
	  hints->functions |= MWM_FUNC_MOVE;
	}
      if (styleMask & NSIconWindowMask)
	{
	  // FIXME
	  hints->flags |= MWM_HINTS_DECORATIONS;
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->decorations = 0;
	  hints->functions = 0;
	}
      if (styleMask & NSMiniWindowMask)
	{
	  // FIXME
	  hints->flags |= MWM_HINTS_DECORATIONS;
	  hints->flags |= MWM_HINTS_FUNCTIONS;
	  hints->decorations = 0;
	  hints->functions = 0;
	}
    }

  /* Set the hints */
  XChangeProperty (dpy, window, mwhints_atom, mwhints_atom, 32,
		   PropModeReplace, (unsigned char *)hints,
		   sizeof (MwmHints) / sizeof (unsigned long));

  /* Free the hints if allocated by the X server for us */
  if (needToFreeHints == YES)
    XFree (hints);
}
```
