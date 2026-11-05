/* GSWindowTabBarLayout.m: the tab bar's sizes, slots and scrolling.

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

/* Upstream these functions go into GSWindowTabBarView.m; they are apart
   here so the display-free tests can compile them in without the
   view. */

#import "GSWindowTabBarView.h"

CGFloat
GSWindowTabWidth(NSUInteger count, CGFloat width,
                 CGFloat minimum, CGFloat maximum)
{
  CGFloat each;

  if (count == 0)
    {
      return 0.0;
    }
  each = floor(width / count);
  if (maximum > 0.0 && each > maximum)
    {
      each = maximum;
    }
  if (each < minimum)
    {
      each = minimum;
    }
  return each;
}

/* The other tabs close up behind the dragged one and open a gap at the
   slot it would drop into, as AdwTabBar's do; a tab pulled out of the
   bar leaves no gap. */
NSUInteger
GSWindowTabSlot(NSUInteger index, NSUInteger dragged,
                NSUInteger slot, BOOL detached)
{
  NSUInteger closed;

  if (index == dragged)
    {
      return slot;
    }
  closed = (index > dragged) ? index - 1 : index;
  if (detached == NO && closed >= slot)
    {
      closed++;
    }
  return closed;
}

NSUInteger
GSWindowTabSlotAtOffset(CGFloat left, CGFloat width,
                        CGFloat spacing, NSUInteger count)
{
  CGFloat step = width + spacing;
  CGFloat slot;

  if (count == 0 || step <= 0.0)
    {
      return 0;
    }
  slot = floor(left / step + 0.5);
  if (slot < 0.0)
    {
      return 0;
    }
  if (slot > count - 1)
    {
      return count - 1;
    }
  return (NSUInteger)slot;
}

CGFloat
GSWindowTabScrollToShow(CGFloat offset, CGFloat left, CGFloat width,
                        CGFloat visible, CGFloat maximum)
{
  if (left < offset)
    {
      offset = left;
    }
  else if (left + width > offset + visible)
    {
      offset = left + width - visible;
    }
  return MAX(0.0, MIN(offset, maximum));
}
