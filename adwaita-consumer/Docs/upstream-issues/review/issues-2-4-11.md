# Review: libs-gui issue drafts 2, 4 and 11

Three reports for gnustep/libs-gui (plugins-themes-Adwaita#29), prepared
under `Docs/UPSTREAM_POLICY.md`. Nothing has been filed.

Checked on 2026-10-08: all three reproducers pass the GCC check
(`Tests/Scripts/gcc-syntax-check.sh --files`); libs-gui master is still
`549f639`, the version they were run against; a search of libs-gui's
issues and pull requests found nothing matching any of them. Drafts 2 and
4 quoted output their programs don't print (a PASS/FAIL tag, and in 4 one
line printed twice); both were rerun on master and corrected (commit
"Docs: drafts 2 and 4 quote their reproducers' output exactly").

Read each draft itself, not only this summary: it is the text that would
be filed. Each reproducer runs with the command in its header comment.

## Draft 2: Windows 95 menu style, windows created after launch get no menu bar

Files: `../2-libs-gui-win95-menu-late-windows.md`, reproducer
`../win95_late_window_menu.m`.

**The bug.** With `NSMenuInterfaceStyle = NSWindows95InterfaceStyle` the
main menu is drawn inside each window, but only in windows that exist when
the menu is first updated. A window created later (a document window, a
window opened from a menu) has no menu bar unless the app attaches one.

**The reproducer** sets the main menu, opens one window at launch and a
second a second later, and checks both. It must run with
`-GSTheme GNUstep`: the Adwaita theme attaches menus itself and hides the
bug.

| Run | Window created at launch | Window created later |
|---|---|---|
| master `549f639` (2026-10-07 and 10-08) | menu attached | menu none (FAIL) |
| installed gui snapshot `7892137bd` (2026-10-07) | menu attached | menu none (FAIL) |

On screen (2026-10-07, Xvfb, no window manager) the later window is the
key window and has no menu bar.

**Cause** (in the draft): `-[NSMenu update]` attaches the menu to all
windows only while `mainMenuChanged` is set (`NSMenu.m:1088`); the flag is
cleared after the first pass, so a later window is never attached.

**Suggested fix:** when a window that can become main becomes key or main
in this style, attach the main menu if it has none.

**To weigh:** the suggested fix comes from reading the code; it hasn't
been tried.

**Hashes** (`git hash-object`):
- draft `62c82f0544cb4f646bbea1478992a1c6e2500e4e`
- reproducer `8501413e20403f7471bab434fc0a7279d53dc39e`

To approve: "I approve libs-gui issue 2 62c82f0/8501413".

## Draft 4: `-overriddenMethod:for:` returns 0 for a subclass of the overridden class

Files: `../4-libs-gui-overriddenMethod-subclasses.md`, reproducer
`../override_subclass.m`.

**The bug.** A theme overrides a method with
`_override<Class>Method_<selector>` and calls the original through
`-overriddenMethod:for:`. When the receiver is an instance of a subclass
that inherits the method, the override runs but the lookup returns 0, so
the original can't be called. It affects every theme that overrides a
class with subclasses: an `NSButtonCell` override also catches pop-up
button cells and toolbar button cells (image-only toolbar items drew
nothing).

**The reproducer:** a theme overrides `-[NSActionCell tag]` and calls the
original; `MyCell` subclasses `NSActionCell` without overriding `-tag`.
Output on master `549f639` (2026-10-08):

```
  override called for NSActionCell: original IMP 0x7f489ee20130
NSActionCell tag = 7
  override called for MyCell: original IMP (null)
  override called for MyCell: original IMP (null)
MyCell tag       = -1  (FAIL)
```

The installed gui fails the same way (2026-10-07).

**Cause:** the lookup matches only the receiver's exact class
(`GSTheme.m`, around line 1079).

**Suggested fix:** walk up through the superclasses and return the first
match, so a subclass with its own override still gets its own original.

**To weigh:** the draft also gives the workaround the theme uses today
(look up again with a receiver of exactly the overridden class).

**Hashes:**
- draft `50909aab032e4fb6643ba19f8a1ba48cb14c2cdb`
- reproducer `50511ece6fecb30a917acbbdeb952623820903f6`

To approve: "I approve libs-gui issue 4 50909aa/50511ec".

## Draft 11: NSScroller without arrows puts its knob one arrow down

Files: `../11-libs-gui-scroller-knob-without-arrows.md`, reproducer
`../scroller_knob_offset.m`.

**The bug.** A scroller with no arrows (`NSScrollerArrowsNone`) has a knob
slot that fills the scroller, but when the arrows aren't "at the same end"
(`GSScrollerArrowsSameEnd NO`, or a theme saying so) the knob is drawn one
arrow's height down the slot: at 0.0 it starts one arrow below the top,
and at 1.0 it runs one arrow past the end, out of the scroller.

**The reproducer:** a 15x200 vertical scroller with no arrows; it compares
the knob's rect at 0.0 and 1.0 with the slot's. Identical on master
`549f639` and the installed gui (2026-10-07):

```
-GSScrollerArrowsSameEnd NO:
value 0.0: knob y 18 to 37, slot y 1 to 199  FAIL
value 1.0: knob y 197 to 216, slot y 1 to 199  FAIL
-GSScrollerArrowsSameEnd YES:
value 0.0: knob y 1 to 20, slot y 1 to 199  PASS
value 1.0: knob y 180 to 199, slot y 1 to 199  PASS
```

**Cause:** in `-rectForPart:`'s knob case (`NSScroller.m:846`), the branch
for arrows not at the same end adds the top arrow's height without
checking for no arrows; the slot case just below does check, which is why
the slot is right and the knob isn't.

**Suggested fix (one line):** `else` becomes
`else if (_arrowsPosition != NSScrollerArrowsNone)`.

**To weigh:** the most direct cause and the smallest fix of the three.

**Hashes:**
- draft `6c51be21a1140aa14c2eaaad4a0c0fe91a039fed`
- reproducer `94f62dfb5226ca7a4346cfbad6d8ab08344903b9`

To approve: "I approve libs-gui issue 11 6c51be2/94f62df".

## After approval

Each approval is recorded in `Docs/UPSTREAM_SIGNOFF.md` with your words
quoted. Nothing is filed until you also say "file issue N", one at a time;
suggested order 11, 4, 2.
