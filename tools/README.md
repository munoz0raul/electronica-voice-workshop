# Workshop tools

Host-side tools for working with the demo boards.

- `stage-target.sh`: assembles a `targets/<name>/` directory — an OS
  (`ostree_repo`) plus one or more staged compose apps — ready for
  `fiocli updates upload`. Wraps `stage-app.py` for each app.

  ```sh
  ./build-apps.sh
  tools/stage-target.sh uno-q-voice build/saved/uno-q-0/ostree_repo \
      webapp-led-mcu-voice webapp-led-mcu-voice-assets
  fiocli updates upload main uno-q-voice ./targets/uno-q-voice/
  ```

- `dev-app.sh`: runs a compose app on a board straight from `images/`,
  without the update-server. It stages the app with `stage-app.py`, copies the
  blobs the board doesn't have yet over ssh, and starts it with `composectl`
  in a separate store under `/var/lib/dev-apps`, which aktualizr-lite doesn't
  manage. For quick iteration; releases go through the update-server.

  ```sh
  ./build-apps.sh --rebuild
  tools/dev-app.sh --jump root@<ventuno-lan-ip> up webapp-led-mcu-voice root@10.42.0.x
  tools/dev-app.sh --jump root@<ventuno-lan-ip> logs webapp-led-mcu-voice root@10.42.0.x
  tools/dev-app.sh --jump root@<ventuno-lan-ip> down webapp-led-mcu-voice root@10.42.0.x
  ```

- `fleet-check.sh`: checks the VENTUNO Q access point and every UNO Q
  connected to it. It reports the Wi-Fi link and factory MAC, chrony sync,
  MCU loader, `/dev/mcu-console`, `demo-server.local` resolution and, unless
  `--no-mcu` is given, the MCU's uptime and latest console lines. It only
  sends session-less commands, so it doesn't disturb the matrix.

  ```sh
  ./fleet-check.sh --ventuno root@<ventuno-lan-ip>
  SSHPASS=<root password> ./fleet-check.sh --ventuno root@<ventuno-lan-ip> --install-keys
  ```

  See `./fleet-check.sh --help` for all options.
