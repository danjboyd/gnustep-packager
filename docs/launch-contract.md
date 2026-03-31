# Launch Contract

## Purpose
The launch contract is the backend-neutral description of how the packaged app
starts from the staged payload.

It answers:
- what executable should launch
- what should be the working directory
- what path entries should be prepended
- which resource roots matter at startup
- which environment variables must be set
- whether an environment value is unconditional or only a default

## Inputs
The current launch contract is built from:
- `payload.stageRoot`
- `payload.appRoot`
- `payload.runtimeRoot`
- `payload.metadataRoot`
- `payload.resourceRoots`
- `launch.entryRelativePath`
- `launch.workingDirectory`
- `launch.arguments`
- `launch.pathPrepend`
- `launch.resourceRoots`
- `launch.env`

## Output Shape
The normalized launch contract includes:
- stage root path
- entry path
- working directory path
- native path-prepend entries
- native resource-root entries
- startup environment variables normalized to `{ value, policy }`
- backend-formatted path variants

Plain string `launch.env` entries normalize to `policy: override`.

Current assignment policies:
- `override`
  Always set the variable in the backend launcher.
- `ifUnset`
  Set the variable only when the variable is not already defined in the
  process environment.

## Runtime Tokens
Backend renderers may expand these tokens inside launch-environment values:

- `{@installRoot}`
- `{@appRoot}`
- `{@runtimeRoot}`
- `{@metadataRoot}`

Those tokens let one manifest describe launch requirements without hard-coding
Windows install paths or Linux mount paths.

## Why It Exists
This is the shared abstraction that should later feed:
- a Windows bootstrap launcher for MSI
- an `AppRun` launcher for AppImage

Without this layer, Windows launch details would hard-code assumptions that
make the Linux backend harder to add cleanly.
