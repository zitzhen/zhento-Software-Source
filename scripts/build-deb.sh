#!/usr/bin/env bash
# Build an amd64 binary package from an upstream repository with debian/ metadata.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: build-deb.sh <upstream-url> <output-dir>" >&2
  exit 1
fi

upstream_url="$1"
output_dir="$2"

if [[ ! "$upstream_url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$ ]]; then
  echo "Error: invalid upstream URL: $upstream_url" >&2
  exit 1
fi

# GitHub runners prepend rustup shims to PATH. The Debian cargo wrapper used by
# dh-cargo must pair with the distribution rustc; rustup's shims otherwise
# select an inconsistent toolchain and fail with "can't find crate for core".
clean_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '\.cargo/bin' | paste -sd: -)"
if [[ -n "$clean_path" ]]; then
  PATH="$clean_path"
  export PATH
fi
unset RUSTUP_HOME RUSTUP_TOOLCHAIN CARGO_HOME RUSTC RUSTDOC RUSTFLAGS || true

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

source_dir="$work_dir/source"
echo "Cloning $upstream_url" >&2
if ! git clone --depth 1 --quiet "$upstream_url" "$source_dir"; then
  echo "Error: failed to clone $upstream_url" >&2
  exit 1
fi

if [[ ! -d "$source_dir/debian" ]]; then
  echo "Error: $upstream_url has no debian/ directory; cannot build a .deb" >&2
  exit 1
fi

echo "Refreshing package indexes" >&2
sudo apt-get update -qq

echo "Installing build dependencies for $upstream_url" >&2
(
  cd "$source_dir"
  sudo mk-build-deps --install --remove \
    --tool='apt-get -y --no-install-recommends' debian/control
  echo "Running dpkg-buildpackage for $upstream_url" >&2
  dpkg-buildpackage -b -us -uc
)

mkdir -p "$output_dir"
shopt -s nullglob
debs=("$work_dir"/*_amd64.deb)
shopt -u nullglob

if (( ${#debs[@]} == 0 )); then
  echo "Error: no amd64 .deb was produced from $upstream_url" >&2
  exit 1
fi

cp "${debs[@]}" "$output_dir/"
for deb in "${debs[@]}"; do
  echo "Built $(basename "$deb")" >&2
done
