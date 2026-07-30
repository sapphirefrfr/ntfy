// Sapphire ntfy forwarder.
//
// Receives an HTTP POST from Web1 and reposts the identical bytes,
// headers, and path to https://ntfy.sh (or another UPSTREAM_URL).
// Returns 200 to Web1 IMMEDIATELY, then handles the upstream POST
// asynchronously with generous retries.
//
// Web1's publish is a Railway-internal HTTP call: never touches the
// public internet, never times out. The Cloudflare-fronted hop to
// ntfy.sh is done in the background by this container with its own
// retry envelope, so a Cloudflare Anycast flap can't stall Web1's
// checkout response.
//
// Zero deps by design -- node:http and node:https are enough; adding
// express or axios here just adds churn.

import http  from "node:http";
import https from "node:https";
import dns   from "node:dns";

const PORT         = Number(process.env.PORT) || 80;
const UPSTREAM_URL = process.env.UPSTREAM_URL ?? "https://ntfy.sh";

// Pin IPv4 for the upstream POST -- same reason as Web1's own
// ntfy.service.ts. Railway containers have broken IPv6 egress to
// Cloudflare, so Happy Eyeballs falling back to v6 after a v4 timeout
// doubles the outage window per attempt for no benefit.
dns.setDefaultResultOrder("ipv4first");

const upstream = new URL(UPSTREAM_URL);
const upstreamMod = upstream.protocol === "https:" ? https : http;

// Retry envelope for the outbound POST. 5 attempts, exponential
// backoff (2/4/8/16 = 30s cumulative), 10s per-attempt timeout.
// Cloudflare route flaps typically last a few seconds to a minute,
// so ~80s wall-clock spread across 5 attempts covers most.
const MAX_ATTEMPTS      = 5;
const REQUEST_TIMEOUT   = 10_000;
const RETRY_BASE_MS     = 2_000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Copy just the headers that ntfy cares about downstream. Whitelist
// approach: anything we don't explicitly forward stays out of the
// upstream request, so junk like x-forwarded-for or railway-internal
// headers don't leak.
function forwardableHeaders(src) {
  const out = {};
  const allow = [
    "content-type", "title", "message", "priority", "tags",
    "click", "attach", "icon", "actions", "email", "delay", "cache",
    "firebase", "authorization",
  ];
  for (const k of allow) {
    const v = src[k];
    if (v !== undefined) out[k] = v;
  }
  return out;
}

async function forwardOnce(path, headers, body) {
  return new Promise((resolve, reject) => {
    const req = upstreamMod.request(
      {
        hostname: upstream.hostname,
        port: upstream.port || (upstream.protocol === "https:" ? 443 : 80),
        path,
        method: "POST",
        headers: {
          ...headers,
          "content-length": String(body.length),
          host: upstream.hostname,
        },
        timeout: REQUEST_TIMEOUT,
        family: 4,
      },
      (res) => {
        // Drain the response body so the socket can be reused/closed
        // cleanly even though we don't care what ntfy.sh returned.
        res.resume();
        if (res.statusCode !== undefined && res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.statusCode);
        } else {
          reject(new Error(`upstream ${res.statusCode}`));
        }
      },
    );
    req.on("timeout", () => req.destroy(new Error(`timeout after ${REQUEST_TIMEOUT}ms`)));
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

async function forwardWithRetry(path, headers, body) {
  const label = headers.title ?? "(no title)";
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      const status = await forwardOnce(path, headers, body);
      console.log(`[fwd] ok: "${label}" path=${path} status=${status} attempt=${attempt}`);
      return;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[fwd] fail attempt ${attempt}/${MAX_ATTEMPTS}: ${msg}`);
      if (attempt < MAX_ATTEMPTS) {
        await sleep(RETRY_BASE_MS * (2 ** (attempt - 1)));
      }
    }
  }
  console.error(`[fwd] GAVE UP: "${label}" path=${path} after ${MAX_ATTEMPTS} attempts`);
}

const server = http.createServer((req, res) => {
  // Health probe -- Railway hits this to know we're alive. Any GET
  // returns 200 without touching upstream.
  if (req.method === "GET") {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end("ok");
    return;
  }

  if (req.method !== "POST") {
    res.writeHead(405, { allow: "GET, POST", "content-type": "text/plain" });
    res.end("method not allowed");
    return;
  }

  const chunks = [];
  let totalSize = 0;
  const MAX_BODY = 128 * 1024; // 128 KB -- ntfy messages are text, this is very generous

  req.on("data", (chunk) => {
    totalSize += chunk.length;
    if (totalSize > MAX_BODY) {
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on("end", () => {
    if (totalSize > MAX_BODY) {
      res.writeHead(413, { "content-type": "text/plain" });
      res.end("body too large");
      return;
    }

    const body = Buffer.concat(chunks);
    const headers = forwardableHeaders(req.headers);
    const path = req.url ?? "/";

    // Ack the caller immediately -- Web1's checkout webhook doesn't
    // block on ntfy.sh reachability.
    res.writeHead(200, { "content-type": "application/json" });
    res.end('{"ok":true,"forwarded":true}');

    // Kick off the forward. Errors already logged inside; we don't
    // want an unhandled rejection to crash the process.
    forwardWithRetry(path, headers, body).catch((err) => {
      console.error("[fwd] unexpected top-level error:", err);
    });
  });

  req.on("error", (err) => {
    console.error("[recv] request stream error:", err.message);
  });
});

server.listen(PORT, () => {
  console.log(`[fwd] listening on :${PORT}, upstream=${UPSTREAM_URL}`);
});
