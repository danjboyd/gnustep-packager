#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

"""How libadwaita draws a table and an outline (plugins-themes-Adwaita#62).

One window, six cells, each a list in a GtkScrolledWindow:

  1. a plain GtkColumnView (no style class), as the reference demo has it
  2. the same, the scrolled window with has-frame
  3. a GtkColumnView with the "data-table" style class
  4. a GtkListView of GtkTreeExpander rows (an outline), plain
  5. a GtkListBox with "boxed-list" (GNOME's card list), for comparison
  6. a GtkTreeView (GTK 3 style tree), for comparison

The window background is libadwaita's window colour; each cell shows what
the widget draws over it. Run on a private X display only, e.g.

  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:270 python3 table_card.py \
      --screenshot out.png [--dark]

--screenshot saves the window after it has drawn, then quits.
"""

import argparse
import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, GObject, Gtk  # noqa: E402

ROWS = [
    ("NSMenu", "menu bar + popup"),
    ("NSTextField", "normal + disabled"),
    ("NSButton", "default + secondary"),
    ("NSSlider", "0-100"),
    ("NSTableView", "alternating rows"),
]


class Row(GObject.Object):
    def __init__(self, title, detail, children=None):
        super().__init__()
        self.title = title
        self.detail = detail
        self.children = children or []


def column_view(style=None):
    store = Gio.ListStore.new(Row)
    for title, detail in ROWS:
        store.append(Row(title, detail))
    selection = Gtk.SingleSelection.new(store)
    selection.set_selected(1)
    view = Gtk.ColumnView.new(selection)
    if style:
        view.add_css_class(style)
    for name, attr in (("Control", "title"), ("State", "detail")):
        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", lambda _f, item: item.set_child(Gtk.Label(xalign=0)))
        factory.connect("bind", lambda _f, item, a=attr: item.get_child().set_text(getattr(item.get_item(), a)))
        column = Gtk.ColumnViewColumn.new(name, factory)
        column.set_expand(True)
        view.append_column(column)
    return view


def outline_view():
    root = Gio.ListStore.new(Row)
    for title in ("Menus", "Core Controls", "Data Views"):
        root.append(Row(title, "", [Row(t, d) for t, d in ROWS[:2]]))

    def children(item):
        if not item.children:
            return None
        store = Gio.ListStore.new(Row)
        for child in item.children:
            store.append(child)
        return store

    model = Gtk.TreeListModel.new(root, False, False, children)
    selection = Gtk.SingleSelection.new(model)
    selection.set_selected(1)
    factory = Gtk.SignalListItemFactory()

    def setup(_f, item):
        expander = Gtk.TreeExpander()
        expander.set_child(Gtk.Label(xalign=0))
        item.set_child(expander)

    def bind(_f, item):
        row = item.get_item()
        expander = item.get_child()
        expander.set_list_row(row)
        expander.get_child().set_text(row.get_item().title)

    factory.connect("setup", setup)
    factory.connect("bind", bind)
    return Gtk.ListView.new(selection, factory)


def boxed_list():
    box = Gtk.ListBox()
    box.add_css_class("boxed-list")
    for title, detail in ROWS[:4]:
        row = Adw.ActionRow(title=title, subtitle=detail)
        box.append(row)
    box.select_row(box.get_row_at_index(1))
    return box


def tree_view():
    store = Gtk.ListStore(str, str)
    for title, detail in ROWS:
        store.append([title, detail])
    view = Gtk.TreeView(model=store)
    for index, name in enumerate(("Control", "State")):
        view.append_column(Gtk.TreeViewColumn(name, Gtk.CellRendererText(), text=index))
    view.get_selection().select_path(Gtk.TreePath.new_from_indices([1]))
    return view


def cell(title, child, frame=False, scroll=True):
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    label = Gtk.Label(label=title, xalign=0)
    label.add_css_class("heading")
    box.append(label)
    if scroll:
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_has_frame(frame)
        scrolled.set_size_request(360, 200)
        scrolled.set_child(child)
        box.append(scrolled)
    else:
        child.set_size_request(360, -1)
        box.append(child)
    return box


def build(app, args):
    window = Adw.ApplicationWindow(application=app, title="Table card")
    grid = Gtk.Grid(row_spacing=24, column_spacing=24)
    for side in ("top", "bottom", "start", "end"):
        getattr(grid, "set_margin_" + side)(24)
    grid.attach(cell("1 plain ColumnView", column_view()), 0, 0, 1, 1)
    grid.attach(cell("2 has-frame", column_view(), frame=True), 1, 0, 1, 1)
    grid.attach(cell("3 data-table", column_view("data-table")), 2, 0, 1, 1)
    grid.attach(cell("4 outline (ListView)", outline_view()), 0, 1, 1, 1)
    grid.attach(cell("5 boxed-list", boxed_list(), scroll=False), 1, 1, 1, 1)
    grid.attach(cell("6 TreeView", tree_view()), 2, 1, 1, 1)
    window.set_content(grid)
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
    args = parser.parse_args()
    app = Adw.Application(application_id="org.gnustep.adwaita.TableCard",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    if args.dark:
        app.connect("startup", lambda a: Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK))
    app.connect("activate", lambda a: build(a, args))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
