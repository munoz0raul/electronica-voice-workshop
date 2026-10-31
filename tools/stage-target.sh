#!/usr/bin/env bash
# Assemble a target directory for `fiocli updates upload`: an OS (ostree_repo)
# plus one or more staged compose apps. Each app's image comes from
# images/<app>.oci.tar (build-apps.sh), staged with stage-app.py under the
# ref demo-server.local/<app>.
#
#   tools/stage-target.sh <target-name> <ostree-repo> <app> [app ...]
#
# <ostree-repo> is a built OS repo, e.g. build/saved/uno-q-0/ostree_repo.
# The result is targets/<target-name>/, ready to upload:
#
#   tools/stage-target.sh uno-q-voice build/saved/uno-q-0/ostree_repo \
#       webapp-led-mcu-voice webapp-led-mcu-voice-assets
#   fiocli updates upload main uno-q-voice ./targets/uno-q-voice/
#
# See docs/SETUP.md and docs/WORKSHOP.md.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -ge 3 ] || { sed -n '2,16p' "$0" >&2; exit 1; }
name=$1; ostree=$2; shift 2

[ -d "$ostree" ] || { echo "no ostree repo: $ostree" >&2; exit 1; }

dst="targets/$name"
mkdir -p "$dst"

# cp -r onto an existing repo nests the new one inside it, so clear it first.
rm -rf "$dst/ostree_repo"
cp -r "$ostree" "$dst/ostree_repo"
echo ">>> OS: $ostree -> $dst/ostree_repo"

for app in "$@"; do
  [ -d "apps/$app" ] || { echo "no apps/$app" >&2; exit 1; }
  img="images/$app.oci.tar"
  [ -e "$img" ] || { echo "missing $img; run ./build-apps.sh $app" >&2; exit 1; }
  echo ">>> app: $app"
  ./stage-app.py \
    --app-ref "demo-server.local/$app" \
    --image "demo-server.local/$app:latest=$img" \
    "apps/$app" "$dst/"
done

echo ">>> staged targets/$name:"
ls "$dst"
echo ">>> upload with: fiocli updates upload main $name ./$dst/"
