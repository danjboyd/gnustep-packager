# Waiting for Dan's review (2026-10-08)

Everything prepared for GNUstep and not yet sent. Each item has its own
review packet; read it and the item itself (the patch or the draft), then
approve by name and hash in the chat. Nothing is sent until you also say
"send X" / "file X", one at a time (`Docs/UPSTREAM_POLICY.md`).

| Item | Packet | Hash to approve | Can go |
|---|---|---|---|
| libs-back 0002: window types for menus, tool tips, drag images, modal panels | `libs-back-0002.md` | `25affcd98513fd08554fa8cd931348f236143909` | now, on its own |
| libs-back 0003: an alpha channel for borderless windows, when a theme asks | `libs-back-0003.md` | `b94dc1b79bb56ac9cde6b0dbffa289e4ff8c56c3` | now, on its own |
| libs-back 0004: window shadows and rounded corners | `libs-back-0004.md` | `fd508976ce0a3dace81dbd9f7542e14b721bdcf9` | after 0003 is merged (needs 0001 in practice) |
| libs-back 0005: popover shadows for menus | `libs-back-0005.md` | `0c7dc1f0fc0bbdb53d029c8927c6201a227481fb` | after 0004 is merged |
| libs-back 0006: WM_DELETE_WINDOW on closable windows the gui decorates (Alt+F4 under Mutter kills the app) | `libs-back-0006.md` | `1ecd259c67e04f8bd174b4e43efecdf1bc7c6cf6` (**approved 2026-10-15**) | **parked (2026-10-15):** Dan decided to carry it locally and not send it for now (relayed from the LinDirStat session). Approved at `1ecd259`; PR text `../pr/libs-back-0006.md` and the #244 note `../pr/libs-back-244-comment-0006.md` kept, not approved. If it is revisited, it still must land before or with #244 |
| libs-gui 0001: a theme can turn GNUstep-drawn decorations on | `libs-gui-0001.md` | `bd5a9830b1443c41bcf1b26ef7e48df6c6614764` | now, on its own |
| libs-gui issue 14: NSPrintOperation's did-run callback arguments | `../../upstream-issues/review/issue-14.md` | draft `4cc1a76c9b3d5a6e6abb31acaa74067bc5b63885`, reproducer `a842659bd9ac8180b6abd06b5b02dd95f15d43c3` | now |
| libs-gui issue 15: a display pass draws a still-dirty opaque subview again, over the siblings above it (Adwaita #47, WinUI #87) | `../../upstream-issues/15-libs-gui-display-order-overdraws-siblings.md` (the draft is its own summary) | draft `12fabc6d2fbac65493d6a47320541c41e758c86e`, reproducer `e850daf5ba495c937a18a27a0cecfe3760de7142` | now; the WinUI theme will link it rather than file its own |

Approve with, for example: "I approve libs-back-0003" or "I approve
libs-gui issue 14 4cc1a76/a842659".

**Checked on 2026-10-08:**

- **libs-back master** has moved one commit since the packets were made (`9c7bcce`, "Fix leaks in testcases", in `Tests/gsc/` only). The four libs-back branches still merge onto it cleanly (`git merge-tree`), so no rebase is needed and the hashes stand.
- **libs-gui master** is still `549f639`.
- **Already sent:** libs-back 0001, as libs-back#244 (open, no reply yet). libs-gui issues 2, 4 and 11 were filed as #991, #990 and #989 (open, no replies).

**Suggested order:** 0003 and libs-gui 0001 first, since both stand alone and are small. Then 0002, then issue 14. 0004 and 0005 follow as the ones below them are merged.
