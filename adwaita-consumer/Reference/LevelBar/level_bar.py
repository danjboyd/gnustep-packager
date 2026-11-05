#!/usr/bin/env python3
# Copyright (C) 2026 Daniel Boyd
#
# This file is part of the GNUstep Adwaita theme.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.

"""libadwaita's level bars and progress bars, for NSLevelIndicator and
NSProgressIndicator: a continuous GtkLevelBar at 0.7 of 10, one past its
"low" offset, a discrete one at 4 of 10, a GtkProgressBar at 40% and one
pulsing. Run on a private X display only, e.g.

  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:270 python3 level_bar.py \\
      --screenshot out.png [--dark]
"""

import argparse
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402


def build(app, args):
    window = Adw.ApplicationWindow(application=app, title="Level bars")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
    for side in ("top", "bottom", "start", "end"):
        getattr(box, "set_margin_" + side)(24)
    continuous = Gtk.LevelBar(min_value=0, max_value=10, value=7)
    continuous.set_size_request(200, -1)
    low = Gtk.LevelBar(min_value=0, max_value=10, value=2)
    low.set_size_request(200, -1)
    discrete = Gtk.LevelBar(min_value=0, max_value=10, value=4, mode=Gtk.LevelBarMode.DISCRETE)
    discrete.set_size_request(200, -1)
    progress = Gtk.ProgressBar(fraction=0.4)
    progress.set_size_request(300, -1)
    pulse = Gtk.ProgressBar()
    pulse.set_size_request(300, -1)
    pulse.set_pulse_step(0.2)
    for _ in range(3):
        pulse.pulse()
    for widget in (continuous, low, discrete, progress, pulse):
        box.append(widget)
    window.set_content(box)
    window.present()
    if args.screenshot:
        def shoot():
            paintable = Gtk.WidgetPaintable.new(window)
            width, height = window.get_width(), window.get_height()
            snapshot = Gtk.Snapshot()
            paintable.snapshot(snapshot, width, height)
            texture = window.get_native().get_renderer().render_texture(snapshot.to_node(), None)
            texture.save_to_png(args.screenshot)
            app.quit()
            return False
        GLib.timeout_add(1500, shoot)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--screenshot")
    parser.add_argument("--dark", action="store_true")
    args = parser.parse_args()
    app = Adw.Application(application_id="org.gnustep.adwaita.LevelBar",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)
    if args.dark:
        app.connect("startup", lambda a: Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK))
    app.connect("activate", lambda a: build(a, args))
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
