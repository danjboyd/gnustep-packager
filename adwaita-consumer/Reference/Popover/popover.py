#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

"""How libadwaita draws a GtkPopover with its arrow (plugins-themes-Adwaita#74).

One window, as QuirkProbe's -ProbeOnly popover-demo: a "Pen" button whose
popover (a label and a scale) opens below it after a second, with its
arrow, and a GtkDropDown whose list (a popover without an arrow) is left
closed. Run on a private X display only, e.g.

  env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS GDK_BACKEND=x11 \\
      DISPLAY=:371 python3 popover.py
"""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402


def on_activate(app):
    window = Adw.ApplicationWindow(application=app, title="Popover")
    window.set_default_size(520, 360)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.append(Adw.HeaderBar())
    row = Gtk.Box(spacing=120, margin_top=24, margin_start=60)
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                      margin_top=6, margin_bottom=6, margin_start=6, margin_end=6)
    content.append(Gtk.Label(label="Width", xalign=0))
    scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 0.1)
    scale.set_value(0.4)
    scale.set_size_request(184, -1)
    content.append(scale)
    popover = Gtk.Popover(child=content)
    button = Gtk.MenuButton(label="Pen", popover=popover, always_show_arrow=False)
    button.set_size_request(120, -1)
    row.append(button)
    row.append(Gtk.DropDown.new_from_strings(["Cantarell", "DejaVu Sans"]))
    box.append(row)
    window.set_content(box)
    window.present()
    GLib.timeout_add(1000, lambda: (button.popup(), False)[1])


app = Adw.Application(application_id="org.gnustep.adwaita.reference.Popover")
app.connect("activate", on_activate)
app.run(None)
