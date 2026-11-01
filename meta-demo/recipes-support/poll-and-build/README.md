# poll-and-build

A self-hosted, poll-don't-push CI loop for the workshop, baked into the VENTUNO
Q image. A `systemd` timer (`poll-and-build.timer`) watches the workshop repo
over the Ethernet uplink; when something under `apps/` changes it rebuilds the
image(s), stages a UNO Q Target (OS + apps), uploads it to the local
update-server on `:8080`, and (by default) rolls it out to the `demo` group. The
UNO Q's aktualizr-lite then pulls only the changed OCI blobs — a model swap is
~14 MB.

GitHub is only the trigger. The board reaches out; nothing reaches in, so the
`:8080` server and the demo Wi-Fi stay off the public internet.

## What the recipe installs

- `/usr/bin/poll-and-build` — the loop (`poll-and-build.sh`).
- `poll-and-build.service` / `.timer` — the trigger (every `POLL_INTERVAL`,
  default 2 min; builds only on a real `apps/` change).
- `/etc/default/poll-and-build` — config (repo, branch, apps, tag, group,
  `AUTO_ROLLOUT`). A conffile, so device edits survive OS updates.
- Via `RDEPENDS`: `git`, `curl`, `jq`, `python3-pyyaml`, `fiocli`,
  `docker-buildx` (docker itself is already in the image).

## One-time provisioning on the box (not baked into the image)

These are site/secret or large data, so they are set up once on the device, not
shipped in the image:

1. **Private-repo credential.** A read-only **deploy key** for
   `munoz0raul/electronica-voice-workshop` (scoped to this one repo), or a
   fine-grained PAT with `contents:read`. For a deploy key, set `REPO_URL` to the
   `git@github.com:…` form and drop the key where root's SSH can find it. For a
   token, use an `https://x-access-token:<token>@github.com/…` `REPO_URL`.
2. **`fiocli` sign-in.** First `mkdir -p /root/.config`: the minimal rootfs
   ships no `~/.config`, and fiocli (rc3) does not create it, so the login fails
   on save with `open /root/.config/fiocli.yaml: no such file or directory`
   otherwise. Then run `fiocli login demo http://localhost:8080` once and approve
   it in the `:8080` UI (admin/admin). The token caches in root's
   `~/.config/fiocli.yaml`; the service reuses it. Re-run if it expires.
3. **UNO Q OS half.** Put the UNO Q's `ostree_repo` at `OSTREE_REPO`
   (`/var/lib/poll-and-build/uno-q-ostree_repo` by default). `stage-target.sh`
   copies it into every Target so the board sees an app-only update (no reboot).
   It must match the OS flashed on the UNO Q.
4. **First voice-app image.** The Target stages both apps, so
   `images/webapp-led-mcu-voice.oci.tar` must exist even when only the assets
   (model) app changed. It builds on first run (egress + disk are ample on the
   board), or drop a prebuilt tarball into the checkout's `images/`.

## Config

Edit `/etc/default/poll-and-build`. `AUTO_ROLLOUT=0` stages the Target but lets
the instructor fire the rollout by hand for a controlled demo moment.
