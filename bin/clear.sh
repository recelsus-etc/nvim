#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-n] [-y] [-h]

  -n, --dry-run  Show what would be deleted
  -y, --yes      Delete without prompting
  -h, --help     Show this help
EOF
}

dry_run=false
assume_yes=false
for argument in "$@"; do
    case "$argument" in
        -n | --dry-run) dry_run=true ;;
        -y | --yes) assume_yes=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "${HOME:-}" ]]; then
    echo "HOME is not set" >&2
    exit 1
fi

appname="${NVIM_APPNAME:-nvim}"
if [[ -z "$appname" || "$appname" == *..* || "$appname" == /* ]]; then
    echo "Invalid NVIM_APPNAME: $appname" >&2
    exit 1
fi

candidates=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/$appname"
    "${XDG_STATE_HOME:-$HOME/.local/state}/$appname"
    "${XDG_CACHE_HOME:-$HOME/.cache}/$appname"
)
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$appname"

targets=()
for path in "${candidates[@]}"; do
    if [[ "$path" != /* || "$(basename "$path")" != "$appname" || "$path" == "$config_dir" ]]; then
        echo "Refusing unsafe path: $path" >&2
        exit 1
    fi
    if [[ -e "$path" || -L "$path" ]]; then
        targets+=("$path")
    fi
done

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "Nothing to delete."
    exit 0
fi

echo "The following directories will be deleted:"
for path in "${targets[@]}"; do
    size="$(du -sh "$path" 2>/dev/null | cut -f1 || true)"
    printf '  %s (%s)\n' "$path" "${size:-?}"
done

if command -v pgrep >/dev/null 2>&1 && pgrep -x nvim >/dev/null 2>&1; then
    echo "Warning: nvim is running. Files may be recreated when it exits." >&2
fi

if $dry_run; then
    echo "Dry run: nothing deleted."
    exit 0
fi

if ! $assume_yes; then
    read -r -p "Delete these directories? [y/N] " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

for path in "${targets[@]}"; do
    rm -rf -- "$path"
    echo "Deleted: $path"
done
