# Vitreum

A dark, minimal rEFInd boot theme — thin liquid-glass highlight on a
frosted emerald background, no heavy panels, no runtime effects (rEFInd
can't do those pre-boot; everything here is a pre-baked static asset).

## Install

1. Copy this directory into your rEFInd install, e.g.
   `/boot/EFI/refind/theme/vitreum/`.
2. In `refind.conf`, include the bucket file matching your screen
   resolution:

   ```
   include theme/vitreum/theme-hd.conf
   ```

   Available buckets: `theme-sd.conf` (1366×768), `theme-hd.conf`
   (1920×1080), `theme-hidpi.conf` (3840×2160), `theme-ultrawide.conf`
   (3440×1440). Each sets its background 1:1 to that resolution — picking
   the wrong bucket won't break anything, but the background will be
   scaled instead of pixel-perfect.
3. Drop your OS icon set into `icons/`, named per rEFInd's own
   `os_*` / `tool_*` / `vol_*` convention, plus an `os_unknown.png`
   fallback. rEFInd falls back to its built-in icons for anything
   missing.

## Layout

- `theme.conf` — settings shared by every bucket (icon sizes, selection
  highlight, `icons_dir`).
- `theme-<bucket>.conf` — one per resolution, includes `theme.conf` and
  adds only the background for that bucket.
- `background-<bucket>.png` — the frosted-glass backdrop.
- `selection-big.png` / `selection-small.png` (+ `@2x` for HiDPI) — the
  glass highlight behind the focused entry.
- `icons/` — empty; drop your icon set here.
- `src/` — HTML sources the baked PNGs were rendered from, plus the
  original wallpaper they're derived from, kept for regeneration.

See `PROJECT_SPEC.md` (local, untracked) for the full design spec.
