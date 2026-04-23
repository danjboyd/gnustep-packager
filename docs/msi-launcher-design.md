# MSI Launcher Design

## Purpose
GNUstep apps often need startup environment setup before the inner executable
can run on a clean Windows machine.

The MSI backend therefore generates a top-level Windows launcher plus a small
configuration file from the shared launch contract.

## Launcher Shape
The backend ships:

- a generic GUI launcher executable
- a generated `.launcher.ini` file next to it

The executable is reusable across apps. App-specific behavior comes from the
generated config file, not from editing C source per app.

## Generated Inputs
The launcher config is derived from:

- `launch.entryRelativePath`
- `launch.workingDirectory`
- `launch.arguments`
- `launch.pathPrepend`
- `launch.env`
- `packagedDefaults.appDomain`
- `payload.appRoot`
- `payload.runtimeRoot`
- `payload.metadataRoot`
- `backends.msi.fallbackRuntimeRoot`
- `backends.msi.unresolvedDependencyPolicy`

## Runtime Tokens
Environment values may use these runtime-resolved tokens:

- `{@installRoot}`
- `{@appRoot}`
- `{@runtimeRoot}`
- `{@metadataRoot}`

Those tokens are written into launcher config and expanded by the generated
launcher at runtime.

## Launcher Behavior
At runtime the launcher:

- resolves its install root from its own path
- resolves the inner executable relative to that root
- prefers the bundled runtime root
- optionally falls back to `backends.msi.fallbackRuntimeRoot`
- prepends configured runtime paths to `PATH`
- sets configured environment variables according to their assignment policy
- seeds configured app-domain defaults through the bundled `defaults.exe` only
  when the packaged app has not already stored the key
- configures fontconfig when `runtime\etc\fonts\fonts.conf` exists
- forwards command-line arguments to the inner app

Launch-environment entries can either always override or only apply when the
target variable is unset. That lets a package ship defaults such as
`GSTheme=WinUXTheme` without preventing users from setting their own theme.

Generic packaged defaults remain app-domain only. The launcher does not expose
generic GNUstep global-domain writes.

## Why Config-Driven
This keeps the backend reusable:

- the launcher source stays stable
- per-app behavior is manifest-driven
- the same launch contract can later feed an AppImage `AppRun`
