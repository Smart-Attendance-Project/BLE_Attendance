#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

go_version=1.26.11
go_binary=go
if ! command -v go >/dev/null || [[ "$(GOTOOLCHAIN=local go version)" != "go version go${go_version} "* ]]; then
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64)
      platform=linux-amd64
      sha256=9849f4e04ee35303714e34fbc3ac8ab44ea3e448a95aa182f91e3b9b79c710ec
      ;;
    Linux:aarch64)
      platform=linux-arm64
      sha256=6c2f29b458b5add0835f18b776f69c8881a6d88428f1484a6da55755e620757e
      ;;
    *)
      echo "Install Go ${go_version} to build the native attendance API on this platform." >&2
      exit 1
      ;;
  esac
  toolchain="$(mktemp -d)"
  trap 'rm -rf -- "$toolchain"' EXIT
  archive="$toolchain/go.tar.gz"
  curl --retry 3 -fsSL "https://go.dev/dl/go${go_version}.${platform}.tar.gz" -o "$archive"
  printf '%s  %s\n' "$sha256" "$archive" | sha256sum --check --status
  tar -xzf "$archive" -C "$toolchain"
  go_binary="$toolchain/go/bin/go"
fi

PYTHONPATH=. python scripts/build_native_assets.py
(
  cd native
  GOTOOLCHAIN=local CGO_ENABLED=0 "$go_binary" build -mod=readonly -trimpath -o ../build/native/attendance-api .
)
