# Versioning and Release Policy

## Shared Package Version
The authoritative consumer-facing version is `package.version`.

Local and CI release flows may override it with:

- `-PackageVersion`
- `GP_PACKAGE_VERSION_OVERRIDE`

## Artifact Naming
Artifacts are rendered from backend patterns such as:

- `backends.msi.artifactNamePattern`
- `backends.msi.portableArtifactNamePattern`
- `backends.appimage.artifactNamePattern`

Those patterns receive:

- `{name}`
- `{version}`
- `{packageId}`
- `{backend}`

## MSI Version Mapping
MSI upgrade semantics require a numeric version. The backend normalizes package
versions by taking the first four numeric groups it finds.

Examples:

- `1.2.3` -> `1.2.3.0`
- `1.2.3.4` -> `1.2.3.4`
- `1.2.3-rc1+7` -> `1.2.3.1`

The original package version still remains visible in manifest resolution and
artifact file naming.

## Release Guidance
Recommended release flow:

1. tag the consumer repo
2. pass the release version into the reusable workflow
3. let the workflow package, validate, and upload artifacts
4. publish release notes from the consumer repo, not from generated packaging
   output

## Determinism Rule
The same manifest plus the same version override should produce the same
artifact names locally and in CI.
