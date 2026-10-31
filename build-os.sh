#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$(readlink -f -- "$0")")"

action="build"
builddir="$PWD/build"
dl_dir="${builddir}/downloads"
kas_workdir="${builddir}/work"
kasfile=""
lockfile="locks/qli-2.1.lock.yml"
overlays=()
sstate_dir="${builddir}/sstate-cache"
target=""
update_zephyr=false

help()
{
    echo "Usage parameters:"
    echo "(Required)"
    echo "--kasfile: initial kas yaml file"
    echo "(Optional)"
    echo "--action: build|shell (default: ${action})"
    echo "--builddir: location for build files (default: ${builddir})"
    echo "--dl-dir: location for Yocto/OE downloads (default: ${dl_dir})"
    echo "--kas-workdir: location for kas layers (default: ${kas_workdir})"
    echo "--lock: kas lock file pinning the Qualcomm layers (default: ${lockfile}; see locks/)"
    echo "--overlay: kas file adding to the build, e.g. kas/demo-health.yml (repeatable)"
    echo "--sstate-dir: location for Yocto/OE sstate cache (default: ${sstate_dir})"
    echo "--target: Yocto/OE image (optional; overrides kas configuration)"
    echo "--update-zephyr: rebuild the RAM firmware and update the recipe's ELF before running kas (built anyway when missing)"
}

parse_args()
{
    while [ $# -gt 0 ]
    do
        case $1 in
        --action)
            action="$2"
            shift
            shift
            ;;
        --builddir)
            builddir="$2"
            shift
            shift
            ;;
        --dl-dir)
            dl_dir="$2"
            shift
            shift
            ;;
        --kasfile)
            kasfile="$2"
            shift
            shift
            ;;
        --kas-workdir)
            kas_workdir="$2"
            shift
            shift
            ;;
        --lock)
            lockfile="$2"
            shift
            shift
            ;;
        --overlay)
            overlays+=("$2")
            shift
            shift
            ;;
        --sstate-dir)
            sstate_dir="$2"
            shift
            shift
            ;;
        --target)
            target="$2"
            shift
            shift
            ;;
        --update-zephyr)
            update_zephyr=true
            shift
            ;;
        --help)
            help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            exit 1
            ;;
        esac
    done
}

parse_args "$@"

export DL_DIR="${dl_dir}"
export KAS_WORK_DIR="${kas_workdir}"
export SSTATE_DIR="${sstate_dir}"
if [ -n "${target}" ] ; then
    export KAS_TARGET="${target}"
fi

mkdir -p "${builddir}" "${DL_DIR}" "${SSTATE_DIR}" "${KAS_WORK_DIR}"

if ! command -v kas-container >/dev/null 2>&1; then
    echo "Error: kas-container is not installed." >&2
    exit 1
fi

if [ -z "${kasfile}" ] ; then
    echo "ERROR: --kasfile not set" >&2
    exit 1
fi

if [ ! -f "${kasfile}" ] ; then
    echo "ERROR: No such file ${kasfile}" >&2
    exit 1
fi

if [ ! -f "${lockfile}" ] ; then
    echo "ERROR: No such lock file ${lockfile}" >&2
    exit 1
fi

for overlay in "${overlays[@]}"; do
    if [ ! -f "${overlay}" ] ; then
        echo "ERROR: No such overlay ${overlay}" >&2
        exit 1
    fi
done

# Both boards build their Wi-Fi profiles from the same untracked file, so
# create it once with a random passphrase and reuse it for every build.
wifi_conf="meta-demo/recipes-connectivity/demo-wifi/files/wifi.conf"
if [ ! -f "${wifi_conf}" ]; then
    wifi_psk="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
    sed -e "s|^WIFI_PSK=.*|WIFI_PSK=\"${wifi_psk}\"|" \
        "${wifi_conf}.example" > "${wifi_conf}"
    echo "Created ${wifi_conf} with a random Wi-Fi passphrase"
fi

# The MCU firmware isn't tracked: build it when the recipe has none for this
# board, and rebuild it when explicitly requested.
case "$(basename -- "$kasfile")" in
    uno-q.yml) zephyr_board="uno-q" ;;
    ventuno-q.yml) zephyr_board="ventuno-q" ;;
    *) zephyr_board="" ;;
esac
if [ "${update_zephyr}" = true ] && [ -z "${zephyr_board}" ]; then
    echo "ERROR: --update-zephyr requires uno-q.yml or ventuno-q.yml" >&2
    exit 1
fi
zephyr_elf="meta-demo/recipes-bsp/zephyr-firmware/files/zephyr-${zephyr_board}.elf"
if [ -n "${zephyr_board}" ] && [ ! -f "${zephyr_elf}" ]; then
    echo "No ${zephyr_elf}: building the MCU firmware first"
    update_zephyr=true
fi
if [ "${update_zephyr}" = true ]; then
    ./build-zephyr.sh --board "${zephyr_board}" --mode ram --copy-to-recipe
fi

echo "Settings summary:"
echo "action     : ${action}"
echo "builddir   : ${builddir}"
echo "dl-dir     : ${DL_DIR}"
echo "sstate-dir : ${SSTATE_DIR}"
echo "kas-workdir: ${KAS_WORK_DIR}"
echo "kasfile    : ${kasfile}"
echo "lock       : ${lockfile}"
echo "overlays   : ${overlays[*]:-none}"
if [ -n "${KAS_TARGET:-}" ] ; then
    echo "target     : ${KAS_TARGET}"
fi
echo "update-zephyr: ${update_zephyr}"
echo ""

# Overlays add to the board's kas file; the lock comes last, so its branches
# and commits win
kas_chain="${kasfile}"
for overlay in "${overlays[@]}"; do
    kas_chain="${kas_chain}:${overlay}"
done
exec kas-container "${action}" "${kas_chain}:${lockfile}"
