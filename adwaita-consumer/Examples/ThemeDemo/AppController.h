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

#import <AppKit/AppKit.h>

@class ThemeDemoTableDataSource;

@interface AppController : NSObject <NSApplicationDelegate>
{
  NSWindow *_window;
  NSTabView *_tabView;
  ThemeDemoTableDataSource *_tableDataSource;
  NSProgressIndicator *_progressIndicator;
  NSTextField *_sliderValueLabel;
  NSTextField *_stepperValueField;
  NSMenu *_demoMenu;
  NSMenu *_stressMenu;
  NSSegmentedControl *_segmentedControl;
  NSButton *_demoMenuButton;
  NSButton *_stressMenuButton;
  NSTextField *_primaryTextField;
  NSSecureTextField *_passwordField;
  NSSearchField *_searchField;
  NSTextField *_disabledTextField;
  NSTextView *_bodyTextView;
  NSComboBox *_textComboBox;
  NSView *_commandFocusedTextControl;
  NSAlert *_activeAlert;
  NSString *_pendingDropdownCaptureName;
  NSString *_pendingDropdownCapturePath;
  int _commandFIFODescriptor;
  NSMutableData *_commandFIFOBuffer;
  NSTimer *_commandFIFOTimer;
  /* The tool tips shown by the "tooltip" command. */
  id _toolTips;
}

@end
