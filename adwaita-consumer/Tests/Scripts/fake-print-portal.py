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

# A stand-in for xdg-desktop-portal's print dialog
# (org.freedesktop.portal.Print), for QuirkProbe's print-dialog checks on
# a private session bus. Each call is written to LOG as a line of JSON
# and answered 0.2s later, as the user would:
#
#   PreparePrint  A4 landscape, 10 mm margins, 2 copies, pages 2-3, token
#                 42; a title of "Cancel me" is cancelled
#   Print         the document read from the descriptor is written to
#                 DIR/job-N (N from 1), and its size, type and, for a PDF,
#                 pages, page size and rotation (from pdfinfo) logged
#
#   fake-print-portal.py LOG DIR

import json
import os
import re
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

INTERFACE = """
<node>
  <interface name="org.freedesktop.portal.Print">
    <method name="PreparePrint">
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="settings" direction="in"/>
      <arg type="a{sv}" name="page_setup" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="Print">
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="h" name="fd" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""

LOG, DIR = sys.argv[1], sys.argv[2]
jobs = 0

SETTINGS = {
    "n-copies": "2", "collate": "true", "reverse": "false", "orientation": "landscape",
    "scale": "100", "print-pages": "ranges", "page-ranges": "1-2", "paper-format": "iso_a4",
    "printer": "Stand-in printer",
}
PAGE_SETUP = {
    "Name": GLib.Variant("s", "iso_a4"), "DisplayName": GLib.Variant("s", "A4"),
    "Width": GLib.Variant("d", 210.0), "Height": GLib.Variant("d", 297.0),
    "MarginTop": GLib.Variant("d", 10.0), "MarginBottom": GLib.Variant("d", 10.0),
    "MarginLeft": GLib.Variant("d", 10.0), "MarginRight": GLib.Variant("d", 10.0),
    "Orientation": GLib.Variant("s", "landscape"),
}


def describe(name):
    """The document's type, page count and first page's size ("w x h"),
    from pdfinfo for a PDF."""
    with open(name, "rb") as f:
        head = f.read(8)
    info = {"type": "pdf" if head.startswith(b"%PDF") else "ps" if head.startswith(b"%!") else "other"}
    if info["type"] == "pdf":
        try:
            out = subprocess.run(["pdfinfo", name], capture_output=True, text=True, timeout=10).stdout
            pages = re.search(r"^Pages:\s+(\d+)", out, re.M)
            size = re.search(r"^Page size:\s+([\d.]+) x ([\d.]+)", out, re.M)
            rotation = re.search(r"^Page rot:\s+(\d+)", out, re.M)
            if pages:
                info["pages"] = int(pages.group(1))
            if size:
                info["page_size"] = "%.0f x %.0f" % (float(size.group(1)), float(size.group(2)))
            if rotation:
                info["rotation"] = int(rotation.group(1))
        except (OSError, subprocess.SubprocessError):
            pass
    return info


def log(entry):
    with open(LOG, "a") as out:
        out.write(json.dumps(entry) + "\n")


def respond(connection, sender, handle, code, results):
    connection.emit_signal(sender, handle, "org.freedesktop.portal.Request", "Response",
                           GLib.Variant("(ua{sv})", (code, results)))
    return False


def on_call(connection, sender, path, interface, method, parameters, invocation):
    global jobs
    if method == "PreparePrint":
        parent, title, settings, setup, options = parameters.unpack()
        log({"method": method, "parent": parent, "title": title, "settings": settings,
             "page_setup": setup, "options": options})
    else:
        parent, title, index, options = parameters.unpack()
        fds = invocation.get_message().get_unix_fd_list()
        fd = fds.get(index)
        with os.fdopen(fd, "rb") as source:
            data = source.read()
        jobs += 1
        name = os.path.join(DIR, "job-%d" % jobs)
        with open(name, "wb") as out:
            out.write(data)
        log({"method": method, "parent": parent, "title": title, "options": options,
             "file": name, "bytes": len(data), "document": describe(name)})
    token = options.get("handle_token", "t")
    handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender[1:].replace(".", "_"), token)
    invocation.return_value(GLib.Variant("(o)", (handle,)))
    if method == "PreparePrint" and title == "Cancel me":
        GLib.timeout_add(200, respond, connection, sender, handle, 1, {})
    elif method == "PreparePrint":
        results = {"settings": GLib.Variant("a{sv}", {k: GLib.Variant("s", v) for k, v in SETTINGS.items()}),
                   "page-setup": GLib.Variant("a{sv}", PAGE_SETUP),
                   "token": GLib.Variant("u", 42)}
        GLib.timeout_add(200, respond, connection, sender, handle, 0, results)
    else:
        GLib.timeout_add(200, respond, connection, sender, handle, 0, {})


def on_get_property(connection, sender, path, interface, name):
    return GLib.Variant("u", 3)


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
