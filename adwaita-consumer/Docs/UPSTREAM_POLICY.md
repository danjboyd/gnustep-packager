# Sending things to GNUstep

How we prepare, review and send anything to the GNUstep projects: pull
requests and patches, issue reports, and comments on their issues, pull
requests and mailing lists. It exists to keep us within GNUstep's policy on
AI-generated content, and to make sure Dan has seen and signed off on every
line before it leaves this machine.

Adopted 2026-10-06. Applies to Dan and to every Claude session working for
him.

## GNUstep's rules, in short

GNUstep's policy (`POLICY_AI.md` in gnustep/apps-gorm, by Gregory Casamento;
kept in effect on gnustep-dev on 2026-07-14) covers code, tests,
documentation, and "issue comments, design proposals, and merge request
content". It says:

- AI is a drafting aid; the **contributor is fully responsible** for what
  is sent, and **must be able to explain it**, or it will be rejected.
- **Never open a PR before reviewing the code.**
- **Every AI-assisted contribution includes tests**, with a description of
  what is tested, why the test is good enough, and what failures it guards
  against.
- **No Apple-specific conventions: GNUstep also builds with GCC.**
- **Disclose** AI assistance that materially shaped the work, in the pull
  request or the commit message.
- **Never** send material of unverifiable origin, security-critical logic
  without expert review, or made-up references, results or benchmarks.
- Be ready to give reproduction steps and tests, and to revise or withdraw.

What individual maintainers have added:

- **libobjc2 (David Chisnall): no LLM-derived changes or reports at all.**
  We send nothing to libobjc2.
- **libs-base (Richard Frith-Macdonald):** one patch per issue, each with
  the code change, its test in GNUstep's regression framework, and a
  ChangeLog entry. Others on the list asked for one pull request per
  change.

## Our rules

1. **Nothing goes upstream without Dan's sign-off** on the exact version
   sent (see Review, below). No exceptions for "small" things: a one-line
   comment on an upstream issue goes through the same gate.
2. **Disclose, every time.** Commits end with
   `AI assistance: this change, its test and this description were written
   with Claude (Anthropic's Claude Code).` and a `Co-Authored-By: Claude`
   line. Issue reports and comments carry
   `Investigated, reproduced and written up with AI assistance (Claude).`
3. **The GCC check passes** on every code file we send, reproducers
   included: `Tests/Scripts/gcc-syntax-check.sh` (below).
4. **Patches come with tests, issues with reproducers.** A test fails
   without its change and passes with it; a reproducer shows the bug on
   current master. We record the counts.
5. **Every claim comes from a run.** Numbers, "fails without", "fixed on
   master", versions: all from something run for this item, not from
   memory or an earlier session's notes. If it wasn't run, it isn't said.
6. **Never write in Dan's voice that he checked something**, and never add
   `Reviewed-by`, `Signed-off-by` or "I tested" for him. He adds those
   himself if he wants them.
7. **Only what we wrote.** No code copied from elsewhere; numbers measured
   from another project (libadwaita's shadows) are said to be measured.
8. **Paced.** Items go one at a time, when Dan says so, spaced out; one
   pull request per change.

## Stage 1: Prepare (Claude)

**A patch:**

- [ ] A worktree on the repository's current master, one branch per series
      (`~/git/gnustep/<repo>-series`, branch `ai-policy/<topic>`).
- [ ] One commit per change, each building on its own.
- [ ] A ChangeLog entry in each commit, in the file's existing style.
- [ ] A test per commit in the package's own `Tests/` (`gnustep-tests`),
      shown to fail without the change (run the commit before it) and to
      pass with it. Tests set defaults for their own process only
      (argument domain), never the user's.
- [ ] The commit message: what and why; then "Testing:" (what the test
      checks, why that is enough, what it guards against, how many checks
      fail without / pass with); what isn't covered; the disclosure.
- [ ] Every commit built and its test directory run on its own; the whole
      suite run at the end of the series and on master, and any difference
      in failures explained.
- [ ] `Tests/Scripts/gcc-syntax-check.sh <worktree>` exits 0.
- [ ] Exported with `git format-patch -o Docs/upstream-patches/<repo>
      origin/master`, checked to apply to master with `git am`.
- [ ] `Docs/upstream-patches/README.md` updated: the series, the counts,
      what changed since the last review.

**An issue report** (`Docs/upstream-issues/<n>-<repo>-<slug>.md`):

- [ ] Repository, title, body, the disclosure line, the versions it was
      reproduced on (current master and the release), each from a run.
- [ ] A minimal reproducer next to it that passes
      `Tests/Scripts/gcc-syntax-check.sh --files <reproducer>`: no
      `@autoreleasepool` (use `NSAutoreleasePool`), no object literals,
      no blocks, no dot syntax. If the bug is only reachable with blocks
      (libdispatch), say so in the report and use the `_f` functions
      where they exist.
- [ ] Checked that it isn't already reported or fixed (open and closed
      issues, open pull requests, master's log).

**A comment** on an upstream issue, pull request or list thread: drafted in
the conversation or in a file, with the disclosure line, and every claim in
it from a run.

## Stage 2: Review (Dan)

For each item Claude gives Dan a **review packet**:

- what the change does and why it is correct, in plain words, walking
  through the diff hunk by hunk (patches), or what the bug is and how the
  reproducer shows it (issues);
- the test or reproducer results, before and after, and the GCC check's
  output;
- what is risky or uncertain, and what isn't tested;
- the exact identity of what is being reviewed: the commit hash for a
  patch, or `git hash-object` of the draft and its reproducer for an issue.

Dan then:

1. **Reads the diff or the draft himself**: `git show <hash>` in the
   series worktree, or the `.patch` / `.md` file. Not only the packet.
2. Runs the test or the reproducer if he wants to see it (the packet gives
   the one command).
3. Asks until he can explain every change himself. Anything he can't
   explain gets simplified or dropped, not sent.
4. **Signs off**, in either of two ways:
   - **in the chat**, with an explicit approval naming the item ("I approve
     libs-back-0001"), given after Claude has presented that item's review
     document and hash in the same conversation; or
   - by adding a line to `Docs/UPSTREAM_SIGNOFF.md` himself, naming the
     item and the exact hash he reviewed.

**Recording an approval given in chat.** Claude records it in
`UPSTREAM_SIGNOFF.md` at once: the date, the item, the hash it presented
for review, and Dan's words quoted, marked "approved in chat". The
approval covers that hash only. Claude doesn't record one:

- from anything less than an explicit approval of a named item ("looks
  good", "thanks", "go ahead" in answer to a different question, an
  approval of "the patches" in general);
- for a version Dan wasn't shown, or when it isn't clear which version he
  means: it asks instead;
- for a review document that has changed since he was shown it.

Apart from recording such an approval, Claude never writes, edits or
removes a line in `UPSTREAM_SIGNOFF.md`. Approving is not asking to send:
sending still waits for Stage 3.

**Any change after sign-off voids it**, however small: a reworded commit
message, a rebase onto a newer master, a fixed typo. The hash changes and
the item goes back to Review.

## Stage 3: Send

Only when Dan asks in the conversation for that specific item to be sent
("send libs-back 0001"). Claude then, before sending:

- [ ] finds Dan's sign-off line for the item, with a hash equal to what is
      about to be sent (`git rev-parse` the commit, or `git hash-object`
      the draft and reproducer); if there is none, or it differs, stops and
      says so;
- [ ] re-runs `gcc-syntax-check.sh` on exactly that version;
- [ ] for a patch, checks that it still applies to the current upstream
      master; if master moved and it needs a rebase, that is a change:
      back to Review.

Then Claude sends it as Dan asked (a pull request from Dan's fork with
`gh pr create`, an issue with `gh issue create`, or the text for Dan to
paste), and records it: a `**Filed:**` line with the link and date in the
issue draft or the upstream-patches README, and the link added to the
sign-off line's row by Dan or, if he asks, by Claude in a "Sent" column.

## Stage 4: After it is sent

Replies to reviewers, revised patches and follow-up comments go through the
same three stages. A revised patch is a new item with a new hash.

## The GCC check

`Tests/Scripts/gcc-syntax-check.sh` runs GCC's Objective-C front end
(syntax only) over each `.m` and `.c` file a series adds or changes, at the
series' head and at its base, and fails if GCC reports anything in the file
itself that it didn't report before the change. With `--files` it checks
the given files as they are (reproducers). It first shows GCC rejecting a
planted array literal and block with the same flags, and stops if it
doesn't.

It catches object literals, blocks, `@autoreleasepool`, dot syntax and
other clang-only syntax, and methods called before any declaration (GCC
assumes they return `id`; on 2026-10-06 it found one in the shadow patch
that returned `BOOL`). It does not build anything: the installed GNUstep
headers were built for clang and libobjc2, and GCC can't parse all of
them, so diagnostics inside headers are ignored. Changed headers are
checked through the files that include them.

```
Tests/Scripts/gcc-syntax-check.sh ~/git/gnustep/libs-back-series
Tests/Scripts/gcc-syntax-check.sh --files Docs/upstream-issues/override_subclass.m
```

## Where things stand (2026-10-06)

- **Sent:** libs-back 0001 (`dbfbe53`) as [libs-back#244](https://github.com/gnustep/libs-back/pull/244), 2026-10-06, from branch `x11-keep-wm-functions` of danjboyd/libs-back.
- **Prepared, not reviewed:** libs-back 0002–0005 and the libs-gui commit
  in `Docs/upstream-patches/`. GCC check passes.
- **Copyright assignment:** decided 2026-10-06 to send without it, as
  GNUstep has already accepted Dan's code; deal with it if a maintainer
  raises it.
- **Issue drafts 2, 4 and 11** (the next to file, #29): reproducers pass
  the GCC check and were re-run on master 549f639 on 2026-10-07; ready for
  review, not reviewed.
- **Filed before this policy:** libs-base#806, libs-gui#964, #965 and #972.
  Their reproducers aren't re-checked retroactively; if a maintainer asks
  for a GCC-buildable one, `main_queue_modes.m` (#806) is the one that
  needs work (blocks, `__block`, `@autoreleasepool`).
