#!/usr/bin/env bash
set -euo pipefail

# Update these when moving to a new Zephyr release or SDK build environment.
ZEPHYR_VERSION="${ZEPHYR_VERSION:-4.4.2}"
ZEPHYR_IMAGE="${ZEPHYR_IMAGE:-ghcr.io/embeddedcontainers/zephyr:arm-1.0.1SDK@sha256:80e661fff9792e713f602567d9c70d81982cbf4d275f255feeb65cb19e9db9a3}"

die() { echo "Error: $*" >&2; exit 1; }

# This branch runs inside the prebuilt container with /build writable and
# /repo (and optionally /app) mounted from the host.
container_build()
{
    local action=$1 board=$2 source=$3 pristine=$4 build_mode=$5
    shift 5
    local sdk_version board_dir xip=y
    [[ "$build_mode" != ram ]] || xip=n
    case "$board" in
        arduino_uno_q/stm32u585xx) board_dir=uno-q ;;
        arduino_ventuno_q/stm32h5f5xx) board_dir=ventuno-q ;;
        *) board_dir=${board//\//_} ;;
    esac

    cd /build/work
    cat > manifest/west.yml <<EOF
manifest:
  projects:
    - name: zephyr
      url: https://github.com/zephyrproject-rtos/zephyr
      revision: v${ZEPHYR_VERSION}
      clone-depth: 1
      import:
        name-allowlist:
          - cmsis
          - cmsis_6
          - hal_stm32
          - zcbor
  self:
    path: manifest
EOF

    # Keep Python packages in the build directory, owned by the invoking user.
    if [[ ! -x /build/venv/bin/west ]]; then
        python3 -m venv /build/venv
        /build/venv/bin/python -m pip --cache-dir /build/cache/pip install 'west>=1.5,<2'
    fi
    # shellcheck source=/dev/null
    source /build/venv/bin/activate
    if [[ ! -d .west ]]; then
        west init -l manifest
    fi

    # Local fixes on top of the Zephyr release (firmware/zephyr-patches).
    # Reset and repatch only when the release or the patch set changes, so
    # incremental builds keep their timestamps.
    local patches=() patch stamp=/build/work/.zephyr-patches sum
    for patch in /repo/firmware/zephyr-patches/*.patch; do
        [[ -f "$patch" ]] && patches+=("$patch")
    done
    sum=$( { printf '%s\n' "$ZEPHYR_VERSION"; cat "${patches[@]}" /dev/null; } | sha256sum)
    local repatch=false
    if [[ ! -f "$stamp" || $(<"$stamp") != "$sum" ]]; then
        repatch=true
        if [[ -d zephyr/.git ]]; then
            git -C zephyr reset -q --hard
            git -C zephyr clean -fdq
        fi
    fi
    west update --narrow --fetch-opt=--depth=1
    if [[ "$repatch" == true ]]; then
        for patch in "${patches[@]}"; do
            echo "Applying $(basename "$patch")"
            git -C zephyr apply "$patch"
        done
        printf '%s\n' "$sum" > "$stamp"
    fi

    sdk_version=$(<zephyr/SDK_VERSION)
    export ZEPHYR_BASE=/build/work/zephyr
    export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
    export ZEPHYR_SDK_INSTALL_DIR="/opt/toolchains/zephyr-sdk-${sdk_version}"
    [[ -d "$ZEPHYR_SDK_INSTALL_DIR" ]] || die \
        "Zephyr ${ZEPHYR_VERSION} recommends SDK ${sdk_version}; choose a matching --image."

    if [[ ! -f /build/.python-version ]] || \
       [[ $(</build/.python-version) != "$ZEPHYR_VERSION" ]]; then
        python -m pip --cache-dir /build/cache/pip install -r zephyr/scripts/requirements-base.txt
        printf '%s\n' "$ZEPHYR_VERSION" > /build/.python-version
    fi

    if [[ "$action" == shell ]]; then
        exec bash --noprofile --norc -i
    fi
    if [[ "$source" != /app ]]; then
        source="${ZEPHYR_BASE}/${source}"
    fi
    [[ -f "$source/CMakeLists.txt" ]] || die "No Zephyr application at ${source}"
    west build --board "$board" --build-dir "/build/output/${board_dir}/${build_mode}" \
        --pristine "$pristine" "$source" -- -DBOARD_ROOT=/repo/firmware "$@" "-DCONFIG_XIP=${xip}"
}

if [[ "${1:-}" == --container ]]; then
    shift
    container_build "$@"
    exit
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
action=build
board=uno-q
build_mode=ram
copy_to_recipe=false
builddir="${repo_dir}/build/zephyr"
app_source="${repo_dir}/firmware"
pristine=auto
cmake_args=()

help()
{
    cat <<EOF
Usage: $0 [options] [-- CMake arguments]

Build STM32 firmware in a prebuilt Zephyr ARM SDK container.

  --action build|shell   Build firmware (default) or open a configured shell
  --board <board>        uno-q (default), ventuno-q, or a full Zephyr target
  --mode ram|flash       Execute from SRAM (default) or STM32 flash
  --copy-to-recipe       Update the recipe's machine-named ELF after a RAM build
  --source <directory>   Zephyr sample path or a local application directory
                        (default: ${app_source})
  --builddir <directory> Workspace, Python dependencies and build output
                        (default: ${builddir})
  --image <image>        Prebuilt container image (default: ZEPHYR_IMAGE)
  --pristine auto|always|never
                        When to recreate build output (default: ${pristine})
  --help                Show this help

Environment:
  ZEPHYR_VERSION        Zephyr release (default: ${ZEPHYR_VERSION})
  ZEPHYR_IMAGE          Container image including the matching Zephyr SDK

Artifacts: <builddir>/output/<board>/<mode>/zephyr/zephyr.{elf,bin,hex}
--copy-to-recipe installs the ELF in meta-demo/recipes-bsp/zephyr-firmware/files/.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --action|--board|--mode|--source|--builddir|--image|--pristine)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 requires a value"
            case $1 in
                --action) action=$2 ;;
                --board) board=$2 ;;
                --mode) build_mode=$2 ;;
                --source) app_source=$2 ;;
                --builddir) builddir=$2 ;;
                --image) ZEPHYR_IMAGE=$2 ;;
                --pristine) pristine=$2 ;;
            esac
            shift 2
            ;;
        --copy-to-recipe) copy_to_recipe=true; shift ;;
        --help|-h) help; exit 0 ;;
        --) shift; cmake_args=("$@"); break ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ "$action" == build || "$action" == shell ]] || die "--action must be build or shell"
[[ "$build_mode" == ram || "$build_mode" == flash ]] || die "--mode must be ram or flash"
[[ "$pristine" == auto || "$pristine" == always || "$pristine" == never ]] || \
    die "--pristine must be auto, always or never"
[[ "$ZEPHYR_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    die "ZEPHYR_VERSION must be a release number such as 4.4.2"
case "$board" in
    uno-q|arduino_uno_q|arduino_uno_q/stm32u585xx)
        board=arduino_uno_q/stm32u585xx
        board_dir=uno-q
        ;;
    ventuno-q|arduino_ventuno_q|arduino_ventuno_q/stm32h5f5xx)
        board=arduino_ventuno_q/stm32h5f5xx
        board_dir=ventuno-q
        ;;
    *)
        if [[ ! "$board" =~ ^[a-zA-Z0-9_]+(@[a-zA-Z0-9_.-]+)?(/[a-zA-Z0-9_/.-]+)?$ || \
              "$board" == *..* ]]; then
            die "Invalid Zephyr board target: ${board}"
        fi
        board_dir=${board//\//_}
        ;;
esac
if [[ "$copy_to_recipe" == true ]]; then
    [[ "$action" == build && "$build_mode" == ram ]] || \
        die "--copy-to-recipe requires --action build and --mode ram"
    [[ "$board_dir" == uno-q || "$board_dir" == ventuno-q ]] || \
        die "--copy-to-recipe supports uno-q and ventuno-q"
fi
command -v docker >/dev/null 2>&1 || die "docker is not installed"

mkdir -p "$builddir"
builddir=$(cd -- "$builddir" && pwd)
mkdir -p "$builddir/work/manifest" "$builddir/cache"
docker_args=(run --rm --user "$(id -u):$(id -g)"
    --mount "type=bind,src=${repo_dir},dst=/repo,readonly"
    --mount "type=bind,src=${builddir},dst=/build"
    --workdir /build/work --entrypoint /bin/bash
    --env "ZEPHYR_VERSION=${ZEPHYR_VERSION}"
    # Docker Desktop on macOS shows bind mounts as another owner, so git in
    # the container refuses them ("dubious ownership")
    --env GIT_CONFIG_COUNT=1 --env GIT_CONFIG_KEY_0=safe.directory
    --env "GIT_CONFIG_VALUE_0=*")

# A source outside this repository can also be built without copying it.
if [[ -d "$app_source" ]]; then
    app_source=$(cd -- "$app_source" && pwd)
    docker_args+=(--mount "type=bind,src=${app_source},dst=/app,readonly")
    app_source=/app
elif [[ "$app_source" == /* || "$app_source" == ../* ]]; then
    die "Local source directory does not exist: ${app_source}"
fi
if [[ "$action" == shell ]]; then
    docker_args+=(-i)
    if [[ -t 0 && -t 1 ]]; then
        docker_args+=(-t)
    fi
fi

printf 'Zephyr: %s\nBoard: %s\nMode: %s\nImage: %s\nBuild directory: %s\n' \
    "$ZEPHYR_VERSION" "$board" "$build_mode" "$ZEPHYR_IMAGE" "$builddir"
docker "${docker_args[@]}" "$ZEPHYR_IMAGE" /repo/build-zephyr.sh --container \
    "$action" "$board" "$app_source" "$pristine" "$build_mode" ${cmake_args[@]+"${cmake_args[@]}"}
if [[ "$action" == build ]]; then
    printf '\nFirmware artifacts: %s/output/%s/%s/zephyr/\n' "$builddir" "$board_dir" "$build_mode"
    if [[ "$copy_to_recipe" == true ]]; then
        recipe_dir="${repo_dir}/meta-demo/recipes-bsp/zephyr-firmware/files"
        mkdir -p "$recipe_dir"
        install -m 0644 "$builddir/output/$board_dir/ram/zephyr/zephyr.elf" \
            "$recipe_dir/zephyr-$board_dir.elf"
        printf 'Updated recipe firmware: %s/zephyr-%s.elf\n' "$recipe_dir" "$board_dir"
    fi
fi
