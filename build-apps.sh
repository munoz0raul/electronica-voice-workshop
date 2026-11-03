#!/usr/bin/env bash
# Build the apps' images as OCI tarballs (images/<app>.oci.tar) for
# stage-app.py, on a docker-container buildx builder.
#
# usage: build-apps.sh [--rebuild] [app ...]
#   --rebuild      build every image again, even when its output exists
#   app ...        build only these apps (default: all)
set -euo pipefail
cd "$(dirname "$0")"

# arm64 apps; each builds from its own directory under apps/. The set is
# discovered from the directories present: every apps/<name>/ with a
# docker-compose.yml is an app. Add or remove an app by adding or removing its
# directory — there is no list to keep in sync (here or in poll-and-build).
APPS=()
for d in apps/*/; do
  [ -f "${d}docker-compose.yml" ] && APPS+=("$(basename "${d%/}")")
done

rebuild=0
want=()
explicit=0   # set when caller names specific apps (implies rebuild — they already ran git diff)
for arg in "$@"; do
  case "$arg" in
  --rebuild) rebuild=1 ;;
  -*) echo "usage: $0 [--rebuild] [app ...]" >&2; exit 1 ;;
  *) want+=("$arg"); explicit=1 ;;
  esac
done
[ ${#want[@]} -gt 0 ] || want=("${APPS[@]}")

BUILDER=${BUILDX_BUILDER:-host-builder}
# Read the whole output first: grep -q exits at the first match, and with
# pipefail the writer's SIGPIPE then fails the check.
driver=$(docker buildx inspect "$BUILDER")
grep -q '^Driver: *docker-container' <<<"$driver" ||
  { echo "buildx builder '$BUILDER' must use the docker-container driver" >&2; exit 1; }

mkdir -p images

# Build when the output is missing or --rebuild was given. buildx writes to a
# temporary file, so a failed build never leaves an output that later runs skip.
needs_build() {
  [ "$rebuild" = 1 ] || [ ! -e "$1" ] || [ "$explicit" = 1 ]
}

for app in "${want[@]}"; do
  [ -d "apps/$app" ] || { echo "no apps/$app" >&2; exit 1; }
  out=images/$app.oci.tar
  if needs_build "$out"; then
    echo ">>> building $app"
    docker buildx build --builder "$BUILDER" --platform linux/arm64 \
      --provenance=false --sbom=false \
      --network=host \
      --output type=oci,dest="$out.tmp",name=demo-server.local/$app:latest \
      "apps/$app"
    mv "$out.tmp" "$out"
  else
    echo ">>> $app up to date ($out); --rebuild to force"
  fi
done
