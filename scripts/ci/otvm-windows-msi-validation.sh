#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: otvm-windows-msi-validation.sh [options]

Lease a Windows OracleTestVMs guest, install the managed GNUstep MSYS2/CLANG64
toolchain with gnustep-cli, run the sample MSI package and validate flow, pull
evidence back locally, and destroy the lease unless preserved.

Options:
  --gnustep-cli PATH      Local gnustep.exe to upload instead of building one
  --gnustep-cli-repo PATH Local gnustep-cli repo root (default: ~/git/gnustep/gnustep-cli)
  --otvm-config PATH      OracleTestVMs runtime config path
  --ssh-key PATH          SSH private key for lease access
  --ttl-hours N           Lease TTL override
  --evidence-dir PATH     Local output directory (default under dist/otvm/)
  --idempotency-key KEY   Stable OracleTestVMs idempotency key
  --keep-on-failure       Preserve the lease when remote validation fails
  --keep-lease            Always preserve the lease instead of destroying it
  --progress MODE         otvm progress mode: off, human, or json
  --help                  Show this message
EOF
}

resolve_path() {
  local path_value="$1"
  python3 - "$path_value" <<'PY'
from __future__ import annotations

import os
import sys

print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "required command not found: $name" >&2
    exit 1
  fi
}

resolve_otvm_command() {
  local repo_root="$1"
  local explicit="${OTVM:-}"
  local repo_otvm_python="$repo_root/../../OracleTestVMs/.venv/bin/python"

  if [[ -n "$explicit" ]]; then
    if command -v "$explicit" >/dev/null 2>&1; then
      otvm_cmd=("$explicit")
      return
    fi
    explicit="$(resolve_path "$explicit")"
    if [[ -x "$explicit" ]]; then
      otvm_cmd=("$explicit")
      return
    fi
    echo "OTVM override not found or not executable: $explicit" >&2
    exit 1
  fi

  if command -v otvm >/dev/null 2>&1; then
    otvm_cmd=("otvm")
    return
  fi

  if [[ -x "$repo_otvm_python" ]]; then
    otvm_cmd=("$repo_otvm_python" "-m" "oracletestvms")
    return
  fi

  echo "could not find otvm on PATH or OracleTestVMs virtualenv at $repo_otvm_python" >&2
  exit 1
}

python_extract_lease_fields() {
  local json_path="$1"
  python3 - "$json_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

lease = payload["lease"]
remote_access = lease["remote_access"]
print(lease["lease_id"])
print(remote_access["host"])
print(remote_access["ssh"]["username"])
PY
}

resolve_default_ssh_key() {
  local config_path="$1"
  python3 - "$config_path" <<'PY'
from __future__ import annotations

import os
import pathlib
import tomllib
import sys


def expand(path: str) -> pathlib.Path:
    return pathlib.Path(path).expanduser().resolve()


def first_existing(paths: list[str]) -> pathlib.Path | None:
    for item in paths:
        candidate = expand(item)
        if candidate.exists():
            return candidate
    return None


config_path_arg = sys.argv[1]
if config_path_arg:
    config_path = expand(config_path_arg)
else:
    override = os.environ.get("ORACLETESTVMS_CONFIG")
    if override:
        config_path = expand(override)
    else:
        config_home = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser()
        config_path = (config_home / "oracletestvms" / "config.toml").resolve()

project = {}
if config_path.exists():
    with open(config_path, "rb") as handle:
        project = tomllib.load(handle).get("project", {})

public_key = project.get("operator_public_key_file")
if public_key:
    candidate = expand(str(public_key))
else:
    candidate = first_existing(["~/.ssh/id_ed25519.pub", "~/.ssh/id_rsa.pub"])
    if candidate is None:
        candidate = expand("~/.ssh/id_ed25519.pub")

private_key = candidate.with_suffix("") if candidate.suffix == ".pub" else candidate
print(private_key)
PY
}

copy_remote_output() {
  local ssh_target="$1"
  local remote_parent="$2"
  local remote_stage="$3"
  local lease_id="$4"
  local evidence_dir="$5"
  local remote_archive="$remote_parent/gnustep-packager-output-$lease_id.tar.gz"
  local local_archive="$evidence_dir/remote-output-$lease_id.tar.gz"
  local archive_cmd=(
    powershell
    -NoProfile
    -NonInteractive
    -ExecutionPolicy
    Bypass
    -File
    "$remote_stage/scripts/ci/otvm-windows-pack-output.ps1"
    -StageRoot
    "$remote_stage"
    -ArchivePath
    "$remote_archive"
  )

  if ! ssh "${ssh_opts[@]}" "$ssh_target" "${archive_cmd[@]}" >"$evidence_dir/evidence-archive.stdout" 2>"$evidence_dir/evidence-archive.stderr"; then
    return 1
  fi

  if ! scp "${ssh_opts[@]}" "$ssh_target:$remote_archive" "$local_archive" >"$evidence_dir/evidence-copy.stdout" 2>"$evidence_dir/evidence-copy.stderr"; then
    return 1
  fi

  if ! python3 - "$local_archive" "$evidence_dir" >"$evidence_dir/evidence-extract.stdout" 2>"$evidence_dir/evidence-extract.stderr" <<'PY'
from __future__ import annotations

import os
import shutil
import sys
import tarfile

archive_path, evidence_dir = sys.argv[1], sys.argv[2]
output_dir = os.path.join(evidence_dir, "output")
if os.path.isdir(output_dir):
    shutil.rmtree(output_dir)

evidence_root = os.path.realpath(evidence_dir)
with tarfile.open(archive_path, "r:gz") as archive:
    for member in archive.getmembers():
        target = os.path.realpath(os.path.join(evidence_root, member.name))
        if os.path.commonpath([evidence_root, target]) != evidence_root:
            raise SystemExit(f"unsafe archive entry: {member.name}")
    archive.extractall(evidence_root)
PY
  then
    return 1
  fi

  ssh "${ssh_opts[@]}" "$ssh_target" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath '$remote_archive' -Force -ErrorAction SilentlyContinue" >"$evidence_dir/evidence-cleanup.stdout" 2>"$evidence_dir/evidence-cleanup.stderr" || true
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gnustep_cli_repo="${GNUSTEP_CLI_REPO:-$HOME/git/gnustep/gnustep-cli}"
gnustep_cli_path=""
evidence_dir=""
idempotency_key=""
keep_lease="false"
keep_on_failure="false"
otvm_config=""
progress="human"
ssh_key=""
ttl_hours=""
otvm_cmd=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gnustep-cli)
      gnustep_cli_path="$2"
      shift 2
      ;;
    --gnustep-cli-repo)
      gnustep_cli_repo="$2"
      shift 2
      ;;
    --evidence-dir)
      evidence_dir="$2"
      shift 2
      ;;
    --idempotency-key)
      idempotency_key="$2"
      shift 2
      ;;
    --keep-on-failure)
      keep_on_failure="true"
      shift
      ;;
    --keep-lease)
      keep_lease="true"
      shift
      ;;
    --otvm-config)
      otvm_config="$2"
      shift 2
      ;;
    --progress)
      progress="$2"
      shift 2
      ;;
    --ssh-key)
      ssh_key="$2"
      shift 2
      ;;
    --ttl-hours)
      ttl_hours="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unexpected argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

resolve_otvm_command "$repo_root"
require_command python3
require_command ssh
require_command scp
require_command go

if [[ -z "$ssh_key" ]]; then
  ssh_key="$(resolve_default_ssh_key "$otvm_config")"
fi
ssh_key="$(resolve_path "$ssh_key")"
if [[ ! -f "$ssh_key" ]]; then
  echo "SSH private key not found: $ssh_key" >&2
  exit 1
fi

gnustep_cli_repo="$(resolve_path "$gnustep_cli_repo")"
if [[ ! -d "$gnustep_cli_repo" ]]; then
  echo "gnustep-cli repo not found: $gnustep_cli_repo" >&2
  exit 1
fi

if [[ -n "$gnustep_cli_path" ]]; then
  gnustep_cli_path="$(resolve_path "$gnustep_cli_path")"
  if [[ ! -f "$gnustep_cli_path" ]]; then
    echo "gnustep-cli binary not found: $gnustep_cli_path" >&2
    exit 1
  fi
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "$idempotency_key" ]]; then
  idempotency_key="gnustep-packager-msi-validation-${timestamp}-$$"
fi

if [[ -z "$evidence_dir" ]]; then
  evidence_dir="$repo_root/dist/otvm/windows-msi-validation-$timestamp"
fi
mkdir -p "$evidence_dir"

work_root="$(mktemp -d)"
lease_id=""
lease_host=""
lease_user=""
run_succeeded="false"

cleanup() {
  local destroy_lease="true"
  local destroy_rc=0
  if [[ "$keep_lease" == "true" ]]; then
    destroy_lease="false"
  elif [[ "$run_succeeded" != "true" && "$keep_on_failure" == "true" ]]; then
    destroy_lease="false"
  fi
  if [[ -n "$lease_id" ]]; then
    if ! "${otvm_cmd[@]}" status "$lease_id" >"$evidence_dir/final-status.json" 2>"$evidence_dir/final-status.stderr"; then
      :
    fi
  fi
  if [[ -n "$lease_id" && "$destroy_lease" == "true" ]]; then
    if ! "${otvm_cmd[@]}" destroy "$lease_id" --progress "$progress" >"$evidence_dir/destroy.json" 2>"$evidence_dir/destroy.stderr"; then
      destroy_rc=$?
      echo "lease destroy failed; inspect $evidence_dir/destroy.stderr" >&2
    fi
  fi
  rm -rf "$work_root"
  if [[ $destroy_rc -ne 0 ]]; then
    exit "$destroy_rc"
  fi
}
trap cleanup EXIT

if [[ -n "$otvm_config" ]]; then
  otvm_cmd+=(--config "$otvm_config")
fi

create_cmd=("${otvm_cmd[@]}" create windows-2022 --idempotency-key "$idempotency_key" --metadata purpose=gnustep-packager-msi-validation --progress "$progress")
if [[ -n "$ttl_hours" ]]; then
  create_cmd+=(--ttl-hours "$ttl_hours")
fi

if ! "${create_cmd[@]}" >"$evidence_dir/create.json" 2>"$evidence_dir/create.stderr"; then
  echo "lease creation failed; inspect $evidence_dir/create.json and $evidence_dir/create.stderr" >&2
  exit 1
fi

mapfile -t lease_fields < <(python_extract_lease_fields "$evidence_dir/create.json")
lease_id="${lease_fields[0]}"
lease_host="${lease_fields[1]}"
lease_user="${lease_fields[2]}"

stage_root="$work_root/gnustep-packager-otvm-$lease_id"
mkdir -p "$stage_root/scripts/ci" "$stage_root/input" "$stage_root/output"

cp "$repo_root/scripts/ci/otvm-windows-remote.ps1" "$stage_root/scripts/ci/"
cp "$repo_root/scripts/ci/otvm-windows-pack-output.ps1" "$stage_root/scripts/ci/"
mkdir -p "$stage_root/repo"
for relative_path in AGENTS.md README.md Roadmap.md backends defaults docs schemas scripts; do
  cp -R "$repo_root/$relative_path" "$stage_root/repo/"
done
mkdir -p "$stage_root/repo/examples"
cp -R "$repo_root/examples/sample-gui" "$stage_root/repo/examples/"

if [[ -z "$gnustep_cli_path" ]]; then
  gnustep_cli_path="$work_root/gnustep.exe"
  (
    cd "$gnustep_cli_repo"
    GOOS=windows GOARCH=amd64 go build -o "$gnustep_cli_path" ./cmd/gnustep
  )
fi
cp "$gnustep_cli_path" "$stage_root/input/gnustep.exe"

ssh_target="$lease_user@$lease_host"
remote_parent="C:/Users/$lease_user"
remote_stage="$remote_parent/$(basename "$stage_root")"
ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=30
  -i "$ssh_key"
)

scp "${ssh_opts[@]}" -r "$stage_root" "$ssh_target:$remote_parent/" >"$evidence_dir/stage-copy.stdout" 2>"$evidence_dir/stage-copy.stderr"

remote_cmd=(
  powershell
  -NoProfile
  -NonInteractive
  -ExecutionPolicy
  Bypass
  -File
  "$remote_stage/scripts/ci/otvm-windows-remote.ps1"
  -Backend
  "windows-msys2-clang64"
  -CLI
  "input/gnustep.exe"
  -Manifest
  "repo/examples/sample-gui/package.manifest.json"
)

remote_failed="false"
if ! ssh "${ssh_opts[@]}" "$ssh_target" "${remote_cmd[@]}" >"$evidence_dir/remote-run.stdout" 2>"$evidence_dir/remote-run.stderr"; then
  remote_failed="true"
fi

if ! copy_remote_output "$ssh_target" "$remote_parent" "$remote_stage" "$lease_id" "$evidence_dir"; then
  echo "remote evidence copy failed; inspect $evidence_dir/evidence-archive.stderr, $evidence_dir/evidence-copy.stderr, and $evidence_dir/evidence-extract.stderr" >&2
  if [[ "$remote_failed" != "true" ]]; then
    exit 1
  fi
fi

if [[ "$remote_failed" == "true" ]]; then
  echo "remote Windows MSI validation failed; evidence is in $evidence_dir" >&2
  if [[ "$keep_lease" == "true" || "$keep_on_failure" == "true" ]]; then
    echo "lease preserved: $lease_id ($ssh_target)" >&2
  fi
  exit 1
fi

run_succeeded="true"
python3 - "$evidence_dir/create.json" "$evidence_dir" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

lease = payload["lease"]
print(json.dumps({
    "lease_id": lease["lease_id"],
    "profile": lease["profile_slug"],
    "host": lease["remote_access"]["host"],
    "ssh_username": lease["remote_access"]["ssh"]["username"],
    "evidence_dir": sys.argv[2],
}, indent=2))
PY
