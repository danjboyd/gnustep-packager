#!/usr/bin/env bash
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

set -eu

DELAY="5"
OUTPUT="$HOME/Pictures/wayland-shot.png"

usage() {
  cat <<'EOF'
Usage: delayed-wayland-screenshot.sh [--delay SECONDS] [--output PATH]

Takes a screenshot through the Wayland screenshot portal after a delay.

Options:
  --delay SECONDS   Delay before the screenshot is taken. Default: 5
  --output PATH     Output PNG path. Default: ~/Pictures/wayland-shot.png
  --help            Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --delay)
      DELAY="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$(dirname "$OUTPUT")"

python3 - "$DELAY" "$OUTPUT" <<'PY'
import os
import sys
import time
import uuid

import gi
from gi.repository import Gio, GLib


def finish(loop, state, ok, message):
    state["ok"] = ok
    state["message"] = message
    loop.quit()


def main():
    delay = float(sys.argv[1])
    output = os.path.expanduser(sys.argv[2])
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    token = "shot" + uuid.uuid4().hex
    sender = conn.get_unique_name()[1:].replace(".", "_")
    expected_path = (
        f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    )
    state = {"ok": False, "message": "timeout"}

    def on_response(connection, sender_name, object_path, interface_name,
                    signal_name, parameters, user_data):
        response, results = parameters.unpack()

        if response != 0:
            finish(loop, state, False, f"portal response={response}")
            return

        uri = results.get("uri")
        if hasattr(uri, "unpack"):
            uri = uri.unpack()
        if not uri:
            finish(loop, state, False, "no uri returned")
            return

        src = Gio.File.new_for_uri(uri)
        dst = Gio.File.new_for_path(output)

        try:
            if os.path.exists(output):
                os.remove(output)
            src.copy(dst, Gio.FileCopyFlags.OVERWRITE, None, None, None)
        except Exception as exc:
            finish(loop, state, False, f"copy failed: {exc}")
            return

        finish(loop, state, True, f"saved to {output}")

    sub_id = conn.signal_subscribe(
        "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request",
        "Response",
        expected_path,
        None,
        Gio.DBusSignalFlags.NO_MATCH_RULE,
        on_response,
        None,
    )

    print(f"Waiting {delay:g} seconds before capture...")
    time.sleep(delay)

    proxy = Gio.DBusProxy.new_sync(
        conn,
        Gio.DBusProxyFlags.NONE,
        None,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Screenshot",
        None,
    )

    handle = proxy.call_sync(
        "Screenshot",
        GLib.Variant(
            "(sa{sv})",
            (
                "",
                {
                    "handle_token": GLib.Variant("s", token),
                    "modal": GLib.Variant("b", False),
                    "interactive": GLib.Variant("b", False),
                },
            ),
        ),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    ).unpack()[0]

    if handle != expected_path:
        conn.signal_unsubscribe(sub_id)
        sub_id = conn.signal_subscribe(
            "org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.Request",
            "Response",
            handle,
            None,
            Gio.DBusSignalFlags.NO_MATCH_RULE,
            on_response,
            None,
        )

    GLib.timeout_add_seconds(
        20, lambda: (finish(loop, state, False, "timeout"), False)[1]
    )
    loop.run()
    conn.signal_unsubscribe(sub_id)

    if state["ok"]:
        print(state["message"])
        return 0

    print(state["message"], file=sys.stderr)
    return 1


sys.exit(main())
PY
