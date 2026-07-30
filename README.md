# Sapphire self-hosted ntfy

Replaces `ntfy.sh` for payment / audit notifications. Runs the upstream
[`binwiederhier/ntfy`](https://github.com/binwiederhier/ntfy) server on
Railway.

Same trust model as the old `ntfy.sh` setup: **public topic, name is
the secret**. The whole reason we self-host is to get out of the
`ntfy.sh` → Cloudflare Anycast → Railway egress path that occasionally
throws `AggregateError [ETIMEDOUT]`. Traffic now stays inside Railway.

## Deploy

1. **Create the GitHub repo.**
   ```sh
   cd ntfy/
   git init
   git add .
   git commit -m "initial: sapphire self-hosted ntfy"
   git remote add origin https://github.com/sapphirefrfr/ntfy.git
   git push -u origin main
   ```

2. **Railway → New Project → Deploy from GitHub → pick `sapphirefrfr/ntfy`.**
   Railway detects the Dockerfile and starts building.

3. **No env vars to set.** Railway sets `$PORT` and
   `$RAILWAY_PUBLIC_DOMAIN` automatically; the entrypoint reads both.

4. **Wait for green deploy.** Railway assigns a public URL like
   `ntfy-production-abc.up.railway.app`. Open it in a browser — you
   should see the ntfy web UI.

5. **Optional: custom domain** (Railway → Settings → Networking) like
   `ntfy.sapphire.gg`. Not required.

## Point Web1/Backend at the new instance

On the Web1/Backend Railway service, only one env change:

| Variable | New value |
|---|---|
| `NTFY_URL` | `https://<your-railway-domain>` (no trailing slash) |
| `NTFY_TOPIC` | `sapphire-notis-admin` (unchanged) |
| `NTFY_AUTH_TOKEN` | *unset — remove it, no auth needed* |

Redeploy Web1/Backend. Next payment webhook should log:

```
[ntfy] publish start title="Payment completed" url=https://<your-domain>/sapphire-notis-admin
[ntfy] dns <your-domain> -> <railway-egress-ip> (v4)
[ntfy] publish OK title="Payment completed" status=200
```

## Subscribe on your phone

Open the ntfy app → Add subscription:
- Server URL: `https://<your-railway-domain>`
- Topic: `sapphire-notis-admin`

No credentials needed. Done.

## Local test

```sh
docker build -t sapphire-ntfy .
docker run --rm -p 8080:8080 -e PORT=8080 sapphire-ntfy
```

Then:

```sh
# Publish
curl -H "Title: Local test" -d "hello" \
  http://localhost:8080/sapphire-notis-admin

# Subscribe (SSE stream)
curl http://localhost:8080/sapphire-notis-admin/json
```

## If the topic name leaks

You'll notice spam in the phone app. Two options:

- **Rotate the topic name.** Change `NTFY_TOPIC` on Web1/Backend and
  the topic in the phone app. Old subscribers to the leaked name
  keep seeing whatever anyone posts to that name; you just move to
  a fresh one.
- **Flip on auth.** Edit `server.yml`: change
  `auth-default-access: "read-write"` to `"deny-all"`, add
  `auth-file: "/tmp/ntfy-auth.db"`, and reintroduce the user-seed
  logic in `entrypoint.sh`. Prior version of both files in git
  history — `git log -p server.yml` at the initial commit shows the
  auth setup.

## Upstream reference

- Docs: https://docs.ntfy.sh/config/
- Release notes (bump the pinned tag after reading): https://github.com/binwiederhier/ntfy/releases
