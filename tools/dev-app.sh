#!/usr/bin/env bash
# Run a compose app on a board straight from images/, without the
# update-server: stage it, stream the blobs over ssh and start it with
# composectl. Uses its own store and compose root under /var/lib/dev-apps, so
# aktualizr-lite never sees or prunes it.
#
#   tools/dev-app.sh [--jump HOST] up   <app> <ssh-target>   # stage, copy, (re)start
#   tools/dev-app.sh [--jump HOST] down <app> <ssh-target>   # stop and uninstall
#   tools/dev-app.sh [--jump HOST] logs <app> <ssh-target>   # follow the logs
#
# <app> is a directory under apps/ with images/<app>.oci.tar built by
# build-apps.sh. UNO Qs are reached through the VENTUNO Q, for example
#   tools/dev-app.sh --jump root@192.168.101.168 up led-matrix-client root@10.42.0.236
set -euo pipefail
cd "$(dirname "$0")/.."

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
if [ "${1-}" = --jump ]; then
  ssh_opts+=(-J "$2")
  shift 2
fi
[ $# -eq 3 ] || { sed -n '2,15p' "$0" >&2; exit 1; }
cmd=$1 app=$2 target=$3

ROOT=/var/lib/dev-apps
# Commands are built locally, with the store paths expanded before sending.
# shellcheck disable=SC2029
remote() { ssh "${ssh_opts[@]}" "$target" "$@"; }
dc() { echo "composectl --store $ROOT/store --compose $ROOT/projects $*"; }

case "$cmd" in
up)
  [ -d "apps/$app" ] || { echo "no apps/$app" >&2; exit 1; }
  # Every image the compose file names, from images/<image name>.oci.tar
  mapfile -t images < <(sed -n 's/^ *image: *//p' "apps/$app/docker-compose.yml")
  image_args=()
  for img in "${images[@]}"; do
    name=${img##*/}
    name=${name%%:*}
    [ -e "images/$name.oci.tar" ] || { echo "missing images/$name.oci.tar; run ./build-apps.sh" >&2; exit 1; }
    image_args+=(--image "$img=images/$name.oci.tar")
  done

  stage=$(mktemp -d)
  trap 'rm -rf "$stage"' EXIT
  out=$(python3 stage-app.py --app-ref "demo-server.local/$app" "${image_args[@]}" "apps/$app" "$stage")
  uri=$(sed -n 's/^app uri: *//p' <<<"$out")
  [ -n "$uri" ] || { echo "$out" >&2; exit 1; }

  # Earlier versions stay in the store until the new blobs are in, so the
  # copy below skips the blobs they share.
  digest=${uri##*@sha256:}
  old=$(remote "mkdir -p $ROOT/store $ROOT/projects
    ls $ROOT/store/apps/$app 2>/dev/null" | grep -vxF "$digest" || true)
  # Send only the blobs the board lacks: on a redeploy that is the changed
  # layers and the app metadata, not the whole image. The board's pull below
  # builds the apps/<name>/<digest> tree from them.
  have=$(remote "ls $ROOT/store/blobs/sha256 2>/dev/null" || true)
  send=()
  bytes=0
  for f in "$stage"/apps/blobs/sha256/*; do
    grep -qxF "${f##*/}" <<<"$have" && continue
    send+=("blobs/sha256/${f##*/}")
    bytes=$((bytes + $(stat -c %s "$f")))
  done
  echo "copying $uri to $target: ${#send[@]} new blob(s), $((bytes / 1024)) KiB"
  if [ ${#send[@]} -gt 0 ]; then
    tar -C "$stage/apps" -cf - "${send[@]}" | remote "tar -xf - -C $ROOT/store"
  fi
  # pull from the store into itself verifies what arrived and builds the new
  # version's app tree, so it holds on to the blobs it shares with older ones.
  remote "$(dc pull --source-store-path $ROOT/store "$uri") >/dev/null"
  # composectl installs one version of an app per store: drop the earlier
  # ones. Uninstalling without --prune keeps the loaded image layers, and rm
  # prunes only blobs that no remaining app uses.
  for d in $old; do
    remote "$(dc stop "$app") >/dev/null 2>&1
      $(dc uninstall --ignore-non-installed "$app") >/dev/null 2>&1
      $(dc rm "demo-server.local/$app@sha256:$d")" >/dev/null || true
  done
  remote "set -e
    $(dc install "$uri")
    $(dc run --apps "$app")
    docker ps --filter label=com.docker.compose.project=$app --format '{{.Names}}: {{.Status}}'"
  ;;
down)
  remote "$(dc stop "$app") || true; $(dc uninstall --ignore-non-installed --prune "$app") || true; $(dc rm --quiet "$app") || true"
  ;;
logs)
  remote "docker logs -f --tail 50 \$(docker ps -aq --filter label=com.docker.compose.project=$app | head -1)"
  ;;
*)
  sed -n '2,15p' "$0" >&2
  exit 1
  ;;
esac
