#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

"""How GTK 4 draws a sorted column's header (plugins-themes-Adwaita#71).

A GtkColumnView of two sortable columns, sorted by the first, ascending
(or descending with --descending). Run on a private X display only, e.g.

  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:270 python3 sort_indicator.py \
      --screenshot out.png [--dark] [--descending]
"""

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, GObject, Gtk  # noqa: E402

ROWS = [("Documents", "12 GB"), ("Music", "3 GB"), ("Pictures", "8 GB")]


class Row(GObject.Object):
    def __init__(self, title, detail):
        super().__init__()
        self.title = title
        self.detail = detail


def column_view(descending):
    store = Gio.ListStore.new(Row)
    for title, detail in ROWS:
        store.append(Row(title, detail))
    view = Gtk.ColumnView()
    sorted_model = Gtk.SortListModel.new(store, view.get_sorter())
    view.set_model(Gtk.NoSelection.new(sorted_model))
    columns = []
    for name, attr in (("Name", "title"), ("Size", "detail")):
        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", lambda _f, item: item.set_child(Gtk.Label(xalign=0)))
        factory.connect("bind", lambda _f, item, a=attr: item.get_child().set_text(getattr(item.get_item(), a)))
        column = Gtk.ColumnViewColumn.new(name, factory)
        column.set_fixed_width(180)
        sorter = Gtk.CustomSorter.new(lambda a, b, _d, at=attr: (getattr(a, at) > getattr(b, at)) - (getattr(a, at) < getattr(b, at)), None)
        column.set_sorter(sorter)
        view.append_column(column)
        columns.append(column)
    view.sort_by_column(columns[0], Gtk.SortType.DESCENDING if descending else Gtk.SortType.ASCENDING)
    return view


def build(app, args):
    window = Adw.ApplicationWindow(application=app, title="Sort indicator")
    box = Gtk.Box()
    for side in ("top", "bottom", "start", "end"):
        getattr(box, "set_margin_" + side)(24)
    box.append(column_view(args.descending))
    window.set_content(box)
    window.present()
    if args.screenshot:
        def shoot():
            paintable = Gtk.WidgetPaintable.new(window)
            width, height = window.get_width(), window.get_height()
            snapshot = Gtk.Snapshot()
            paintable.snapshot(snapshot, width, height)
            node = snapshot.to_node()
            texture = window.get_native().get_renderer().render_texture(node, None)
            texture.save_to_png(args.screenshot)
            app.quit()
            return False
        GLib.timeout_add(1500, shoot)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot")
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--descending", action="store_true")
    args = parser.parse_args()
    app = Adw.Application(application_id="org.gnustep.adwaita.SortIndicator",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    if args.dark:
        app.connect("startup", lambda a: Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK))
    app.connect("activate", lambda a: build(a, args))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
