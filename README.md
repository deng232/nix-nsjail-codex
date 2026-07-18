# codex-nsjail

NixOS-only flake wrappers for running an agent command inside `nsjail`.

## Entrypoints

```sh
nix run .#nsjail-env
nix run .#nsjail-codex -- [codex args...]
```

`nsjail-env` opens an interactive Bash shell inside the jail. `nsjail-codex`
runs the flake-provided `codex` package and preserves all arguments after `--`.

## Runtime Behavior

- The base nsjail protobuf text configuration lives in
  `config/nsjail.pbtxt.in`; the wrapper renders a temporary `.pbtxt` from that
  template before invoking `nsjail`.
- `nsjail` owns all namespaces and uses its native `user_net` pasta backend for
  networking.
- `/nix` is mounted read-only.
- `$HOME/.codex` is mounted read-write.
- The current working directory is mounted read-write and used as the jailed
  working directory.
- Parent environment variables are kept, including `PATH`.
- CA certificates are resolved from the host `/etc/ssl/certs` symlink target
  with `readlink -f` and mounted read-only at the default CA filenames.
- Wayland, PipeWire, and PulseAudio sockets are mounted only when they exist.
- `$BROWSER` is set to `browserchannel` inside the jail.
- `browserchannel` writes browser URLs to a FIFO mounted into the jail.
- The parent process reads the FIFO and opens accepted URLs with `xdg-open`.
- The parent rejects `file:`, socket-style, and localhost browser URLs,
  including `http://localhost`, `http://127.0.0.1`, and `http://[::1]`.
- nsjail's native pasta backend handles networking and loopback port forwarding.
- The packaged `pasta` shim adds `--host-lo-to-ns-lo` so callbacks from the
  host browser can reach services that listen on jailed `127.0.0.1`.

## Port Controls

Codex ChatGPT login listens on port `1455` in the jail. The wrapper first tries
to map parent loopback port `1455` to jailed `1455`:

```text
127.0.0.1:1455 on the parent -> 127.0.0.1:1455 in the namespace
```

If parent port `1455` is already taken, the wrapper prints an informational
message and skips inbound TCP forwarding for that instance. Outbound networking
from the jail remains enabled.

Only the instance mapped from parent `1455` is expected to complete Codex's
browser OAuth login. Other instances should reuse existing credentials or use a
non-browser login flow.

Override the parent-to-namespace TCP forwarding spec when needed:

```sh
NSJAIL_PARENT_PORTS='127.0.0.1/1455:1455' nix run .#nsjail-codex
```
