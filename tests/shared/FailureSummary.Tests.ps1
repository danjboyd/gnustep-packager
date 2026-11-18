Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# A failed build left its cause in dist/logs/build/<time>.log, reachable only by
# downloading the logs artifact. These cases use the shape of SpreadsheetApp's
# real Windows failure: a gnustep-cli report with the compiler error inside it,
# colored PowerShell exceptions, and gnustep-cli-new's own diagnostics beside it.
Describe "Packaging failure summary" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))
    . (Join-Path $script:repoRoot "scripts\\lib\\core.ps1")
    $script:workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gp-failure-summary-" + [guid]::NewGuid().ToString("N"))

    function New-GpFailureLogRoot {
      $root = Join-Path $script:workRoot ([guid]::NewGuid().ToString("N"))
      foreach ($dir in @("host-preflight", "build", "gnustep-cli-new")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null
      }
      $preflight = Join-Path $root "host-preflight/20261117-230557-968.log"
      Set-Content -Path $preflight -Value "Host dependency preflight completed."
      (Get-Item $preflight).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-5)

      $esc = [char]27
      Set-Content -Path (Join-Path $root "build/20261117-230600-002.log") -Value @(
        "[2026-11-17T23:06:00.0513753+00:00] shell=pwsh"
        "doctor: status=ok classification=toolchain_compatible"
        "build: GNUstep project build failed."
        "build: exit_status=2"
        "../Document/SPWorkbookPackage.m:151:28: error: no known class method for selector 'dataWithContentsOfFile:options:error:'"
        "  151 |     NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];"
        "D:/a/App/Vendor/CocoaTerminal/src/COTTerminalSession.mm:15:10: fatal error: 'sys/ioctl.h' file not found"
        "make[1]: *** [GNUmakefile:138: before-all] Error 1"
        "${esc}[31;1mException: ${esc}[0mD:\a\App\packaging\scripts\build.ps1:19"
        "warning: unused variable 'x'"
      )
      # Newer, but gnustep-cli-new's diagnostics have their own artifact.
      Set-Content -Path (Join-Path $root "gnustep-cli-new/bootstrap.log") -Value "error: unrelated"
      return $root
    }
  }

  AfterAll {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $script:workRoot
  }

  It "picks the newest pipeline log and pulls out the error lines" {
    $summary = Get-GpFailureLogSummary -LogRoot (New-GpFailureLogRoot)

    $summary.LogPath | Should -Match "build[\\/]20261117-230600-002\.log$"
    $summary.ErrorLines | Should -Contain "../Document/SPWorkbookPackage.m:151:28: error: no known class method for selector 'dataWithContentsOfFile:options:error:'"
    $summary.ErrorLines | Should -Contain "make[1]: *** [GNUmakefile:138: before-all] Error 1"
    $summary.ErrorLines | Should -Contain "Exception: D:\a\App\packaging\scripts\build.ps1:19"
    $summary.ErrorLines | Should -Not -Contain "warning: unused variable 'x'"
    $summary.ErrorLines | Should -Not -Contain "doctor: status=ok classification=toolchain_compatible"
    @($summary.TailLines).Count | Should -Be 10
  }

  It "turns compiler errors into file and line annotations" {
    $summary = Get-GpFailureLogSummary -LogRoot (New-GpFailureLogRoot)
    $annotations = @($summary.Annotations)

    $annotations.Count | Should -Be 2
    $annotations[0].File | Should -Be "../Document/SPWorkbookPackage.m"
    $annotations[0].Line | Should -Be 151
    $annotations[0].Column | Should -Be 28
    $annotations[1].File | Should -Be "D:/a/App/Vendor/CocoaTerminal/src/COTTerminalSession.mm"
    $annotations[1].Message | Should -Be "'sys/ioctl.h' file not found"

    Format-GpFailureAnnotation -Annotation $annotations[1] |
      Should -Be "::error file=D%3A/a/App/Vendor/CocoaTerminal/src/COTTerminalSession.mm,line=15,col=10::'sys/ioctl.h' file not found"
  }

  It "renders a job summary with the log path, error lines and tail" {
    $summary = Get-GpFailureLogSummary -LogRoot (New-GpFailureLogRoot) -TailLines 3
    $markdown = Format-GpFailureSummaryMarkdown -Summary $summary

    $markdown | Should -Match "### Run Packaging Pipeline failed"
    $markdown | Should -Match "\*\*Error lines\*\*"
    $markdown | Should -Match "\*\*Last 3 lines\*\*"
    $markdown | Should -Match "dataWithContentsOfFile"
  }

  It "returns nothing when there's no pipeline log" {
    Get-GpFailureLogSummary -LogRoot (Join-Path $script:workRoot "missing") | Should -BeNullOrEmpty
    $empty = Join-Path $script:workRoot "empty"
    New-Item -ItemType Directory -Force -Path (Join-Path $empty "gnustep-cli-new") | Out-Null
    Set-Content -Path (Join-Path $empty "gnustep-cli-new/x.log") -Value "error: x"
    Get-GpFailureLogSummary -LogRoot $empty | Should -BeNullOrEmpty
  }

  It "is wired into the reusable workflow after the pipeline step, only on its failure" {
    $workflow = Get-Content -Raw (Join-Path $script:repoRoot ".github/workflows/package-gnustep-app.yml")
    $pipeline = $workflow.IndexOf("- name: Run Packaging Pipeline")
    $summaryStep = $workflow.IndexOf("- name: Summarize Packaging Failure")
    $summaryStep | Should -BeGreaterThan $pipeline
    $workflow | Should -Match "failure\(\) && steps\.pipeline\.outcome == 'failure'"
    $workflow | Should -Match "Get-GpFailureLogSummary -LogRoot"
  }
}
