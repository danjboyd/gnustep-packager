#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; see the file COPYING.LIB.
# If not, see <http://www.gnu.org/licenses/>.

"""libadwaita's tab bar, for comparing the theme's window tabs with it.

A window with a header bar, an AdwTabBar below it and an AdwTabView with
three pages, as GNOME Text Editor lays them out; the bar's end action is
a flat "+" button (list-add-symbolic). Options:

  --dark              force the dark style
  --screenshot PATH   save the window as a PNG after it settles, then quit
  --select N          select page N (0-based)
  --dump              print the bar's and tabs' allocations
  --width W           the window's width (760)
  --tabs N            the number of tabs (3)

Run on a private X display only (GDK_BACKEND=x11, WAYLAND_DISPLAY unset,
DBUS_SESSION_BUS_ADDRESS=disabled:).
High contrast comes from GNOME's setting
(org.gnome.desktop.a11y.interface high-contrast).
"""

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

TITLES = ["Document 1.txt", "Document 2.txt", "Document 3.txt"]


def build(app, args):
    if args.dark:
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
    window = Adw.ApplicationWindow(application=app, title=TITLES[0])
    window.set_default_size(args.width, 420)

    titles = TITLES + ["Document %d.txt" % (i + 1) for i in range(len(TITLES), args.tabs)]
    view = Adw.TabView()
    for title in titles[:max(args.tabs, 1)]:
        label = Gtk.Label(label="This is %s." % title, xalign=0, yalign=0)
        label.set_margin_start(12)
        label.set_margin_top(12)
        page = view.append(label)
        page.set_title(title)

    bar = Adw.TabBar(view=view, autohide=False)
    add = Gtk.Button(icon_name="list-add-symbolic")
    add.add_css_class("flat")
    bar.set_end_action_widget(add)

    toolbar = Adw.ToolbarView()
    toolbar.add_top_bar(Adw.HeaderBar())
    toolbar.add_top_bar(bar)
    toolbar.set_content(view)
    window.set_content(toolbar)

    view.set_selected_page(view.get_nth_page(args.select))

    def settle():
        if args.dump:
            dump(window, bar, view, add)
        if args.screenshot:
            save(window, args.screenshot)
            app.quit()
        return False

    window.present()
    GLib.timeout_add(1500, settle)


def bounds(widget, window):
    ok, rect = widget.compute_bounds(window)
    if not ok:
        return None
    return (rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)


def dump(window, bar, view, add):
    print("bar", bounds(bar, window))
    print("add", bounds(add, window))
    # The tabs are internal widgets: walk the bar's tree for them.
    stack = [bar]
    while stack:
        widget = stack.pop()
        name = widget.get_css_name()
        if name in ("tab", "tabbox", "button", "label") and widget is not bar:
            print(name, " ".join(widget.get_css_classes()), bounds(widget, window))
        child = widget.get_first_child()
        while child is not None:
            stack.append(child)
            child = child.get_next_sibling()
    sys.stdout.flush()


def save(window, path):
    paintable = Gtk.WidgetPaintable(widget=window)
    width = window.get_width()
    height = window.get_height()
    snapshot = Gtk.Snapshot()
    paintable.snapshot(snapshot, width, height)
    node = snapshot.to_node()
    renderer = window.get_native().get_renderer()
    texture = renderer.render_texture(node, None)
    texture.save_to_png(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--screenshot")
    parser.add_argument("--select", type=int, default=0)
    parser.add_argument("--dump", action="store_true")
    parser.add_argument("--width", type=int, default=760)
    parser.add_argument("--tabs", type=int, default=3)
    args = parser.parse_args()

    # NON_UNIQUE: no session bus is needed (run it with none).
    from gi.repository import Gio
    app = Adw.Application(application_id="org.gnustep.AdwaitaTabBarReference",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("activate", lambda a: build(a, args))
    app.run([])


if __name__ == "__main__":
    main()
