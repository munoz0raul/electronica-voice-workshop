# Documentation

Documentation for the Electronica voice workshop — a self-hosted Foundries.io
update-server managing container apps on an Arduino UNO Q.

## Running the workshop

- [Setup](SETUP.md): from flashed boards to a running app. Prerequisites,
  register the boards with the update-server, stage and upload the first
  Target, and roll it out.
- [Workshop](WORKSHOP.md): the loop. Retrain the Edge Impulse model, rebuild
  the assets app, upload a new Target, roll it out to the UNO Q, and watch it
  land on the status page.
- [Architecture](ARCHITECTURE.md): the components, the demo Wi-Fi, and the
  update flow.

## Building the OS and firmware

The boards are reused already flashed, so these are only needed to rebuild the
image (for example to bake in `kernel-module-snd-usb-audio`, see
[Building the OS](BUILDING-OS.md#usb-audio)).

- [Building the OS](BUILDING-OS.md): `build-os.sh`, layer locks, Yocto caches,
  the demo Wi-Fi network, the startup loader and the update-server host service.
- [Building Zephyr](BUILDING-ZEPHYR.md): `build-zephyr.sh`, board selection and
  firmware updates.

## Reference

- [MCU interface specification](lighting-protocol/MCU-INTERFACE.md):
  Linux–Zephyr transport, command schema and bitmaps. This is the protocol
  `apps/webapp-led-mcu-voice/mcu_matrix.py` speaks to the matrix.
- [Docs style guide](STYLE.md): how these docs, commit messages and patches
  are written.

## Glossary

| Term | Meaning |
| --- | --- |
| aktualizr-lite | The update client on each board: it checks the update-server, installs updates and runs the compose apps |
| Bughopper | Arduino's debug adapter: a UNO Q's serial console over USB-C |
| Compose app | A Docker Compose application, delivered in an update and run by aktualizr-lite |
| Context | A saved fiocli sign-in to one update-server (`~/.config/fiocli.yaml`) |
| EDL | Emergency Download mode: the boot mode QDL flashes a board in |
| fiocli | The update-server's command-line client |
| fioconfig | The board's configuration client: it applies the configuration files and remote actions the update-server sends |
| Group | A named set of devices on the update-server; configuration and rollouts can target one |
| QDL | Qualcomm Device Loader: flashes a board over USB |
| QLI | Qualcomm Linux, the BSP release the OS builds on |
| Rollout | An instruction to a set of devices to install one update |
| Tag | A label on updates and devices; a device takes only updates that carry its tag (`main` here) |
| Target | An update's entry in its metadata. aktualizr-lite installs it: the OS hash, the apps, a version and the tag. Each upload creates one |
| Update | An OS (`ostree_repo`) and compose apps, uploaded together with `fiocli updates upload` |
| update-server | Foundries' self-hosted server for updates, devices and configuration, run on the VENTUNO Q |
