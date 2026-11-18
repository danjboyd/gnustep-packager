Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# build-keep-going sets MAKEFLAGS=-k for the pipeline step. These cases check
# what that does to a make build with two broken objects (the SpreadsheetApp
# Windows port turned up its errors one hosted run at a time), and that the
# reusable workflow only sets it when asked.
Describe "build-keep-going" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    $script:make = (Get-Command make -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-keep-going-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $script:workRoot | Out-Null
    Set-Content -Path (Join-Path $script:workRoot "Makefile") -Value @(
      "all: first.o second.o"
      "first.o:"
      "`t@echo 'first.m:1:1: error: first failure' && false"
      "second.o:"
      "`t@echo 'second.m:2:2: error: second failure' && false"
    )

    function Invoke-GpTestMake([string]$MakeFlags) {
      $previous = $env:MAKEFLAGS
      try {
        $env:MAKEFLAGS = $MakeFlags
        $output = & $script:make -C $script:workRoot 2>&1 | Out-String
        return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
      } finally {
        $env:MAKEFLAGS = $previous
      }
    }
  }

  AfterAll {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $script:workRoot
  }

  It "stops at the first failure without it" {
    if (-not $script:make) { Set-ItResult -Skipped -Because "make is needed"; return }
    $result = Invoke-GpTestMake -MakeFlags ""
    $result.ExitCode | Should -Not -Be 0
    $result.Output | Should -Match "first failure"
    $result.Output | Should -Not -Match "second failure"
  }

  It "reports every failure with MAKEFLAGS=-k, and still fails" {
    if (-not $script:make) { Set-ItResult -Skipped -Because "make is needed"; return }
    $result = Invoke-GpTestMake -MakeFlags ("" + " -k").Trim()
    $result.ExitCode | Should -Not -Be 0
    $result.Output | Should -Match "first failure"
    $result.Output | Should -Match "second failure"
  }

  It "is an off-by-default workflow input that only adds -k when true" {
    $workflow = Get-Content -Raw (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $workflow | Should -Match "(?s)build-keep-going:.*?type: boolean\s+default: false"
    $workflow | Should -Match ([regex]::Escape("if ('`${{ inputs.build-keep-going }}' -eq 'true') {"))
    $workflow | Should -Match ([regex]::Escape('$env:MAKEFLAGS = ("$env:MAKEFLAGS -k").Trim()'))
  }
}
