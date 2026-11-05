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

# A stand-in for xdg-desktop-portal's file chooser
# (org.freedesktop.portal.FileChooser), for QuirkProbe's file-chooser
# checks on a private session bus. Each call is written to LOG as a line
# of JSON, and answered 0.2s later, as the user would:
#
#   OpenFile   DIR/a.txt; DIR/a.txt and DIR/b.txt when multiple; DIR/folder
#              for a directory
#   SaveFile   current_folder (or DIR) / current_name (or "untitled"), with
#              the filter named in the title after "filter:" as the one
#              chosen, else current_filter
#
# A title of "Cancel me" is cancelled.
#
#   fake-file-chooser-portal.py LOG DIR

import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

INTERFACE = """
<node>
  <interface name="org.freedesktop.portal.FileChooser">
    <method name="OpenFile">
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="SaveFile">
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""

LOG, DIR = sys.argv[1], sys.argv[2]


# Byte strings (ay, such as current_folder) as strings.
BYTE_STRINGS = ("current_folder", "current_file")


def plain(value, key=None):
    if key in BYTE_STRINGS:
        return bytes(value).rstrip(b"\0").decode()
    if isinstance(value, (list, tuple)):
        return [plain(v) for v in value]
    if isinstance(value, dict):
        return {k: plain(v, k) for k, v in value.items()}
    return value


def answer(connection, sender, handle, method, title, options):
    filters = options.get("filters")
    current = options.get("current_filter")
    if title == "Cancel me":
        connection.emit_signal(sender, handle, "org.freedesktop.portal.Request", "Response",
                               GLib.Variant("(ua{sv})", (1, {})))
        return False
    if method == "OpenFile":
        if options.get("directory"):
            paths = [DIR + "/folder"]
        elif options.get("multiple"):
            paths = [DIR + "/a.txt", DIR + "/b.txt"]
        else:
            paths = [DIR + "/a.txt"]
    else:
        folder = plain(options.get("current_folder", b""), "current_folder") or DIR
        paths = [folder + "/" + options.get("current_name", "untitled")]
        if "filter:" in title and filters:
            wanted = title.split("filter:", 1)[1]
            current = next((f for f in filters if f[0] == wanted), current)
    results = {"uris": GLib.Variant("as", [GLib.filename_to_uri(p) for p in paths])}
    if current is not None:
        results["current_filter"] = GLib.Variant("(sa(us))", current)
    connection.emit_signal(sender, handle, "org.freedesktop.portal.Request", "Response",
                           GLib.Variant("(ua{sv})", (0, results)))
    return False


def on_call(connection, sender, path, interface, method, parameters, invocation):
    parent, title, options = parameters.unpack()
    with open(LOG, "a") as log:
        log.write(json.dumps({"method": method, "parent": parent, "title": title,
                              "options": plain(options)}) + "\n")
    token = options.get("handle_token", "t")
    handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (
        sender[1:].replace(".", "_"), token)
    invocation.return_value(GLib.Variant("(o)", (handle,)))
    GLib.timeout_add(200, answer, connection, sender, handle, method, title, options)


def on_get_property(connection, sender, path, interface, name):
    return GLib.Variant("u", 4)


def on_bus(connection, name):
    info = Gio.DBusNodeInfo.new_for_xml(INTERFACE).interfaces[0]
    connection.register_object("/org/freedesktop/portal/desktop", info, on_call, on_get_property, None)


def on_name(connection, name):
    print("ready", flush=True)


def on_lost(connection, name):
    print("could not own " + name, file=sys.stderr, flush=True)
    sys.exit(1)


Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.portal.Desktop", Gio.BusNameOwnerFlags.NONE,
                 on_bus, on_name, on_lost)
GLib.MainLoop().run()
