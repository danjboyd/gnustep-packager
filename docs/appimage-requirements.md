# AppImage Requirements

## Supported Host Baseline
The implemented AppImage path targets:

- Linux x64
- PowerShell 7+
- `squashfs-tools`
- `desktop-file-utils`
- `appimagetool` x86_64

Repo CI uses `ubuntu-latest` as the Linux baseline.

## Packaging Assumptions
The AppImage backend assumes:

- the consumer already stages a self-contained payload
- the staged payload follows the shared `app/`, `runtime/`, and `metadata/`
  contract
- the packaged icon is a staged `.png`
- Linux-specific dependency closure is handled before packaging rather than by
  the backend discovering arbitrary system libraries

## Tooling Decision
The backend uses `appimagetool` directly.

Behavior:
- use `appimagetool` from `PATH` when present
- otherwise bootstrap the configured x86_64 AppImage build into
  `tools/appimage`
- pass `-n` by default to skip AppStream validation unless the manifest opts
  into stricter behavior later

`linuxdeploy` remains optional future tooling, not part of the current
contract.

## Portability Boundary
The current implementation is designed for predictable Linux CI and local
reproduction, not for automatic distro-specific runtime discovery.

Consumers are responsible for staging:
- the app payload
- the bundled GNUstep runtime
- required metadata, notices, and icons
- any ELF dependencies that must travel with the app
