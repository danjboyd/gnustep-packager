**Repository:** gnustep/libs-gui

**Status:** fixed on master by 8a092cfa7 (Todd White, 2026-07-26,
[libs-gui#816](https://github.com/gnustep/libs-gui/pull/816)). Nothing to
report. Kept as the record of the font-lookup crash noted in #29 and as a
packaging warning: our gui package must include that commit before it is
paired with a libs-back built from master.

**Title:** The font roles' default names are not retained, and a backend returning autoreleased names leaves them dangling

### Summary

`init_font_roles()` (Source/NSFont.m) stored the names returned by
`-[GSFontEnumerator defaultSystemFontName]`, `-defaultBoldSystemFontName`
and `-defaultFixedPitchFontName` without retaining them. When the user
defaults set no `NSFont` / `NSBoldFont`, a later `getNSFont()` falls back
to these names, and once the pool that was current at the first lookup
has drained, it passes a freed string to `+_fontWithName:size:role:`.

Until 2026-07-27 every backend returned string constants, so nothing went
wrong. libs-back 0d9f1db (2026-07-27, "back/fontconfig: select the default
font fallbacks with a shared helper") makes the fontconfig enumerator
return names built at run time, which exposes the bug. gui master already
had the fix the day before; no released gui is affected, because 0.32.0
can't load a libs-back master bundle at all (it lacks
`GSFontAssetInstaller`).

It hits this machine because the installed gui package (0.32.0-5+csd2) is
the master snapshot 7892137bd (2026-03-31, `gui-0_32_0-442`), which is
older than 8a092cfa7. The installed libs-back package (snapshot
45eeba418c, 2026-05-10) is older than 0d9f1db, so apps on the installed packages are fine. A libs-back built
from current master (the `-series` and `-csd` worktrees) run against the
installed gui is not, and that was the crash in libs-back's own tests
noted in #29.

The suspicion recorded in #29 (the name read from the defaults in
`fontNameForRole()` not being retained) was wrong. The freed string is the
backend's default name.

### Steps to reproduce

`font_lookup_zombie.m`: one font lookup in an inner pool, then
`[NSFont boldSystemFontOfSize: 0]` in another. Run with empty user
defaults (a GNUstep.conf copy whose `GNUSTEP_USER_DEFAULTS_DIR` is an
empty directory) and with `NSZombieEnabled=YES`, so the font roles fall
back to the backend's names.

Runs on 2026-10-07, Xvfb, empty defaults, libs-base 1.31.1:

| gui | libs-back | Result |
|---|---|---|
| installed (0.32.0-5+csd2, snapshot 7892137bd) | installed (0.32.0-6+csd3) | pass: DejaVuSans, DejaVuSans-Bold |
| installed | series worktree (master 23fbe39 + our patches) | `-[GSCInlineString copy]: message sent to deallocated instance`; second lookup gets DejaVuSans |
| 7892137bd, debug build | series worktree | same zombie message |
| 7892137bd + 8a092cfa7, debug build | series worktree | pass: DejaVuSans, DejaVuSans-Bold |
| master 549f639 | series worktree | pass: DejaVuSans, DejaVuSans-Bold |
| master 549f639 | installed | pass |
| 0.32.0 release (gui-0_32_0), debug build | series worktree | backend doesn't load: undefined symbol `._OBJC_REF_CLASS_GSFontAssetInstaller` |

With zombies off, 7892137bd (debug) with the series backend segfaulted in
4 of 5 runs.

Backtrace at the zombie message (7892137bd, debug build, gdb, break on
`GSLogZombie`):

```
#5  keyForFont (name=0x55555630d0e8, matrix=..., screenFont=0, role=2) at NSFont.m:126
#6  -[NSFont initWithName:matrix:screenFont:role:] (..., name=0x55555630d0e8, ..., aRole=2) at NSFont.m:840
#7  +[NSFont _fontWithName:size:role:] (..., fontSize=0, aRole=2) at NSFont.m:762
#8  getNSFont (fontSize=12, role=1) at NSFont.m:366
#9  main (...) at font_lookup_zombie.m:27
```

`getNSFont` for the bold role (1) reaches `+_fontWithName:size:role:` with
`font_roles[RoleBoldSystemFont].defaultFont`, and `keyForFont` copies the
freed name.

### Duplicate search

gnustep/libs-gui issues and pull requests for "font roles retain",
"defaultFont", "deallocated instance font", "GSCInlineString"
(2026-10-07): only #816, the fix.

### What to do here

- Nothing upstream.
- When the gui package is next rebuilt (for example to pair it with a
  libs-back package built from master), build it from a snapshot that
  contains 8a092cfa7, or carry that commit as a patch.
- libs-back's tests in the series worktree: run them against gui master,
  or expect this crash wherever a test looks up a font after
  `[NSApplication sharedApplication]`.

---

Investigated, reproduced and written up with AI assistance (Claude).
