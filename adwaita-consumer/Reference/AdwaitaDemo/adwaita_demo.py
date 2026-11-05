#!/usr/bin/env python3
#
# Copyright (C) 2025-2026 Daniel Boyd
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

import argparse
import ctypes
import ctypes.util
import json
import os
import sys

import gi
from PIL import Image, ImageGrab

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Graphene", "1.0")
gi.require_version("Gsk", "4.0")
gi.require_version("GdkX11", "4.0")

from gi.repository import Adw, Gio, GLib, GObject, Graphene, Gsk, Gtk, Pango, GdkX11


PAGE_NAMES = ("controls", "text", "data", "menus", "stress")
PAGE_TITLES = {
    "controls": "Controls",
    "text": "Text & Inputs",
    "data": "Data Views",
    "menus": "Menus",
    "stress": "Stress",
}
DEMO_WINDOW_WIDTH = 760
DEMO_WINDOW_HEIGHT = 620

DATA_ROWS = (
    ("NSMenu", "menu bar + popup", "Validate font roles, row height, separators, and long labels"),
    ("NSTextField", "normal + disabled", "Check vertical rhythm against Adwaita-like spacing"),
    ("NSButton", "default + secondary + disabled", "Baseline control family before custom rendering lands"),
    ("NSSlider", "0 - 100", "Track perceived density and label spacing"),
    ("NSProgressIndicator", "determinate", "Verify bar height and control rhythm"),
    ("NSPopUpButton", "long labels", "Check field height and menu width behavior"),
    ("NSScrollView", "both scrollers", "Validate scroller width and border treatment"),
    ("NSTableView", "alternating rows", "Header, grid, and row background colors"),
    ("NSOutlineView", "expandable sections", "Disclosure geometry and indentation rhythm"),
)

OUTLINE_SECTIONS = (
    (
        "Menus",
        "Typography and row density must align with Adwaita",
        (
            ("Menu bar", "Inspect title weight, top/bottom padding, and active state"),
            ("Popup menus", "Inspect separators, checkmarks, and submenu arrows"),
        ),
    ),
    (
        "Core Controls",
        "Track the baseline widget family through phases 3 and 4",
        (
            ("Buttons and toggles", "Compare spacing between text, indicator, and bezel"),
            ("Text inputs", "Compare field height and focus treatment"),
        ),
    ),
    (
        "Data Views",
        "Validate rows, headers, scrollbars, and dense content",
        (
            ("Table view", "Alternating rows and header chrome"),
            ("Outline view", "Disclosure geometry and indentation rhythm"),
        ),
    ),
)

TEXT_VIEW_BODY = (
    "Use this page to inspect paragraph spacing, text selection, caret visibility, "
    "and how the theme handles dense multiline content.\n\n"
    "The goal in Phases 2 and 3 is not custom widget chrome yet. It is typography, "
    "spacing, and visual rhythm."
)

SCROLLBAR_PREVIEW_TEXT = (
    "Scroll through this text to preview both orientations of the themed scrollbars under the GNOME theme.\n\n"
    "This first paragraph is intentionally ordinary so the active vertical scrollbar remains easy to read during normal multiline content review.\n\n"
    "Horizontal overflow sample: /workspace/very-long-project-name/configuration/profiles/default/environment/overrides/synchronization/diagnostics/panel/layout/with/a/path/that/should/not/wrap/inside/the/demo/scroll/view.txt\n\n"
    "Additional notes:\n"
    "1. The text view is deliberately taller than the viewport.\n"
    "2. The long path above is deliberately wider than the viewport.\n"
    "3. This keeps both scrollbars active so the page no longer falls back to disabled GNUstep scrollbars.\n\n"
    "Line 05: selection, caret, and viewport edges should still feel balanced.\n"
    "Line 06: the scrollbar track width should read as intentional, not accidental.\n"
    "Line 07: this page is a live control-surface check, not placeholder lorem ipsum.\n"
    "Line 08: leaving real overflow in place makes visual review far more reliable.\n"
    "Line 09: if either scrollbar disappears here, the demo content regressed.\n"
    "Line 10: this should now be long enough for sustained vertical scrolling."
)

STRESS_NOTES = (
    "Use this page to decide whether typography and spacing are genuinely fixed.\n\n"
    "If the theme only looks good on the tidy demo pages but still collapses under long labels, "
    "long menu items, mixed states, and disabled fields, Phase 3 is not done yet."
)


class DemoRow(GObject.Object):
    control = GObject.Property(type=str, default="")
    state = GObject.Property(type=str, default="")
    notes = GObject.Property(type=str, default="")

    def __init__(self, control, state, notes):
        super().__init__()
        self.props.control = control
        self.props.state = state
        self.props.notes = notes


class OutlineRow(GObject.Object):
    title = GObject.Property(type=str, default="")
    details = GObject.Property(type=str, default="")

    def __init__(self, title, details, children=None):
        super().__init__()
        self.props.title = title
        self.props.details = details
        self.children = None

        if children:
            store = Gio.ListStore.new(OutlineRow)
            for child_title, child_details in children:
                store.append(OutlineRow(child_title, child_details))
            self.children = store


class AdwaitaDemoWindow(Adw.ApplicationWindow):
    def __init__(self, app, options):
        super().__init__(application=app, title=options.window_title or "Adwaita Demo")
        self._options = options
        self._measure_widgets = {}
        self._typography_widgets = {}
        self._text_audit_widgets = {}
        self._focused_text_audit_widget = None
        self._command_fifo_fd = None
        self._command_fifo_buffer = ""
        self.set_default_size(DEMO_WINDOW_WIDTH, DEMO_WINDOW_HEIGHT)

        header = Adw.HeaderBar()
        switcher = Adw.ViewSwitcher()

        self._stack = Adw.ViewStack()
        switcher.set_stack(self._stack)
        header.set_title_widget(switcher)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(self._stack)
        self.set_content(toolbar)

        self._stack.add_titled(self._controls_page(), "controls", PAGE_TITLES["controls"])
        self._stack.add_titled(self._text_page(), "text", PAGE_TITLES["text"])
        self._stack.add_titled(self._data_page(), "data", PAGE_TITLES["data"])
        self._stack.add_titled(self._menus_page(), "menus", PAGE_TITLES["menus"])
        self._stack.add_titled(self._stress_page(), "stress", PAGE_TITLES["stress"])

        if options.page:
            self._stack.set_visible_child_name(options.page)

        self.connect("map", self._on_map)

    def _on_map(self, *_args):
        if self._options.dump_metrics:
            GLib.idle_add(self._dump_metrics_and_quit, priority=GLib.PRIORITY_LOW)
        elif self._options.dump_typography:
            GLib.idle_add(self._dump_typography_and_quit, priority=GLib.PRIORITY_LOW)
        elif self._options.screenshot:
            GLib.timeout_add(200, self._screenshot_and_quit)
        else:
            self._start_command_interface()

    def _scrolled_page(self, child):
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(child)
        return scroll

    def _page_box(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        box.set_margin_top(24)
        box.set_margin_bottom(24)
        box.set_margin_start(24)
        box.set_margin_end(24)
        return box

    def _section_title(self, text):
        label = Gtk.Label(label=text, xalign=0)
        label.add_css_class("title-4")
        return label

    def _grid(self):
        grid = Gtk.Grid(column_spacing=18, row_spacing=14)
        grid.set_hexpand(True)
        return grid

    def _labeled_row(self, grid, row, label_text, widget):
        label = Gtk.Label(label=label_text, xalign=0)
        label.set_valign(Gtk.Align.CENTER)
        widget.set_hexpand(False)
        grid.attach(label, 0, row, 1, 1)
        grid.attach(widget, 1, row, 1, 1)

    def _full_width_row(self, grid, row, widget):
        widget.set_hexpand(False)
        widget.set_halign(Gtk.Align.START)
        grid.attach(widget, 0, row, 2, 1)

    def _make_dropdown(self, values, width=360, selected=0):
        model = Gtk.StringList.new(values)
        dropdown = Gtk.DropDown.new(model, None)
        dropdown.set_selected(selected)
        dropdown.set_size_request(width, -1)
        return dropdown

    def _make_text_frame(self, text, min_height=220, wrap_mode=Gtk.WrapMode.WORD_CHAR):
        frame = Gtk.Frame()
        frame.set_hexpand(True)
        frame.set_vexpand(True)
        frame.set_focusable(True)

        scroll = Gtk.ScrolledWindow()
        scroll.set_min_content_height(min_height)
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)

        text_view = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=wrap_mode)
        text_view.get_buffer().set_text(text)
        scroll.set_child(text_view)
        frame.set_child(scroll)
        return frame

    def _make_scrollbar_preview(self):
        scroll = Gtk.ScrolledWindow()
        scroll.set_min_content_height(220)
        scroll.set_min_content_width(360)
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)

        text_view = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.NONE)
        text_view.set_size_request(960, 720)
        text_view.get_buffer().set_text(SCROLLBAR_PREVIEW_TEXT)
        scroll.set_child(text_view)
        return scroll

    def _build_demo_menu_model(self):
        menu = Gio.Menu()
        recent = Gio.Menu()
        primary = Gio.Menu()
        secondary = Gio.Menu()
        footer = Gio.Menu()

        recent.append("Project Alpha", "app.noop")
        recent.append("Project Beta", "app.noop")
        recent.append("Clear Menu", "app.noop")

        primary.append_submenu("Open Recent", recent)
        primary.append("Automatically sync workspace", "app.noop")
        primary.append("Workspace indexing pending", "app.noop")

        secondary.append("Preferences…", "app.noop")
        secondary.append("Keyboard Shortcuts", "app.noop")

        footer.append("Sign Out", "app.noop")

        menu.append_section(None, primary)
        menu.append_section(None, secondary)
        menu.append_section(None, footer)
        return menu

    def _build_stress_menu_model(self):
        menu = Gio.Menu()
        primary = Gio.Menu()
        export = Gio.Menu()
        footer = Gio.Menu()

        primary.append("Open the project settings window with all advanced options", "app.noop")
        primary.append("Keep diagnostics overlay visible during synchronization", "app.noop")
        primary.append("Mirror remote workspace settings when available", "app.noop")

        export.append("Export as human-readable configuration snapshot", "app.noop")
        export.append("Export as compressed archive for backup and transfer", "app.noop")
        primary.append_submenu("Export workspace state", export)

        footer.append("Sign out of synchronized services", "app.noop")

        menu.append_section(None, primary)
        menu.append_section(None, footer)
        return menu

    def _make_linked_segmented(self):
        box = Gtk.Box(spacing=0)
        box.add_css_class("linked")
        first = Gtk.ToggleButton(label="One")
        second = Gtk.ToggleButton(label="Two")
        third = Gtk.ToggleButton(label="Three")
        second.set_group(first)
        third.set_group(first)
        first.set_active(True)

        for button in (first, second, third):
            box.append(button)

        return box

    def _controls_page(self):
        page = self._page_box()
        section_title = self._section_title("Buttons")
        self._typography_widgets["section_title"] = section_title
        page.append(section_title)

        grid = self._grid()

        button_row = Gtk.Box(spacing=12)
        default_button = Gtk.Button(label="Default")
        secondary_button = Gtk.Button(label="Secondary")
        disabled_button = Gtk.Button(label="Disabled")
        disabled_button.set_sensitive(False)
        default_button.add_css_class("suggested-action")
        for button in (default_button, secondary_button, disabled_button):
            button.set_size_request(160, -1)
            button_row.append(button)
        self._measure_widgets["button"] = default_button
        self._typography_widgets["default_button"] = default_button
        self._typography_widgets["secondary_button"] = secondary_button
        self._full_width_row(grid, 0, button_row)

        checkbox_row = Gtk.Box(spacing=18)
        enable_check = Gtk.CheckButton(label="Enable advanced options")
        enable_check.set_active(True)
        mixed_check = Gtk.CheckButton(label="Mixed state")
        mixed_check.set_inconsistent(True)
        checkbox_row.append(enable_check)
        checkbox_row.append(mixed_check)
        self._measure_widgets["check"] = enable_check
        self._typography_widgets["checkbox"] = enable_check
        self._full_width_row(grid, 1, checkbox_row)

        radio_row = Gtk.Box(spacing=18)
        radio_a = Gtk.CheckButton(label="Radio Option A")
        radio_b = Gtk.CheckButton(label="Radio Option B")
        radio_b.set_group(radio_a)
        radio_a.set_active(True)
        radio_row.append(radio_a)
        radio_row.append(radio_b)
        self._measure_widgets["radio"] = radio_a
        self._typography_widgets["radio"] = radio_a
        self._full_width_row(grid, 2, radio_row)

        segmented = self._make_linked_segmented()
        segmented_label = Gtk.Label(label="Segmented", xalign=0)
        segmented_label.set_valign(Gtk.Align.CENTER)
        self._typography_widgets["segmented_label"] = segmented_label
        self._typography_widgets["segmented_button"] = segmented.get_first_child()
        segmented.set_hexpand(False)
        grid.attach(segmented_label, 0, 3, 1, 1)
        grid.attach(segmented, 1, 3, 1, 1)

        slider_box = Gtk.Box(spacing=12)
        slider = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.0, 100.0, 1.0)
        slider.set_value(45.0)
        slider.set_draw_value(False)
        slider.set_size_request(240, -1)
        slider_value = Gtk.Label(label="45", xalign=0)
        slider.connect("value-changed", lambda control: slider_value.set_text(str(int(control.get_value()))))
        slider_box.append(slider)
        slider_box.append(slider_value)
        self._measure_widgets["slider"] = slider
        self._typography_widgets["slider_value"] = slider_value
        self._labeled_row(grid, 4, "Slider", slider_box)

        progress = Gtk.ProgressBar()
        progress.set_fraction(0.6)
        progress.set_size_request(240, -1)
        self._measure_widgets["progress"] = progress
        self._labeled_row(grid, 5, "Progress", progress)

        dropdown = self._make_dropdown(["Adwaita", "Adwaita-dark", "High Contrast"], width=360)
        self._measure_widgets["dropdown"] = dropdown
        self._typography_widgets["dropdown"] = dropdown
        self._labeled_row(grid, 6, "Pop-up", dropdown)

        adjustment = Gtk.Adjustment.new(3.0, 0.0, 10.0, 1.0, 1.0, 0.0)
        spin = Gtk.SpinButton.new(adjustment, 1.0, 0)
        spin.set_size_request(80, -1)
        self._measure_widgets["spin"] = spin
        self._typography_widgets["spin"] = spin
        self._labeled_row(grid, 7, "Stepper", spin)

        page.append(grid)
        page.append(Gtk.Box(vexpand=True))
        return self._scrolled_page(page)

    def _text_page(self):
        page = self._page_box()
        page.append(self._section_title("Text Inputs"))
        stack = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)

        entry = Gtk.Entry()
        entry.set_text("Primary text field")
        entry.set_size_request(300, -1)
        entry.set_halign(Gtk.Align.START)
        self._measure_widgets["entry"] = entry
        self._text_audit_widgets["primary"] = entry
        stack.append(entry)

        password = Gtk.PasswordEntry()
        password.set_text("password")
        password.set_size_request(300, -1)
        password.set_halign(Gtk.Align.START)
        self._text_audit_widgets["password"] = password
        stack.append(password)

        combo = self._make_dropdown(
            ["First option", "Second option", "Third option"],
            width=300,
            selected=1,
        )
        combo.set_halign(Gtk.Align.START)
        self._measure_widgets["combo"] = combo
        self._text_audit_widgets["combo"] = combo
        stack.append(combo)

        search = Gtk.SearchEntry()
        search.set_text("Search query")
        search.set_size_request(300, -1)
        search.set_halign(Gtk.Align.START)
        self._measure_widgets["search"] = search
        self._text_audit_widgets["search"] = search
        stack.append(search)

        disabled = Gtk.Entry()
        disabled.set_text("Disabled input")
        disabled.set_sensitive(False)
        disabled.set_size_request(300, -1)
        disabled.set_halign(Gtk.Align.START)
        self._text_audit_widgets["disabled"] = disabled
        stack.append(disabled)

        text_frame = self._make_text_frame("NSTextView\n\n" + TEXT_VIEW_BODY, min_height=240)
        self._text_audit_widgets["body"] = text_frame
        stack.append(text_frame)

        page.append(stack)
        page.append(Gtk.Box(vexpand=True))
        return self._scrolled_page(page)

    def _make_column_view(self):
        store = Gio.ListStore.new(DemoRow)
        for control, state, notes in DATA_ROWS:
            store.append(DemoRow(control, state, notes))

        selection = Gtk.SingleSelection.new(store)
        selection.set_autoselect(False)
        selection.set_can_unselect(True)
        view = Gtk.ColumnView.new(selection)
        view.set_vexpand(True)
        view.set_hexpand(True)

        for title, prop_name, expand in (
            ("Control", "control", True),
            ("State", "state", True),
            ("Notes", "notes", True),
        ):
            factory = Gtk.SignalListItemFactory()

            def setup(_factory, list_item):
                label = Gtk.Label(xalign=0)
                label.set_wrap(True)
                label.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
                list_item.set_child(label)

            def bind(_factory, list_item, property_name=prop_name):
                item = list_item.get_item()
                list_item.get_child().set_text(getattr(item.props, property_name))

            factory.connect("setup", setup)
            factory.connect("bind", bind)
            column = Gtk.ColumnViewColumn.new(title, factory)
            column.set_expand(expand)
            view.append_column(column)

        self._measure_widgets["column_view"] = view
        return view

    def _make_outline_view(self):
        root = Gio.ListStore.new(OutlineRow)
        for title, details, children in OUTLINE_SECTIONS:
            root.append(OutlineRow(title, details, children))

        def create_model(item, _user_data, _unused):
            return item.children

        model = Gtk.TreeListModel.new(root, False, True, create_model, None, None)
        selection = Gtk.SingleSelection.new(model)
        selection.set_autoselect(False)
        selection.set_can_unselect(True)
        view = Gtk.ColumnView.new(selection)
        view.set_vexpand(True)
        view.set_hexpand(True)

        title_factory = Gtk.SignalListItemFactory()

        def setup_title(_factory, list_item):
            expander = Gtk.TreeExpander()
            label = Gtk.Label(xalign=0)
            label.set_wrap(True)
            label.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
            expander.set_child(label)
            list_item.set_child(expander)

        def bind_title(_factory, list_item):
            tree_row = list_item.get_item()
            row = tree_row.get_item()
            expander = list_item.get_child()
            expander.set_list_row(tree_row)
            expander.get_child().set_text(row.props.title)

        def unbind_title(_factory, list_item):
            expander = list_item.get_child()
            expander.set_list_row(None)
            expander.get_child().set_text("")

        title_factory.connect("setup", setup_title)
        title_factory.connect("bind", bind_title)
        title_factory.connect("unbind", unbind_title)
        title_column = Gtk.ColumnViewColumn.new("Section", title_factory)
        title_column.set_expand(True)
        view.append_column(title_column)

        details_factory = Gtk.SignalListItemFactory()

        def setup_details(_factory, list_item):
            label = Gtk.Label(xalign=0)
            label.set_wrap(True)
            label.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
            list_item.set_child(label)

        def bind_details(_factory, list_item):
            tree_row = list_item.get_item()
            row = tree_row.get_item()
            list_item.get_child().set_text(row.props.details)

        def unbind_details(_factory, list_item):
            list_item.get_child().set_text("")

        details_factory.connect("setup", setup_details)
        details_factory.connect("bind", bind_details)
        details_factory.connect("unbind", unbind_details)
        details_column = Gtk.ColumnViewColumn.new("What To Check", details_factory)
        details_column.set_expand(True)
        view.append_column(details_column)

        return view

    def _data_page(self):
        page = self._page_box()

        split = Gtk.Paned.new(Gtk.Orientation.HORIZONTAL)
        split.set_position(560)
        split.set_wide_handle(True)
        split.set_vexpand(True)

        left_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        left_box.append(self._section_title("Table View"))
        column_scroll = Gtk.ScrolledWindow()
        column_scroll.set_hexpand(True)
        column_scroll.set_vexpand(True)
        column_scroll.set_child(self._make_column_view())
        left_box.append(column_scroll)
        split.set_start_child(left_box)

        right_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        right_box.append(self._section_title("Outline View"))
        outline_scroll = Gtk.ScrolledWindow()
        outline_scroll.set_hexpand(True)
        outline_scroll.set_vexpand(True)
        outline_scroll.set_child(self._make_outline_view())
        right_box.append(outline_scroll)
        split.set_end_child(right_box)

        page.append(split)
        return self._scrolled_page(page)

    def _menus_page(self):
        page = self._page_box()
        page.append(self._section_title("Scrollbars"))

        scroll = self._make_scrollbar_preview()
        page.append(scroll)

        page.append(self._section_title("Menu Preview"))
        menu_button = Gtk.MenuButton(label="Show Demo Menu")
        menu_button.set_menu_model(self._build_demo_menu_model())
        self._measure_widgets["menu_button"] = menu_button
        page.append(menu_button)
        page.append(Gtk.Box(vexpand=True))
        return self._scrolled_page(page)

    def _stress_page(self):
        page = self._page_box()
        page.append(self._section_title("Density and Stress"))

        grid = self._grid()

        long_button = Gtk.Button(label="Create and synchronize workspace settings")
        long_button.set_size_request(360, -1)
        long_button.add_css_class("suggested-action")
        self._labeled_row(grid, 0, "Very long primary action label that should still feel balanced", long_button)

        long_entry = Gtk.Entry()
        long_entry.set_text("Long field value used to test horizontal padding")
        long_entry.set_size_request(360, -1)
        self._labeled_row(grid, 1, "Secondary label with a slightly longer caption", long_entry)

        disabled = Gtk.Entry()
        disabled.set_text("Disabled but still legible")
        disabled.set_sensitive(False)
        disabled.set_size_request(360, -1)
        self._labeled_row(grid, 2, "Disabled content should remain readable", disabled)

        long_dropdown = self._make_dropdown([
            "Adwaita default action with a longer title",
            "A second item that forces wider menu geometry",
            "Short item",
        ], width=420)
        self._labeled_row(grid, 3, "Pop-up labels and arrows", long_dropdown)

        stress_menu_button = Gtk.MenuButton(label="Show Long-Label Menu")
        stress_menu_button.set_menu_model(self._build_stress_menu_model())
        self._labeled_row(grid, 4, "Stress Menu", stress_menu_button)

        note_frame = self._make_text_frame(STRESS_NOTES, min_height=200)

        page.append(grid)
        page.append(note_frame)
        page.append(Gtk.Box(vexpand=True))
        return self._scrolled_page(page)

    def _measure_height(self, widget):
        minimum, natural, _minimum_baseline, _natural_baseline = widget.measure(Gtk.Orientation.VERTICAL, -1)
        return max(minimum, natural)

    def _dump_metrics_and_quit(self):
        metrics = {
            "gtk_font_name": Gtk.Settings.get_default().get_property("gtk-font-name"),
            "page": self._stack.get_visible_child_name(),
        }

        for name, widget in sorted(self._measure_widgets.items()):
            metrics[f"{name}_height"] = self._measure_height(widget)

        print(json.dumps(metrics, indent=2, sort_keys=True))
        self.get_application().quit()
        return GLib.SOURCE_REMOVE

    def _font_description_string(self, widget):
        context = widget.get_pango_context()
        if context is None:
            return ""
        description = context.get_font_description()
        if description is None:
            return ""
        return description.to_string()

    def _dump_typography_and_quit(self):
        print(f"TYPOGRAPHY gtk_font_name={Gtk.Settings.get_default().get_property('gtk-font-name')}")

        for name, widget in sorted(self._typography_widgets.items()):
            description = self._font_description_string(widget)
            minimum, natural, _minimum_baseline, _natural_baseline = widget.measure(Gtk.Orientation.VERTICAL, -1)
            classes = ",".join(widget.get_css_classes())
            print(
                "TYPOGRAPHY "
                f"widget={name} "
                f"class={widget.__class__.__name__} "
                f"font=\"{description}\" "
                f"height={max(minimum, natural)} "
                f"css=\"{classes}\""
            )

        self.get_application().quit()
        return GLib.SOURCE_REMOVE

    def _screenshot_and_quit(self):
        if not self._write_screenshot(self._options.screenshot):
            print(f"failed to write screenshot: {self._options.screenshot}", file=sys.stderr)
        self.get_application().quit()
        return GLib.SOURCE_REMOVE

    def _start_command_interface(self):
        if self._options.command_script:
            GLib.idle_add(self._run_command_script, priority=GLib.PRIORITY_LOW)

        if self._options.command_fifo:
            try:
                fd = os.open(self._options.command_fifo, os.O_RDWR | os.O_NONBLOCK)
            except OSError as exc:
                print(f"failed to open command fifo {self._options.command_fifo}: {exc}", file=sys.stderr)
                return

            self._command_fifo_fd = fd
            GLib.timeout_add(50, self._poll_command_fifo)

    def _run_command_script(self):
        try:
            with open(self._options.command_script, "r", encoding="utf-8") as command_file:
                commands = command_file.read()
        except OSError as exc:
            print(f"failed to read command script {self._options.command_script}: {exc}", file=sys.stderr)
            return GLib.SOURCE_REMOVE

        self._execute_command_lines(commands)
        return GLib.SOURCE_REMOVE

    def _poll_command_fifo(self):
        if self._command_fifo_fd is None:
            return GLib.SOURCE_REMOVE
        try:
            data = os.read(self._command_fifo_fd, 4096)
        except BlockingIOError:
            return GLib.SOURCE_CONTINUE
        except OSError as exc:
            print(f"failed to read command fifo: {exc}", file=sys.stderr)
            return GLib.SOURCE_REMOVE

        if not data:
            return GLib.SOURCE_CONTINUE

        self._command_fifo_buffer += data.decode("utf-8", errors="replace")
        while "\n" in self._command_fifo_buffer:
            line, self._command_fifo_buffer = self._command_fifo_buffer.split("\n", 1)
            self._execute_command_line(line)

        return GLib.SOURCE_CONTINUE

    def _execute_command_lines(self, commands):
        for line in commands.splitlines():
            self._execute_command_line(line)

    def _execute_command_line(self, line):
        line = line.strip()
        if not line or line.startswith("#"):
            return

        parts = line.split()
        command = parts[0]

        if command == "page" and len(parts) >= 2:
            self._stack.set_visible_child_name(parts[1])
        elif command in ("click", "double-click") and len(parts) >= 3:
            count = 2 if command == "double-click" else 1
            for _index in range(count):
                self._click(float(parts[1]), float(parts[2]))
        elif command in ("mouse-down", "mouse-up") and len(parts) >= 3:
            self._click(float(parts[1]), float(parts[2]))
        elif command in ("type", "key"):
            text = line[len(command):].lstrip()
            self._type_text(text)
        elif command == "focus" and len(parts) >= 2:
            self._focus_text_audit_widget(parts[1], select_all=False)
        elif command == "blur-to" and len(parts) >= 2:
            self._focus_text_audit_widget(parts[1], select_all=False)
        elif command == "select-all":
            self._select_focused_text_audit_widget()
        elif command == "open-dropdown" and len(parts) >= 2:
            self._open_dropdown(parts[1])
        elif command == "wait" and len(parts) >= 2:
            end_time = GLib.get_monotonic_time() + int(float(parts[1]) * 1_000_000)
            context = GLib.MainContext.default()
            while GLib.get_monotonic_time() < end_time:
                context.iteration(False)
        elif command == "display":
            self.queue_draw()
        elif command == "screenshot" and len(parts) >= 2:
            if not self._write_screenshot(parts[1]):
                print(f"failed to write screenshot: {parts[1]}", file=sys.stderr)
        elif command == "screenshot-screen" and len(parts) >= 2:
            if not self._write_screen_screenshot(parts[1]):
                print(f"failed to write screen screenshot: {parts[1]}", file=sys.stderr)
        elif command == "quit":
            self.get_application().quit()
        else:
            print(f"unknown AdwaitaDemo command: {line}", file=sys.stderr)

    def _widget_at_pixel(self, x, y):
        scale = self.get_scale_factor() or 1
        return self.pick(x / scale, y / scale, Gtk.PickFlags.DEFAULT)

    def _click(self, x, y):
        widget = self._widget_at_pixel(x, y)
        if widget is None:
            return

        if isinstance(widget, Gtk.Editable):
            widget.grab_focus()
            self._focused_text_audit_widget = widget
            if hasattr(widget, "select_region"):
                widget.select_region(0, -1)
            return

        focus = widget
        while focus is not None and not focus.get_can_focus() and not isinstance(focus, Gtk.Button):
            focus = focus.get_parent()

        if isinstance(focus, Gtk.Button):
            focus.activate()
        elif focus is not None:
            focus.grab_focus()

    def _focus_text_audit_widget(self, name, select_all=False):
        widget = self._text_audit_widgets.get(name)
        if widget is None:
            print(f"unknown AdwaitaDemo text audit target: {name}", file=sys.stderr)
            return

        if self._click_widget_center(widget):
            self._focused_text_audit_widget = widget
            if select_all:
                self._select_focused_text_audit_widget()
            return

        widget.grab_focus()
        self._focused_text_audit_widget = widget

        editable = self._editable_delegate(widget)
        if editable is not None:
            self._queue_editable_selection(editable, select_all)

    def _select_focused_text_audit_widget(self):
        widget = self._focused_text_audit_widget or self.get_focus()
        editable = self._editable_delegate(widget)
        if editable is not None:
            self._queue_editable_selection(editable, True)

    def _editable_delegate(self, widget):
        if hasattr(widget, "get_delegate"):
            delegate = widget.get_delegate()
            if isinstance(delegate, Gtk.Editable):
                return delegate
        if isinstance(widget, Gtk.Editable):
            return widget
        return None

    def _click_widget_center(self, widget):
        try:
            success, bounds = widget.compute_bounds(self)
        except TypeError:
            return False

        if not success:
            return False

        scale = self.get_scale_factor() or 1
        self._click((bounds.get_x() + bounds.get_width() / 2.0) * scale,
                    (bounds.get_y() + bounds.get_height() / 2.0) * scale)
        return True

    def _open_dropdown(self, name):
        widget = self._text_audit_widgets.get(name)
        if widget is None:
            print(f"unknown AdwaitaDemo dropdown audit target: {name}", file=sys.stderr)
            return

        if hasattr(widget, "popup"):
            widget.popup()
        else:
            self._click_widget_center(widget)

    def _queue_editable_selection(self, widget, select_all):
        def apply_selection():
            text_length = len(widget.get_text())
            if select_all:
                widget.select_region(0, text_length)
            else:
                widget.select_region(text_length, text_length)
            widget.queue_draw()
            return GLib.SOURCE_REMOVE

        GLib.idle_add(apply_selection, priority=GLib.PRIORITY_HIGH_IDLE)

    def _type_text(self, text):
        focus = self.get_focus()
        if isinstance(focus, Gtk.Editable):
            focus.delete_selection()
            position = focus.get_position()
            focus.insert_text(text, position)
            focus.set_position(position + len(text))

    def _write_screenshot(self, path):
        width = self.get_width()
        height = self.get_height()

        if width <= 0 or height <= 0:
            return False

        snapshot = Gtk.Snapshot()
        paintable = Gtk.WidgetPaintable.new(self)
        paintable.snapshot(snapshot, width, height)
        node = snapshot.to_node()
        if node is None:
            return False

        renderer = Gsk.CairoRenderer.new()
        surface = self.get_surface()
        if surface is not None:
            renderer.realize(surface)

        viewport = Graphene.Rect()
        viewport.init(0, 0, width, height)
        texture = renderer.render_texture(node, viewport)
        if surface is not None:
            renderer.unrealize()
        if texture is None:
            return False

        directory = os.path.dirname(path)
        if directory:
            os.makedirs(directory, exist_ok=True)

        return texture.save_to_png(path)

    def _write_screen_screenshot(self, path):
        try:
            image = ImageGrab.grab()
            directory = os.path.dirname(path)
            if directory:
                os.makedirs(directory, exist_ok=True)
            image.save(path)
            return True
        except Exception:
            pass

        display_name = os.environ.get("DISPLAY")
        library_name = ctypes.util.find_library("X11")
        if not display_name or not library_name:
            return False

        x11 = ctypes.cdll.LoadLibrary(library_name)
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XDefaultScreen.argtypes = [ctypes.c_void_p]
        x11.XDefaultScreen.restype = ctypes.c_int
        x11.XRootWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x11.XRootWindow.restype = ctypes.c_ulong
        x11.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x11.XDisplayWidth.restype = ctypes.c_int
        x11.XDisplayHeight.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x11.XDisplayHeight.restype = ctypes.c_int
        x11.XTranslateCoordinates.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,
            ctypes.c_int, ctypes.c_int,
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_ulong),
        ]
        x11.XTranslateCoordinates.restype = ctypes.c_int
        x11.XGetImage.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
            ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int,
        ]
        x11.XGetImage.restype = ctypes.c_void_p
        x11.XGetPixel.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        x11.XGetPixel.restype = ctypes.c_ulong
        x11.XDestroyImage.argtypes = [ctypes.c_void_p]
        x11.XCloseDisplay.argtypes = [ctypes.c_void_p]

        display = x11.XOpenDisplay(display_name.encode("utf-8"))
        if not display:
            return False

        image_ptr = None
        try:
            screen = x11.XDefaultScreen(display)
            root = x11.XRootWindow(display, screen)
            display_width = x11.XDisplayWidth(display, screen)
            display_height = x11.XDisplayHeight(display, screen)
            surface = self.get_surface()
            if surface is None:
                return False

            xid = GdkX11.X11Surface.get_xid(surface)
            root_x = ctypes.c_int(0)
            root_y = ctypes.c_int(0)
            child = ctypes.c_ulong(0)
            if not x11.XTranslateCoordinates(display, xid, root, 0, 0,
                                             ctypes.byref(root_x),
                                             ctypes.byref(root_y),
                                             ctypes.byref(child)):
                return False

            x = max(0, root_x.value - 40)
            y = max(0, root_y.value - 40)
            width = min(self.get_width() + 80, display_width - x)
            height = min(self.get_height() + 420, display_height - y)
            if width <= 0 or height <= 0:
                return False
            image_ptr = x11.XGetImage(display, root, x, y, width, height,
                                      ctypes.c_ulong(-1).value, 2)
            if not image_ptr:
                return False

            image = Image.new("RGB", (width, height))
            pixels = image.load()
            for y in range(height):
                for x in range(width):
                    pixel = x11.XGetPixel(image_ptr, x, y)
                    pixels[x, y] = ((pixel >> 16) & 0xff,
                                    (pixel >> 8) & 0xff,
                                    pixel & 0xff)

            directory = os.path.dirname(path)
            if directory:
                os.makedirs(directory, exist_ok=True)
            image.save(path)
            return True
        finally:
            if image_ptr:
                x11.XDestroyImage(image_ptr)
            x11.XCloseDisplay(display)


class AdwaitaDemoApplication(Adw.Application):
    def __init__(self, options):
        super().__init__(application_id=options.application_id or "org.gnustep.AdwaitaDemo")
        self._options = options

    def do_startup(self):
        Adw.Application.do_startup(self)
        action = Gio.SimpleAction.new("noop", None)
        action.connect("activate", lambda *_args: None)
        self.add_action(action)

    def do_activate(self):
        window = self.props.active_window
        if window is None:
            window = AdwaitaDemoWindow(self, self._options)
        window.present()


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Adwaita comparison harness for the GNUstep Adwaita theme")
    parser.add_argument("--page", choices=PAGE_NAMES, help="Open the app with a specific page selected")
    parser.add_argument("--dump-metrics", action="store_true", help="Print widget metrics from the current Adwaita environment and exit")
    parser.add_argument("--dump-typography", action="store_true", help="Print live widget font descriptions from the current Adwaita environment and exit")
    parser.add_argument("--application-id", help="Override the application ID for parallel capture runs")
    parser.add_argument("--window-title", help="Override the window title for deterministic screenshot capture")
    parser.add_argument("--command-script", help="Run ThemeDemo-compatible UI commands from a text file")
    parser.add_argument("--command-fifo", help="Read ThemeDemo-compatible UI commands from a FIFO")
    parser.add_argument("--screenshot", help="Write an internal PNG screenshot and exit")
    return parser.parse_args(argv)


def main(argv=None):
    options = parse_args(argv or sys.argv[1:])
    app = AdwaitaDemoApplication(options)
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
