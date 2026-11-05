# Review: libs-back#246 (already sent)

**Item:** gnustep/libs-back#246, "win32pbs: bridge images between the Windows clipboard and gpbs"
**Commit:** `4737eff4b700a428795d999797726402ea045979`
**Base:** libs-back master `9c7bcce` ("Fix leaks in testcases")
**Where:** branch `win32pbs-images` on danjboyd/libs-back. The WinUI theme session (Windows) prepared it and opened the pull request on 2026-10-08 at 19:51 UTC.
**PR text:** saved from GitHub on 2026-10-09; `git hash-object` gives `9858a619a8643f36bbb4c50ad1da112b1fab75b4`.
**Files:** `Tools/win32pbs.m` (+504 −11), `Tests/win32/pasteboard.m` (new, 322 lines), `Tests/win32/GNUmakefile.preamble` (new, 15), `Tests/win32/TestInfo` (new, empty), `Tools/GNUmakefile` (+1), `ChangeLog` (+17)

**This went out without a sign-off.** `Docs/UPSTREAM_SIGNOFF.md` has no row for it, and the WinUI repository keeps no sign-off log. Its notes say it was "posted 2026-10-08 after the owner's review". This document is for reviewing it now, so you can either record a sign-off after the fact or decide to change or withdraw it. No maintainer has commented yet.

## The problem

On Windows, gpbs (`Tools/win32pbs.m`) bridges GNUstep's general pasteboard and the Windows clipboard, but only for text (`CF_UNICODETEXT`). An image copied in a Windows program can't be pasted into a GNUstep app, and the reverse doesn't work either. ScreenshotTool's "paste from the clipboard" and copying a capture out are the cases that hit it.

## What the change does

### Windows to GNUstep

- **What's offered** (`-clipboardHasTypes`, line 489, which replaces `-clipboardHasString`): when another program owns the clipboard, gpbs declares `NSStringPboardType` if there's text, and `NSTIFFPboardType` if there's a `CF_DIB`, `CF_DIBV5`, `CF_BITMAP` or "PNG". It also declares `NSPasteboardTypePNG` if there's a "PNG". Before, it declared the string type only.
- **When the data is made** (`-provideImageTo:type:`, line 717): only when an app asks for it, as for text.
  - A PNG is passed through as PNG, or converted to TIFF.
  - Otherwise the clipboard's `CF_DIB` is converted.
  - It reads `CF_DIB` rather than `CF_DIBV5`. The `CF_DIBV5` Windows synthesizes can have colour masks after the header, so where the pixels start is ambiguous.
- **DIB conversion** (`bitmapFromDIB()`, line 127):
  - **Checks first:** the header's size and the image's dimensions, capped at `MAX_PIXELS`, 2^28 pixels (1 GB at 32 bits a pixel). Then that the pixels and any masks or colour table lie inside the data.
  - **32-bit DIBs** (`BI_RGB` or `BI_BITFIELDS`) are read directly. The fourth byte counts as alpha only when the header gives an alpha mask and some pixel's alpha isn't zero. Programs often leave it zero, and the DIB Windows makes from a bitmap can have junk there.
  - **Other depths and compressions** are drawn by GDI (`SetDIBitsToDevice`) into a 32-bit top-down section, then read the same way.

### GNUstep to Windows

- **What's published** (`-grapClipboard`, line 636): for text, `CF_UNICODETEXT` as before. For TIFF or PNG, `CF_DIB` and "PNG". All of them use delayed rendering, which is passing `NULL` and supplying the data on `WM_RENDERFORMAT`.
- **Rendering** (`-setClipboardData:`, line 616, and `-setClipboardImage:`, line 564): `WM_RENDERFORMAT` now passes on the format it's asked for (`wParam`); before, it always rendered text.
  - **`CF_DIB`:** made by `dibFromImageData()` (line 307), which writes a 32-bit bottom-up DIB with unpremultiplied alpha in the fourth byte. Integer RGB and grey samples are read directly, with premultiplied alpha undone. Anything else goes through `NSColor` one pixel at a time.
  - **"PNG":** the pasteboard's PNG, or the image converted to PNG.
- **`WM_RENDERALLFORMATS`** (line 900) renders `CF_DIB` and "PNG" as well as text. Each renderer returns without setting anything when the pasteboard has nothing of its kind (for text, `-setClipboardString` returns on a nil string).
- **`Tools/GNUmakefile`** links gpbs with `-lgdi32` on Windows.

### Behaviour changes (both stated in the PR)

1. **Text only when there's text:** `CF_UNICODETEXT` is published only when the pasteboard holds a string. Before, it was always offered, so an image-only copy looked like text to Windows.
2. **Image over text when both are offered:** when a Windows program offers both text and a bitmap (Excel cells, for example), a GNUstep text view that accepts images now pastes the image, as on macOS.

## The test: `Tests/win32/pasteboard.m`

Sixteen checks, in four groups of four:

| Group | Checks |
|---|---|
| A 24-bit bottom-up DIB put on the Windows clipboard | offered as TIFF; same size; orientation and colours kept |
| A PNG on the Windows clipboard | offered as PNG and TIFF; the PNG passed on byte for byte; the TIFF keeps colours and the half-transparent corner |
| A TIFF on the general pasteboard | published as `CF_DIB` and "PNG", and no text; the DIB is 4x4, 32-bit, bottom-up; pixels and alpha exact; the PNG holds the image |
| Text, with a non-ASCII character each way | offered as a string only; the strings match; published as text only, with no `CF_DIB` |

- **Why it's enough:**
  - Its test images have different colours top and bottom, left and right, plus a half-transparent corner. Flipping, shifting or losing alpha would show.
  - The text group guards against the image formats disturbing text.
- **Skipping:** it skips when libs-back isn't built for the win32 display server, so it does nothing on Linux CI.
- **A weakness reviewers may raise:** the test talks to whichever gpbs serves the general pasteboard, "normally the installed one" (its own comment says so). Run against a tree that hasn't been installed, it can test the old gpbs. The PR's "10 fail on the unpatched gpbs" was a run against an installed gpbs.

## Results

| Check | Result | By whom |
|---|---|---|
| `Tests/win32/pasteboard.m`, patched gpbs | 16 of 16 pass | reported in the PR (WinUI session, Windows); not run here |
| `Tests/win32/pasteboard.m`, unpatched gpbs | 10 of 16 fail | reported in the PR; not run here |
| By hand: 64x48 `Clipboard.SetImage`, palettized DIB, PNG, 1920x1080 DIB, both ways; non-ASCII text | as expected | reported in the PR |
| Build | clang 21, MSYS2 CLANG64; no new warnings | reported in the PR |
| GCC | GCC 14.2 `-fsyntax-only -Wall` on `win32pbs.m` and the test; nothing reported | reported in the PR |
| Our `gcc-syntax-check.sh`, on this commit against `9c7bcce`, Linux | **proves nothing** | run here, 2026-10-09 |

**Our GCC check on Linux:**
- It reports `win32pbs.m` "ok" only because GCC stops at `windows.h` both before and after the change.
- `pasteboard.m` fails on a missing `config.h` (the tree isn't configured).
- Without MinGW headers, this machine can't check Windows code. The PR's own syntax check on Windows is the only GCC evidence.

## What I found reading the code

None of these block the change. The first is the one worth mentioning before a maintainer finds it.

1. **The test may not test the patched gpbs** (above). A sentence in the PR, or the test checking that gpbs comes from the build tree, would answer it.
2. **`maskedComponent()` can overflow** (line 116). `((pixel & mask) >> shift) * 255` is a 32-bit product, so a mask wider than 24 bits overflows it. Real DIB masks are 8 to 10 bits, so in practice this doesn't happen.
3. **`dibFromImageData()` doesn't check `GlobalLock`'s result** (line 353) before writing. A failed lock would crash gpbs. The text path written earlier doesn't check either.
4. **Slow path for unusual images:** anything other than integer RGB or grey, such as CMYK or floating-point samples, makes one `NSColor` a pixel. That's correct but slow on large images. A pool is drained each row, so memory stays bounded.
5. **Two problems in `WM_RENDERALLFORMATS` that predate the PR** (line 900):
   - If the clipboard opens but gpbs isn't its owner, or `EmptyClipboard` fails, the clipboard is never closed.
   - It calls `EmptyClipboard` before rendering, which Microsoft's sample doesn't.

   The PR only adds two more `SendMessage` calls inside it, so this is a separate issue, if one is wanted.
6. **No fallback from a broken PNG:** if a PNG on the clipboard can't be decoded, a TIFF request gets nothing instead of falling back to the DIB.

## Against our policy (`Docs/UPSTREAM_POLICY.md`)

| Rule | This PR |
|---|---|
| Your sign-off on the exact version, then your "send it" | **Missing.** Only the session's word that you reviewed it. |
| GCC check passes on what's sent | GCC syntax only, on Windows, by the session. Our script can't check Windows code. |
| Tests, with what they test and why they're enough | Yes (the test's header comment and the PR's Testing section). |
| Disclosure | Present, in its own words, not ours. Commit: "This change was written with the help of an AI assistant (Claude); the code was reviewed and tested by the author before submission." PR: "…I reviewed and tested it before submission…". Both have a `Co-Authored-By: Claude` line. |
| No Apple-only syntax | Yes: no literals, blocks, ARC or dot syntax. |
| ChangeLog entry | Yes. |
| FSF copyright assignment | Open: the WinUI notes say it's yours to settle with GNUstep. |

**Watch out:** the commit and the PR both say, in your voice, that you reviewed and tested it. If you hadn't when it went out, that statement wasn't true when it was made.

## Your options

1. **Sign off after the fact.** If this review satisfies you, say e.g. "I approve libs-back#246 at 4737eff and its PR text 9858a61". I'll record it in `Docs/UPSTREAM_SIGNOFF.md` as recorded on 2026-10-09 for an item already sent.
2. **Sign off and add a comment.** For example, a sentence on the test running against the installed gpbs, or fixing points 2 and 3. A comment, or a new commit pushed to the PR, is another upstream action. It gets its own review document and sign-off.
3. **Withdraw it.** Close the PR with a short note. That is also an upstream action that needs your OK.

## Questions to be able to answer

- *Why `CF_DIB` and not `CF_DIBV5`?* The `CF_DIBV5` Windows synthesizes from a bitmap can have colour masks after a `BITMAPV5HEADER`, so the pixels' offset depends on how it was made. A 32-bit `CF_DIB` still holds any alpha.
- *Why is alpha ignored unless some pixel has it?* Many programs leave the fourth byte zero, and the DIB Windows makes from a bitmap can have stray values there. Reading those as alpha would make images transparent. Images with real alpha usually come with a PNG, which is preferred.
- *Why publish both `CF_DIB` and "PNG"?* Browsers and many newer programs read "PNG" and keep alpha. Older programs read DIBs. Windows makes `CF_BITMAP` and `CF_DIBV5` from the `CF_DIB` itself.
- *What does text-only publishing change for existing users?* Copying only an image in a GNUstep app no longer leaves an empty text entry on the Windows clipboard. Copying text works as before.
