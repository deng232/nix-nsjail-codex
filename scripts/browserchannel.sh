#!/usr/bin/env bash
set -euo pipefail

export PATH="@runtime_path@${PATH:+:$PATH}"

if [[ -z "${BROWSERCHANNEL_FIFO:-}" ]]; then
  printf 'browserchannel: BROWSERCHANNEL_FIFO is not set\n' >&2
  exit 1
fi

if [[ ! -p "$BROWSERCHANNEL_FIFO" ]]; then
  printf 'browserchannel: FIFO does not exist: %s\n' "$BROWSERCHANNEL_FIFO" >&2
  exit 1
fi

if [[ "$#" -eq 0 ]]; then
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    http://*|https://*)
      printf '%s\n' "$arg" > "$BROWSERCHANNEL_FIFO"
      ;;
    *)
      printf 'browserchannel: rejected non-browser argument: %s\n' "$arg" >&2
      ;;
  esac
done
