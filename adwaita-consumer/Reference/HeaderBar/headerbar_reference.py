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

"""Measures and renders libadwaita's header bar, for the theme's header bar.

Builds an AdwApplicationWindow whose content is an AdwToolbarView with an
AdwHeaderBar (title, a main menu button and the window buttons), prints the
geometry of the header bar, the title and each window button as JSON, and
writes a PNG of the header bar (and one of each window button in its hover
state) when --output is given.

Run it on a private X display (no window manager, so GTK draws its solid
border instead of a shadow) with GNOME's default settings, for example:

    Xvfb :58 -screen 0 1280x800x24 &
    DISPLAY=:58 GDK_BACKEND=x11 GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME=DIR \
      python3 Reference/HeaderBar/headerbar_reference.py --output OUT

where DIR/glib-2.0/settings/keyfile sets org/gnome/desktop/interface as
Tests/Scripts/run-quirk-probe.sh does. --dark renders the dark style.
"""

import argparse
import json
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gsk", "4.0")
gi.require_version("Graphene", "1.0")
from gi.repository import Adw, Gio, GLib, Graphene, Gsk, Gtk  # noqa: E402


def bounds_in(widget, ancestor):
    ok, rect = widget.compute_bounds(ancestor)
    if not ok:
        return None
    return {
        "x": round(rect.get_x(), 2),
        "y": round(rect.get_y(), 2),
        "width": round(rect.get_width(), 2),
        "height": round(rect.get_height(), 2),
    }


def walk(widget):
    yield widget
    child = widget.get_first_child()
    while child is not None:
        yield from walk(child)
        child = child.get_next_sibling()


def render_png(widget, path):
    paintable = Gtk.WidgetPaintable.new(widget)
    width = widget.get_width()
    height = widget.get_height()
    snapshot = Gtk.Snapshot()
    paintable.snapshot(snapshot, width, height)
    node = snapshot.to_node()
    if node is None:
        return False
    renderer = Gsk.CairoRenderer()
    renderer.realize(None)
    texture = renderer.render_texture(node, Graphene.Rect().init(0, 0, width, height))
    renderer.unrealize()
    texture.save_to_png(path)
    return True


class Reference(Adw.Application):
    def __init__(self, options):
        super().__init__(application_id="org.gnustep.AdwaitaHeaderBarReference")
        self._options = options
        self._window = None
        self._header = None
        self._steps = []
        self._pending = None

    def do_activate(self):
        settings = Gtk.Settings.get_default()
        settings.set_property("gtk-decoration-layout", self._options.layout)
        # Without a settings daemon (a private X display) GTK doesn't pick
        # up GNOME's interface font, so set it as GNOME's default is.
        settings.set_property("gtk-font-name", self._options.font)
        if self._options.rtl:
            Gtk.Widget.set_default_direction(Gtk.TextDirection.RTL)
        if self._options.dark:
            Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)

        window = Adw.ApplicationWindow(application=self)
        window.set_default_size(self._options.width, 300)
        window.set_title(self._options.title)

        header = Adw.HeaderBar()
        menu_button = Gtk.MenuButton(icon_name="open-menu-symbolic")
        menu_button.set_tooltip_text("Main Menu")
        # A menu button without a menu is insensitive (drawn dimmed).
        menu = Gio.Menu()
        menu.append("About", "app.about")
        menu_button.set_menu_model(menu)
        header.pack_end(menu_button)

        toolbar_view = Adw.ToolbarView()
        toolbar_view.add_top_bar(header)
        toolbar_view.set_content(Gtk.Label(label="content", vexpand=True))
        window.set_content(toolbar_view)

        self._window = window
        self._header = header
        self._menu_button = menu_button
        window.present()
        GLib.timeout_add(800, self._measure_and_quit)

    def _measure_and_quit(self):
        window = self._window
        header = self._header
        result = {
            "layout": self._options.layout,
            "window": {"width": window.get_width(), "height": window.get_height()},
            "headerbar": bounds_in(header, window),
            "menu_button": bounds_in(self._menu_button, window),
            "window_buttons": [],
        }

        for widget in walk(header):
            name = widget.get_css_name()
            classes = widget.get_css_classes()
            if name == "button" and widget.get_parent() is not None \
                    and widget.get_parent().get_css_name() == "windowcontrols":
                image = widget.get_first_child()
                result["window_buttons"].append({
                    "classes": classes,
                    "bounds": bounds_in(widget, window),
                    "icon": bounds_in(image, window) if image is not None else None,
                })
            elif name == "windowcontrols":
                result.setdefault("windowcontrols", []).append({
                    "classes": classes,
                    "bounds": bounds_in(widget, window),
                })
            elif "title" in classes and isinstance(widget, Gtk.Label):
                layout = widget.get_layout()
                description = widget.get_pango_context().get_font_description()
                result["title"] = {
                    "text": widget.get_text(),
                    "bounds": bounds_in(widget, window),
                    "font": description.to_string() if description else "",
                    "attributes": str(widget.get_attributes()),
                    "baseline": layout.get_baseline() / 1024.0,
                }

        # A private display has no window manager to focus the window, so
        # check which state GTK draws it in.
        result["window_is_active"] = window.is_active()
        print(json.dumps(result, indent=2))

        if not self._options.output:
            self.quit()
            return GLib.SOURCE_REMOVE

        # Renders of the whole window (the header bar paints no background
        # of its own; AdwToolbarView does), one per state. State changes are
        # restyled on the next frame, so each render waits for one.
        buttons = [b for b in walk(header)
                   if b.get_css_name() == "button" and b.get_parent() is not None
                   and b.get_parent().get_css_name() == "windowcontrols"]
        steps = [("window", lambda: None)]
        for button in buttons:
            name = button.get_css_classes()[0]
            steps.append((f"window-{name}-hover",
                          lambda b=button: b.set_state_flags(Gtk.StateFlags.PRELIGHT, False)))
            steps.append((f"window-{name}-pressed",
                          lambda b=button: b.set_state_flags(Gtk.StateFlags.ACTIVE, False)))
            steps.append((None,
                          lambda b=button: b.unset_state_flags(
                              Gtk.StateFlags.PRELIGHT | Gtk.StateFlags.ACTIVE)))
        steps.append(("window-backdrop",
                      lambda: window.set_state_flags(Gtk.StateFlags.BACKDROP, False)))
        self._steps = steps
        GLib.timeout_add(150, self._next_step)
        return GLib.SOURCE_REMOVE

    def _next_step(self):
        if self._pending is not None:
            render_png(self._window, f"{self._options.output}/{self._pending}.png")
            self._pending = None
        if not self._steps:
            self.quit()
            return GLib.SOURCE_REMOVE
        name, action = self._steps.pop(0)
        action()
        self._pending = name
        return GLib.SOURCE_CONTINUE



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layout", default="appmenu:minimize,maximize,close",
                        help="gtk-decoration-layout (default: %(default)s)")
    parser.add_argument("--title", default="Adwaita Theme Demo")
    parser.add_argument("--font", default="Cantarell 11")
    parser.add_argument("--dark", action="store_true", help="use the dark style")
    parser.add_argument("--rtl", action="store_true", help="lay out right to left")
    parser.add_argument("--width", type=int, default=760)
    parser.add_argument("--output", help="directory for PNG renders")
    options = parser.parse_args()
    return Reference(options).run([])


if __name__ == "__main__":
    sys.exit(main())
