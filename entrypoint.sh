#!/bin/sh
# Sapphire ntfy entrypoint.
#
# Two jobs:
#   1. Point ntfy at Railway's assigned $PORT and public URL, then
#      exec `ntfy serve` in the foreground so Railway monitors it.
#   2. If UPSTREAM_URL is set, run a background forwarder loop that
#      subscribes to our local instance's topic and reposts every
#      message to that upstream (typically ntfy.sh). Lets a phone
#      that's already subscribed to ntfy.sh keep working while Web1
#      publishes to us over Railway's private network -- Web1's
#      publish path never touches the public internet, but the phone
#      still gets its alerts through its existing subscription.
#
# Web1 -> Railway ntfy = fast, no Cloudflare hop, always <1s.
# Railway ntfy -> ntfy.sh (forwarder) = async, retried aggressively,
# doesn't block Web1's response.

set -eu

# ---- Runtime port + base URL --------------------------------------
export NTFY_LISTEN_HTTP=":${PORT:-80}"

if [ -z "${NTFY_BASE_URL:-}" ]; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    export NTFY_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
  else
    export NTFY_BASE_URL="http://localhost:${PORT:-80}"
  fi
fi

# TOPIC is exported so the forwarder subshell inherits it -- referenced
# from single-quoted context inside the ntfy subscribe command below.
export TOPIC="${NTFY_TOPIC:-sapphire-notis-admin}"

echo "[ntfy entrypoint] listen=${NTFY_LISTEN_HTTP} base-url=${NTFY_BASE_URL} topic=${TOPIC}"

# ---- Optional upstream forwarder ---------------------------------
# Enabled by setting UPSTREAM_URL (e.g. UPSTREAM_URL=https://ntfy.sh).
# Unset -> pure self-hosted, phone must subscribe to Railway's URL.
if [ -n "${UPSTREAM_URL:-}" ]; then
  export UPSTREAM_URL
  echo "[ntfy entrypoint] forwarder: local -> ${UPSTREAM_URL}/${TOPIC}"

  # Background loop. `ntfy subscribe TOPIC 'shell command'` runs the
  # command once per received message with NTFY_MESSAGE / NTFY_TITLE /
  # NTFY_TAGS / NTFY_PRIORITY populated as env vars.
  #
  # The `for i in 1..5` retry gives the outbound POST a fair shake
  # against the exact Cloudflare Anycast timeouts that motivated this
  # whole setup. 5 attempts, exponential backoff (2/4/8/16s = 30s
  # cumulative), 10s per-attempt timeout -- ~80s total worst case
  # before a single message is dropped.
  #
  # 127.0.0.1 (not railway.internal) keeps the local subscribe path
  # entirely intra-container so there's zero network dependency for
  # the forwarder to start; only the outbound POST hits the network.
  (
    # Small delay so ntfy serve has bound its listener before we
    # try to subscribe to ourselves. Ntfy itself starts in ~1s.
    sleep 5

    while true; do
      ntfy subscribe "http://127.0.0.1:${PORT:-80}/${TOPIC}" \
        'for i in 1 2 3 4 5; do
           if curl -fsS -X POST --max-time 10 \
                -H "Title: $NTFY_TITLE" \
                -H "Tags: $NTFY_TAGS" \
                -H "Priority: $NTFY_PRIORITY" \
                --data "$NTFY_MESSAGE" \
                "$UPSTREAM_URL/$TOPIC" > /dev/null; then
             echo "[fwd] ok: $NTFY_TITLE" >&2
             break
           fi
           delay=$((1 << i))
           echo "[fwd] attempt $i failed, retry in ${delay}s" >&2
           sleep $delay
         done' 2>&1 \
        | sed 's/^/[fwd] /'

      echo "[fwd] subscribe stream exited, reconnecting in 3s" >&2
      sleep 3
    done
  ) &
fi

# ---- Hand off to upstream ntfy -----------------------------------
exec ntfy serve --config /etc/ntfy/server.yml
