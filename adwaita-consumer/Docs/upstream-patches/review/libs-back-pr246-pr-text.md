On Windows, gpbs (`Tools/win32pbs.m`) bridged only text, so images couldn't be copied or pasted between GNUstep apps and other Windows apps (for example a screenshot tool's "paste from the clipboard"). This bridges images both ways.

**Windows → GNUstep**
- A clipboard holding `CF_DIBV5`, `CF_DIB`, `CF_BITMAP` or the registered "PNG" format is offered as `NSTIFFPboardType`, and also as `NSPasteboardTypePNG` when "PNG" is there.
- The data is produced only when an app asks for it. PNG is passed through or converted to TIFF. Otherwise the `CF_DIB` is converted: 32-bit DIBs (`BI_RGB`/`BI_BITFIELDS`) are read directly, and other depths and compressions go through GDI.
- `CF_DIB` is used rather than `CF_DIBV5`. The `CF_DIBV5` Windows synthesises from a bitmap puts masks after its header, which makes the pixel offset ambiguous.
- The fourth byte is taken as alpha only when the header has an alpha mask and some pixel's alpha isn't zero.

**GNUstep → Windows**
- TIFF or PNG on the general pasteboard is published as `CF_DIB` (32-bit, alpha in the fourth byte) and "PNG", with delayed rendering, as the text is.
- `WM_RENDERFORMAT` now renders the format it's asked for, and `WM_RENDERALLFORMATS` renders the image formats too.
- `Tools/GNUmakefile` links gpbs with `-lgdi32` on Windows.

**Behaviour changes**
- `CF_UNICODETEXT` is published only when the pasteboard holds a string. Before, it was always advertised, so an image-only copy looked like text to Windows.
- When a Windows app offers both text and a bitmap (Excel cells, for example), a text view that accepts images now pastes the image, as it would on macOS.

**Testing**
- `Tests/win32/pasteboard.m` adds 16 checks: images and text in both directions, and which formats are published. They pass with the patched gpbs, and 10 of them fail with the unpatched one.
- Checked by hand: a 64x48 image from `Clipboard.SetImage`, a palettized DIB, PNG, and a 1920x1080 DIB, read back with the right pixels; GNUstep TIFF and PNG pasteboards pasted into Windows apps; non-ASCII text both ways.
- Built with clang 21 in MSYS2 CLANG64; the only warnings are existing ones on lines this doesn't change.
- **GCC:** no GCC-built gnustep-base was available, so GCC 14.2 (gcc-objc) only checked syntax, with `-fsyntax-only -Wall`, on `win32pbs.m` and the test. No diagnostics. No Apple-only syntax is used: no literals, blocks or ARC.

This change was written with the help of an AI assistant (Claude); I reviewed and tested it before submission, as the AI policy asks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

