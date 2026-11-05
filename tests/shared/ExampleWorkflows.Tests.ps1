Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Consumers copy the example workflows, so an input they pass that a reusable
# workflow no longer declares (or a new required input they lack) should fail
# here rather than in a consumer's first run. This reads the YAML as text, by
# indentation, which is enough for the plain block style these files use.
Describe "Example workflows" {
  BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\\.."))

    function Get-GpYamlChildKeys {
      param([string[]]$Lines, [int]$ParentIndex)
      $parentIndent = ($Lines[$ParentIndex] -replace '^(\s*).*$', '$1').Length
      $childIndent = -1
      $keys = [System.Collections.Generic.List[object]]::new()
      for ($i = $ParentIndex + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s*(#.*)?$') { continue }
        $indent = ($line -replace '^(\s*).*$', '$1').Length
        if ($indent -le $parentIndent) { break }
        if ($childIndent -lt 0) { $childIndent = $indent }
        if ($indent -eq $childIndent -and $line -match '^\s*([A-Za-z0-9_-]+):') {
          $keys.Add([pscustomobject]@{ Name = $Matches[1]; Index = $i }) | Out-Null
        }
      }
      return $keys.ToArray()
    }

    function Find-GpYamlKey {
      param([string[]]$Lines, [string]$Name, [int]$From = 0)
      for ($i = $From; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ('^\s*' + [regex]::Escape($Name) + ':\s*$')) { return $i }
      }
      return -1
    }

    # Inputs and secrets a reusable workflow declares under on.workflow_call.
    function Get-GpWorkflowCallInterface {
      param([string]$Path)
      $lines = @(Get-Content -Path $Path)
      $call = Find-GpYamlKey -Lines $lines -Name "workflow_call"
      if ($call -lt 0) { throw "$Path has no workflow_call trigger." }
      $interface = @{ Inputs = @{}; Secrets = @{} }
      foreach ($section in Get-GpYamlChildKeys -Lines $lines -ParentIndex $call) {
        $target = switch ($section.Name) { "inputs" { "Inputs" } "secrets" { "Secrets" } default { $null } }
        if (-not $target) { continue }
        foreach ($key in Get-GpYamlChildKeys -Lines $lines -ParentIndex $section.Index) {
          $required = $false
          foreach ($prop in Get-GpYamlChildKeys -Lines $lines -ParentIndex $key.Index) {
            if ($prop.Name -eq "required" -and $lines[$prop.Index] -match 'required:\s*true') { $required = $true }
          }
          $interface[$target][$key.Name] = $required
        }
      }
      return $interface
    }
  }

  It "passes only declared inputs and secrets to the reusable workflows, and every required input" {
    $tracked = @(& git -C $script:repoRoot ls-files -- "examples/*.yml" "examples/*.yaml")
    if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) {
      throw "Could not list the tracked example workflows."
    }

    $interfaces = @{}
    $refs = [System.Collections.Generic.HashSet[string]]::new()
    $calls = 0
    $failures = [System.Collections.Generic.List[string]]::new()

    foreach ($relative in $tracked) {
      $lines = @(Get-Content -Path (Join-Path $script:repoRoot $relative))
      for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^(\s*)uses:\s*danjboyd/gnustep-packager/\.github/workflows/([^@\s]+)@(\S+)') { continue }
        $workflowFile = $Matches[2]
        $null = $refs.Add($Matches[3])
        $calls++
        $where = "{0}:{1}" -f $relative, ($i + 1)

        $workflowPath = Join-Path $script:repoRoot ".github/workflows/$workflowFile"
        if (-not (Test-Path -LiteralPath $workflowPath)) {
          $failures.Add("${where}: .github/workflows/$workflowFile does not exist") | Out-Null
          continue
        }
        if (-not $interfaces.ContainsKey($workflowFile)) {
          $interfaces[$workflowFile] = Get-GpWorkflowCallInterface -Path $workflowPath
        }
        $interface = $interfaces[$workflowFile]

        # The job is the key that holds this uses: line.
        $jobIndex = $i - 1
        $usesIndent = ($lines[$i] -replace '^(\s*).*$', '$1').Length
        while ($jobIndex -ge 0 -and (($lines[$jobIndex] -replace '^(\s*).*$', '$1').Length -ge $usesIndent -or $lines[$jobIndex] -match '^\s*$')) { $jobIndex-- }

        $passed = @{ with = @(); secrets = @() }
        foreach ($block in Get-GpYamlChildKeys -Lines $lines -ParentIndex $jobIndex) {
          if ($passed.ContainsKey($block.Name)) {
            $passed[$block.Name] = @(Get-GpYamlChildKeys -Lines $lines -ParentIndex $block.Index | ForEach-Object Name)
          }
        }

        foreach ($name in $passed.with) {
          if (-not $interface.Inputs.ContainsKey($name)) { $failures.Add("${where}: input '$name' is not declared by $workflowFile") | Out-Null }
        }
        foreach ($name in $passed.secrets) {
          if (-not $interface.Secrets.ContainsKey($name)) { $failures.Add("${where}: secret '$name' is not declared by $workflowFile") | Out-Null }
        }
        foreach ($name in $interface.Inputs.Keys) {
          if ($interface.Inputs[$name] -and $passed.with -notcontains $name) { $failures.Add("${where}: required input '$name' is missing") | Out-Null }
        }
      }
    }

    $calls | Should -BeGreaterOrEqual 8
    $failures -join "`n" | Should -BeNullOrEmpty
    # One release pin across every example, so a release PR can't miss one.
    @($refs) | Should -HaveCount 1
  }
}
