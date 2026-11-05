/*
   Copyright (C) 2025-2026 Daniel Boyd

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

#import "ThemeDemoTableDataSource.h"

#import <GNUstepBase/GSObjCRuntime.h>

@implementation ThemeDemoTableDataSource

- (instancetype) init
{
  self = [super init];
  if (self != nil)
    {
      _rows = [@[
        @{ @"control": @"NSMenu", @"state": @"menu bar + popup", @"notes": @"Validate font roles, row height, separators, and long labels" },
        @{ @"control": @"NSTextField", @"state": @"normal + disabled", @"notes": @"Check vertical rhythm against Adwaita-like spacing" },
        @{ @"control": @"NSButton", @"state": @"default + secondary + disabled", @"notes": @"Baseline control family before custom rendering lands" },
        @{ @"control": @"NSSlider", @"state": @"0 – 100", @"notes": @"Track perceived density and label spacing" },
        @{ @"control": @"NSProgressIndicator", @"state": @"determinate", @"notes": @"Verify bar height and control rhythm" },
        @{ @"control": @"NSPopUpButton", @"state": @"long labels", @"notes": @"Check field height and menu width behavior" },
        @{ @"control": @"NSScrollView", @"state": @"both scrollers", @"notes": @"Validate scroller width and border treatment" },
        @{ @"control": @"NSTableView", @"state": @"alternating rows", @"notes": @"Header, grid, and row background colors" },
        @{ @"control": @"NSOutlineView", @"state": @"expandable sections", @"notes": @"Disclosure triangles, indentation, and selection density" }
      ] retain];

      _outlineRows = [@[
        @{
          @"title": @"Menus",
          @"details": @"Typography and row density must align with Adwaita",
          @"children": @[
            @{
              @"title": @"Menu bar",
              @"details": @"Inspect title weight, top/bottom padding, and active state",
              @"children": @[]
            },
            @{
              @"title": @"Popup menus",
              @"details": @"Inspect separators, checkmarks, and submenu arrows",
              @"children": @[]
            }
          ]
        },
        @{
          @"title": @"Core Controls",
          @"details": @"Track the baseline widget family through phases 3 and 4",
          @"children": @[
            @{
              @"title": @"Buttons and toggles",
              @"details": @"Compare spacing between text, indicator, and bezel",
              @"children": @[]
            },
            @{
              @"title": @"Text inputs",
              @"details": @"Compare field height and focus treatment",
              @"children": @[]
            }
          ]
        },
        @{
          @"title": @"Data Views",
          @"details": @"Validate rows, headers, scrollbars, and dense content",
          @"children": @[
            @{
              @"title": @"Table view",
              @"details": @"Alternating rows and header chrome",
              @"children": @[]
            },
            @{
              @"title": @"Outline view",
              @"details": @"Disclosure geometry and indentation rhythm",
              @"children": @[]
            }
          ]
        }
      ] retain];
    }
  return self;
}

- (void) dealloc
{
  RELEASE (_rows);
  RELEASE (_outlineRows);
  [super dealloc];
}

- (NSInteger) numberOfRowsInTableView: (NSTableView *)tableView
{
  return [_rows count];
}

- (id) tableView: (NSTableView *)tableView
  objectValueForTableColumn: (NSTableColumn *)tableColumn
                       row: (NSInteger)row
{
  NSDictionary *entry = nil;
  NSString *identifier = nil;
  id value = nil;

  if (row < 0 || row >= (NSInteger)[_rows count])
    {
      return @"";
    }

  entry = [_rows objectAtIndex: row];
  identifier = [tableColumn identifier];
  value = [entry objectForKey: identifier];
  return (value != nil) ? value : @"";
}

- (void) tableView: (NSTableView *)tableView
  willDisplayCell: (id)cell
   forTableColumn: (NSTableColumn *)tableColumn
              row: (NSInteger)row
{
  (void)tableView;
  (void)tableColumn;
  (void)row;

  if ([cell respondsToSelector: @selector(setBackgroundColor:)])
    {
      [cell setBackgroundColor: [NSColor clearColor]];
    }
}

- (NSInteger) outlineView: (NSOutlineView *)outlineView
  numberOfChildrenOfItem: (id)item
{
  NSArray *children = nil;

  (void)outlineView;

  if (item == nil)
    {
      return [_outlineRows count];
    }

  children = [item objectForKey: @"children"];
  return [children count];
}

- (id) outlineView: (NSOutlineView *)outlineView
  child: (NSInteger)index
  ofItem: (id)item
{
  NSArray *children = nil;

  (void)outlineView;

  if (item == nil)
    {
      return [_outlineRows objectAtIndex: index];
    }

  children = [item objectForKey: @"children"];
  return [children objectAtIndex: index];
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  isItemExpandable: (id)item
{
  NSArray *children = [item objectForKey: @"children"];

  (void)outlineView;

  return ([children count] > 0);
}

- (id) outlineView: (NSOutlineView *)outlineView
  objectValueForTableColumn: (NSTableColumn *)tableColumn
  byItem: (id)item
{
  NSString *identifier = [tableColumn identifier];
  id value = [item objectForKey: identifier];

  (void)outlineView;

  return (value != nil) ? value : @"";
}

- (void) outlineView: (NSOutlineView *)outlineView
  willDisplayCell: (id)cell
  forTableColumn: (NSTableColumn *)tableColumn
  item: (id)item
{
  (void)outlineView;
  (void)tableColumn;
  (void)item;

  if ([cell respondsToSelector: @selector(setBackgroundColor:)])
    {
      [cell setBackgroundColor: [NSColor clearColor]];
    }
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  acceptDrop: (id <NSDraggingInfo>)info
  item: (id)item
  childIndex: (NSInteger)index
{
  (void)outlineView;
  (void)info;
  (void)item;
  (void)index;
  return NO;
}

- (id) outlineView: (NSOutlineView *)outlineView
  itemForPersistentObject: (id)object
{
  (void)outlineView;
  (void)object;
  return nil;
}

- (id) outlineView: (NSOutlineView *)outlineView
  persistentObjectForItem: (id)item
{
  (void)outlineView;
  (void)item;
  return nil;
}

- (void) outlineView: (NSOutlineView *)outlineView
  setObjectValue: (id)object
  forTableColumn: (NSTableColumn *)tableColumn
  byItem: (id)item
{
  (void)outlineView;
  (void)object;
  (void)tableColumn;
  (void)item;
}

- (NSDragOperation) outlineView: (NSOutlineView *)outlineView
  validateDrop: (id <NSDraggingInfo>)info
  proposedItem: (id)item
  proposedChildIndex: (NSInteger)index
{
  (void)outlineView;
  (void)info;
  (void)item;
  (void)index;
  return NSDragOperationNone;
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  writeItems: (NSArray *)items
  toPasteboard: (NSPasteboard *)pasteboard
{
  (void)outlineView;
  (void)items;
  (void)pasteboard;
  return NO;
}

- (void) outlineView: (NSOutlineView *)outlineView
  sortDescriptorsDidChange: (NSArray *)oldDescriptors
{
  (void)outlineView;
  (void)oldDescriptors;
}

- (NSArray *) outlineView: (NSOutlineView *)outlineView
  namesOfPromisedFilesDroppedAtDestination: (NSURL *)dropDestination
  forDraggedItems: (NSArray *)items
{
  (void)outlineView;
  (void)dropDestination;
  (void)items;
  return [NSArray array];
}

- (void) outlineViewColumnDidMove: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewColumnDidResize: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewItemDidCollapse: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewItemDidExpand: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewItemWillCollapse: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewItemWillExpand: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewSelectionDidChange: (NSNotification *)notification
{
  (void)notification;
}

- (void) outlineViewSelectionIsChanging: (NSNotification *)notification
{
  (void)notification;
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  shouldCollapseItem: (id)item
{
  (void)outlineView;
  (void)item;
  return YES;
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  shouldEditTableColumn: (NSTableColumn *)tableColumn
  item: (id)item
{
  (void)outlineView;
  (void)tableColumn;
  (void)item;
  return NO;
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  shouldExpandItem: (id)item
{
  (void)outlineView;
  (void)item;
  return YES;
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  shouldSelectItem: (id)item
{
  (void)outlineView;
  (void)item;
  return YES;
}

- (BOOL) outlineView: (NSOutlineView *)outlineView
  shouldSelectTableColumn: (NSTableColumn *)tableColumn
{
  (void)outlineView;
  (void)tableColumn;
  return NO;
}

- (NSCell *) outlineView: (NSOutlineView *)outlineView
  dataCellForTableColumn: (NSTableColumn *)tableColumn
  item: (id)item
{
  (void)outlineView;
  (void)item;
  return [tableColumn dataCell];
}

- (void) outlineView: (NSOutlineView *)outlineView
  willDisplayOutlineCell: (id)cell
  forTableColumn: (NSTableColumn *)tableColumn
  item: (id)item
{
  (void)outlineView;
  (void)cell;
  (void)tableColumn;
  (void)item;
}

- (BOOL) selectionShouldChangeInOutlineView: (NSOutlineView *)outlineView
{
  (void)outlineView;
  return YES;
}

- (void) outlineView: (NSOutlineView *)outlineView
  didClickTableColumn: (NSTableColumn *)tableColumn
{
  (void)outlineView;
  (void)tableColumn;
}

- (NSView *) outlineView: (NSOutlineView *)outlineView
  viewForTableColumn: (NSTableColumn *)tableColumn
  item: (id)item
{
  (void)outlineView;
  (void)tableColumn;
  (void)item;
  return nil;
}

- (NSTableRowView *) outlineView: (NSOutlineView *)outlineView
  rowViewForItem: (id)item
{
  (void)outlineView;
  (void)item;
  return nil;
}

- (void) outlineView: (NSOutlineView *)outlineView
  didAddRowView: (NSTableRowView *)rowView
  forRow: (NSInteger)row
{
  (void)outlineView;
  (void)rowView;
  (void)row;
}

- (void) outlineView: (NSOutlineView *)outlineView
  didRemoveRowView: (NSTableRowView *)rowView
  forRow: (NSInteger)row
{
  (void)outlineView;
  (void)rowView;
  (void)row;
}

@end
