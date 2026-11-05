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

# A modal dialog that gets its parent only after it is mapped, as the
# portal's file chooser gets an X11 parent; see
# 10-mutter-late-transient-not-attached.md. Run on a GNOME Wayland session:
#
#   python3 late_transient_attach.py          parent set 1s after mapping
#   python3 late_transient_attach.py --early  parent set before mapping
#
# With --early the dialog is attached (it sits on the parent's title bar
# and moves with it; the parent dims). Without it, Mutter 48.7 leaves the
# dialog unattached.

import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk

EARLY = "--early" in sys.argv


def on_activate(app):
    parent = Gtk.ApplicationWindow(application=app, title="Parent")
    parent.set_default_size(600, 400)
    parent.present()

    dialog = Gtk.Window(application=app, title="Dialog", modal=True)
    dialog.set_default_size(300, 200)
    if EARLY:
        dialog.set_transient_for(parent)
        dialog.present()
    else:
        dialog.present()
        GLib.timeout_add(1000, lambda: dialog.set_transient_for(parent) or False)


app = Gtk.Application(application_id="org.example.LateTransientAttach")
app.connect("activate", on_activate)
app.run([])
