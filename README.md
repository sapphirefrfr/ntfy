# Sapphire ntfy forwarder

Tiny Node proxy on Railway. Receives HTTP POSTs from Web1/Backend and
reposts them to `https://ntfy.sh` with retries. Not an ntfy server —
just a dumb pass-through.

## Why

Web1 → ntfy.sh direct was occasionally timing out at the Cloudflare
Anycast layer from Railway egress. This container gives Web1 a
Railway-internal target that acks in <1s, then handles the flaky
Cloudflare hop on its own with a 5-attempt retry envelope
(2s → 4s → 8s → 16s backoff, 10s per-attempt timeout).

Your phone stays subscribed to `ntfy.sh/sapphire-notis-admin`. No
phone-side change ever.

```
Web1  ─(POST /sapphire-notis-admin)─►  this container
                                             │
                                             ▼
                        POST /sapphire-notis-admin
                        w/ retry, IPv4-pinned
                                             │
                                             ▼
                                        ntfy.sh
                                             │
                                             ▼
                                    phone (subscribed)
```

## Deploy

1. Push this repo to `sapphirefrfr/ntfy` (already done).
2. **Railway → New Project → Deploy from GitHub** → pick the repo.
3. **No env vars needed.** `UPSTREAM_URL` defaults to `https://ntfy.sh`
   and `PORT` is set by Railway automatically.
4. Turn on private networking on the service (default) so
   `ntfy.railway.internal` resolves for Web1.

## Point Web1/Backend at the forwarder

On the Web1/Backend Railway service, env vars:

| Variable | Value |
|---|---|
| `NTFY_URL` | `http://ntfy.railway.internal:${{ntfy.PORT}}` |
| `NTFY_TOPIC` | `sapphire-notis-admin` |
| `NTFY_AUTH_TOKEN` | *unset* |

The `${{ntfy.PORT}}` is a Railway reference variable — resolves to
whatever port this service is listening on.

Redeploy Web1/Backend. Next payment webhook logs:

**Web1/Backend:**
```
[ntfy] publish start title="Payment completed" url=http://ntfy.railway.internal:8080/sapphire-notis-admin
[ntfy] dns ntfy.railway.internal -> 10.x.x.x (v4)
[ntfy] publish OK title="Payment completed" status=200
```

**ntfy forwarder service:**
```
[fwd] ok: "Payment completed" path=/sapphire-notis-admin status=200 attempt=1
```

If Cloudflare is flaky, the forwarder side shows the retry pattern:
```
[fwd] fail attempt 1/5: timeout after 10000ms
[fwd] fail attempt 2/5: timeout after 10000ms
[fwd] ok: "Payment completed" path=/sapphire-notis-admin status=200 attempt=3
```

Web1 already saw a 200 in <1s regardless — this happens in the
background.

## What gets forwarded

- HTTP method: POST only (GET returns `ok` for Railway's healthcheck)
- Path: verbatim (`/sapphire-notis-admin`, whatever)
- Headers: `content-type`, `title`, `message`, `priority`, `tags`,
  `click`, `attach`, `icon`, `actions`, `email`, `delay`, `cache`,
  `firebase`, `authorization`. Everything else stripped so junk like
  `x-forwarded-for` doesn't leak.
- Body: verbatim, up to 128KB.

## Local test

```sh
docker build -t sapphire-fwd .
docker run --rm -p 8080:8080 -e PORT=8080 sapphire-fwd

# In another terminal:
curl -H "Title: local test" -d "hello" http://localhost:8080/sapphire-notis-admin
```

The message lands on `ntfy.sh/sapphire-notis-admin` within a couple
seconds — check the ntfy app.

## Rotate the topic name

Just change `NTFY_TOPIC` on Web1/Backend and the topic in the ntfy
app on your phone. The forwarder doesn't hardcode a topic — whatever
path Web1 POSTs to gets forwarded verbatim.

## Change the upstream

If you ever want to point at a different ntfy server (self-hosted,
Uptime Kuma, whatever), set `UPSTREAM_URL` on the Railway service.
Default: `https://ntfy.sh`.
