/*
   Copyright (C) 2026 Daniel Boyd

   This file is part of the GNUstep Adwaita theme.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/>.
*/

/* GNOME's settings, followed while the app runs (#64).

   GSettings tells its "changed" handlers from GLib's default main
   context, and nothing iterates that context in a GNUstep app. So the
   context is run from the NSRunLoop, as GTK runs it from its own loop:
   prepare it, watch the descriptors g_main_context_query() hands back
   (with -addEvent:type:watcher:forMode:, in the run loop modes an app
   spends its time in), and when one is readable or the context's next
   timeout is due, check and dispatch it and prepare it again. No polling
   and no extra thread. A change is told to the theme once for a batch:
   GNOME Settings writes some keys together. */

#import "GnomeThemeSettingsMonitor.h"

#import <AppKit/AppKit.h>
#include <gio/gio.h>

NSString *GnomeThemeDesktopSettingsDidChangeNotification
  = @"GnomeThemeDesktopSettingsDidChangeNotification";

/* The settings the theme reads (GnomeThemeSettings.m). */
static const char *GnomeThemeMonitoredSchemas[] = {
  "org.gnome.desktop.interface",
  "org.gnome.desktop.a11y.interface",
  "org.gnome.desktop.wm.preferences",
  NULL
};

#define GNOME_THEME_MONITORED_MAX 3

static NSArray *
GnomeThemeMonitorModes(void)
{
  return [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                  NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil];
}

/* GLib's default main context, run from the NSRunLoop. */
@interface GnomeThemeGLibRunLoopSource : NSObject <RunLoopEvents>
{
  GMainContext *_context;
  GPollFD *_fds;
  gint _allocated;
  gint _count;
  gint _priority;
  BOOL _prepared;
  BOOL _running;
  NSTimer *_timer;
  NSMutableArray *_watched;
}
- (id) initWithContext: (GMainContext *)context;
- (void) invalidate;
@end

@interface GnomeThemeGLibRunLoopSource (Private)
- (void) prepare;
- (void) runContext;
- (void) watchDescriptors;
- (void) unwatchDescriptors;
- (void) scheduleTimeout: (gint)timeout;
@end

@implementation GnomeThemeGLibRunLoopSource

- (id) initWithContext: (GMainContext *)context
{
  self = [super init];
  if (self != nil)
    {
      /* The main thread owns the context from now on; another owner
         (an app running its own GLib loop on another thread) wins. */
      if (g_main_context_acquire (context) == FALSE)
        {
          DESTROY (self);
          return nil;
        }
      _context = g_main_context_ref (context);
      _allocated = 8;
      _fds = g_new0 (GPollFD, _allocated);
      _watched = [NSMutableArray new];
      [self prepare];
    }
  return self;
}

- (void) invalidate
{
  [_timer invalidate];
  DESTROY (_timer);
  [self unwatchDescriptors];
  if (_context != NULL)
    {
      g_main_context_release (_context);
      g_main_context_unref (_context);
      _context = NULL;
    }
}

- (void) dealloc
{
  [self invalidate];
  g_free (_fds);
  RELEASE (_watched);
  [super dealloc];
}

/* RunLoopEvents: one of the context's descriptors is readable. */
- (void) receivedEvent: (void *)data
                  type: (RunLoopEventType)type
                 extra: (void *)extra
               forMode: (NSString *)mode
{
  [self runContext];
}

- (void) timeoutFired: (NSTimer *)timer
{
  if (timer == _timer)
    {
      DESTROY (_timer);
    }
  [self runContext];
}

@end

@implementation GnomeThemeGLibRunLoopSource (Private)

- (void) prepare
{
  gint timeout = -1;
  gint needed;
  gboolean ready;

  if (_context == NULL || _prepared)
    {
      return;
    }
  ready = g_main_context_prepare (_context, &_priority);
  while ((needed = g_main_context_query (_context, _priority, &timeout,
                                         _fds, _allocated)) > _allocated)
    {
      _allocated = needed;
      _fds = g_renew (GPollFD, _fds, _allocated);
    }
  _count = needed;
  _prepared = YES;
  [self watchDescriptors];
  [self scheduleTimeout: ready ? 0 : timeout];
}

/* Check and dispatch the context, then prepare it for the next round. */
- (void) runContext
{
  if (_context == NULL || _running)
    {
      return;
    }
  _running = YES;
  if (_prepared == NO)
    {
      [self prepare];
    }
  else
    {
      [_timer invalidate];
      DESTROY (_timer);
      g_poll (_fds, _count, 0);
      _prepared = NO;
      if (g_main_context_check (_context, _priority, _fds, _count))
        {
          g_main_context_dispatch (_context);
        }
      [self prepare];
    }
  _running = NO;
}

- (void) watchDescriptors
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = GnomeThemeMonitorModes ();
  NSMutableArray *wanted = [NSMutableArray array];
  NSEnumerator *enumerator;
  NSNumber *fd;
  NSString *mode;
  gint i;

  for (i = 0; i < _count; i++)
    {
      if (_fds[i].events & (G_IO_IN | G_IO_HUP | G_IO_ERR))
        {
          NSNumber *number = [NSNumber numberWithInt: _fds[i].fd];

          if ([wanted containsObject: number] == NO)
            {
              [wanted addObject: number];
            }
        }
    }
  if ([wanted isEqualToArray: _watched])
    {
      return;
    }
  [self unwatchDescriptors];
  enumerator = [wanted objectEnumerator];
  while ((fd = [enumerator nextObject]) != nil)
    {
      NSEnumerator *modeEnumerator = [modes objectEnumerator];

      while ((mode = [modeEnumerator nextObject]) != nil)
        {
          [loop addEvent: (void *)(intptr_t)[fd intValue]
                    type: ET_RDESC
                 watcher: self
                 forMode: mode];
        }
    }
  [_watched setArray: wanted];
}

- (void) unwatchDescriptors
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  NSArray *modes = GnomeThemeMonitorModes ();
  NSEnumerator *enumerator = [_watched objectEnumerator];
  NSNumber *fd;

  while ((fd = [enumerator nextObject]) != nil)
    {
      NSEnumerator *modeEnumerator = [modes objectEnumerator];
      NSString *mode;

      while ((mode = [modeEnumerator nextObject]) != nil)
        {
          [loop removeEvent: (void *)(intptr_t)[fd intValue]
                       type: ET_RDESC
                    forMode: mode
                        all: NO];
        }
    }
  [_watched removeAllObjects];
}

- (void) scheduleTimeout: (gint)timeout
{
  NSEnumerator *enumerator;
  NSString *mode;

  [_timer invalidate];
  DESTROY (_timer);
  if (timeout < 0)
    {
      return;
    }
  _timer = RETAIN ([NSTimer timerWithTimeInterval: timeout / 1000.0
                                            target: self
                                          selector: @selector(timeoutFired:)
                                          userInfo: nil
                                           repeats: NO]);
  enumerator = [GnomeThemeMonitorModes () objectEnumerator];
  while ((mode = [enumerator nextObject]) != nil)
    {
      [[NSRunLoop currentRunLoop] addTimer: _timer forMode: mode];
    }
}

@end

/* Posts the notification once for a batch of changes. */
@interface GnomeThemeSettingsNotifier : NSObject
+ (void) noteChange;
+ (void) postChange;
@end

static BOOL GnomeThemeChangePending = NO;

@implementation GnomeThemeSettingsNotifier

+ (void) noteChange
{
  if (GnomeThemeChangePending)
    {
      return;
    }
  GnomeThemeChangePending = YES;
  [self performSelector: @selector(postChange)
             withObject: nil
             afterDelay: 0.1
                inModes: GnomeThemeMonitorModes ()];
}

+ (void) postChange
{
  GnomeThemeChangePending = NO;
  [[NSNotificationCenter defaultCenter]
    postNotificationName: GnomeThemeDesktopSettingsDidChangeNotification
                  object: nil];
}

@end

static GnomeThemeGLibRunLoopSource *GnomeThemeMonitorSource = nil;
static GSettings *GnomeThemeMonitoredSettings[GNOME_THEME_MONITORED_MAX];
static gulong GnomeThemeMonitorHandlers[GNOME_THEME_MONITORED_MAX];
static BOOL GnomeThemeMonitorStarted = NO;

static void
GnomeThemeSettingChanged(GSettings *settings, gchar *key, gpointer data)
{
  [GnomeThemeSettingsNotifier noteChange];
}

/* GSettings tells "changed" only for keys read since a handler was
   connected: read each one once. */
static void
GnomeThemeReadAllKeys(GSettings *settings, GSettingsSchema *schema)
{
  gchar **keys = g_settings_schema_list_keys (schema);
  gchar **key;

  for (key = keys; key != NULL && *key != NULL; key++)
    {
      GVariant *value = g_settings_get_value (settings, *key);

      if (value != NULL)
        {
          g_variant_unref (value);
        }
    }
  g_strfreev (keys);
}

void
GnomeThemeSettingsMonitorStart(void)
{
  GSettingsSchemaSource *source = g_settings_schema_source_get_default ();
  NSUInteger count = 0;
  NSUInteger i;

  if (GnomeThemeMonitorStarted || source == NULL)
    {
      return;
    }
  GnomeThemeMonitorStarted = YES;
  for (i = 0; GnomeThemeMonitoredSchemas[i] != NULL; i++)
    {
      GSettingsSchema *schema = g_settings_schema_source_lookup (source, GnomeThemeMonitoredSchemas[i], TRUE);

      GnomeThemeMonitoredSettings[i] = NULL;
      GnomeThemeMonitorHandlers[i] = 0;
      if (schema == NULL)
        {
          continue;
        }
      GnomeThemeMonitoredSettings[i] = g_settings_new_full (schema, NULL, NULL);
      GnomeThemeMonitorHandlers[i]
        = g_signal_connect (GnomeThemeMonitoredSettings[i], "changed",
                            G_CALLBACK (GnomeThemeSettingChanged), NULL);
      GnomeThemeReadAllKeys (GnomeThemeMonitoredSettings[i], schema);
      g_settings_schema_unref (schema);
      count++;
    }
  if (count > 0)
    {
      GnomeThemeMonitorSource
        = [[GnomeThemeGLibRunLoopSource alloc] initWithContext: g_main_context_default ()];
    }
  if (GnomeThemeMonitorSource == nil)
    {
      GnomeThemeSettingsMonitorStop ();
    }
}

void
GnomeThemeSettingsMonitorStop(void)
{
  NSUInteger i;

  for (i = 0; i < GNOME_THEME_MONITORED_MAX; i++)
    {
      if (GnomeThemeMonitoredSettings[i] != NULL)
        {
          g_signal_handler_disconnect (GnomeThemeMonitoredSettings[i],
                                       GnomeThemeMonitorHandlers[i]);
          g_object_unref (GnomeThemeMonitoredSettings[i]);
          GnomeThemeMonitoredSettings[i] = NULL;
        }
    }
  [GnomeThemeMonitorSource invalidate];
  DESTROY (GnomeThemeMonitorSource);
  GnomeThemeMonitorStarted = NO;
}
