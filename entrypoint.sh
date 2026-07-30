#!/bin/sh
# Sapphire ntfy entrypoint.
#
# One job: point ntfy at Railway's assigned $PORT and public URL,
# then hand off to the upstream binary. No auth setup -- this is a
# public topic instance, same trust model as ntfy.sh but on our own
# infra so egress stays inside Railway's network.

set -eu

# Railway assigns $PORT at boot. Fallback to 80 so `docker run` locally
# still works without setting anything.
export NTFY_LISTEN_HTTP=":${PORT:-80}"

# NTFY_BASE_URL is used in web-UI links + Web Push registration. Prefer
# an explicit override; else fall back to Railway's assigned public
# hostname; else localhost for local dev.
if [ -z "${NTFY_BASE_URL:-}" ]; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    export NTFY_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
  else
    export NTFY_BASE_URL="http://localhost:${PORT:-80}"
  fi
fi

echo "[ntfy entrypoint] listen=${NTFY_LISTEN_HTTP} base-url=${NTFY_BASE_URL}"

exec ntfy serve --config /etc/ntfy/server.yml
