# The workshop loop

[SETUP.md](SETUP.md) left the UNO Q running the voice app with the model baked
into the repo. This is the loop you run live: **retrain the Edge Impulse model,
rebuild the app that carries it, upload it as a new Target, roll it out, and
watch it land** — the FoundriesFactory OTA flow, run from your laptop.

The model is shipped by `webapp-led-mcu-voice-assets`: that app carries a
`deployment.eim` and drops it at `/var/local/assets/deployment.eim`, where the
voice app reads it in preference to its own baked-in copy and restarts to pick
it up. So a model update is just a new build of the **assets** app — the voice
app itself doesn't change.

## 1. Retrain and export from Edge Impulse

In your Edge Impulse project, retrain the keyword model, then
**Deployment → Linux (AARCH64)** → build. You get a `.eim` file.

The labels the voice app expects are `select` and the colours
`blue green purple red yellow`; keep them, or the matrix/LED mapping won't
match. The detection threshold is `THRESH` in
`apps/webapp-led-mcu-voice/docker-compose.yml` (0.70).

**Check:** the downloaded file runs as an EIM for this architecture
(arm64/AARCH64), not x86.

## 2. Drop the new model into the assets app

Replace the baked-in model:

```sh
cp ~/Downloads/<your-model>.eim apps/webapp-led-mcu-voice-assets/deployment.eim
```

**Check:** `git status` shows only `deployment.eim` changed.

## 3. Rebuild just the assets app

```sh
./build-apps.sh webapp-led-mcu-voice-assets
```

**Check:** `images/webapp-led-mcu-voice-assets.oci.tar` has a fresh timestamp.

## 4. Stage a new Target

Stage both UNO Q apps together — the Target is the whole app set for the board,
so the unchanged voice app rides along with the rebuilt assets app. Bump the
name so it's distinct from the last upload (`-0`, `-1`, …):

```sh
tools/stage-target.sh uno-q build/saved/uno-q-0/ostree_repo \
    webapp-led-mcu-voice webapp-led-mcu-voice-assets
fiocli updates upload main uno-q-voice-1 ./targets/uno-q/
```

Same OS `ostree_repo` as setup — only the apps change, so the board does an
app-only update and doesn't reboot.

**Check:** `fiocli updates list` shows `uno-q-voice-1` above `uno-q-voice-0`,
tag `main`, a higher version.

## 5. Roll it out

```sh
fiocli updates create-rollout uno-q-voice-1 retrain-1 retrain-1 --groups demo
```

To send it to one board instead of the whole group, use `--uuids <uno-q-uuid>`.

**Check:** `fiocli devices list --columns name,group,target` — the UNO Q's
target moves to `uno-q-voice-1` within a check interval (~5 s poll, then the
pull).

## 6. Watch it land

- **Devices view** (`http://<ventuno-q-ip>:8080/devices`, login `admin`/`admin`):
  the UNO Q's version ticks up to the new Target.
- **The board**: the assets app writes the new `deployment.eim` and restarts
  the voice app, which reloads the model. Say "select" then a colour and
  confirm the retrained model reacts.

To follow it on the device:

```sh
ssh -J root@<ventuno-q-ip> root@<uno-q-ip> \
    'docker logs -f $(docker ps -q -f name=webapp-led-mcu-voice-assets)'
```

## If it doesn't land

- **Target didn't move.** Check the device is in the `demo` group and tagged
  `main` (`fiocli devices list --columns name,group,tag`); a rollout only
  reaches its group, and a device only takes updates carrying its tag.
- **Target moved, model didn't change.** The assets app only restarts the voice
  app when the `.eim` content differs. Confirm step 2 actually replaced the
  file (`md5sum apps/webapp-led-mcu-voice-assets/deployment.eim`).
- **Voice app won't recognise words.** Wrong labels or an x86 EIM — redo the
  export (step 1). The app logs the model path and labels at startup.
- **No audio at all.** The USB-audio workaround in the voice app's `start.sh`
  (`apps/webapp-led-mcu-voice/README.md`) depends on the bundled kernel module
  matching the running kernel. If the OS was rebuilt, rebuild the module to
  match — see [Building the OS](BUILDING-OS.md#usb-audio).

## Reset between runs

To demo the loop again from the original model, `git checkout
apps/webapp-led-mcu-voice-assets/deployment.eim` and repeat from step 3 with a
fresh Target name.
