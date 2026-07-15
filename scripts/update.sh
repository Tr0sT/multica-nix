#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="multica-ai/multica"
if [ -z "${LOG_FILE:-}" ]; then
  LOG_FILE="$(mktemp)"
  CLEAN_LOG_FILE=1
else
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  CLEAN_LOG_FILE=0
fi
trap 'if [ "${CLEAN_LOG_FILE:-0}" = "1" ]; then rm -f "$LOG_FILE"; fi' EXIT

usage() {
  cat <<'EOF'
Usage:
  scripts/update.sh --version 0.3.38
  scripts/update.sh --version v0.3.38
  scripts/update.sh --latest

Environment:
  LOG_FILE=path    keep the last hash-discovery build log at path
  VERIFY_BUILDS=0  skip final package build verification
  RUN_VM_TEST=1    also build .#checks.x86_64-linux.multica-vm during verification
EOF
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required tool not found: $1" >&2
    exit 1
  }
}

normalise_version() {
  local version="$1"
  version="${version#v}"
  printf '%s\n' "$version"
}

current_version() {
  sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' flake.nix | head -n1
}

latest_version() {
  local headers=(
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )
  if [ -n "${GH_TOKEN:-}" ]; then
    headers+=( -H "Authorization: Bearer ${GH_TOKEN}" )
  fi

  curl -fsSL "${headers[@]}" "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].removeprefix("v"))'
}

patch_nix_files() {
  local mode="$1"
  local value="${2:-}"

  python3 - "$mode" "$value" <<'PY'
import re
import sys
from pathlib import Path

mode = sys.argv[1]
value = sys.argv[2] if len(sys.argv) > 2 else ""


def sub1(path, pattern, repl, flags=re.S):
    p = Path(path)
    text = p.read_text()
    new, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"failed to patch {path}: pattern not found: {pattern}")
    p.write_text(new)


def replace_src_hash(replacement):
    pattern = r"(src = fetchFromGitHub \{.*?\n\s*hash = )([^;\n]+);"
    for path in ["packages/multica-server.nix", "packages/multica-web.nix"]:
        sub1(path, pattern, lambda m: f"{m.group(1)}{replacement};")


def replace_vendor_hash(replacement):
    sub1(
        "packages/multica-server.nix",
        r"(vendorHash = )([^;\n]+);",
        lambda m: f"{m.group(1)}{replacement};",
    )


def replace_pnpm_hash(replacement):
    sub1(
        "packages/multica-web.nix",
        r"(pnpmDeps = fetchPnpmDeps \{.*?\n\s*hash = )([^;\n]+);",
        lambda m: f"{m.group(1)}{replacement};",
    )


def replace_cli_hash(system, replacement):
    sub1(
        "packages/multica-cli.nix",
        rf"({re.escape(system)} = \{{.*?\n\s*hash = )([^;\n]+);",
        lambda m: f"{m.group(1)}{replacement};",
    )


if mode == "version":
    version = value.removeprefix("v")

    sub1(
        "flake.nix",
        r"(^\s*version = )\"[^\"]+\";",
        lambda m: f'{m.group(1)}"{version}";',
        flags=re.M,
    )

    for path in [
        "packages/multica-cli.nix",
        "packages/multica-server.nix",
        "packages/multica-web.nix",
    ]:
        sub1(
            path,
            r"(version \? )\"[^\"]+\"",
            lambda m: f'{m.group(1)}"{version}"',
            flags=re.M,
        )

elif mode == "fake-hashes":
    replace_src_hash("lib.fakeHash")
    replace_vendor_hash("lib.fakeHash")
    replace_pnpm_hash("lib.fakeHash")
    replace_cli_hash("x86_64-linux", "lib.fakeHash")
    replace_cli_hash("aarch64-linux", "lib.fakeHash")

elif mode == "src-hash":
    replace_src_hash(f'"{value}"')

elif mode == "vendor-hash":
    replace_vendor_hash(f'"{value}"')

elif mode == "pnpm-hash":
    replace_pnpm_hash(f'"{value}"')

elif mode == "cli-amd64-hash":
    replace_cli_hash("x86_64-linux", f'"{value}"')

elif mode == "cli-arm64-hash":
    replace_cli_hash("aarch64-linux", f'"{value}"')

else:
    raise SystemExit(f"unknown patch mode: {mode}")
PY
}

prefetch_cli_hash() {
  local version="$1"
  local arch="$2"
  local url="https://github.com/${UPSTREAM_REPO}/releases/download/v${version}/multica-cli-${version}-linux-${arch}.tar.gz"

  echo "Prefetching Multica CLI linux-${arch} release archive..." >&2
  nix store prefetch-file --json "$url" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["hash"])'
}

parse_got_hash() {
  sed -n 's/.*got:[[:space:]]*\(sha256-[A-Za-z0-9+\/=]*\).*/\1/p' "$LOG_FILE" | tail -n1
}

expect_hash_mismatch() {
  local attr="$1"
  local description="$2"

  echo "Discovering $description hash with nix build .#$attr ..." >&2
  {
    echo
    echo "--- Discovering $description hash with nix build .#$attr ---"
  } >> "$LOG_FILE"

  set +e
  nix build ".#$attr" --no-link --print-build-logs >>"$LOG_FILE" 2>&1
  local status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "error: expected a hash mismatch for $description, but the build succeeded" >&2
    exit 1
  fi

  local hash
  hash="$(parse_got_hash)"
  if [ -z "$hash" ]; then
    echo "error: build failed, but no 'got: sha256-...' hash was found while updating $description" >&2
    cat "$LOG_FILE" >&2
    exit "$status"
  fi

  printf '%s\n' "$hash"
}

verify_builds() {
  if [ "${VERIFY_BUILDS:-1}" = "0" ]; then
    echo "Skipping final build verification because VERIFY_BUILDS=0"
    return 0
  fi

  echo "Verifying packages..."
  nix build .#multica-cli .#multica-server .#multica-web --no-link --print-build-logs

  if [ "${RUN_VM_TEST:-0}" = "1" ]; then
    echo "Verifying NixOS VM test..."
    nix build .#checks.x86_64-linux.multica-vm --no-link --print-build-logs
  fi
}

main() {
  need_tool curl
  need_tool nix
  need_tool python3

  local target=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --version)
        target="${2:-}"
        shift 2
        ;;
      --latest)
        target="$(latest_version)"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [ -z "$target" ]; then
    echo "error: pass --version VERSION or --latest" >&2
    usage
    exit 1
  fi

  target="$(normalise_version "$target")"

  local current
  current="$(current_version)"

  if [ -z "$current" ]; then
    echo "error: could not detect current version from flake.nix" >&2
    exit 1
  fi

  if [ "$current" = "$target" ]; then
    echo "Already up to date: $current"
    exit 0
  fi

  echo "Updating Multica: $current -> $target"

  patch_nix_files version "$target"
  patch_nix_files fake-hashes

  local src_hash
  src_hash="$(expect_hash_mismatch multica-server "upstream source")"
  echo "source hash: $src_hash"
  patch_nix_files src-hash "$src_hash"

  local vendor_hash
  vendor_hash="$(expect_hash_mismatch multica-server "Go vendor")"
  echo "vendor hash: $vendor_hash"
  patch_nix_files vendor-hash "$vendor_hash"

  local pnpm_hash
  pnpm_hash="$(expect_hash_mismatch multica-web "pnpm dependencies")"
  echo "pnpm hash: $pnpm_hash"
  patch_nix_files pnpm-hash "$pnpm_hash"

  local cli_amd64_hash
  cli_amd64_hash="$(prefetch_cli_hash "$target" amd64)"
  echo "CLI linux-amd64 hash: $cli_amd64_hash"
  patch_nix_files cli-amd64-hash "$cli_amd64_hash"

  local cli_arm64_hash
  cli_arm64_hash="$(prefetch_cli_hash "$target" arm64)"
  echo "CLI linux-arm64 hash: $cli_arm64_hash"
  patch_nix_files cli-arm64-hash "$cli_arm64_hash"

  nix fmt
  verify_builds

  echo "Update complete:"
  git diff --stat
}

main "$@"
