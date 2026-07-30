# Sapphire self-hosted ntfy server + upstream forwarder.
#
# Runs the upstream binwiederhier/ntfy binary AND a small forwarder
# loop in the same container. The forwarder subscribes to the local
# instance's topic and reposts every message to a configured upstream
# ntfy server (typically ntfy.sh), so a phone already subscribed to
# the upstream keeps receiving notifications without any phone-side
# change.
#
# Pinning the tag prevents an upstream backward-incompatible change
# from breaking a redeploy at 4am. Bump manually after reading the
# release notes.
FROM binwiederhier/ntfy:v2.11.0

# curl is what the forwarder loop uses to POST each message upstream.
# ~2MB extra image size; adds no runtime overhead when the forwarder
# isn't enabled (UPSTREAM_URL unset).
USER root
RUN apk add --no-cache curl

COPY server.yml /etc/ntfy/server.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Documentation-only -- Railway assigns $PORT at boot and our
# entrypoint reads it. Nothing binds to 80 unless PORT is unset.
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
