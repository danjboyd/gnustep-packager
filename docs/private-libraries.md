# Bundling Your Own Libraries

Some apps link a library of their own that isn't part of GNUstep: built from
source in the app's tree, pinned to a commit, and not installed anywhere on the
user's machine. AIManager's Trellis is one. This page says where such a library
goes in each installer, how the app finds it at runtime, and what validation
checks.

The library can be C or Objective-C. For Objective-C, build it with the same
toolchain as the app (the gnustep-cli-new clang and libobjc2), so it links the
same `libobjc` and `libgnustep-base` the package already carries.

The rule is the same everywhere: **the library ships inside the package, and
the app finds it there through a path relative to itself**, never through the
build directory.

## AppImage

Stage the library under the runtime, for example `runtime/lib/libTrellis.so`,
or next to the executable. Then do one of these:

- **RUNPATH (recommended):** link the app with an `$ORIGIN`-relative RUNPATH,
  for example `-Wl,--enable-new-dtags,-rpath,'$ORIGIN/../../runtime/lib'` for
  an executable in `app/Demo.app/`. Only this app sees it; programs the app
  starts don't.
- **`launch.env.LD_LIBRARY_PATH`:** add the directory, with policy
  `prepend`, the way the examples add `{@runtimeRoot}/lib`. Every process the
  app starts inherits it (see `docs/appimage-runpath-design.md`).

If the library itself links other libraries of yours, give it a RUNPATH too
(`$ORIGIN` when they sit side by side).

What validation checks (`validation.runtimeClosure: "strict"`):

- A RUNPATH or RPATH that points outside the AppDir, such as the build
  directory, fails: "escaped the AppDir via RUNPATH/RPATH".
- A library that wasn't staged fails: "unresolved dependency".
- A library staged in `runtime/lib` with neither a RUNPATH nor an
  `LD_LIBRARY_PATH` entry is a warning: "in the AppDir but not on its runtime
  search path". Validation follows the loader's real search (RUNPATH with
  `$ORIGIN`, and the `LD_LIBRARY_PATH` the generated `AppRun` exports), so it
  sees that the app won't find the library. Set
  `backends.appimage.validation.requireLoaderSearchPath: true` to make it fail.

`tests/linux/AppImagePrivateLibrary.Tests.ps1` builds such a library and app
and checks each case.

## MSI

Name the directory your build writes the DLL to in
`backends.msi.runtimeSearchRoots`:

```json
"backends": {
  "msi": {
    "runtimeSearchRoots": ["C:/a/myapp/myapp/build/trellis/bin"]
  }
}
```

Use an absolute path. A relative one isn't resolved against the manifest: it's
taken from the directory the packager runs in (in the reusable workflow, the
checkout root), which is easy to get wrong.

When the packager computes the runtime closure, it copies every DLL the app
imports from those roots into `runtime\bin`. The launcher puts `runtime\bin`
on `PATH`, so the app finds it there. You can also stage the DLL yourself,
next to the `.exe` or in `runtime\bin`.

What validation checks: a DLL the app imports that isn't in the install tree
and isn't in a search root is reported missing, and the MSI isn't built. A DLL
that is in the tree but not where Windows will search (the importing file's
folder, the app's folder, the working directory, `launch.pathPrepend` or
`runtime\bin`), for example one left under `Resources`, is a warning. Set
`backends.msi.validation.requireLoaderSearchPath: true` to make it fail.

`tests/windows/MsiPrivateLibrary.Tests.ps1` builds such a DLL and app and
checks both cases.

## DMG

Put the dylib (or framework) in `Contents/Frameworks`, give it an `@rpath`
install name, and give the executable an `LC_RPATH` that points there:

```sh
clang -dynamiclib -install_name @rpath/libTrellis.dylib -o libTrellis.dylib ...
clang -o Demo ... libTrellis.dylib -Wl,-rpath,@executable_path/../Frameworks
cp libTrellis.dylib Demo.app/Contents/Frameworks/
```

For a dylib that's already built with another install name, fix it with
`install_name_tool -id @rpath/libTrellis.dylib` and
`install_name_tool -change <old> @rpath/libTrellis.dylib <executable>`, then
sign the bundle again.

What validation checks: the `library-references` check reads every Mach-O file
in the mounted app with `otool`. Each library it loads must be under `/usr/lib`
or `/System`, or resolve inside the bundle through `@executable_path`,
`@loader_path` or `@rpath`. A dylib referenced by its build path
(`/Users/runner/work/...`) loads on the build Mac, so the smoke launch passes
there, but it fails on every other Mac; this check is what catches it. It warns
by default. Set `backends.dmg.validation.requireBundledDependencies: true` to
make it fail.

A helper tool shipped inside the bundle (say in `Contents/Resources`) is its
own main executable to dyld. It doesn't get the app's run paths, and
`@executable_path` in it means the helper's folder. Give it its own, for
example `-Wl,-rpath,@executable_path/../Frameworks` from `Contents/Resources`.
The check follows the same rule.

`tests/macos/DmgLibraryReferences.Tests.ps1` builds such a dylib and app and
checks the bundled, build-path, missing-rpath and helper-executable cases.

## Reading the warnings

The three checks above warn by default, so a build that passed before still
passes. Each warning names the file that loads the library, the library, and
where it was found. Find them in the package log, inside the run's logs
artifact; the AppImage and MSI ones also appear in the job output as
`WARNING:` lines. Each one means the app works on the build machine but may
not start elsewhere.

**AppImage**

```text
Loader search path check (AppRun LD_LIBRARY_PATH: ...): 1 issue(s)
WARNING library not on the runtime search path: usr/bin/Demo needs libTrellis.so.1, which is in the AppDir but not on its runtime search path (no RUNPATH or AppRun LD_LIBRARY_PATH entry reaches it)
```

`usr/bin/Demo` will ask the loader for `libTrellis.so.1`. The file is in the
AppDir, but nothing the loader searches reaches its folder. On the build
machine the library may also be installed system-wide, which is why the app
still starts there. Fix it with a RUNPATH on `Demo`, or by adding the folder to
`launch.env.LD_LIBRARY_PATH` (see [AppImage](#appimage)).

**MSI**

```text
DLL search path check (...): 1 issue(s); warning only (...)
WARNING app\Demo.app\Demo.exe imports Trellis.dll, which is only at app\Demo.app\Resources\Trellis.dll: not in its own folder, the app's folder, the working directory or the launcher's PATH
```

Windows won't look in `Resources`. Move the DLL to `runtime\bin` or next to
`Demo.exe`, or add its folder to `launch.pathPrepend` (see [MSI](#msi)).

**DMG**

```text
Library reference: Contents/MacOS/Demo loads /Users/runner/work/demo/build/libTrellis.dylib, which is outside the bundle and the system
WARN    library-references: 1 reference(s) outside the bundle (works only where that path exists): ...
```

The executable records the build path. Change it to `@rpath/...` and bundle the
dylib (see [DMG](#dmg)). "which doesn't resolve inside the bundle" means the
reference is already `@rpath` or `@loader_path`, but no run path or folder in
the bundle holds the library. Usually the `LC_RPATH` is missing, or the dylib
wasn't copied into `Contents/Frameworks`.

**After the fix,** rebuild and check that the count reads `0 issue(s)` (DMG:
`PASS    library-references`). Then turn the check into a failure so it can't
come back:

| Installer | Setting |
| --- | --- |
| AppImage | `backends.appimage.validation.requireLoaderSearchPath: true` |
| MSI | `backends.msi.validation.requireLoaderSearchPath: true` |
| DMG | `backends.dmg.validation.requireBundledDependencies: true` |

A warning about a library you didn't add, such as a GNUstep or toolchain
library, is a packager bug. Report it with the log line.

## Notices

A library you ship is a third-party component even when you wrote it. If its
license needs a notice, add it to `compliance.runtimeNotices`, as for the
GNUstep runtime.
