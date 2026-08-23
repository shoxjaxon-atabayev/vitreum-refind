# Vitreum

A dark, minimal rEFInd boot theme — thin liquid-glass highlight on a
frosted emerald background, no heavy panels, no runtime effects (rEFInd
can't do those pre-boot; everything here is a pre-baked static asset).

## Install

### Recommended: `install.sh`

```
git clone https://github.com/shoxjaxon-atabayev/vitreum-refind.git
cd vitreum-refind
sudo ./install.sh
```

It finds your rEFInd install itself (checks `/boot/efi`, `/boot/EFI`,
`/efi`, `/boot`, and any other FAT-mounted volume for a `refind.conf`
sitting next to a real `refind_*.efi`), detects your display resolution
to pick the closest bucket, copies the theme to
`<refind-dir>/theme/vitreum/`, and adds a single managed
`include theme/vitreum/theme-<bucket>.conf` line to `refind.conf` —
backing it up first, and never touching anything else (no EFI boot
entries, no Secure Boot, no other bootloader config). Safe to re-run;
it won't duplicate the include line or corrupt an existing install.

Useful flags:

| Flag | Effect |
|---|---|
| `--dry-run` | show the plan, change nothing |
| `--bucket <sd\|hd\|hidpi\|ultrawide>` | override resolution detection |
| `--refind-dir <path>` | skip auto-detection, use this dir directly |
| `--yes` | skip the confirmation prompt |
| `--uninstall` | remove Vitreum and revert `refind.conf` |

### Manual install

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

- `install.sh` — the installer described above (also handles `--uninstall`).
- `theme.conf` — settings shared by every bucket (icon sizes, selection
  highlight, `icons_dir`).
- `theme-<bucket>.conf` — one per resolution, includes `theme.conf` and
  adds only the background for that bucket.
- `background-<bucket>.png` — the frosted-glass backdrop.
- `selection-big.png` / `selection-small.png` (+ `@2x` for HiDPI) — the
  glass highlight behind the focused entry.
- `icons/` — the OS icon set, named per rEFInd's `os_*`/`tool_*`/`vol_*`
  convention; swap in your own if you'd rather.
- `src/` — HTML sources the baked PNGs were rendered from, plus the
  original wallpaper they're derived from, kept for regeneration.