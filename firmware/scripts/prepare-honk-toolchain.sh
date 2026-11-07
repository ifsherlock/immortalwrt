#!/usr/bin/env bash
# Run after checking out the pinned honk source. apt dependencies are installed by CI.
set -euo pipefail
source_dir=$(realpath "${1:?usage: prepare-honk-toolchain.sh <honk-source>}")
command -v rustup >/dev/null
command -v zstd >/dev/null
command -v curl >/dev/null
stable=$(sed -n 's/^channel *= *"\([^"]*\)"/\1/p' "$source_dir/rust-toolchain.toml")
nightly=$(sed -n 's/^channel *= *"\([^"]*\)"/\1/p' "$source_dir/crates/honk-ebpf/rust-toolchain.toml")
[[ -n "$stable" && -n "$nightly" ]]
rustup toolchain install "$stable" --profile minimal --component rustfmt --component clippy
rustup target add --toolchain "$stable" x86_64-unknown-linux-musl
rustup toolchain install "$nightly" --profile minimal --component rust-src --component llvm-tools
# Only public, source-pinned build-tool versions and hashes are read here.
source "$source_dir/.github/ci/pins.env"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
curl -fsSL --retry 3 -o "$temp_dir/bpf-linker.tar.zst" \
  "https://github.com/aya-rs/bpf-linker/releases/download/v${BPF_LINKER_VERSION}/bpf-linker-x86_64-unknown-linux-musl.tar.zst"
printf '%s  %s\n' "$BPF_LINKER_SHA256" "$temp_dir/bpf-linker.tar.zst" | sha256sum -c -
cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"
mkdir -p "$cargo_bin"
zstd -dc "$temp_dir/bpf-linker.tar.zst" | tar -xf - -C "$cargo_bin"
"$cargo_bin/bpf-linker" --version
printf 'honk Rust toolchains ready: stable=%s nightly=%s\n' "$stable" "$nightly"
