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

## Port Controls

By default the wrapper finds a free host TCP port and maps:

```text
127.0.0.1:$NSJAIL_OAUTH_PORT -> 127.0.0.1:$NSJAIL_OAUTH_PORT in the namespace
```

The chosen port is exported inside the jail as both `NSJAIL_OAUTH_PORT` and
`CODEX_OAUTH_PORT`.

Override the mapping when needed:

```sh
NSJAIL_OAUTH_PORT=1455 nix run .#nsjail-codex
NSJAIL_TCP_MAP_IN='127.0.0.1/1455:1455' nix run .#nsjail-codex
```

`NSJAIL_TCP_PORTS` is still accepted as a compatibility alias for
`NSJAIL_TCP_MAP_IN`.
