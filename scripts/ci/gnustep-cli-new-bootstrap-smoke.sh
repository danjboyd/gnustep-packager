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

write_report() {
  status="$1"
  {
    printf '# gnustep-cli-new Bootstrap Report\n\n'
    printf '- status: %s\n' "$status"
    printf '- host: %s\n' "$(uname -a 2>/dev/null || printf unknown)"
    printf '- manifest: %s\n' "$manifest_url"
    printf '- bootstrap: %s\n' "$bootstrap_url"
    printf '- install root: %s\n' "$install_root"
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

printf 'gnustep-cli-new manifest: %s\n' "$manifest_url" | tee "$log_root/gnustep-cli-new-selection.log"
printf 'gnustep-cli-new bootstrap: %s\n' "$bootstrap_url" | tee -a "$log_root/gnustep-cli-new-selection.log"
printf 'gnustep-cli-new root: %s\n' "$install_root" | tee -a "$log_root/gnustep-cli-new-selection.log"

curl -fsSL "$bootstrap_url" -o "$bootstrap_path"
chmod +x "$bootstrap_path"

"$bootstrap_path" --json --yes setup --user --root "$install_root" \
  --manifest "$manifest_url" 2>&1 | tee "$log_root/gnustep-cli-new-setup.log"

PATH="$install_root/bin:$install_root/Tools:$install_root/System/Tools:$PATH"
export PATH

gnustep --version 2>&1 | tee "$log_root/gnustep-cli-new-version.log"
gnustep doctor --json --manifest "$manifest_url" 2>&1 | tee "$log_root/gnustep-cli-new-doctor.json"

work_root="$smoke_root/work"
rm -rf "$work_root"
mkdir -p "$work_root"
cd "$work_root"

gnustep new cli-tool HelloPackager --json 2>&1 | tee "$log_root/gnustep-cli-new-new.json"
cd HelloPackager
gnustep build --json 2>&1 | tee "$log_root/gnustep-cli-new-build.json"
gnustep run --json 2>&1 | tee "$log_root/gnustep-cli-new-run.json"
