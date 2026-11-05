# AdwaitaDemo

`AdwaitaDemo` is the GNOME-side comparison harness for this repository.

It exists to give the GNUstep theme a concrete visual target instead of relying
on memory.

## Usage

Run the app:

```sh
python3 Reference/AdwaitaDemo/adwaita_demo.py
```

Open a specific page:

```sh
python3 Reference/AdwaitaDemo/adwaita_demo.py --page controls
python3 Reference/AdwaitaDemo/adwaita_demo.py --page stress
```

Dump measured widget metrics from the live Adwaita environment:

```sh
python3 Reference/AdwaitaDemo/adwaita_demo.py --dump-metrics
```

Run command automation for focused visual checks:

```sh
python3 Reference/AdwaitaDemo/adwaita_demo.py --command-script /tmp/adwaita-demo.commands
python3 Reference/AdwaitaDemo/adwaita_demo.py --command-fifo /tmp/adwaita-demo.fifo
```

Supported commands are `page NAME`, `click X Y`, `focus NAME`, `blur-to NAME`,
`select-all`, `open-dropdown NAME`, `type TEXT`, `key TEXT`, `wait SECONDS`,
`display`, `screenshot PATH`, `screenshot-screen PATH`, and `quit`. Text audit
names are `primary`, `password`, `search`, `disabled`, `body`, and `combo`.
Coordinates are backing-pixel positions from the top-left of the internally
captured window image, so they line up with screenshots produced by
`screenshot PATH`. Use `screenshot-screen PATH` when auditing popups or dropdowns
that render outside the application window.

Write one internal screenshot and exit:

```sh
python3 Reference/AdwaitaDemo/adwaita_demo.py --page text --screenshot /tmp/adwaita-text.png
```

The current app depends on system-provided `PyGObject`, GTK4, and libadwaita.
