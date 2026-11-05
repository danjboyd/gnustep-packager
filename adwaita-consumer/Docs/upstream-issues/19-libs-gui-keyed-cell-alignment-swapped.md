**Repository:** gnustep/libs-gui

**Status:** draft, not filed. From plugins-themes-Adwaita#29 (the
`NSTextAlignment` renumbering). Before filing:
- check how Cocoa .nib files store a cell's alignment in `NSCellFlags2` (below), with a nib saved on a Mac;
- Dan's sign-off.

The libs-gui master tested is `fdc5cfe83`, 2026-10-13. Master is unreleased, so this is worth raising before the next release.

**Title:** Keyed archives from 0.32 decode centred cells as right-aligned (and the reverse) since the NSTextAlignment renumbering

### Summary

3237efda8 renumbered `NSTextAlignment` (centre 1 and right 2, where 0.32 has
right 1 and centre 2). It bumped NSParagraphStyle to version 4 and maps old
values when decoding.

0a25af3b4 did the same for NSCell's non-keyed decoding: version 5, mapping
older values. NSCell's keyed decoding reads the alignment straight from
`NSCellFlags2` (bits 26–28) and maps nothing. So a cell in a keyed archive
written by 0.32 comes back with centre and right swapped: a centred label is
drawn right-aligned, and a right-aligned one centred.

### Steps to reproduce

The complete program is `align_archive.m`, to paste in or attach. It needs a
display; a private Xvfb is enough.

1. Build it against 0.32.
2. Write the archives with 0.32.
3. Read them with 0.32, then with master: `LD_LIBRARY_PATH=<libs-gui master>/Source/obj`. Master keeps the 0.32 soname, so the same binary loads it.

```objc
[centre setAlignment: NSCenterTextAlignment];
[right setAlignment: NSRightTextAlignment];
cells = [NSArray arrayWithObjects: centre, right, nil];
[NSArchiver archiveRootObject: cells toFile: ...];
[NSKeyedArchiver archiveRootObject: cells toFile: ...];
```

```
wrote with NSParagraphStyle version 3: centre 2, right 1

read with NSParagraphStyle version 3                        (0.32)
NSArchiver:      "centre" cell is centre, "right" cell is right
NSKeyedArchiver: "centre" cell is centre, "right" cell is right

read with NSParagraphStyle version 4                        (master fdc5cfe83)
NSArchiver:      "centre" cell is centre, "right" cell is right
NSKeyedArchiver: "centre" cell is right, "right" cell is centre
```

The program names each value by the running library's numbering. A library
that has the renumbering is recognised by `[NSParagraphStyle version] >= 4`.

### Expected

The keyed archive decodes as it does with 0.32 (centre, right), as the
non-keyed one now does.

### Cause

`-[NSCell initWithCoder:]` (Source/NSCell.m), keyed branch:

```objc
[self setAlignment: ((cFlags2 & 0x1C000000) >> 26)];
```

The non-keyed branch maps values from archives before version 5 (0a25af3b4).
Keyed archives carry no class version, so the keyed branch can't tell an old
GNUstep archive from a new one in the same way.

### Open question for the maintainers: Cocoa nibs

The keyed branch also decodes Cocoa .nib files, so the right fix depends on
how AppKit stores the alignment in `NSCellFlags2`. AppKit's own enum depends
on the architecture: right 1 and centre 2 on Intel Macs, centre 1 and right 2
where `TARGET_ABI_USES_IOS_VALUES` (Apple silicon). We haven't checked which
numbering ends up in a nib's `NSCellFlags2`. That decides whether:
- 0.32 or master reads Cocoa nibs correctly, and
- the keyed branch should map 1 and 2 always, never, or only for GNUstep-written archives (for example, keyed archives marked by a key that only GNUstep's encoder writes).

Gorm's own .gorm files use NSArchiver and decode correctly on master, as above.

### Suggested fix

Once the nib question is settled, either:
- map `1 ↔ 2` in the keyed branch when the archive comes from GNUstep 0.32 or earlier; or
- have the keyed encoder write a marker key (say, `GSCellAlignmentVersion`) from now on, and map when it is absent and the archive is GNUstep's.

Other classes that keep the alignment in keyed archives should be checked
the same way: NSParagraphStyle's keyed decoding, `NSMatrix`, and the text
system's typing attributes.

Investigated, reproduced and written up with AI assistance (Claude).
