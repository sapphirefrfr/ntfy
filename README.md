# Sapphire self-hosted ntfy

Runs the upstream
[`binwiederhier/ntfy`](https://github.com/binwiederhier/ntfy) server
on Railway. Two operating modes:

## Mode A — pure self-hosted (default)

Web1/Backend publishes to Railway. Phone subscribes to Railway. Done.

## Mode B — self-hosted + forwarding to ntfy.sh (recommended)

Web1/Backend publishes to Railway (fast, no Cloudflare hop). Railway
forwards every message to ntfy.sh in the background. Phone subscribes
to ntfy.sh, no phone-side change.

Enable by setting `UPSTREAM_URL=https://ntfy.sh` on the Railway ntfy
service.

**Why this pattern:** the original problem was Web1/Backend →
Cloudflare Anycast → ntfy.sh occasionally timing out from Railway
egress. In mode B:

- Web1's publish path is Railway internal networking only, <1s,
  reliable.
- The Cloudflare-facing hop is done by the forwarder, which lives in
  the same Railway container as ntfy and retries aggressively (5
  attempts, exponential backoff, 10s per-attempt timeout) without
  blocking Web1's response.
- A dropped forward doesn't block the publish; Web1 doesn't have to
  care. Worst case a notification lands a few seconds late.

Your phone stays subscribed to `ntfy.sh/sapphire-notis-admin` and
sees no difference.

## Deploy

1. **Push the repo** to `sapphirefrfr/ntfy` (already done if you're
   reading this).
2. **Railway → New Project → Deploy from GitHub** → pick the repo.
3. **Env vars on the Railway ntfy service:**

   | Variable | Value | Required? |
   |---|---|---|
   | `UPSTREAM_URL` | `https://ntfy.sh` | Only for Mode B |
   | `NTFY_TOPIC` | `sapphire-notis-admin` | Optional, defaults to this |

   No auth, no user setup. Public topic, name is the secret.

4. **Networking on the Railway ntfy service:**
   - Private networking is enabled by default (`ntfy.railway.internal`).
   - Turn on public networking only if you want to hit the ntfy web
     UI from a browser or subscribe your phone directly (Mode A).

## Point Web1/Backend at Railway ntfy

On the Web1/Backend Railway service, env vars:

| Variable | Value |
|---|---|
| `NTFY_URL` | `http://ntfy.railway.internal:${{ntfy.PORT}}` |
| `NTFY_TOPIC` | `sapphire-notis-admin` |
| `NTFY_AUTH_TOKEN` | *unset — no auth needed* |

The `${{ntfy.PORT}}` is a Railway reference variable — resolves to
whatever port the ntfy service is listening on. Auto-follows if
Railway ever reassigns.

Redeploy Web1/Backend. Next payment webhook logs should show:

```
[ntfy] publish start title="Payment completed" url=http://ntfy.railway.internal:8080/sapphire-notis-admin
[ntfy] dns ntfy.railway.internal -> 10.x.x.x (v4)
[ntfy] publish OK title="Payment completed" status=200
```

And in the ntfy Railway service logs:

```
[fwd] ok: Payment completed
```

## Local test

```sh
docker build -t sapphire-ntfy .

# Mode A (pure self-hosted)
docker run --rm -p 8080:8080 -e PORT=8080 sapphire-ntfy

# Mode B (with forwarder)
docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e UPSTREAM_URL=https://ntfy.sh \
  sapphire-ntfy
```

Publish a test message locally:
```sh
curl -H "Title: local test" -d "hello" http://localhost:8080/sapphire-notis-admin
```

In Mode B, the message also lands on `ntfy.sh/sapphire-notis-admin`
within a couple seconds — check the ntfy app.

## Failure modes

- **`ECONNREFUSED` on port 80 from Web1** — you didn't specify the
  port in `NTFY_URL`. Use `${{ntfy.PORT}}`.
- **`301` from Web1** — you used `http://` on the public
  `.up.railway.app` URL. Railway edge redirects HTTP → HTTPS. Use
  `https://` for public URLs, or switch to the internal URL for the
  backend path.
- **Forwarder log spam** — `[fwd] attempt N failed` means the
  Cloudflare route flap you were trying to escape is happening RIGHT
  NOW to the forwarder. Web1 doesn't care; the message will land on
  ntfy.sh within 30s worst case.

## Rotate the topic name

If it leaks and starts getting sprayed:

1. Change `NTFY_TOPIC` env var here (defaults to `sapphire-notis-admin`).
2. Change `NTFY_TOPIC` on Web1/Backend to match.
3. Change the topic in the ntfy app on your phone.

Or go full auth — edit `server.yml` and put back the
`auth-default-access: deny-all` + user seeding logic. Prior version
in git history.

## Upstream reference

- Docs: https://docs.ntfy.sh/config/
- Release notes: https://github.com/binwiederhier/ntfy/releases
