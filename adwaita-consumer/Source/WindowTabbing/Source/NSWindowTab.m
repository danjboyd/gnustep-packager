/** <title>NSWindowTab</title>

   <abstract>What the tab bar shows for one window of a tab group.</abstract>

   Copyright (C) 2026 Daniel Boyd

   Author: Daniel Boyd <danieljboyd@icloud.com>
   Date: 2026

   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

#import "GSWindowTabbingPrivate.h"

#ifndef GS_HAS_WINDOW_TABBING

/* The title -setTitleWithRepresentedFilename: gives a window showing
   filename: GNUstep's form, "Notes.txt  --  ~/Documents". */
static NSString *
GSTabRepresentedFileTitle(NSString *filename)
{
  NSString *folder;

  folder = [[filename stringByDeletingLastPathComponent]
             stringByAbbreviatingWithTildeInPath];
  return [NSString stringWithFormat: @"%@  --  %@",
    [filename lastPathComponent], folder];
}

@implementation NSWindowTab

- (id) initWithWindow: (NSWindow *)window
{
  if ((self = [super init]) != nil)
    {
      /* Not retained: the window owns its tab. */
      _window = window;
    }
  return self;
}

- (void) dealloc
{
  RELEASE(_title);
  RELEASE(_attributedTitle);
  RELEASE(_toolTip);
  RELEASE(_accessoryView);
  [super dealloc];
}

- (NSString *) title
{
  NSString *filename;

  if (_title != nil)
    {
      return _title;
    }
  if (_attributedTitle != nil)
    {
      return [_attributedTitle string];
    }
  /* A document's tab shows its file's name, as macOS's does: GNUstep's
     -setTitleWithRepresentedFilename: also puts the file's folder in the
     window's title.  Only while the title is still that one: GNUstep's
     default represented filename is "Window", and a title the app sets
     afterwards wins. */
  filename = [(id <GSWindowTabbable>)_window representedFilename];
  if ([filename length] > 0
    && [[_window title] isEqualToString: GSTabRepresentedFileTitle(filename)])
    {
      return [filename lastPathComponent];
    }
  return [_window title];
}

- (void) setTitle: (NSString *)title
{
  ASSIGNCOPY(_title, title);
  [self _tabDidChange];
}

- (NSAttributedString *) attributedTitle
{
  return _attributedTitle;
}

- (void) setAttributedTitle: (NSAttributedString *)title
{
  ASSIGNCOPY(_attributedTitle, title);
  [self _tabDidChange];
}

- (NSString *) toolTip
{
  return _toolTip;
}

- (void) setToolTip: (NSString *)toolTip
{
  ASSIGNCOPY(_toolTip, toolTip);
  [self _tabDidChange];
}

- (NSView *) accessoryView
{
  return _accessoryView;
}

- (void) setAccessoryView: (NSView *)view
{
  ASSIGN(_accessoryView, view);
  [self _tabDidChange];
}

/* The tab bar shows the change. */
- (void) _tabDidChange
{
  [(id <GSWindowTabbable>)_window _tabbingGroupDidChange];
}

@end

#endif /* GS_HAS_WINDOW_TABBING */
