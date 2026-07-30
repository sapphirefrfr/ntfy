# Sapphire self-hosted ntfy server.
#
# Built on the upstream image so the security surface is exactly what
# binwiederhier ships. We only add our own entrypoint that:
#   * points listen-http at Railway's $PORT
#   * bootstraps an ephemeral auth DB from env vars
#   * seeds one publisher user (write-only on the topic) so the public
#     URL can't be spammed with anonymous POSTs
#
# Pinning the tag prevents an upstream backward-incompatible change from
# breaking a redeploy at 4am. Bump manually after reading the release
# notes.
FROM binwiederhier/ntfy:v2.11.0

# Base config file. Runtime settings that need env expansion are set
# via NTFY_* environment variables in entrypoint.sh (see below).
COPY server.yml /etc/ntfy/server.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Documentation-only -- Railway assigns $PORT at boot and our
# entrypoint reads it. Nothing binds to 80 unless PORT is unset.
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
