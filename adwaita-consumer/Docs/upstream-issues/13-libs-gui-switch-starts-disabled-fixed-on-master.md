**Repository:** gnustep/libs-gui

**Status:** fixed on master by 89c7f7eb6 (Todd White, 2026-07-24,
[libs-gui#765](https://github.com/gnustep/libs-gui/pull/765), "Fix:
NSSwitch is enabled by default and handles -performClick:"). Not in the
0.32.0 release (`git merge-base --is-ancestor` says no), nor in the
installed gui package (snapshot 7892137bd). Nothing to report. Kept as the
record of the finding noted in #29 (from #35).

**Title:** A new NSSwitch made in code starts disabled

### Summary

`NSSwitch` keeps its own `_enabled` ivar. Before 89c7f7eb6,
`-initWithFrame:` didn't set it, so a switch made in code started
disabled: drawn faded, and `-mouseDown:` ignored clicks until the app
called `-setEnabled: YES`. In Cocoa a new switch is enabled. Master now
sets `_enabled = YES` in `-initWithFrame:` and `-initWithCoder:`.

### Steps to reproduce

`switch_enabled.m` makes a switch with `-initWithFrame:` and prints
`-isEnabled`. Runs on 2026-10-07, Xvfb, `-GSTheme GNUstep`, libs-base
1.31.1:

```
gui installed (0.32.0-5+csd2, snapshot 7892137bd): new switch: isEnabled NO  FAIL
gui 7892137bd, debug build:                        new switch: isEnabled NO  FAIL
gui master 549f639:                                new switch: isEnabled YES  PASS
```

### What to do here

- Nothing upstream.
- Apps on the installed gui package that make switches in code need
  `-setEnabled: YES` until the package is built from a snapshot with
  89c7f7eb6.

---

Investigated, reproduced and written up with AI assistance (Claude).
