# Sapphire ntfy forwarder.
#
# ~30MB Node runtime, zero npm deps. Receives HTTP POSTs from
# Web1/Backend over Railway private networking and reposts them to
# https://ntfy.sh with generous retries so a Cloudflare Anycast flap
# doesn't stall Web1's checkout response.

FROM node:20-alpine

WORKDIR /app

COPY package.json ./
COPY server.js    ./

# No `npm install` -- server.js uses only node built-ins.

EXPOSE 80

CMD ["node", "server.js"]
