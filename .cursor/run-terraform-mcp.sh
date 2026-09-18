#!/usr/bin/env bash
# Launch HashiCorp terraform-mcp-server (replaces yanked awslabs-terraform-mcp-server).
# Downloads the official binary to a user cache on first run. No TFE token: public registry only.

set -euo pipefail

VERSION="${TERRAFORM_MCP_VERSION:-1.3.0}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hashicorp-terraform-mcp-server/${VERSION}"
BIN="${CACHE}/terraform-mcp-server"

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
esac

zip="terraform-mcp-server_${VERSION}_${os}_${arch}.zip"
# Pinned SHA256 for v1.3.0 darwin/linux (https://releases.hashicorp.com/terraform-mcp-server/1.3.0/)
expected=""
case "${os}_${arch}" in
  darwin_arm64) expected="94469fe7ce9a7b3af6cf5c7949619f3bab84dfb9e038914fd8f59e4d33a6add4" ;;
  darwin_amd64) expected="5167ab20714ec95f51a922f9cb17eaf68c076a132afd60dab79bae1186b65c78" ;;
  linux_arm64)  expected="9682ca6ac0a7cc0ab30cf1451bdb828ac7429f76f047168ddbaa75388dec6f2f" ;;
  linux_amd64)  expected="f8ecdbfb8473af4d54f6ca428de59649ff4c74f1c8a904da1c2973fa345d4d26" ;;
esac

if [[ ! -x "$BIN" ]]; then
  if [[ -z "$expected" ]]; then
    echo "Unsupported platform ${os}/${arch} for terraform-mcp-server ${VERSION}" >&2
    exit 1
  fi
  mkdir -p "$CACHE"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  url="https://releases.hashicorp.com/terraform-mcp-server/${VERSION}/${zip}"
  curl -fsSL "$url" -o "${tmp}/${zip}"
  actual=$(shasum -a 256 "${tmp}/${zip}" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for ${zip}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
  unzip -q "${tmp}/${zip}" -d "$tmp"
  mv "${tmp}/terraform-mcp-server" "$BIN"
  chmod +x "$BIN"
  rm -rf "$tmp"
  trap - EXIT
fi

exec "$BIN" stdio "$@"
