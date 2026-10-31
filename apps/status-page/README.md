# status-page

A one-page fleet status for the VENTUNO Q, on `:8081`. It polls the
update-server and shows each device's current **Target** and **version**, so a
workshop audience sees a new model land after an OTA rollout.

It is a cut-down version of the demo dashboard's update-server client, using the
same API (`/v1/devices`, `/v1/updates`, `/v1/updates/<name>/tuf`) and the same
Bearer token.

## Token

The update-server API needs a token. The page reads one of, in order:

1. env `STATUS_TOKEN`
2. `/run/secrets/status-token`
3. `/run/secrets/dashboard-token` (reuse the dashboard's, if present)

Tokens are delivered to the device encrypted by fioconfig; nothing is committed
here. When no token resolves, or the server refuses it, the page says so rather
than showing an empty table — see [`docs/WORKSHOP.md`](../../docs/WORKSHOP.md)
for provisioning.

## Build

```sh
./build-apps.sh                 # builds images/status-page.oci.tar
```

## Status

The HTTP server, the HTML page, and the no-token / server-unreachable / token-
refused paths were tested locally (served `/` and `/api`, exercised each error
path). The happy path — parsing a live update-server's `/v1/devices` and TUF
metadata into the table — was **not** tested against a running server; the API
shape is taken from the demo dashboard's `server.py`.
