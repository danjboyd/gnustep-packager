#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

"""How libadwaita draws a GtkDropDown's list and a navigation-sidebar list
(plugins-themes-Adwaita#66).

One window: a GtkDropDown of plain strings, the third item chosen, and a
GtkListView with the "navigation-sidebar" style class in a popover-coloured
box: one row selected, the pointer kept off it. --open opens the
drop-down's list after a second, as a click would. Run on a private X
display only, e.g.

  env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS GDK_BACKEND=x11 \\
      DISPLAY=:371 python3 dropdown_list.py --open [--dark]

--metrics prints the drop-down's and the list's sizes once the list is
open, then quits.
"""

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

ITEMS = ["Cantarell", "DejaVu Sans", "DejaVu Serif", "Liberation Mono",
         "Noto Sans", "Noto Serif", "Source Code Pro", "Ubuntu"]
SIDEBAR = ["Recent", "Favourites", "Sans Serif", "Serif", "Monospace"]


def sidebar():
    model = Gtk.StringList.new(SIDEBAR)
    selection = Gtk.SingleSelection.new(model)
    selection.set_selected(2)
    factory = Gtk.SignalListItemFactory()
    factory.connect("setup", lambda _f, item: item.set_child(Gtk.Label(xalign=0)))
    factory.connect("bind", lambda _f, item: item.get_child().set_text(item.get_item().get_string()))
    view = Gtk.ListView.new(selection, factory)
    view.add_css_class("navigation-sidebar")
    view.set_size_request(220, -1)
    return view


def walk(widget, depth=0, out=None):
    """Each widget's CSS name, classes and allocation, in the window's
    coordinates."""
    if out is None:
        out = []
    root = widget.get_native()
    ok, bounds = widget.compute_bounds(root)
    if ok:
        out.append("%s%s.%s %.0f,%.0f %.0fx%.0f" % (
            "  " * depth, widget.get_css_name(), ".".join(widget.get_css_classes()),
            bounds.get_x(), bounds.get_y(), bounds.get_width(), bounds.get_height()))
    child = widget.get_first_child()
    while child is not None:
        walk(child, depth + 1, out)
        child = child.get_next_sibling()
    return out


def build(app, args):
    window = Adw.ApplicationWindow(application=app, title="DropDown list",
                                   default_width=560, default_height=420)
    view = Adw.ToolbarView()
    view.add_top_bar(Adw.HeaderBar())
    box = Gtk.Box(spacing=24, margin_top=24, margin_start=24, margin_end=24, margin_bottom=24)
    left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    dropdown = Gtk.DropDown.new_from_strings(ITEMS)
    dropdown.set_selected(2)
    dropdown.set_halign(Gtk.Align.START)
    left.append(dropdown)
    box.append(left)
    frame = Gtk.Box()
    frame.add_css_class("background")
    frame.append(sidebar())
    box.append(frame)
    view.set_content(box)
    window.set_content(view)
    window.present()

    def report():
        print("dropdown", dropdown.get_width(), "x", dropdown.get_height())
        popover = None
        child = dropdown.get_first_child()
        while child is not None:
            if isinstance(child, Gtk.Popover):
                popover = child
            child = child.get_next_sibling()
        if popover is not None:
            print("\n".join(walk(popover)))
        print("\n".join(walk(frame)))
        if args.metrics:
            app.quit()
        return False

    def open_it():
        if args.open or args.metrics:
            dropdown.activate()
            GLib.timeout_add(800, report)
        return False

    GLib.timeout_add(1000, open_it)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--open", action="store_true")
    parser.add_argument("--metrics", action="store_true")
    parser.add_argument("--dark", action="store_true")
    args = parser.parse_args()
    app = Adw.Application(application_id="org.gnustep.adwaita.DropDownList",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    if args.dark:
        app.connect("startup", lambda a: Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK))
    app.connect("activate", lambda a: build(a, args))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
