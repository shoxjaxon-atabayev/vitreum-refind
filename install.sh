#!/usr/bin/env bash
# Vitreum rEFInd theme installer.
#
# Usage:
#   sudo ./install.sh                  auto-detect everything, install
#   sudo ./install.sh --bucket hd      force a resolution bucket
#   sudo ./install.sh --refind-dir P   skip auto-detection, use P (dir holding refind.conf)
#   sudo ./install.sh --dry-run        show what would happen, change nothing
#   sudo ./install.sh --yes            skip the confirmation prompt
#   sudo ./install.sh --uninstall      remove Vitreum, revert refind.conf
#
# Only ever touches: <refind-dir>/theme/vitreum/ and the Vitreum-managed
# block inside refind.conf. Never touches EFI boot entries, Secure Boot,
# or any other bootloader.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_BEGIN="# BEGIN Vitreum theme (managed by install.sh — do not edit this block by hand)"
MARKER_END="# END Vitreum theme"
THEME_SUBDIR="theme/vitreum"

BUCKET_OVERRIDE=""
REFIND_DIR_OVERRIDE=""
DRY_RUN=0
ASSUME_YES=0
UNINSTALL=0

# ---------------------------------------------------------------- output --

c_red()   { printf '\033[31m%s\033[0m' "$1"; }
c_green() { printf '\033[32m%s\033[0m' "$1"; }
c_yellow(){ printf '\033[33m%s\033[0m' "$1"; }

info()  { printf '  %s\n' "$1"; }
ok()    { printf '%s %s\n' "$(c_green '[ok]')" "$1"; }
warn()  { printf '%s %s\n' "$(c_yellow '[warn]')" "$1"; }
die()   { printf '%s %s\n' "$(c_red '[error]')" "$1" >&2; exit 1; }

# --------------------------------------------------------------- helpers --

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "must run as root (sudo $0 ...) — refind.conf and the ESP are root-owned."
  fi
}

timestamp() { date +%Y%m%d-%H%M%S; }

# Print a path guaranteed not to exist yet, starting from "$1-$(timestamp)"
# and adding a numeric suffix on collision (two runs in the same second,
# repeated dry immediate re-runs, etc. must never clobber/merge backups).
unique_backup_path() {
  local base candidate n
  base="$1-$(timestamp)"
  candidate="$base"
  n=2
  while [ -e "$candidate" ]; do
    candidate="${base}-${n}"
    n=$((n + 1))
  done
  printf '%s\n' "$candidate"
}

# Find every plausible ESP/boot mount root, deduplicated.
candidate_roots() {
  local roots=(/boot/efi /boot/EFI /efi /boot)
  if command -v findmnt >/dev/null 2>&1; then
    while IFS= read -r line; do
      [ -n "$line" ] && roots+=("$line")
    done < <(findmnt -rno TARGET,FSTYPE 2>/dev/null | awk '$2 ~ /vfat|fat32|fat/ {print $1}')
  fi
  local seen="" root
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    case ",$seen," in *",$root,"*) continue ;; esac
    seen="$seen,$root"
    printf '%s\n' "$root"
  done
}

# Look for refind.conf under each candidate root, keep only ones that sit
# beside an actual rEFInd binary (i.e. a real install, not a stray file).
# Candidate roots often overlap in practice — the ESP mounted at both
# /boot/efi and /boot/EFI (or /efi as well), a bind mount, a symlink — so
# dedup by the (device, inode) of refind.conf itself, not by path string,
# or the same install shows up twice and install.sh refuses to proceed.
find_refind_installs() {
  local root conf dir key found=""
  while IFS= read -r root; do
    while IFS= read -r conf; do
      dir="$(dirname "$conf")"
      ls "$dir"/refind_*.efi >/dev/null 2>&1 || continue
      key="$(stat -c '%d:%i' "$conf" 2>/dev/null || printf 'path:%s' "$conf")"
      case ",$found," in *",$key,"*) continue ;; esac
      found="$found,$key"
      printf '%s\n' "$dir"
    done < <(find "$root" -maxdepth 5 -iname 'refind.conf' 2>/dev/null)
  done < <(candidate_roots)
}

is_refind_install_dir() {
  local dir="$1"
  [ -f "$dir/refind.conf" ] || return 1
  ls "$dir"/refind_*.efi >/dev/null 2>&1 || return 1
  return 0
}

detect_resolution() {
  local f status_file modes_file first_mode raw w h res

  for status_file in /sys/class/drm/*/status; do
    [ -r "$status_file" ] || continue
    [ "$(cat "$status_file" 2>/dev/null)" = "connected" ] || continue
    modes_file="${status_file%status}modes"
    [ -r "$modes_file" ] || continue
    first_mode="$(head -n1 "$modes_file" 2>/dev/null || true)"
    if [[ "$first_mode" =~ ^([0-9]+)x([0-9]+)$ ]]; then
      printf '%sx%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0
    fi
  done

  if [ -r /sys/class/graphics/fb0/virtual_size ]; then
    raw="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)"
    w="${raw%%,*}"; h="${raw##*,}"
    if [[ "$w" =~ ^[0-9]+$ ]] && [[ "$h" =~ ^[0-9]+$ ]] && [ "$w" -gt 0 ] 2>/dev/null && [ "$h" -gt 0 ] 2>/dev/null; then
      printf '%sx%s\n' "$w" "$h"
      return 0
    fi
  fi

  if command -v xrandr >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    res="$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"
    if [[ "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
      printf '%s\n' "$res"
      return 0
    fi
  fi

  return 1
}

# Map a WxH string to a Vitreum bucket name.
resolution_to_bucket() {
  local wh="$1" w h ratio_x100
  w="${wh%x*}"; h="${wh#*x}"
  [[ "$w" =~ ^[0-9]+$ ]] && [[ "$h" =~ ^[0-9]+$ ]] && [ "$h" -gt 0 ] || { echo hd; return; }

  ratio_x100=$(( w * 100 / h ))

  if [ "$ratio_x100" -ge 210 ]; then
    echo ultrawide
  elif [ "$w" -ge 3840 ] || [ "$h" -ge 2160 ]; then
    echo hidpi
  elif [ "$w" -ge 1600 ]; then
    echo hd
  else
    echo sd
  fi
}

required_assets() {
  cat <<'EOF'
theme.conf
theme-sd.conf
theme-hd.conf
theme-hidpi.conf
theme-ultrawide.conf
background-sd.png
background-hd.png
background-hidpi.png
background-ultrawide.png
selection-big.png
selection-small.png
selection-big@2x.png
selection-small@2x.png
EOF
}

validate_source_assets() {
  local missing=0 f
  while IFS= read -r f; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
      warn "missing source asset: $f"
      missing=1
    fi
  done < <(required_assets)
  [ -d "$SCRIPT_DIR/icons" ] || { warn "missing source directory: icons/"; missing=1; }
  if [ "$missing" -eq 1 ]; then
    die "theme source is incomplete — run this script from inside the vitreum-refind checkout."
  fi
}

# Remove any existing Vitreum-managed block from a conf file, print result
# to stdout (caller redirects to a temp file). Safe to run on a file with
# no block at all.
strip_managed_block() {
  local conf="$1"
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    skip { next }
    { print }
  ' "$conf"
}

# ------------------------------------------------------------------ main --

do_install() {
  local resolution bucket refind_dir target_dir conf backup tmp installs count

  echo "Vitreum rEFInd theme installer"
  echo

  echo "-- locating rEFInd --"
  if [ -n "$REFIND_DIR_OVERRIDE" ]; then
    refind_dir="$REFIND_DIR_OVERRIDE"
    is_refind_install_dir "$refind_dir" \
      || die "$refind_dir does not look like a rEFInd install (need refind.conf + refind_*.efi)."
  else
    mapfile -t installs < <(find_refind_installs)
    count="${#installs[@]}"
    if [ "$count" -eq 0 ]; then
      die "no rEFInd install found under /boot/efi, /boot/EFI, /efi, /boot (or any mounted FAT volume). Pass --refind-dir explicitly."
    elif [ "$count" -gt 1 ]; then
      warn "multiple rEFInd installs found:"
      printf '    %s\n' "${installs[@]}"
      die "ambiguous — re-run with --refind-dir <path> to pick one."
    fi
    refind_dir="${installs[0]}"
  fi
  ok "rEFInd install: $refind_dir"
  conf="$refind_dir/refind.conf"

  echo
  echo "-- picking a resolution bucket --"
  if [ -n "$BUCKET_OVERRIDE" ]; then
    bucket="$BUCKET_OVERRIDE"
    ok "bucket forced: $bucket"
  elif resolution="$(detect_resolution)"; then
    bucket="$(resolution_to_bucket "$resolution")"
    ok "detected ${resolution}, matched bucket: $bucket"
  else
    bucket="hd"
    warn "could not detect display resolution — falling back to safest default: $bucket"
  fi
  case "$bucket" in
    sd|hd|hidpi|ultrawide) ;;
    *) die "invalid bucket '$bucket' (expected sd, hd, hidpi, or ultrawide)." ;;
  esac

  echo
  echo "-- validating theme assets --"
  validate_source_assets
  ok "all required assets present in $SCRIPT_DIR"

  target_dir="$refind_dir/$THEME_SUBDIR"

  echo
  echo "-- plan --"
  info "source:        $SCRIPT_DIR"
  info "refind.conf:   $conf"
  info "install to:    $target_dir"
  info "bucket:        $bucket"
  info "conf line:     include $THEME_SUBDIR/theme-$bucket.conf"
  echo

  if [ "$DRY_RUN" -eq 1 ]; then
    warn "dry run — no changes made."
    return 0
  fi

  if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Proceed? [y/N] " reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *) die "aborted by user." ;;
    esac
  fi

  echo
  echo "-- installing --"

  # Back up an existing Vitreum install (rename, never delete) so a
  # user-customized icons/ set is never silently lost.
  if [ -d "$target_dir" ]; then
    backup="$(unique_backup_path "${target_dir}.backup")"
    mv "$target_dir" "$backup"
    ok "backed up previous install to $backup"
  fi

  mkdir -p "$target_dir"
  while IFS= read -r f; do
    install -m 0644 "$SCRIPT_DIR/$f" "$target_dir/$f"
  done < <(required_assets)
  # Plain cp -r, not -a: the ESP is FAT, which has no per-file ownership
  # at all, so "preserve ownership" (what -a/-p do) fails with EPERM even
  # as root — FAT only supports it as a fs-wide mount option, not a
  # per-file chown target.
  cp -r "$SCRIPT_DIR/icons" "$target_dir/icons"
  ok "copied theme files to $target_dir"

  # Update refind.conf: strip any prior Vitreum block, then append a
  # fresh one. Back up first — but only if this run actually changes
  # anything, so re-running with the same bucket doesn't pile up backups.
  tmp="$(mktemp)"
  # Command substitution strips all trailing newlines/blank lines from the
  # stripped content, so re-running this never piles up blank lines before
  # the marker block (that would make cmp below see a spurious diff).
  body="$(strip_managed_block "$conf")"
  {
    [ -n "$body" ] && printf '%s\n\n' "$body"
    echo "$MARKER_BEGIN"
    echo "include $THEME_SUBDIR/theme-$bucket.conf"
    echo "$MARKER_END"
  } > "$tmp"

  if cmp -s "$tmp" "$conf"; then
    rm -f "$tmp"
    ok "refind.conf already up to date, nothing to change"
  else
    backup="$(unique_backup_path "${conf}.vitreum-backup")"
    cp "$conf" "$backup"
    cat "$tmp" > "$conf"
    rm -f "$tmp"
    ok "refind.conf updated (backup: $backup)"
  fi

  echo
  ok "Vitreum installed."
  info "location: $target_dir"
  info "bucket:   $bucket"
  info "reboot to see it — if anything looks wrong, run: sudo $0 --uninstall"
}

do_uninstall() {
  local refind_dir target_dir conf tmp backup latest_backup

  echo "Vitreum rEFInd theme uninstaller"
  echo

  if [ -n "$REFIND_DIR_OVERRIDE" ]; then
    refind_dir="$REFIND_DIR_OVERRIDE"
  else
    mapfile -t installs < <(find_refind_installs)
    if [ "${#installs[@]}" -eq 0 ]; then
      die "no rEFInd install found. Pass --refind-dir explicitly."
    elif [ "${#installs[@]}" -gt 1 ]; then
      warn "multiple rEFInd installs found:"
      printf '    %s\n' "${installs[@]}"
      die "ambiguous — re-run with --refind-dir <path> to pick one."
    fi
    refind_dir="${installs[0]}"
  fi
  conf="$refind_dir/refind.conf"
  target_dir="$refind_dir/$THEME_SUBDIR"

  if [ "$DRY_RUN" -eq 1 ]; then
    warn "dry run — would remove $target_dir and the Vitreum block from $conf."
    return 0
  fi

  if [ -f "$conf" ]; then
    if grep -qF "$MARKER_BEGIN" "$conf"; then
      tmp="$(mktemp)"
      strip_managed_block "$conf" > "$tmp"
      backup="$(unique_backup_path "${conf}.vitreum-backup")"
      cp "$conf" "$backup"
      cat "$tmp" > "$conf"
      rm -f "$tmp"
      ok "removed Vitreum block from $conf (backup: $backup)"
    else
      info "no Vitreum block found in $conf — leaving it untouched."
      latest_backup="$(ls -t "${conf}".vitreum-backup-* 2>/dev/null | head -n1 || true)"
      # Deliberately not auto-restored: we can't tell whether this backup
      # predates Vitreum entirely or is mid-history, and restoring the
      # wrong one would silently discard the user's own later edits.
      [ -n "$latest_backup" ] && info "a backup exists if you want to restore it by hand: $latest_backup"
    fi
  fi

  if [ -d "$target_dir" ]; then
    rm -rf "$target_dir"
    ok "removed $target_dir"
  else
    info "$target_dir not present — nothing to remove."
  fi

  echo
  ok "Vitreum uninstalled."
}

# --------------------------------------------------------------- parsing --

while [ $# -gt 0 ]; do
  case "$1" in
    --bucket) BUCKET_OVERRIDE="${2:-}"; shift 2 ;;
    --bucket=*) BUCKET_OVERRIDE="${1#*=}"; shift ;;
    --refind-dir) REFIND_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    --refind-dir=*) REFIND_DIR_OVERRIDE="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

if [ "$DRY_RUN" -ne 1 ]; then
  require_root
fi

if [ "$UNINSTALL" -eq 1 ]; then
  do_uninstall
else
  do_install
fi
