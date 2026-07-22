 ## SSHD work completed

  1. Added automatic sshd startup for nsjail-env; nsjail-codex remains unchanged.
  2. Runs sshd as the invoking non-root user and terminates it when the jail exits.
  3. Added automatic SSH port selection:
      - Uses NSJAIL_SSH_PORT when specified.
      - Otherwise selects an available port.
      - Prints the complete SSH command at startup.
      - Exports the selected port inside the jail.

  4. Added localhost-only pasta forwarding from the host SSH port to the jail.
  5. Corrected the pasta multiple-port syntax that previously caused pasta to exit and kill the jail.
  6. Implemented public-key-only authentication:
      - Password authentication disabled.
      - Keyboard-interactive authentication disabled.
      - Root login disabled.
      - No private identity key is copied into the jail.

  7. Authorized keys can come from:
      - NSJAIL_SSH_AUTHORIZED_KEYS
      - ~/.ssh/authorized_keys
      - Common ~/.ssh/*.pub files
      - Public keys loaded in the host SSH agent

  8. Added a persistent SSH host key under:

     $XDG_STATE_HOME/nsjail-env/ssh_host_ed25519_key

     or:

     ~/.local/state/nsjail-env/ssh_host_ed25519_key

  9. Added an internal SFTP subsystem for Zed and other SSH clients.
  10. Enabled SSH agent and TCP forwarding while keeping X11 forwarding disabled.
  11. Added a private devpts mount and /dev/ptmx symlink so SSH PTY allocation works.
  12. Removed the unmapped host tty group from the jail’s SSH group view, allowing PTY ownership to use the mapped primary group.
  13. Built a dedicated OpenSSH package with root-only login accounting disabled:

  - lastlog
  - utmp/utmpx
  - wtmp/wtmpx
  - libutil login handling

  14. Patched OpenSSH’s misleading non-root login-record warning.
  15. Propagated the complete jail PATH into SSH sessions because sshd normally replaces it with a generic /usr/bin:/bin path.
  16. Added /bin/sh as a symlink to the mounted NixOS Bash.
  17. Added required remote-bootstrap commands such as gzip, tar, wget, and which.
  18. Added persistent writable mounts for remote editor data:

  - ~/.vscode-server
  - ~/.zed_server
  - ~/.local/share/zed
  - ~/.config/zed
  - ~/.cache/zed
  - ~/.local/state/zed

  19. Propagated certificate variables into SSH sessions:

  - SSL_CERT_FILE
  - NIX_SSL_CERT_FILE
  - CURL_CA_BUNDLE
  - REQUESTS_CA_BUNDLE

  20. Propagated uppercase and lowercase HTTP proxy variables when present.
  21. Consolidated SSH environment variables into one SetEnv directive because OpenSSH ignored repeated command-line SetEnv options after the first.
  22. Verified:

  - Public-key authentication
  - PTY and non-PTY SSH commands
  - SSH session PATH
  - Zed remote-server execution
  - OpenSSH CA environment parsing
  - Nix package builds and shell syntax checks
