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
- **Not caught by static validation:** a library staged in `runtime/lib` with
  neither a RUNPATH nor `LD_LIBRARY_PATH`. Validation's `ldd` searches every
  directory in the AppDir that holds an ELF file, so it finds the library,
  but the app won't. Run the smoke launch (`-RunSmoke`, or `run-smoke: true`
  in the reusable workflow); it starts the real `AppRun` and fails there.

`tests/linux/AppImagePrivateLibrary.Tests.ps1` builds such a library and app
and checks each case.

## MSI

Name the directory your build writes the DLL to in
`backends.msi.runtimeSearchRoots`:

```json
"backends": {
  "msi": {
    "runtimeSearchRoots": ["build/trellis/bin"]
  }
}
```

When the packager computes the runtime closure, it copies every DLL the app
imports from those roots into `runtime\bin`. The launcher puts `runtime\bin`
on `PATH`, so the app finds it there. You can also stage the DLL yourself,
next to the `.exe` or in `runtime\bin`.

What validation checks: a DLL the app imports that isn't in the install tree
and isn't in a search root is reported missing, and the MSI isn't built. The
check counts a DLL found anywhere in the install tree as present, so don't
leave one in a folder Windows won't search (for example under `Resources`).

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

`tests/macos/DmgLibraryReferences.Tests.ps1` builds such a dylib and app and
checks the bundled, build-path and missing-rpath cases.

## Notices

A library you ship is a third-party component even when you wrote it. If its
license needs a notice, add it to `compliance.runtimeNotices`, as for the
GNUstep runtime.
