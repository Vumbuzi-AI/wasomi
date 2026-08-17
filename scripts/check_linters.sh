#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v mix >/dev/null 2>&1; then
  echo "mix is required, but it was not found in PATH." >&2
  exit 1
fi

echo "==> Installing missing Mix dependencies"
mix deps.get

echo "==> Checking formatting"
mix format --check-formatted

echo "==> Running Credo"
mix credo --strict

echo "==> Running tests"
# i9-14900HX exposes 32 schedulers. BEAM allocator arenas for all of them,
# plus LiveView tests, plus no swap → kernel SIGKILL. Cap the VM at boot
# (too late to do this from test_helper.exs).
export ERL_AFLAGS="+S 4:4 +SDcpu 2:2 +SDio 2 ${ERL_AFLAGS:-}"
mix test

echo "==> Checks passed"
