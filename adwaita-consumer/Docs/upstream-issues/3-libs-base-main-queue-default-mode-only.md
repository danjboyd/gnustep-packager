**Repository:** gnustep/libs-base

**Filed:** [gnustep/libs-base#806](https://github.com/gnustep/libs-base/issues/806), 2026-10-02 (reproduced again on 1.31.1; unchanged on master 2e5067f8e)

**Title:** Main dispatch queue is only drained in NSDefaultRunLoopMode (stalls during modal loops, sheets, and tracking)

### Summary

With libdispatch run-loop integration (`GS_USE_LIBDISPATCH_RUNLOOP`), blocks
submitted to `dispatch_get_main_queue()` run only while the main run loop is
in `NSDefaultRunLoopMode`. While the run loop is in
`NSModalPanelRunLoopMode` or `NSEventTrackingRunLoopMode`, they wait. In
AppKit that means any main-queue work stalls while a modal panel or sheet is
up (`-beginSheet:...` runs a modal loop in GNUstep), or while a menu or a
scroller is being tracked. Code that blocks waiting for that work never
finishes.

On macOS the main queue is serviced in the common modes, which include both
the modal-panel and event-tracking modes.

### Steps to reproduce

Excerpt below; the complete program is `main_queue_modes.m`, to paste in or attach. It uses Foundation only: it queues a block on the
main queue, runs the run loop in one mode for up to one second, and reports
whether the block ran.

```objc
static BOOL
drainsInMode(NSString *mode)
{
  __block BOOL ran = NO;
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: 1.0];
  /* Keep the mode alive: a mode with no input sources returns at once. */
  NSTimer *keepAlive = [NSTimer timerWithTimeInterval: 0.1 target: loop
                                             selector: @selector(description)
                                             userInfo: nil repeats: YES];

  [loop addTimer: keepAlive forMode: mode];
  dispatch_async(dispatch_get_main_queue(), ^{ ran = YES; });
  while (ran == NO && [limit timeIntervalSinceNow] > 0)
    {
      [loop runMode: mode beforeDate: limit];
    }
  [keepAlive invalidate];
  /* (the program then drains the leftover block in the default mode) */
  return ran;
}
```

Output:

```
main-queue block runs within 1s in NSDefaultRunLoopMode: yes
main-queue block runs within 1s in NSModalPanelRunLoopMode: NO
main-queue block runs within 1s in NSEventTrackingRunLoopMode: NO
```

The same thing happens in an AppKit app: a block posted from a background
queue to the main queue doesn't run while
`-beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:` is
showing a sheet (checked 2.2 seconds after the sheet appeared; with no sheet,
the same block runs straight away).

### Cause

`+[NSRunLoop _runLoopForThread:]` (Source/NSRunLoop.m, line 945 on master)
registers the main queue's file descriptor for one mode only:

```objc
[current addEvent: [GSMainQueueDrainer mainQueueFileDescriptor]
             type: ET_RDESC
          watcher: drainer
          forMode: NSDefaultRunLoopMode];
```

### Suggested fix

Also register the drainer for `NSModalPanelRunLoopMode` and
`NSEventTrackingRunLoopMode` (the AppKit mode names, as string literals), to
match Apple's behaviour. libs-base defines `NSRunLoopCommonModes`, but as far
as I can tell it has no common-modes behaviour, so registering for it alone
wouldn't cover the other modes. Implementing common modes properly would be
the more complete fix.

### Environment

- libs-base master a8dd1b8 (2026-09-23), also the released 1.31.1.
- Debian 13, clang 19, libobjc2 (gnustep-2.2 runtime), swift-corelibs-libdispatch
  (configure found `_dispatch_main_queue_callback_4CF` and
  `_dispatch_get_main_queue_handle_4CF`).
