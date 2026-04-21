#!/bin/sh
set -eu

manifest_url="${GP_GNUSTEP_CLI_MANIFEST_URL:-https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0-dev/release-manifest.json}"
bootstrap_url="${GP_GNUSTEP_CLI_BOOTSTRAP_URL:-https://raw.githubusercontent.com/danjboyd/gnustep-cli-new/master/scripts/bootstrap/gnustep-bootstrap.sh}"
install_root="${GP_GNUSTEP_CLI_ROOT:-/tmp/gnustep-cli-new}"
log_root="${GP_GNUSTEP_CLI_LOG_ROOT:-/tmp/gnustep-cli-new-logs}"
smoke_root="${GP_GNUSTEP_CLI_SMOKE_ROOT:-/tmp/gnustep-cli-new-smoke}"

mkdir -p "$install_root" "$log_root" "$smoke_root"
bootstrap_path="$smoke_root/gnustep-bootstrap.sh"
report_path="$log_root/gnustep-cli-new-blocker-report.md"
host_context_path="$log_root/gnustep-cli-new-host-context.log"
path_context_path="$log_root/gnustep-cli-new-path-context.log"

run_logged() {
  log_path="$1"
  shift
  {
    printf '$'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
  } >"$log_path"
  "$@" >>"$log_path" 2>&1
  status_code="$?"
  cat "$log_path"
  return "$status_code"
}

write_host_context() {
  {
    printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
    printf 'uname=%s\n' "$(uname -a 2>/dev/null || printf unknown)"
    printf 'pwd=%s\n' "$(pwd)"
    printf 'shell=%s\n' "${SHELL:-unknown}"
    printf 'msystem=%s\n' "${MSYSTEM:-}"
    printf 'msys2_location=%s\n' "${MSYS2_LOCATION:-}"
    printf 'runner_os=%s\n' "${RUNNER_OS:-}"
    printf 'host_kind=%s\n' "${GP_GNUSTEP_CLI_HOST_KIND:-}"
    printf 'github_workflow=%s\n' "${GITHUB_WORKFLOW:-}"
    printf 'github_run_id=%s\n' "${GITHUB_RUN_ID:-}"
    printf 'github_ref=%s\n' "${GITHUB_REF:-}"
    printf 'install_root_posix=%s\n' "$install_root"
    printf 'log_root_posix=%s\n' "$log_root"
    printf 'smoke_root_posix=%s\n' "$smoke_root"
    if command -v cygpath >/dev/null 2>&1; then
      printf 'install_root_windows=%s\n' "$(cygpath -w "$install_root" 2>/dev/null || true)"
      printf 'log_root_windows=%s\n' "$(cygpath -w "$log_root" 2>/dev/null || true)"
      printf 'smoke_root_windows=%s\n' "$(cygpath -w "$smoke_root" 2>/dev/null || true)"
    fi
    printf '\nPATH entries:\n'
    printf '%s\n' "$PATH" | tr ':' '\n'
  } >"$host_context_path"
}

write_path_context() {
  {
    printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
    printf 'PATH entries:\n'
    printf '%s\n' "$PATH" | tr ':' '\n'
    printf '\ncommand lookup:\n'
    for tool in gnustep curl tar gzip sh bash make clang cc powershell pwsh; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '%s=%s\n' "$tool" "$(command -v "$tool")"
      else
        printf '%s=\n' "$tool"
      fi
    done
    if command -v cygpath >/dev/null 2>&1; then
      printf '\ncygpath install roots:\n'
      cygpath -w "$install_root" 2>/dev/null || true
      cygpath -w "$install_root/bin" 2>/dev/null || true
      cygpath -w "$install_root/Tools" 2>/dev/null || true
      cygpath -w "$install_root/System/Tools" 2>/dev/null || true
    fi
    if command -v cmd.exe >/dev/null 2>&1; then
      printf '\ncmd.exe where gnustep:\n'
      cmd.exe /c where gnustep 2>/dev/null || true
    fi
  } >"$path_context_path"
}

write_report() {
  status="$1"
  {
    printf '# gnustep-cli-new Bootstrap Report\n\n'
    printf '- status: %s\n' "$status"
    printf '- host: %s\n' "$(uname -a 2>/dev/null || printf unknown)"
    printf '- manifest: %s\n' "$manifest_url"
    printf '- bootstrap: %s\n' "$bootstrap_url"
    printf '- install root: %s\n' "$install_root"
    printf '- host kind: %s\n' "${GP_GNUSTEP_CLI_HOST_KIND:-unknown}"
    printf '- log root: %s\n\n' "$log_root"
    printf '## Command Contract\n\n'
    printf '```sh\n'
    printf 'gnustep-bootstrap.sh --json --yes setup --user --root "%s" --manifest "%s"\n' "$install_root" "$manifest_url"
    printf 'gnustep --version\n'
    printf 'gnustep doctor --json --manifest "%s"\n' "$manifest_url"
    printf 'gnustep new cli-tool HelloPackager --json\n'
    printf 'gnustep build --json\n'
    printf 'gnustep run --json\n'
    printf '```\n\n'
    for log_name in \
      gnustep-cli-new-host-context.log \
      gnustep-cli-new-path-context.log \
      gnustep-cli-new-selection.log \
      gnustep-cli-new-setup.log \
      gnustep-cli-new-version.log \
      gnustep-cli-new-doctor.json \
      gnustep-cli-new-new.json \
      gnustep-cli-new-build.json \
      gnustep-cli-new-run.json
    do
      log_path="$log_root/$log_name"
      if [ -f "$log_path" ]; then
        printf '## %s\n\n' "$log_name"
        printf '```text\n'
        tail -n 120 "$log_path"
        printf '\n```\n\n'
      fi
    done
  } >"$report_path"
}

finish_report() {
  status_code="$?"
  if [ "$status_code" -eq 0 ]; then
    write_report "passed"
  else
    write_report "failed"
  fi
  exit "$status_code"
}

trap finish_report EXIT

write_host_context

printf 'gnustep-cli-new manifest: %s\n' "$manifest_url" | tee "$log_root/gnustep-cli-new-selection.log"
printf 'gnustep-cli-new bootstrap: %s\n' "$bootstrap_url" | tee -a "$log_root/gnustep-cli-new-selection.log"
printf 'gnustep-cli-new root: %s\n' "$install_root" | tee -a "$log_root/gnustep-cli-new-selection.log"

curl -fsSL "$bootstrap_url" -o "$bootstrap_path"
chmod +x "$bootstrap_path"

run_logged "$log_root/gnustep-cli-new-setup.log" \
  "$bootstrap_path" --json --yes setup --user --root "$install_root" \
  --manifest "$manifest_url"

PATH="$install_root/bin:$install_root/Tools:$install_root/System/Tools:$PATH"
export PATH

write_path_context

run_logged "$log_root/gnustep-cli-new-version.log" gnustep --version
run_logged "$log_root/gnustep-cli-new-doctor.json" gnustep doctor --json --manifest "$manifest_url"

work_root="$smoke_root/work"
rm -rf "$work_root"
mkdir -p "$work_root"
cd "$work_root"

run_logged "$log_root/gnustep-cli-new-new.json" gnustep new cli-tool HelloPackager --json
cd HelloPackager
run_logged "$log_root/gnustep-cli-new-build.json" gnustep build --json
run_logged "$log_root/gnustep-cli-new-run.json" gnustep run --json
