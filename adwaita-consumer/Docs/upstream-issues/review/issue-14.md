# Review: libs-gui issue draft 14

A report for gnustep/libs-gui (plugins-themes-Adwaita#29), found while
building GNOME's print dialog (#52) and prepared under
`Docs/UPSTREAM_POLICY.md`. Nothing has been filed.

Files: `../14-libs-gui-print-did-run-arguments.md`, reproducer
`../print_did_run.m`. Read the draft itself: it is the text that would be
filed.

## The bug

`-[NSPrintOperation runOperationModalForWindow:delegate:didRunSelector:contextInfo:]`
calls the delegate back without the operation. Cocoa's callback is
`-printOperationDidRun: (NSPrintOperation *)op success: (BOOL)success
contextInfo: (void *)info`; libs-gui calls it as
`(delegate, sel, success, contextInfo)` (`NSPrintOperation.m`, lines
702-727 on master `549f639`), so the operation is missing and every
argument after it is shifted.

## The reproducer

Runs an operation as a sheet whose print panel ends at once with Cancel
(a stand-in panel; nothing is printed: `-GSPrinting GSLPR`, no panels),
and prints what the callback received. On master `549f639` (uninstalled)
and the installed gui, 2026-10-08:

```
printOperation: (nil) (the operation is 0x564dfaa194c8)  FAIL
success:        -1075220032 (want 0, the sheet was cancelled)  FAIL
contextInfo:    0x7f636b58f530 (passed 0x564dbfe971c0)  FAIL
```

The GCC check passes on it. No existing issue or pull request matches;
`NSPrintOperation.m` hasn't changed on master since 2011.

## Suggested fix, and what to weigh

Call the selector with the operation first. **GNUstep's own NSDocument
depends on the bug**: its private callback
`_runModalPrintOperationDidSucceed:contextInfo:` takes the shifted
arguments, so the fix has to change NSDocument in the same commit, or
document printing breaks. The draft says so.

It also notes, from reading the code only (not run), that
`-[NSDocument runModalPageLayoutWithPrintInfo:...]` passes the caller's
selector to the page layout sheet, so a Cocoa-style delegate would get the
panel where the document should be. It is labelled as unverified.

The print panel's and page layout's own sheet callbacks are fine: they go
through `-[NSApplication beginSheet:...]`, which matches Cocoa.

## Hashes

- draft `4cc1a76c9b3d5a6e6abb31acaa74067bc5b63885`
- reproducer `a842659bd9ac8180b6abd06b5b02dd95f15d43c3`

To approve: "I approve libs-gui issue 14 4cc1a76/a842659".
