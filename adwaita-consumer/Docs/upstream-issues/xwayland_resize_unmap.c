/* An X11 window that is resized and then unmapped at once stays frozen
 * under Mutter + Xwayland: _XWAYLAND_ALLOW_COMMITS stays 0 and the window
 * shows nothing the next time it is mapped.
 *
 * The program maps a small undecorated blue window at (300, 300) three
 * times. Between showings it hides the window the way GNUstep hides its
 * tool tip: resize to 1x1, then unmap.
 *
 * Build: cc xwayland_resize_unmap.c -o xwayland_resize_unmap -lX11
 * Run:   ./xwayland_resize_unmap              resize, then unmap: shown once
 *        ./xwayland_resize_unmap --no-resize  unmap only: shown three times
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static Display *dpy;

static long
allow_commits(Window w)
{
  Atom type;
  int format;
  unsigned long n, after;
  unsigned char *data = NULL;
  long v = -1;

  if (XGetWindowProperty(dpy, w,
                         XInternAtom(dpy, "_XWAYLAND_ALLOW_COMMITS", False),
                         0, 1, False, XA_CARDINAL, &type, &format, &n, &after,
                         &data) == Success && data != NULL && n == 1)
    v = *(long *)data;
  if (data != NULL)
    XFree(data);
  return v;
}

/* Handle events for ms milliseconds, painting the window on Expose. */
static void
run(Window w, GC gc, int ms)
{
  for (int t = 0; t < ms; t += 10)
    {
      while (XPending(dpy))
        {
          XEvent e;

          XNextEvent(dpy, &e);
          if (e.type == Expose && e.xexpose.window == w)
            XFillRectangle(dpy, w, gc, 0, 0, 1000, 1000);
        }
      XFlush(dpy);
      usleep(10000);
    }
}

int
main(int argc, char **argv)
{
  int resize = !(argc > 1 && strcmp(argv[1], "--no-resize") == 0);
  long motif[5] = { 2 /* MWM_HINTS_DECORATIONS */, 0, 0, 0, 0 };
  XSizeHints *hints;
  Atom mwm;
  Window w;
  GC gc;

  dpy = XOpenDisplay(NULL);
  if (dpy == NULL)
    return 1;

  w = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 300, 300, 160, 40, 0,
                          0, 0x3070c0);
  XSelectInput(dpy, w, ExposureMask | StructureNotifyMask);
  XStoreName(dpy, w, "resize-unmap");

  /* Like a tool tip: no decorations, at a position the program chose. */
  mwm = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
  XChangeProperty(dpy, w, mwm, mwm, 32, PropModeReplace,
                  (unsigned char *)motif, 5);
  hints = XAllocSizeHints();
  hints->flags = PPosition | USPosition;
  hints->x = 300;
  hints->y = 300;
  XSetWMNormalHints(dpy, w, hints);
  XFree(hints);

  gc = XCreateGC(dpy, w, 0, NULL);
  XSetForeground(dpy, gc, 0x3070c0);

  for (int i = 1; i <= 3; i++)
    {
      XMoveResizeWindow(dpy, w, 300, 300, 160, 40);
      XMapRaised(dpy, w);
      run(w, gc, 1000);
      printf("showing %d: _XWAYLAND_ALLOW_COMMITS = %ld\n", i,
             allow_commits(w));
      fflush(stdout);

      if (resize)
        XResizeWindow(dpy, w, 1, 1);
      XUnmapWindow(dpy, w);
      run(w, gc, 1000);
    }
  return 0;
}
