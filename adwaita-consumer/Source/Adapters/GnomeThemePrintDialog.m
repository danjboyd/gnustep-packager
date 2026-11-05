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

/* The print panel as GNOME's print dialog, asked for through the XDG
   desktop portal (org.freedesktop.portal.Print) as GTK and Flatpak apps
   ask for it, parented to the app's window (plugins-themes-Adwaita#52).

   GNUstep asks the theme for the print panel's class (-printPanelClass).
   Its runs ask the portal's PreparePrint when they can: the dialog's
   settings and page setup go into the NSPrintInfo, and the run returns OK
   or Cancel as GNUstep's panel does. The operation then renders the
   document to a PDF file (a save job: GNUstep's printing bundles draw PDF
   for a path ending in .pdf), and instead of spooling it,
   -[GSPrintOperation deliverResult] hands the file to the portal's Print
   with PreparePrint's token, so GNOME prints it on the printer chosen in
   its dialog, or writes it to the file chosen there.

   GNUstep's own panel runs when GnomeThemeNativePrintDialog is NO, when
   the panel has an accessory view or accessory controllers (the portal
   can't show them), or when the portal call fails (no portal, or one
   without Print). The page layout panel stays GNUstep's: the portal has
   no page setup dialog of its own (its print dialog has the page setup).

   A run blocks until the dialog answers, as GNUstep's modal panels and
   sheets do; meanwhile the app redraws and takes no input. The portal's
   answers are D-Bus signals, dispatched on a GLib main context of its own
   that the wait pumps. */

#import "../GnomeTheme.h"
#import "GnomeThemeWindowManager.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>

#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <fcntl.h>
#include <unistd.h>

static NSString *const GnomeThemePrintDialogDefault = @"GnomeThemeNativePrintDialog";

/* Kept in the NSPrintInfo's dictionary between the dialog and the
   delivery of the job. */
static NSString *const GnomeThemePrintTokenKey = @"GnomeThemePrintPortalToken";
static NSString *const GnomeThemePrintParentKey = @"GnomeThemePrintPortalParent";
static NSString *const GnomeThemePrintTitleKey = @"GnomeThemePrintPortalTitle";
static NSString *const GnomeThemePrintJobKey = @"GnomeThemePrintPortalJob";
static NSString *const GnomeThemePrintOrientationKey = @"GnomeThemePrintPortalOrientation";

#pragma mark Portal requests

/* One PreparePrint or Print call and its answer. */
@interface GnomeThemePrintRequest : NSObject
{
@public
  BOOL done;
  guint32 response;             /* 0 done, 1 cancelled, 2 failed. */
  GVariant *results;
  GDBusConnection *bus;
  guint subscription;
}
@end

static GMainContext *
GnomeThemePrintContext(void)
{
  static GMainContext *context = NULL;

  if (context == NULL)
    {
      context = g_main_context_new ();
    }
  return context;
}

static void
GnomeThemePrintResponse(GDBusConnection *connection, const gchar *sender, const gchar *path,
                        const gchar *interface, const gchar *signal, GVariant *parameters,
                        gpointer data)
{
  GnomeThemePrintRequest *request = (GnomeThemePrintRequest *)data;

  if (request->done == NO && g_variant_is_of_type (parameters, G_VARIANT_TYPE ("(ua{sv})")))
    {
      g_variant_get (parameters, "(u@a{sv})", &request->response, &request->results);
      request->done = YES;
    }
}

@implementation GnomeThemePrintRequest

- (void) dealloc
{
  if (subscription != 0)
    {
      g_dbus_connection_signal_unsubscribe (bus, subscription);
    }
  if (bus != NULL)
    {
      g_object_unref (bus);
    }
  if (results != NULL)
    {
      g_variant_unref (results);
    }
  [super dealloc];
}

- (void) subscribeToPath: (const char *)path
{
  GMainContext *context = GnomeThemePrintContext ();

  if (subscription != 0)
    {
      g_dbus_connection_signal_unsubscribe (bus, subscription);
    }
  /* The signal is dispatched on the context that is the thread's default
     when subscribing. */
  g_main_context_push_thread_default (context);
  subscription = g_dbus_connection_signal_subscribe (bus, "org.freedesktop.portal.Desktop",
                                                     "org.freedesktop.portal.Request", "Response", path,
                                                     NULL, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE,
                                                     GnomeThemePrintResponse, self, NULL);
  g_main_context_pop_thread_default (context);
}

/* Calls method with the arguments built by `arguments`, which gets the
   options with the request's handle_token added; fds, if any, go with
   the call. NO when the call fails. */
- (BOOL) start: (const char *)method
     arguments: (GVariant *(^)(GVariantBuilder *options))arguments
       options: (GVariantBuilder *)options
           fds: (GUnixFDList *)fds
{
  static unsigned long serial = 0;
  NSString *token;
  NSMutableString *sender;
  NSString *expected;
  GVariant *reply;
  GError *error = NULL;
  const char *handle = NULL;

  bus = g_bus_get_sync (G_BUS_TYPE_SESSION, NULL, NULL);
  if (bus == NULL)
    {
      g_variant_builder_clear (options);
      return NO;
    }

  /* The request's object path follows from the token and the bus name;
     subscribe before calling, as the answer can come before the reply. */
  token = [NSString stringWithFormat: @"gnustepprint%d_%lu", (int)getpid (), ++serial];
  sender = [NSMutableString stringWithUTF8String: g_dbus_connection_get_unique_name (bus) + 1];
  [sender replaceOccurrencesOfString: @"." withString: @"_" options: 0 range: NSMakeRange (0, [sender length])];
  expected = [NSString stringWithFormat: @"/org/freedesktop/portal/desktop/request/%@/%@", sender, token];
  [self subscribeToPath: [expected UTF8String]];

  g_variant_builder_add (options, "{sv}", "handle_token", g_variant_new_string ([token UTF8String]));
  reply = g_dbus_connection_call_with_unix_fd_list_sync (bus, "org.freedesktop.portal.Desktop",
                                                         "/org/freedesktop/portal/desktop",
                                                         "org.freedesktop.portal.Print", method,
                                                         arguments (options), G_VARIANT_TYPE ("(o)"),
                                                         G_DBUS_CALL_FLAGS_NONE, -1, fds, NULL, NULL,
                                                         &error);
  if (reply == NULL)
    {
      NSDebugLLog (@"GnomeTheme", @"print portal: %s", error->message);
      g_error_free (error);
      return NO;
    }
  /* Portals before 0.9 choose the path themselves. */
  g_variant_get (reply, "(&o)", &handle);
  if (strcmp (handle, [expected UTF8String]) != 0)
    {
      [self subscribeToPath: handle];
    }
  g_variant_unref (reply);
  return YES;
}

@end

/* Input to the app while it waits for the dialog: dropped, as a modal
   panel's run drops input to other windows. */
static BOOL
GnomeThemePrintIsInputEvent(NSEvent *event)
{
  switch ([event type])
    {
    case NSLeftMouseDown:
    case NSLeftMouseUp:
    case NSRightMouseDown:
    case NSRightMouseUp:
    case NSOtherMouseDown:
    case NSOtherMouseUp:
    case NSMouseMoved:
    case NSLeftMouseDragged:
    case NSRightMouseDragged:
    case NSOtherMouseDragged:
    case NSMouseEntered:
    case NSMouseExited:
    case NSScrollWheel:
    case NSKeyDown:
    case NSKeyUp:
    case NSFlagsChanged:
    case NSCursorUpdate:
      return YES;
    case NSAppKitDefined:
      /* The window manager's close button. */
      return [event subtype] == GSAppKitWindowClose;
    default:
      return NO;
    }
}

/* Waits for the portal's answer, as a modal run does. */
static void
GnomeThemePrintWait(GnomeThemePrintRequest *request)
{
  while (request->done == NO)
    {
      CREATE_AUTORELEASE_POOL (pool);
      NSEvent *event;

      while (g_main_context_iteration (GnomeThemePrintContext (), FALSE))
        {
        }
      if (request->done)
        {
          RELEASE (pool);
          break;
        }
      event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                 untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                    inMode: NSModalPanelRunLoopMode
                                   dequeue: YES];
      if (event == nil || GnomeThemeHeaderBarMoveWindowFromModalPress (event))
        {
          /* The app's window still moves from its header bar (#43). */
        }
      else if (GnomeThemePrintIsInputEvent (event) == NO)
        {
          [NSApp sendEvent: event];
        }
      RELEASE (pool);
    }
}

#pragma mark Settings

/* GNUstep's paper names and their PWG names, as GTK's paper sizes are
   named. Others go by size, with their own name as the display name. */
static NSString *const GnomeThemePaperNames[][2] = {
  { @"A3", @"iso_a3" },
  { @"A4", @"iso_a4" },
  { @"A5", @"iso_a5" },
  { @"B4", @"iso_b4" },
  { @"B5", @"iso_b5" },
  { @"Letter", @"na_letter" },
  { @"Legal", @"na_legal" },
  { @"Executive", @"na_executive" },
  { @"Tabloid", @"na_ledger" },
};

static NSString *
GnomeThemePWGPaperName(NSString *name)
{
  NSUInteger i;

  for (i = 0; i < sizeof (GnomeThemePaperNames) / sizeof (GnomeThemePaperNames[0]); i++)
    {
      if ([name caseInsensitiveCompare: GnomeThemePaperNames[i][0]] == NSOrderedSame)
        {
          return GnomeThemePaperNames[i][1];
        }
    }
  return nil;
}

static NSString *
GnomeThemeGNUstepPaperName(NSString *pwg)
{
  NSUInteger i;

  for (i = 0; i < sizeof (GnomeThemePaperNames) / sizeof (GnomeThemePaperNames[0]); i++)
    {
      if ([pwg isEqualToString: GnomeThemePaperNames[i][1]])
        {
          return GnomeThemePaperNames[i][0];
        }
    }
  return nil;
}

static const CGFloat GnomeThemePointsPerMM = 72.0 / 25.4;

static void
GnomeThemeAddSetting(GVariantBuilder *settings, const char *key, NSString *value)
{
  g_variant_builder_add (settings, "{sv}", key, g_variant_new_string ([value UTF8String]));
}

/* The NSPrintInfo as GtkPrintSettings (all values strings; page ranges
   counted from 0, as GTK writes them). */
static GVariant *
GnomeThemePrintSettings(NSPrintInfo *info)
{
  NSDictionary *dict = [info dictionary];
  GVariantBuilder settings;
  NSString *pwg = GnomeThemePWGPaperName ([info paperName]);
  id value;

  g_variant_builder_init (&settings, G_VARIANT_TYPE_VARDICT);
  value = [dict objectForKey: NSPrintCopies];
  GnomeThemeAddSetting (&settings, "n-copies",
                        [NSString stringWithFormat: @"%d", MAX (1, value ? [value intValue] : 1)]);
  GnomeThemeAddSetting (&settings, "collate", [[dict objectForKey: NSPrintMustCollate] boolValue] ? @"true" : @"false");
  GnomeThemeAddSetting (&settings, "reverse",
                        [[dict objectForKey: NSPrintReversePageOrder] boolValue] ? @"true" : @"false");
  GnomeThemeAddSetting (&settings, "orientation",
                        [info orientation] == NSLandscapeOrientation ? @"landscape" : @"portrait");
  value = [dict objectForKey: NSPrintScalingFactor];
  GnomeThemeAddSetting (&settings, "scale",
                        [NSString stringWithFormat: @"%g", (value ? [value doubleValue] : 1.0) * 100.0]);
  value = [dict objectForKey: NSPrintAllPages];
  if (value != nil && [value boolValue] == NO
      && [dict objectForKey: NSPrintFirstPage] != nil && [dict objectForKey: NSPrintLastPage] != nil)
    {
      int first = [[dict objectForKey: NSPrintFirstPage] intValue];
      int last = [[dict objectForKey: NSPrintLastPage] intValue];

      GnomeThemeAddSetting (&settings, "print-pages", @"ranges");
      GnomeThemeAddSetting (&settings, "page-ranges",
                            [NSString stringWithFormat: @"%d-%d", MAX (0, first - 1), MAX (0, last - 1)]);
    }
  else
    {
      GnomeThemeAddSetting (&settings, "print-pages", @"all");
    }
  if (pwg != nil)
    {
      GnomeThemeAddSetting (&settings, "paper-format", pwg);
    }
  if ([[[info printer] name] length] > 0)
    {
      GnomeThemeAddSetting (&settings, "printer", [[info printer] name]);
    }
  return g_variant_builder_end (&settings);
}

/* The NSPrintInfo as a GtkPageSetup: the paper in mm as it stands in
   portrait, the margins, the orientation. */
static GVariant *
GnomeThemePrintPageSetup(NSPrintInfo *info)
{
  GVariantBuilder setup;
  NSSize paper = [info paperSize];
  NSString *name = [info paperName];
  NSString *pwg = GnomeThemePWGPaperName (name);
  CGFloat width = MIN (paper.width, paper.height);
  CGFloat height = MAX (paper.width, paper.height);

  g_variant_builder_init (&setup, G_VARIANT_TYPE_VARDICT);
  if (pwg != nil)
    {
      g_variant_builder_add (&setup, "{sv}", "Name", g_variant_new_string ([pwg UTF8String]));
    }
  if ([name length] > 0)
    {
      g_variant_builder_add (&setup, "{sv}", "DisplayName", g_variant_new_string ([name UTF8String]));
    }
  g_variant_builder_add (&setup, "{sv}", "Width", g_variant_new_double (width / GnomeThemePointsPerMM));
  g_variant_builder_add (&setup, "{sv}", "Height", g_variant_new_double (height / GnomeThemePointsPerMM));
  g_variant_builder_add (&setup, "{sv}", "MarginTop", g_variant_new_double ([info topMargin] / GnomeThemePointsPerMM));
  g_variant_builder_add (&setup, "{sv}", "MarginBottom",
                         g_variant_new_double ([info bottomMargin] / GnomeThemePointsPerMM));
  g_variant_builder_add (&setup, "{sv}", "MarginLeft",
                         g_variant_new_double ([info leftMargin] / GnomeThemePointsPerMM));
  g_variant_builder_add (&setup, "{sv}", "MarginRight",
                         g_variant_new_double ([info rightMargin] / GnomeThemePointsPerMM));
  g_variant_builder_add (&setup, "{sv}", "Orientation",
                         g_variant_new_string ([info orientation] == NSLandscapeOrientation ? "landscape" : "portrait"));
  return g_variant_builder_end (&setup);
}

static NSString *
GnomeThemeVardictString(GVariant *dict, const char *key)
{
  const gchar *value = NULL;

  if (dict != NULL && g_variant_lookup (dict, key, "&s", &value))
    {
      return [NSString stringWithUTF8String: value];
    }
  return nil;
}

static BOOL
GnomeThemeVardictDouble(GVariant *dict, const char *key, double *value)
{
  return dict != NULL && g_variant_lookup (dict, key, "d", value);
}

/* The dialog's page setup and settings, into the NSPrintInfo. */
static void
GnomeThemeApplyPrintResults(NSPrintInfo *info, GVariant *settings, GVariant *setup)
{
  NSMutableDictionary *dict = [info dictionary];
  NSString *orientation = GnomeThemeVardictString (setup, "Orientation");
  NSString *value;
  double width, height, margin;

  if (orientation == nil)
    {
      orientation = GnomeThemeVardictString (settings, "orientation");
    }
  if (GnomeThemeVardictDouble (setup, "Width", &width) && GnomeThemeVardictDouble (setup, "Height", &height)
      && width > 0 && height > 0)
    {
      NSString *name = GnomeThemeVardictString (setup, "Name");
      NSString *paper = (name != nil) ? GnomeThemeGNUstepPaperName (name) : nil;

      if (paper == nil)
        {
          paper = GnomeThemeVardictString (setup, "DisplayName");
        }
      if (paper == nil)
        {
          paper = GnomeThemeVardictString (setup, "PPDName");
        }
      /* GNUstep keeps the paper as it lies: wide for landscape. */
      [info setPaperSize: NSMakeSize (width * GnomeThemePointsPerMM, height * GnomeThemePointsPerMM)];
      if (paper != nil)
        {
          [dict setObject: paper forKey: NSPrintPaperName];
        }
    }
  if (orientation != nil)
    {
      [info setOrientation: [orientation hasSuffix: @"landscape"] ? NSLandscapeOrientation : NSPortraitOrientation];
    }
  if (GnomeThemeVardictDouble (setup, "MarginTop", &margin))
    {
      [info setTopMargin: margin * GnomeThemePointsPerMM];
    }
  if (GnomeThemeVardictDouble (setup, "MarginBottom", &margin))
    {
      [info setBottomMargin: margin * GnomeThemePointsPerMM];
    }
  if (GnomeThemeVardictDouble (setup, "MarginLeft", &margin))
    {
      [info setLeftMargin: margin * GnomeThemePointsPerMM];
    }
  if (GnomeThemeVardictDouble (setup, "MarginRight", &margin))
    {
      [info setRightMargin: margin * GnomeThemePointsPerMM];
    }

  if ((value = GnomeThemeVardictString (settings, "n-copies")) != nil && [value intValue] > 0)
    {
      [dict setObject: [NSNumber numberWithInt: [value intValue]] forKey: NSPrintCopies];
    }
  if ((value = GnomeThemeVardictString (settings, "collate")) != nil)
    {
      [dict setObject: [NSNumber numberWithBool: [value isEqualToString: @"true"]] forKey: NSPrintMustCollate];
    }
  if ((value = GnomeThemeVardictString (settings, "reverse")) != nil)
    {
      [dict setObject: [NSNumber numberWithBool: [value isEqualToString: @"true"]] forKey: NSPrintReversePageOrder];
    }
  if ((value = GnomeThemeVardictString (settings, "scale")) != nil && [value doubleValue] > 0)
    {
      [dict setObject: [NSNumber numberWithFloat: [value doubleValue] / 100.0] forKey: NSPrintScalingFactor];
    }
  /* The pages to draw. GNUstep draws one range: of several, the span
     from the first to the last page. "current" means the first page. */
  value = GnomeThemeVardictString (settings, "print-pages");
  if ([value isEqualToString: @"ranges"])
    {
      NSArray *ranges = [GnomeThemeVardictString (settings, "page-ranges") componentsSeparatedByString: @","];
      int first = INT_MAX, last = -1;
      NSUInteger i;

      for (i = 0; i < [ranges count]; i++)
        {
          NSArray *ends = [[ranges objectAtIndex: i] componentsSeparatedByString: @"-"];
          NSString *start = [ends objectAtIndex: 0];

          if ([start length] == 0)
            {
              continue;
            }
          first = MIN (first, [start intValue]);
          last = MAX (last, [ends count] > 1 && [[ends objectAtIndex: 1] length] > 0
                      ? [[ends objectAtIndex: 1] intValue] : [start intValue]);
        }
      if (last >= first)
        {
          [dict setObject: [NSNumber numberWithBool: NO] forKey: NSPrintAllPages];
          [dict setObject: [NSNumber numberWithInt: first + 1] forKey: NSPrintFirstPage];
          [dict setObject: [NSNumber numberWithInt: last + 1] forKey: NSPrintLastPage];
        }
    }
  else if ([value isEqualToString: @"current"])
    {
      [dict setObject: [NSNumber numberWithBool: NO] forKey: NSPrintAllPages];
      [dict setObject: [NSNumber numberWithInt: 1] forKey: NSPrintFirstPage];
      [dict setObject: [NSNumber numberWithInt: 1] forKey: NSPrintLastPage];
    }
  else if (value != nil)
    {
      [dict setObject: [NSNumber numberWithBool: YES] forKey: NSPrintAllPages];
    }
}

#pragma mark The dialog

static BOOL
GnomeThemePrintDialogWanted(NSPrintPanel *panel)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  if ([defaults objectForKey: GnomeThemePrintDialogDefault] != nil
      && [defaults boolForKey: GnomeThemePrintDialogDefault] == NO)
    {
      return NO;
    }
  if ([panel accessoryView] != nil || [[panel accessoryControllers] count] > 0)
    {
      return NO;
    }
  return YES;
}

/* The window the dialog is a dialog of, and what to call the job. */
static NSWindow *
GnomeThemePrintParentWindow(NSPrintPanel *panel, NSWindow *window)
{
  if (window == nil || window == panel)
    {
      window = [NSApp keyWindow];
    }
  if (window == nil || window == panel)
    {
      window = [NSApp mainWindow];
    }
  return (window == panel) ? nil : window;
}

static NSString *
GnomeThemePrintJobTitle(NSWindow *window)
{
  NSString *title = [window title];

  if ([title length] == 0)
    {
      title = [[NSProcessInfo processInfo] processName];
    }
  return title;
}

/* PreparePrint, waited for. NSOKButton or NSCancelButton, or -1 when this
   run should be GNUstep's panel. */
static NSInteger
GnomeThemePrintDialogRun(NSPrintPanel *panel, NSPrintInfo *info, NSWindow *window)
{
  GnomeThemePrintRequest *request;
  GVariantBuilder options;
  NSString *parent;
  NSString *title;
  GVariant *settings;
  GVariant *setup;
  GVariant *resultSettings = NULL;
  GVariant *resultSetup = NULL;
  guint32 token = 0;
  NSMutableDictionary *dict;
  NSString *format;
  NSString *path;
  static unsigned long serial = 0;

  if (info == nil || GnomeThemePrintDialogWanted (panel) == NO)
    {
      return -1;
    }
  window = GnomeThemePrintParentWindow (panel, window);
  parent = (window != nil) ? GnomeThemeWindowManagerPortalHandle (window) : nil;
  if (parent == nil)
    {
      parent = @"";
    }
  title = GnomeThemePrintJobTitle (window);
  settings = GnomeThemePrintSettings (info);
  setup = GnomeThemePrintPageSetup (info);

  g_variant_builder_init (&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add (&options, "{sv}", "modal", g_variant_new_boolean (TRUE));
  if ([[panel defaultButtonTitle] length] > 0)
    {
      g_variant_builder_add (&options, "{sv}", "accept_label",
                             g_variant_new_string ([[panel defaultButtonTitle] UTF8String]));
    }
  request = AUTORELEASE ([GnomeThemePrintRequest new]);
  if ([request start: "PreparePrint"
           arguments: ^GVariant *(GVariantBuilder *opts) {
             return g_variant_new ("(ss@a{sv}@a{sv}a{sv})", [parent UTF8String], [title UTF8String],
                                   settings, setup, opts);
           }
             options: &options
                 fds: NULL] == NO)
    {
      return -1;
    }
  GnomeThemePrintWait (request);
  if (request->response != 0)
    {
      return NSCancelButton;
    }
  if (g_variant_lookup (request->results, "token", "u", &token) == FALSE)
    {
      return NSCancelButton;
    }
  resultSettings = g_variant_lookup_value (request->results, "settings", G_VARIANT_TYPE_VARDICT);
  resultSetup = g_variant_lookup_value (request->results, "page-setup", G_VARIANT_TYPE_VARDICT);
  GnomeThemeApplyPrintResults (info, resultSettings, resultSetup);

  /* The job is drawn to a file in the format GNOME's dialog asked for
     when it prints to a file (PostScript or PDF; PDF for the rest). */
  format = GnomeThemeVardictString (resultSettings, "output-file-format");
  if ([format isEqualToString: @"ps"] == NO)
    {
      format = @"pdf";
    }
  if (resultSettings != NULL)
    {
      g_variant_unref (resultSettings);
    }
  if (resultSetup != NULL)
    {
      g_variant_unref (resultSetup);
    }
  path = [NSTemporaryDirectory () stringByAppendingPathComponent:
            [NSString stringWithFormat: @"GNUstep-print-%d-%lu.%@", (int)getpid (), ++serial, format]];
  dict = [info dictionary];
  [dict setObject: [info jobDisposition] forKey: GnomeThemePrintJobKey];
  [dict setObject: [NSNumber numberWithUnsignedInt: token] forKey: GnomeThemePrintTokenKey];
  [dict setObject: parent forKey: GnomeThemePrintParentKey];
  [dict setObject: title forKey: GnomeThemePrintTitleKey];
  [info setJobDisposition: NSPrintSaveJob];
  [dict setObject: path forKey: NSPrintSavePath];
  /* GNUstep draws a landscape job turned on portrait paper; GTK gives
     the portal landscape pages, which its backends turn as the printer
     needs. Draw it as GTK does: the landscape paper, not turned. The
     print info is landscape again once the job is delivered. */
  if ([info orientation] == NSLandscapeOrientation)
    {
      [dict setObject: [NSNumber numberWithInt: NSLandscapeOrientation] forKey: GnomeThemePrintOrientationKey];
      [dict setObject: [NSNumber numberWithInt: NSPortraitOrientation] forKey: NSPrintOrientation];
    }
  return NSOKButton;
}

/* Puts the print info's job back as it was before the dialog, and gives
   back what the dialog left in it for the delivery. */
static NSDictionary *
GnomeThemePrintForget(NSPrintInfo *info)
{
  NSMutableDictionary *dict = [info dictionary];
  NSMutableDictionary *job = [NSMutableDictionary dictionary];
  NSString *keys[] = { GnomeThemePrintTokenKey, GnomeThemePrintParentKey, GnomeThemePrintTitleKey,
                       GnomeThemePrintJobKey, GnomeThemePrintOrientationKey, NSPrintSavePath };
  unsigned i;

  for (i = 0; i < sizeof (keys) / sizeof (keys[0]); i++)
    {
      id value = [dict objectForKey: keys[i]];

      if (value != nil)
        {
          [job setObject: value forKey: keys[i]];
          [dict removeObjectForKey: keys[i]];
        }
    }
  [info setJobDisposition: ([job objectForKey: GnomeThemePrintJobKey] != nil)
                            ? [job objectForKey: GnomeThemePrintJobKey] : NSPrintSpoolJob];
  /* Landscape again, on the same (landscape) paper. */
  if ([job objectForKey: GnomeThemePrintOrientationKey] != nil)
    {
      [dict setObject: [job objectForKey: GnomeThemePrintOrientationKey] forKey: NSPrintOrientation];
    }
  return job;
}

/* Hands the drawn job to the portal's Print. */
static BOOL
GnomeThemePrintDeliver(NSPrintInfo *info)
{
  NSDictionary *job = GnomeThemePrintForget (info);
  NSNumber *token = [job objectForKey: GnomeThemePrintTokenKey];
  NSString *parent = [job objectForKey: GnomeThemePrintParentKey];
  NSString *title = [job objectForKey: GnomeThemePrintTitleKey];
  NSString *path = [job objectForKey: NSPrintSavePath];
  GnomeThemePrintRequest *request;
  GVariantBuilder options;
  GUnixFDList *fds;
  BOOL ok = NO;
  int fd;

  fd = open ([path fileSystemRepresentation], O_RDONLY | O_CLOEXEC);
  /* The portal reads it through the descriptor. */
  unlink ([path fileSystemRepresentation]);
  if (fd < 0)
    {
      return NO;
    }
  fds = g_unix_fd_list_new_from_array (&fd, 1);

  g_variant_builder_init (&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add (&options, "{sv}", "token", g_variant_new_uint32 ([token unsignedIntValue]));
  g_variant_builder_add (&options, "{sv}", "modal", g_variant_new_boolean (TRUE));
  request = AUTORELEASE ([GnomeThemePrintRequest new]);
  if ([request start: "Print"
           arguments: ^GVariant *(GVariantBuilder *opts) {
             return g_variant_new ("(ssha{sv})", [parent UTF8String], [title UTF8String], 0, opts);
           }
             options: &options
                 fds: fds])
    {
      GnomeThemePrintWait (request);
      ok = (request->response == 0);
    }
  g_object_unref (fds);
  return ok;
}

#pragma mark The panel

@interface GnomeThemePrintPanel : GSPrintPanel
@end

@implementation GnomeThemePrintPanel

- (BOOL) gnomeThemeUsesPrintDialog
{
  return GnomeThemePrintDialogWanted (self);
}

- (NSInteger) runModalWithPrintInfo: (NSPrintInfo *)printInfo
{
  NSInteger result = GnomeThemePrintDialogRun (self, printInfo, nil);

  if (result < 0)
    {
      return [super runModalWithPrintInfo: printInfo];
    }
  return result;
}

- (void) beginSheetWithPrintInfo: (NSPrintInfo *)printInfo
                  modalForWindow: (NSWindow *)docWindow
                        delegate: (id)delegate
                  didEndSelector: (SEL)didEndSelector
                     contextInfo: (void *)contextInfo
{
  NSInteger result = GnomeThemePrintDialogRun (self, printInfo, docWindow);

  if (result < 0)
    {
      [super beginSheetWithPrintInfo: printInfo
                      modalForWindow: docWindow
                            delegate: delegate
                      didEndSelector: didEndSelector
                         contextInfo: contextInfo];
      return;
    }
  if (delegate != nil && didEndSelector != NULL)
    {
      void (*didEnd)(id, SEL, NSWindow *, NSInteger, void *);

      didEnd = (void (*)(id, SEL, NSWindow *, NSInteger, void *))[delegate methodForSelector: didEndSelector];
      didEnd (delegate, didEndSelector, self, result, contextInfo);
    }
}

@end

@implementation GnomeTheme (PrintDialog)

- (Class) printPanelClass
{
  return [GnomeThemePrintPanel class];
}

/* A job the print dialog prepared goes to the portal, not the spooler. */
- (BOOL) _overrideGSPrintOperationMethod_deliverResult
{
  typedef BOOL (*DeliverIMP)(id, SEL);
  NSPrintInfo *info = [(NSPrintOperation *)self printInfo];
  DeliverIMP originalIMP;

  if ([[info dictionary] objectForKey: GnomeThemePrintTokenKey] != nil)
    {
      return GnomeThemePrintDeliver (info);
    }
  originalIMP = (DeliverIMP)GnomeThemeOriginalMethod (_cmd, self, NSClassFromString (@"GSPrintOperation"));
  return originalIMP != NULL ? originalIMP (self, _cmd) : NO;
}

/* A job the dialog prepared that wasn't delivered (the drawing failed):
   the print info as it was, and no file left behind. */
- (void) _overrideNSPrintOperationMethod_cleanUpOperation
{
  typedef void (*CleanUpIMP)(id, SEL);
  NSPrintInfo *info = [(NSPrintOperation *)self printInfo];
  CleanUpIMP originalIMP;

  if ([[info dictionary] objectForKey: GnomeThemePrintTokenKey] != nil)
    {
      NSString *path = [GnomeThemePrintForget (info) objectForKey: NSPrintSavePath];

      if (path != nil)
        {
          unlink ([path fileSystemRepresentation]);
        }
    }
  originalIMP = (CleanUpIMP)GnomeThemeOriginalMethod (_cmd, self, [NSPrintOperation class]);
  if (originalIMP != NULL)
    {
      originalIMP (self, _cmd);
    }
}

@end
