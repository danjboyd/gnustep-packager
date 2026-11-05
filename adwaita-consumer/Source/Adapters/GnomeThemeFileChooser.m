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

/* Open and save panels as GNOME's file chooser, asked for through the XDG
   desktop portal (org.freedesktop.portal.FileChooser) as Flatpak and GTK
   apps ask for it, parented to the app's window so that Mutter attaches it
   as a modal dialog (plugins-themes-Adwaita#40).

   GNUstep asks the theme for the panels' classes (-openPanelClass,
   -savePanelClass). Each run of these asks the portal when it can, and
   otherwise runs GNUstep's own panel: when GnomeThemeNativeFileDialogs is
   NO, when the panel has an accessory view or a delegate that filters or
   validates names (the portal can show and honour neither), or when the
   portal call fails (no portal, or one without a file chooser).
   NSDocument's "File Type" accessory is the exception: its types become
   the chooser's filters, and the filter chosen is sent back to it.

   Runs block until the chooser answers, as GNUstep's sheets and modal
   panels do; meanwhile the app redraws and takes no input, as under a
   modal panel. -beginWithCompletionHandler: doesn't block. The portal's
   answer is a D-Bus signal, dispatched on a GLib main context of its own
   that a timer polls while a chooser is open. */

#import "../GnomeTheme.h"
#import "GnomeThemeWindowManager.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include <gio/gio.h>

static NSString *const GnomeThemeFileChooserDefault = @"GnomeThemeNativeFileDialogs";

@interface NSSavePanel (GnomeThemeFileChooserPrivate)
- (void) _updateDefaultDirectory;
@end

#pragma mark Portal requests

/* One OpenFile or SaveFile call and its answer. */
@interface GnomeThemePortalRequest : NSObject
{
@public
  BOOL done;
  guint32 response;             /* 0 chosen, 1 cancelled, 2 failed. */
  NSArray *paths;
  NSString *filterName;         /* The filter chosen, if the portal says. */
  GDBusConnection *bus;
  guint subscription;
  void (^completion)(void);
}
- (BOOL) startMethod: (const char *)method
              parent: (NSString *)parent
               title: (NSString *)title
             options: (GVariantBuilder *)options;
- (void) setCompletion: (void (^)(void))block;
@end

static NSMutableArray *GnomeThemePendingRequests = nil;
static NSTimer *GnomeThemePortalTimer = nil;

static GMainContext *
GnomeThemePortalContext(void)
{
  static GMainContext *context = NULL;

  if (context == NULL)
    {
      context = g_main_context_new ();
    }
  return context;
}

static void
GnomeThemePortalResponse(GDBusConnection *connection, const gchar *sender, const gchar *path,
                         const gchar *interface, const gchar *signal, GVariant *parameters,
                         gpointer data);

@implementation GnomeThemePortalRequest

/* Delivers the answers of open requests (see the comment at the top). */
+ (void) poll: (NSTimer *)timer
{
  while (g_main_context_iteration (GnomeThemePortalContext (), FALSE))
    {
    }
}

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
  if (completion != NULL)
    {
      Block_release (completion);
    }
  RELEASE (paths);
  RELEASE (filterName);
  [super dealloc];
}

- (void) setCompletion: (void (^)(void))block
{
  if (completion != NULL)
    {
      Block_release (completion);
    }
  completion = (block != NULL) ? Block_copy (block) : NULL;
}

- (void) subscribeToPath: (const char *)path
{
  GMainContext *context = GnomeThemePortalContext ();

  if (subscription != 0)
    {
      g_dbus_connection_signal_unsubscribe (bus, subscription);
    }
  /* The signal is dispatched on the context that is the thread's default
     when subscribing. */
  g_main_context_push_thread_default (context);
  subscription = g_dbus_connection_signal_subscribe (bus, "org.freedesktop.portal.Desktop",
                                                     "org.freedesktop.portal.Request", "Response", path,
                                                     NULL, G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE, GnomeThemePortalResponse,
                                                     self, NULL);
  g_main_context_pop_thread_default (context);
}

- (BOOL) startMethod: (const char *)method
              parent: (NSString *)parent
               title: (NSString *)title
             options: (GVariantBuilder *)options
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
  token = [NSString stringWithFormat: @"gnustep%d_%lu", (int)getpid (), ++serial];
  sender = [NSMutableString stringWithUTF8String: g_dbus_connection_get_unique_name (bus) + 1];
  [sender replaceOccurrencesOfString: @"." withString: @"_" options: 0 range: NSMakeRange (0, [sender length])];
  expected = [NSString stringWithFormat: @"/org/freedesktop/portal/desktop/request/%@/%@", sender, token];
  [self subscribeToPath: [expected UTF8String]];

  g_variant_builder_add (options, "{sv}", "handle_token", g_variant_new_string ([token UTF8String]));
  reply = g_dbus_connection_call_sync (bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                                       "org.freedesktop.portal.FileChooser", method,
                                       g_variant_new ("(ssa{sv})", [(parent ? parent : @"") UTF8String],
                                                      [(title ? title : @"") UTF8String], options),
                                       G_VARIANT_TYPE ("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
  if (reply == NULL)
    {
      NSDebugLLog (@"GnomeTheme", @"file chooser portal: %s", error->message);
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

  if (GnomeThemePendingRequests == nil)
    {
      GnomeThemePendingRequests = [NSMutableArray new];
    }
  [GnomeThemePendingRequests addObject: self];
  if (GnomeThemePortalTimer == nil)
    {
      NSRunLoop *loop = [NSRunLoop currentRunLoop];

      GnomeThemePortalTimer = RETAIN ([NSTimer timerWithTimeInterval: 0.05
                                                               target: [GnomeThemePortalRequest class]
                                                             selector: @selector(poll:)
                                                             userInfo: nil
                                                              repeats: YES]);
      [loop addTimer: GnomeThemePortalTimer forMode: NSDefaultRunLoopMode];
      [loop addTimer: GnomeThemePortalTimer forMode: NSModalPanelRunLoopMode];
      [loop addTimer: GnomeThemePortalTimer forMode: NSEventTrackingRunLoopMode];
    }
  return YES;
}

- (void) finishWithParameters: (GVariant *)parameters
{
  GVariant *results = NULL;
  const gchar **uris = NULL;
  GVariant *filter = NULL;
  NSMutableArray *chosen = [NSMutableArray array];

  g_variant_get (parameters, "(u@a{sv})", &response, &results);
  if (response == 0 && g_variant_lookup (results, "uris", "^a&s", &uris))
    {
      const gchar **uri;

      for (uri = uris; *uri != NULL; uri++)
        {
          gchar *path = g_filename_from_uri (*uri, NULL, NULL);

          if (path != NULL)
            {
              [chosen addObject: [[NSFileManager defaultManager] stringWithFileSystemRepresentation: path
                                                                                             length: strlen (path)]];
              g_free (path);
            }
        }
      g_free (uris);
    }
  filter = g_variant_lookup_value (results, "current_filter", G_VARIANT_TYPE ("(sa(us))"));
  if (filter != NULL)
    {
      const gchar *name = NULL;

      g_variant_get (filter, "(&s@a(us))", &name, NULL);
      ASSIGN (filterName, [NSString stringWithUTF8String: name]);
      g_variant_unref (filter);
    }
  g_variant_unref (results);
  if (response == 0 && [chosen count] == 0)
    {
      response = 2;
    }
  ASSIGN (paths, chosen);

  g_dbus_connection_signal_unsubscribe (bus, subscription);
  subscription = 0;
  done = YES;

  RETAIN (self);
  [GnomeThemePendingRequests removeObjectIdenticalTo: self];
  if ([GnomeThemePendingRequests count] == 0)
    {
      [GnomeThemePortalTimer invalidate];
      DESTROY (GnomeThemePortalTimer);
    }
  /* The completion holds the request: let it go once it has run. */
  if (completion != NULL)
    {
      void (^block)(void) = completion;

      completion = NULL;
      block ();
      Block_release (block);
    }
  RELEASE (self);
}

@end

static void
GnomeThemePortalResponse(GDBusConnection *connection, const gchar *sender, const gchar *path,
                         const gchar *interface, const gchar *signal, GVariant *parameters,
                         gpointer data)
{
  GnomeThemePortalRequest *request = (GnomeThemePortalRequest *)data;

  if (request->done == NO && g_variant_is_of_type (parameters, G_VARIANT_TYPE ("(ua{sv})")))
    {
      [request finishWithParameters: parameters];
    }
}

#pragma mark Filters

/* A glob for files ending in ".type", in either case (the chooser's globs
   are case-sensitive): "*.[mM][dD]". */
static NSString *
GnomeThemeFileChooserGlob(NSString *type)
{
  NSMutableString *glob = [NSMutableString stringWithString: @"*."];
  NSUInteger i;

  for (i = 0; i < [type length]; i++)
    {
      NSString *c = [type substringWithRange: NSMakeRange (i, 1)];
      NSString *lower = [c lowercaseString];
      NSString *upper = [c uppercaseString];

      if ([lower isEqualToString: upper])
        {
          [glob appendString: c];
        }
      else
        {
          [glob appendFormat: @"[%@%@]", lower, upper];
        }
    }
  return glob;
}

/* A filter, (sa(us)): glob patterns for extensions, MIME types for types
   with a slash; any file for "" or "*". NULL when it would match nothing. */
static GVariant *
GnomeThemeFileChooserFilter(NSString *name, NSArray *types)
{
  GVariantBuilder patterns;
  BOOL any = NO;
  NSUInteger i;

  g_variant_builder_init (&patterns, G_VARIANT_TYPE ("a(us)"));
  for (i = 0; i < [types count]; i++)
    {
      NSString *type = [types objectAtIndex: i];

      if ([type isKindOfClass: [NSString class]] == NO)
        {
          continue;
        }
      if ([type hasPrefix: @"."])
        {
          type = [type substringFromIndex: 1];
        }
      if ([type length] == 0 || [type isEqualToString: @"*"])
        {
          g_variant_builder_add (&patterns, "(us)", 0, "*");
        }
      else if ([type rangeOfString: @"/"].location != NSNotFound)
        {
          g_variant_builder_add (&patterns, "(us)", 1, [type UTF8String]);
        }
      else
        {
          g_variant_builder_add (&patterns, "(us)", 0, [GnomeThemeFileChooserGlob (type) UTF8String]);
        }
      any = YES;
    }
  if (any == NO)
    {
      g_variant_builder_clear (&patterns);
      return NULL;
    }
  return g_variant_new ("(s@a(us))", [name UTF8String], g_variant_builder_end (&patterns));
}

/* A type's name as GNOME's file chooser names it ("Markdown document"),
   from the shared MIME database; "MD files" when it doesn't know it. */
static NSString *
GnomeThemeFileChooserTypeName(NSString *type)
{
  NSString *name = nil;
  gchar *contentType;
  gboolean uncertain = FALSE;

  if ([type rangeOfString: @"/"].location != NSNotFound)
    {
      contentType = g_content_type_from_mime_type ([type UTF8String]);
    }
  else
    {
      contentType = g_content_type_guess ([[@"file." stringByAppendingString: type] UTF8String], NULL, 0,
                                          &uncertain);
    }
  if (contentType != NULL)
    {
      if (uncertain == FALSE && g_content_type_is_unknown (contentType) == FALSE)
        {
          gchar *description = g_content_type_get_description (contentType);

          if (description != NULL)
            {
              name = [NSString stringWithUTF8String: description];
              g_free (description);
            }
        }
      g_free (contentType);
    }
  if (name == nil)
    {
      name = [NSString stringWithFormat: @"%@ files", [type uppercaseString]];
    }
  return name;
}

/* NSDocument's "File Type" accessory (a box with one pop-up button, whose
   action is the document's -changeSaveType:), or nil. */
static NSPopUpButton *
GnomeThemeDocumentTypePopUp(NSView *accessory)
{
  NSView *content;
  NSMutableArray *views;
  NSView *view;

  if ([accessory isKindOfClass: [NSBox class]] == NO)
    {
      return nil;
    }
  /* The pop-up is in the box's content view, or beside it. */
  content = [(NSBox *)accessory contentView];
  views = [NSMutableArray arrayWithArray: [content subviews]];
  [views addObjectsFromArray: [accessory subviews]];
  [views removeObjectIdenticalTo: content];
  if ([views count] != 1)
    {
      return nil;
    }
  view = [views objectAtIndex: 0];
  if ([view isKindOfClass: [NSPopUpButton class]] == NO
      || sel_isEqual ([(NSPopUpButton *)view action], @selector(changeSaveType:)) == NO)
    {
      return nil;
    }
  return (NSPopUpButton *)view;
}

/* Adds the panel's filters to `options`: NSDocument's types when it has
   that accessory, else the allowed types (together first, then each, for
   an open panel; each, and any file when other types are allowed, for a
   save panel). */
static void
GnomeThemeFileChooserAddFilters(NSSavePanel *panel, BOOL open, GVariantBuilder *options)
{
  NSPopUpButton *popUp = GnomeThemeDocumentTypePopUp ([panel accessoryView]);
  NSArray *types = [panel allowedFileTypes];
  GVariantBuilder filters;
  GVariant *current = NULL;
  GVariant *filter;
  BOOL any = NO;
  NSUInteger i;

  g_variant_builder_init (&filters, G_VARIANT_TYPE ("a(sa(us))"));
  if (popUp != nil)
    {
      NSDocumentController *controller = [NSDocumentController sharedDocumentController];

      for (i = 0; i < (NSUInteger)[popUp numberOfItems]; i++)
        {
          NSMenuItem *item = (NSMenuItem *)[popUp itemAtIndex: i];

          filter = GnomeThemeFileChooserFilter ([item title],
                                                [controller fileExtensionsFromType: [item representedObject]]);
          if (filter != NULL)
            {
              if ((NSInteger)i == [popUp indexOfSelectedItem])
                {
                  current = g_variant_ref_sink (filter);
                }
              g_variant_builder_add_value (&filters, filter);
              any = YES;
            }
        }
    }
  else if ([types count] > 0)
    {
      if (open && [types count] > 1)
        {
          filter = GnomeThemeFileChooserFilter (@"All supported files", types);
          if (filter != NULL)
            {
              current = g_variant_ref_sink (filter);
              g_variant_builder_add_value (&filters, filter);
              any = YES;
            }
        }
      for (i = 0; i < [types count]; i++)
        {
          NSString *type = [types objectAtIndex: i];

          if ([type isKindOfClass: [NSString class]] == NO || [type length] == 0)
            {
              continue;
            }
          filter = GnomeThemeFileChooserFilter (GnomeThemeFileChooserTypeName (type),
                                                [NSArray arrayWithObject: type]);
          if (filter != NULL)
            {
              if (current == NULL)
                {
                  current = g_variant_ref_sink (filter);
                }
              g_variant_builder_add_value (&filters, filter);
              any = YES;
            }
        }
      if (open == NO && [panel allowsOtherFileTypes])
        {
          g_variant_builder_add_value (&filters,
                                       GnomeThemeFileChooserFilter (@"All files", [NSArray arrayWithObject: @"*"]));
        }
    }
  if (any)
    {
      g_variant_builder_add (options, "{sv}", "filters", g_variant_builder_end (&filters));
      if (current != NULL)
        {
          g_variant_builder_add (options, "{sv}", "current_filter", current);
        }
    }
  else
    {
      g_variant_builder_clear (&filters);
    }
  if (current != NULL)
    {
      g_variant_unref (current);
    }
}

#pragma mark Running the chooser

/* Whether this run of the panel can be the portal's chooser. */
static BOOL
GnomeThemeFileChooserWanted(NSSavePanel *panel)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id delegate = [panel delegate];
  NSView *accessory = [panel accessoryView];

  if ([defaults objectForKey: GnomeThemeFileChooserDefault] != nil
      && [defaults boolForKey: GnomeThemeFileChooserDefault] == NO)
    {
      return NO;
    }
  if (accessory != nil && GnomeThemeDocumentTypePopUp (accessory) == nil)
    {
      return NO;
    }
  if (delegate != nil
      && ([delegate respondsToSelector: @selector(panel:shouldEnableURL:)]
          || [delegate respondsToSelector: @selector(panel:shouldShowFilename:)]
          || [delegate respondsToSelector: @selector(panel:validateURL:error:)]
          || [delegate respondsToSelector: @selector(panel:isValidFilename:)]
          || [delegate respondsToSelector: @selector(panel:userEnteredFilename:confirmed:)]))
    {
      return NO;
    }
  return YES;
}

/* The window the chooser is a dialog of: the one the panel was run for,
   else the key or main window. On a Wayland session GNOME opens the
   chooser over it but doesn't attach it: Nautilus can give a Wayland
   dialog an X11 parent only once the dialog is mapped, and Mutter attaches
   a dialog only when it has its parent from the start
   (plugins-themes-Adwaita#44,
   Docs/upstream-issues/10-mutter-late-transient-not-attached.md). */
static NSString *
GnomeThemeFileChooserParent(NSSavePanel *panel, NSWindow *window)
{
  NSString *handle = nil;

  if (window != nil && window != panel)
    {
      handle = GnomeThemeWindowManagerPortalHandle (window);
    }
  if (handle == nil && [NSApp keyWindow] != panel)
    {
      handle = GnomeThemeWindowManagerPortalHandle ([NSApp keyWindow]);
    }
  if (handle == nil && [NSApp mainWindow] != panel)
    {
      handle = GnomeThemeWindowManagerPortalHandle ([NSApp mainWindow]);
    }
  return handle;
}

static void
GnomeThemeAddFolder(GVariantBuilder *options, NSString *directory)
{
  BOOL isDirectory = NO;

  if ([directory length] > 0
      && [[NSFileManager defaultManager] fileExistsAtPath: directory isDirectory: &isDirectory]
      && isDirectory)
    {
      g_variant_builder_add (options, "{sv}", "current_folder",
                             g_variant_new_bytestring ([directory fileSystemRepresentation]));
    }
}

/* GNUstep's prompt is the name field's label ("Name:"); Cocoa's is the
   button's. Only a prompt that isn't a label names the button. */
static void
GnomeThemeAddAcceptLabel(GVariantBuilder *options, NSSavePanel *panel)
{
  NSString *prompt = [panel prompt];

  if ([prompt length] > 0 && [prompt hasSuffix: @":"] == NO)
    {
      g_variant_builder_add (options, "{sv}", "accept_label", g_variant_new_string ([prompt UTF8String]));
    }
}

/* Asks the portal for the chooser; nil when this run should be
   GNUstep's panel. */
static GnomeThemePortalRequest *
GnomeThemeFileChooserStart(NSSavePanel *panel, NSString *directory, NSString *file, NSWindow *window)
{
  BOOL open = [panel isKindOfClass: [NSOpenPanel class]];
  GnomeThemePortalRequest *request;
  GVariantBuilder options;

  if (GnomeThemeFileChooserWanted (panel) == NO)
    {
      return nil;
    }
  if (directory == nil)
    {
      directory = [panel directory];
    }

  g_variant_builder_init (&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add (&options, "{sv}", "modal", g_variant_new_boolean (TRUE));
  GnomeThemeAddAcceptLabel (&options, panel);
  GnomeThemeAddFolder (&options, directory);
  if (open)
    {
      NSOpenPanel *openPanel = (NSOpenPanel *)panel;

      /* The chooser picks files or folders, not both; GNUstep's open panel
         allows folders by default, so files win. */
      g_variant_builder_add (&options, "{sv}", "directory",
                             g_variant_new_boolean ([openPanel canChooseFiles] == NO
                                                    && [openPanel canChooseDirectories]));
      g_variant_builder_add (&options, "{sv}", "multiple",
                             g_variant_new_boolean ([openPanel allowsMultipleSelection]));
      if ([openPanel canChooseFiles])
        {
          GnomeThemeFileChooserAddFilters (panel, YES, &options);
        }
    }
  else
    {
      NSArray *types = [panel allowedFileTypes];

      if ([file length] == 0)
        {
          file = [panel nameFieldStringValue];
        }
      if ([file length] > 0 && [[file pathExtension] length] == 0 && [types count] > 0
          && [[types objectAtIndex: 0] length] > 0)
        {
          file = [file stringByAppendingPathExtension: [types objectAtIndex: 0]];
        }
      if ([file length] > 0)
        {
          g_variant_builder_add (&options, "{sv}", "current_name", g_variant_new_string ([file UTF8String]));
        }
      GnomeThemeFileChooserAddFilters (panel, NO, &options);
    }

  request = AUTORELEASE ([GnomeThemePortalRequest new]);
  if ([request startMethod: (open ? "OpenFile" : "SaveFile")
                    parent: GnomeThemeFileChooserParent (panel, window)
                     title: [panel title]
                   options: &options] == NO)
    {
      return nil;
    }
  return request;
}

/* Input to the app while it waits for the chooser: dropped, as a modal
   panel's run drops input to other windows. */
static BOOL
GnomeThemeIsInputEvent(NSEvent *event)
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

/* Waits for the chooser, as a modal run does. The answer comes in a
   timer, which doesn't end the run loop's wait for input: wait no longer
   than the timer's interval. */
static void
GnomeThemeFileChooserWait(GnomeThemePortalRequest *request)
{
  while (request->done == NO)
    {
      CREATE_AUTORELEASE_POOL (pool);
      NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                          untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                             inMode: NSModalPanelRunLoopMode
                                            dequeue: YES];

      if (event == nil || GnomeThemeHeaderBarMoveWindowFromModalPress (event))
        {
          /* The app's window still moves from its header bar (#43). */
        }
      else if (GnomeThemeIsInputEvent (event) == NO)
        {
          [NSApp sendEvent: event];
        }
      RELEASE (pool);
    }
}

/* The chooser's answer, taken into the panel. */
@interface NSSavePanel (GnomeThemeFileChooser)
- (void) gnomeThemeTakeChosenPaths: (NSArray *)paths;
@end

/* A document type's extensions, lower case; none for any file. */
static NSArray *
GnomeThemeDocumentTypeExtensions(NSMenuItem *item)
{
  NSArray *extensions = [[NSDocumentController sharedDocumentController]
                          fileExtensionsFromType: [item representedObject]];

  if ([extensions containsObject: @"*"])
    {
      return [NSArray array];
    }
  return [extensions valueForKey: @"lowercaseString"];
}

/* The name saved as another document type than the one it was offered
   as: the old type's extension becomes the new one's, as NSDocument's
   pop-up changes it in Cocoa ("notes.txt" saved as Markdown is
   "notes.md", not "notes.txt.md"). */
static NSString *
GnomeThemeFileChooserRetypedPath(NSString *path, NSMenuItem *from, NSMenuItem *to)
{
  NSString *extension = [[path pathExtension] lowercaseString];
  NSArray *old = GnomeThemeDocumentTypeExtensions (from);
  NSArray *new = GnomeThemeDocumentTypeExtensions (to);

  if ([extension length] == 0 || [new count] == 0 || [old containsObject: extension] == NO
      || [new containsObject: extension])
    {
      return path;
    }
  return [[path stringByDeletingPathExtension] stringByAppendingPathExtension: [new objectAtIndex: 0]];
}

static NSInteger
GnomeThemeFileChooserResult(NSSavePanel *panel, GnomeThemePortalRequest *request)
{
  NSArray *paths = request->paths;
  NSPopUpButton *popUp;

  if (request->response != 0)
    {
      return NSFileHandlingPanelCancelButton;
    }
  /* The document type of the filter chosen, as its pop-up would set it. */
  popUp = GnomeThemeDocumentTypePopUp ([panel accessoryView]);
  if (popUp != nil && request->filterName != nil)
    {
      NSInteger index = [popUp indexOfItemWithTitle: request->filterName];
      NSMenuItem *offered = (NSMenuItem *)[popUp selectedItem];

      if (index >= 0 && index != [popUp indexOfSelectedItem])
        {
          [popUp selectItemAtIndex: index];
          [NSApp sendAction: [popUp action] to: [popUp target] from: popUp];
          if ([paths count] == 1 && [panel isKindOfClass: [NSOpenPanel class]] == NO)
            {
              paths = [NSArray arrayWithObject: GnomeThemeFileChooserRetypedPath ([paths objectAtIndex: 0], offered,
                                                                                  (NSMenuItem *)[popUp selectedItem])];
            }
        }
    }
  [panel gnomeThemeTakeChosenPaths: paths];
  [panel _updateDefaultDirectory];
  return NSFileHandlingPanelOKButton;
}

static NSInteger
GnomeThemeFileChooserRun(NSSavePanel *panel, GnomeThemePortalRequest *request)
{
  GnomeThemeFileChooserWait (request);
  return GnomeThemeFileChooserResult (panel, request);
}

static void
GnomeThemeFileChooserEndSheet(NSSavePanel *panel, NSInteger result, id delegate, SEL didEndSelector,
                              void *contextInfo)
{
  if (delegate != nil && didEndSelector != NULL)
    {
      void (*didEnd)(id, SEL, NSWindow *, NSInteger, void *);

      didEnd = (void (*)(id, SEL, NSWindow *, NSInteger, void *))[delegate methodForSelector: didEndSelector];
      didEnd (delegate, didEndSelector, panel, result, contextInfo);
    }
}

#pragma mark Panels

/* The same overrides in both classes; the open panel's are its
   superclass's, not the save panel's. */
#define GNOME_THEME_FILE_CHOOSER_RUNS                                                              \
- (BOOL) gnomeThemeUsesFileChooser                                                                 \
{                                                                                                  \
  return GnomeThemeFileChooserWanted (self);                                                       \
}                                                                                                  \
                                                                                                   \
/* With the name the app set (-setNameFieldStringValue:, as NSDocument's                           \
   -prepareSavePanel: may), not the last file chosen, which GNUstep's                              \
   -runModal passes and the shared panel still holds. */                                           \
- (NSInteger) runModal                                                                             \
{                                                                                                  \
  if (GnomeThemeFileChooserWanted (self) == NO)                                                    \
    {                                                                                              \
      return [super runModal];                                                                     \
    }                                                                                              \
  return [self runModalForDirectory: [self directory] file: [self nameFieldStringValue]];          \
}                                                                                                  \
                                                                                                   \
- (NSInteger) runModalForDirectory: (NSString *)path file: (NSString *)name                        \
{                                                                                                  \
  GnomeThemePortalRequest *request;                                                                \
                                                                                                   \
  [self gnomeThemeTakeChosenPaths: nil];                                                           \
  request = GnomeThemeFileChooserStart (self, path, name, nil);                                    \
  if (request == nil)                                                                              \
    {                                                                                              \
      return [super runModalForDirectory: path file: name];                                        \
    }                                                                                              \
  return GnomeThemeFileChooserRun (self, request);                                                 \
}                                                                                                  \
                                                                                                   \
- (NSInteger) runModalForDirectory: (NSString *)path                                               \
                              file: (NSString *)name                                               \
                  relativeToWindow: (NSWindow *)window                                             \
{                                                                                                  \
  GnomeThemePortalRequest *request;                                                                \
                                                                                                   \
  [self gnomeThemeTakeChosenPaths: nil];                                                           \
  request = GnomeThemeFileChooserStart (self, path, name, window);                                 \
  if (request == nil)                                                                              \
    {                                                                                              \
      return [super runModalForDirectory: path file: name relativeToWindow: window];               \
    }                                                                                              \
  return GnomeThemeFileChooserRun (self, request);                                                 \
}                                                                                                  \
                                                                                                   \
- (void) beginSheetForDirectory: (NSString *)path                                                  \
                           file: (NSString *)name                                                  \
                 modalForWindow: (NSWindow *)window                                                \
                  modalDelegate: (id)delegate                                                      \
                 didEndSelector: (SEL)didEndSelector                                               \
                    contextInfo: (void *)contextInfo                                               \
{                                                                                                  \
  GnomeThemePortalRequest *request;                                                                \
                                                                                                   \
  [self gnomeThemeTakeChosenPaths: nil];                                                           \
  request = GnomeThemeFileChooserStart (self, path, name, window);                                 \
  if (request == nil)                                                                              \
    {                                                                                              \
      [super beginSheetForDirectory: path                                                          \
                               file: name                                                          \
                     modalForWindow: window                                                        \
                      modalDelegate: delegate                                                      \
                     didEndSelector: didEndSelector                                                \
                        contextInfo: contextInfo];                                                 \
      return;                                                                                      \
    }                                                                                              \
  GnomeThemeFileChooserEndSheet (self, GnomeThemeFileChooserRun (self, request), delegate,         \
                                 didEndSelector, contextInfo);                                     \
}                                                                                                  \
                                                                                                   \
- (void) beginSheetModalForWindow: (NSWindow *)window                                              \
                completionHandler: (GSSavePanelCompletionHandler)handler                           \
{                                                                                                  \
  GnomeThemePortalRequest *request;                                                                \
  NSInteger result;                                                                                \
                                                                                                   \
  [self gnomeThemeTakeChosenPaths: nil];                                                           \
  request = GnomeThemeFileChooserStart (self, nil, nil, window);                                   \
  if (request == nil)                                                                              \
    {                                                                                              \
      [super beginSheetModalForWindow: window completionHandler: handler];                         \
      return;                                                                                      \
    }                                                                                              \
  result = GnomeThemeFileChooserRun (self, request);                                               \
  CALL_BLOCK (handler, result);                                                                    \
}                                                                                                  \
                                                                                                   \
- (void) beginWithCompletionHandler: (GSSavePanelCompletionHandler)handler                         \
{                                                                                                  \
  GnomeThemePortalRequest *request;                                                                \
                                                                                                   \
  [self gnomeThemeTakeChosenPaths: nil];                                                           \
  request = GnomeThemeFileChooserStart (self, nil, nil, nil);                                      \
  if (request == nil)                                                                              \
    {                                                                                              \
      [super beginWithCompletionHandler: handler];                                                 \
      return;                                                                                      \
    }                                                                                              \
  [request setCompletion: ^{                                                                       \
    CALL_BLOCK (handler, GnomeThemeFileChooserResult (self, request));                             \
  }];                                                                                              \
}

@interface GnomeThemeOpenPanel : NSOpenPanel
{
  NSArray *_chosenFilenames;
}
@end

@implementation GnomeThemeOpenPanel

GNOME_THEME_FILE_CHOOSER_RUNS

- (void) dealloc
{
  RELEASE (_chosenFilenames);
  [super dealloc];
}

- (void) gnomeThemeTakeChosenPaths: (NSArray *)paths
{
  ASSIGN (_chosenFilenames, paths);
  if ([paths count] > 0)
    {
      NSString *first = [paths objectAtIndex: 0];
      BOOL isDirectory = NO;

      /* The directory the files are in; for a chosen folder, the folder,
         as GNUstep's panel leaves it. */
      if ([paths count] == 1 && [[NSFileManager defaultManager] fileExistsAtPath: first isDirectory: &isDirectory]
          && isDirectory)
        {
          ASSIGN (_directory, first);
        }
      else
        {
          ASSIGN (_directory, [first stringByDeletingLastPathComponent]);
        }
    }
}

- (NSArray *) filenames
{
  if (_chosenFilenames != nil)
    {
      return _chosenFilenames;
    }
  return [super filenames];
}

- (void) beginForDirectory: (NSString *)path
                      file: (NSString *)name
                     types: (NSArray *)fileTypes
          modelessDelegate: (id)delegate
            didEndSelector: (SEL)didEndSelector
               contextInfo: (void *)contextInfo
{
  GnomeThemePortalRequest *request;

  [self gnomeThemeTakeChosenPaths: nil];
  [self setAllowedFileTypes: fileTypes];
  request = GnomeThemeFileChooserStart (self, path, name, nil);
  if (request == nil)
    {
      [super beginForDirectory: path
                          file: name
                         types: fileTypes
              modelessDelegate: delegate
                didEndSelector: didEndSelector
                   contextInfo: contextInfo];
      return;
    }
  [request setCompletion: ^{
    GnomeThemeFileChooserEndSheet (self, GnomeThemeFileChooserResult (self, request), delegate,
                                   didEndSelector, contextInfo);
  }];
}

@end

@interface GnomeThemeSavePanel : NSSavePanel
@end

@implementation GnomeThemeSavePanel

GNOME_THEME_FILE_CHOOSER_RUNS

- (void) gnomeThemeTakeChosenPaths: (NSArray *)paths
{
  if ([paths count] > 0)
    {
      ASSIGN (_fullFileName, [paths objectAtIndex: 0]);
      ASSIGN (_directory, [_fullFileName stringByDeletingLastPathComponent]);
    }
}

@end

@implementation GnomeTheme (FileChooser)

- (Class) openPanelClass
{
  return [GnomeThemeOpenPanel class];
}

- (Class) savePanelClass
{
  return [GnomeThemeSavePanel class];
}

@end
