#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

"""libadwaita's AdwAboutWindow, for the theme's About panel: an app
icon, name, developer, version, a comment, a website row and the
copyright. Run on a private X display only, e.g.

  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:270 python3 about_dialog.py \\
      --screenshot out.png [--dark]
"""

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402


def build(app, args):
    about = Adw.AboutWindow(application=app,
                            application_name="Theme Demo",
                            application_icon="applications-graphics",
                            developer_name="Daniel Boyd",
                            version="0.1.0",
                            comments="Every control, drawn as GNOME draws it.",
                            website="https://example.org",
                            copyright="© 2026 Daniel Boyd",
                            license_type=Gtk.License.LGPL_2_1)
    about.present()
    if args.screenshot:
        def shoot():
            paintable = Gtk.WidgetPaintable.new(about)
            width, height = about.get_width(), about.get_height()
            snapshot = Gtk.Snapshot()
            paintable.snapshot(snapshot, width, height)
            texture = about.get_native().get_renderer().render_texture(snapshot.to_node(), None)
            texture.save_to_png(args.screenshot)
            print("size", width, height)
            app.quit()
            return False
        GLib.timeout_add(1500, shoot)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot")
    parser.add_argument("--dark", action="store_true")
    args = parser.parse_args()
    app = Adw.Application(application_id="org.gnustep.adwaita.AboutDialog",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    if args.dark:
        app.connect("startup", lambda a: Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK))
    app.connect("activate", lambda a: build(a, args))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
