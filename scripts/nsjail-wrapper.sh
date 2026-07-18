#!/usr/bin/env bash
set -euo pipefail

export PATH="@runtime_path@${PATH:+:$PATH}"

readonly NSJAIL_BIN="@nsjail@"
readonly PYTHON_BIN="@python@"
readonly BROWSERCHANNEL_BIN="@browserchannel@"
readonly DEFAULT_COMMAND="@default_command@"
readonly NSJAIL_CONFIG_TEMPLATE="@config_template@"
readonly BROWSER_FIFO_IN_JAIL="/browserchannel.fifo"
readonly CODEX_CALLBACK_PORT="1455"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

pb_string() {
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

is_local_browser_url() {
  case "$1" in
    http://localhost|http://localhost/*|http://localhost:*|\
    http://127.0.0.1|http://127.0.0.1/*|http://127.0.0.1:*|\
    http://\[::1\]|http://\[::1\]/*|http://\[::1\]:*|\
    https://localhost|https://localhost/*|https://localhost:*|\
    https://127.0.0.1|https://127.0.0.1/*|https://127.0.0.1:*|\
    https://\[::1\]|https://\[::1\]/*|https://\[::1\]:*) return 0 ;;
  esac
  return 1
}

open_browser_url() {
  local url=$1

  case "$url" in
    http://*|https://*) ;;
    *)
      printf 'nsjail-browser: rejected unsupported URL: %s\n' "$url" >&2
      return 0
      ;;
  esac

  if is_local_browser_url "$url"; then
    printf 'nsjail-browser: rejected localhost URL: %s\n' "$url" >&2
    return 0
  fi

  xdg-open "$url" >/dev/null 2>&1 &
}

watch_browser_fifo() {
  local fifo=$1
  local line

  while true; do
    if IFS= read -r line < "$fifo"; then
      open_browser_url "$line"
    fi
  done
}

parent_callback_port_available() {
  "$PYTHON_BIN" - "$CODEX_CALLBACK_PORT" <<'PY'
import socket
import sys

port = int(sys.argv[1])

try:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", port))
except OSError:
    raise SystemExit(1)
PY
}

resolve_ca_file() {
  local path

  for path in /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-bundle.crt; do
    if [[ -e "$path" ]]; then
      readlink -f "$path"
      return 0
    fi
  done

  die 'could not find /etc/ssl/certs/ca-certificates.crt or /etc/ssl/certs/ca-bundle.crt'
}

socket_mount() {
  local path=$1
  [[ -S "$path" ]] || return 0

  printf 'mount {\n'
  printf '  src: %s\n' "$(pb_string "$path")"
  printf '  dst: %s\n' "$(pb_string "$path")"
  printf '  is_bind: true\n'
  printf '  is_dir: false\n'
  printf '  rw: true\n'
  printf '  mandatory: false\n'
  printf '}\n'
}

optional_runtime_mounts() {
  [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR:-}" ]] || return 0

  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    socket_mount "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  fi
  socket_mount "$XDG_RUNTIME_DIR/pipewire-0"
  socket_mount "$XDG_RUNTIME_DIR/pulse/native"
}

render_nsjail_config() {
  local config=$1
  local fifo_host=$2
  local parent_ports=$3
  local ca_file_src=$4
  local optional_mounts

  optional_mounts=$(optional_runtime_mounts)

  NSJAIL_TEMPLATE="$NSJAIL_CONFIG_TEMPLATE" \
    NSJAIL_CONFIG="$config" \
    NSJAIL_CWD="$PWD" \
    NSJAIL_HOME_CODEX="$HOME/.codex" \
    NSJAIL_BROWSERCHANNEL="$BROWSERCHANNEL_BIN" \
    NSJAIL_BROWSER_FIFO_HOST="$fifo_host" \
    NSJAIL_BROWSER_FIFO_JAIL="$BROWSER_FIFO_IN_JAIL" \
    NSJAIL_CA_FILE_SRC="$ca_file_src" \
    NSJAIL_PARENT_PORTS="$parent_ports" \
    NSJAIL_OPTIONAL_MOUNTS="$optional_mounts" \
    "$PYTHON_BIN" - <<'PY'
import os
from pathlib import Path


def pb_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


replacements = {
    "@cwd@": pb_string(os.environ["NSJAIL_CWD"]),
    "@home_codex@": pb_string(os.environ["NSJAIL_HOME_CODEX"]),
    "@browser_fifo_host@": pb_string(os.environ["NSJAIL_BROWSER_FIFO_HOST"]),
    "@browser_fifo_jail@": pb_string(os.environ["NSJAIL_BROWSER_FIFO_JAIL"]),
    "@ca_file_src@": pb_string(os.environ["NSJAIL_CA_FILE_SRC"]),
    "@browser_envar@": pb_string("BROWSER=" + os.environ["NSJAIL_BROWSERCHANNEL"]),
    "@browser_fifo_envar@": pb_string("BROWSERCHANNEL_FIFO=" + os.environ["NSJAIL_BROWSER_FIFO_JAIL"]),
    "@parent_ports@": pb_string(os.environ["NSJAIL_PARENT_PORTS"]),
    "@optional_mounts@": os.environ["NSJAIL_OPTIONAL_MOUNTS"],
}

config = Path(os.environ["NSJAIL_TEMPLATE"]).read_text()
for placeholder, value in replacements.items():
    config = config.replace(placeholder, value)
Path(os.environ["NSJAIL_CONFIG"]).write_text(config)
PY
}

[[ -n "${HOME:-}" ]] || die 'HOME must be set'
[[ -d /nix ]] || die 'This wrapper expects a NixOS-style /nix store'
[[ -d "$PWD" ]] || die "current working directory does not exist: $PWD"

mkdir -p "$HOME/.codex"

tmpdir=$(mktemp -d -t codex-nsjail.XXXXXX)
fifo="$tmpdir/browser.fifo"
config="$tmpdir/nsjail.pbtxt"
watcher_pid=

cleanup() {
  if [[ -n "$watcher_pid" ]]; then
    kill "$watcher_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

mkfifo "$fifo"
watch_browser_fifo "$fifo" &
watcher_pid=$!

if [[ -n "${NSJAIL_PARENT_PORTS:-}" ]]; then
  parent_ports=$NSJAIL_PARENT_PORTS
elif parent_callback_port_available; then
  parent_ports="127.0.0.1/$CODEX_CALLBACK_PORT:$CODEX_CALLBACK_PORT"
else
  printf 'nsjail-wrapper: parent 127.0.0.1:%s is occupied; skipping TCP port mapping\n' "$CODEX_CALLBACK_PORT" >&2
  parent_ports="none"
fi
ca_file_src=$(resolve_ca_file)
render_nsjail_config "$config" "$fifo" "$parent_ports" "$ca_file_src"

read -r -a default_argv <<< "$DEFAULT_COMMAND"
if [[ "$#" -gt 0 ]]; then
  command_argv=("${default_argv[@]}" "$@")
else
  command_argv=("${default_argv[@]}")
fi

exec "$NSJAIL_BIN" --config "$config" -- "${command_argv[@]}"
