# katugen

*matugen, but for KDE.*

Right-click any image in **Dolphin** → **Generate** → **Light** or **Dark**, and
katugen generates a full Material You colorscheme with [matugen][matugen] and
applies it across every app you have installed: KDE Plasma, Alacritty, kitty,
foot, ghostty, wezterm, starship, GTK 3/4, Qt 5/6, btop, helix, yazi, zathura,
cava, BetterDiscord, Vesktop, Vencord, Equibop and the rest of the Discord
ecosystem, Zed, Emacs, Spicetify, Hyprland, Niri, Sway, labwc, Mango, Scroll,
Hyprtoolkit, fuzzel, walker, vicinae, Noctalia shell, Zen Browser, Steam,
Telegram Desktop — and Firefox via pywalfox.

For most apps, katugen also **auto-edits the app's main config** so the new
theme is picked up automatically (e.g. it inserts an `include` line into
`fuzzel.ini`, `theme = "matugen"` into `walker/config.toml`, an `@import` into
`gtk-3.0/gtk.css`, etc.) and sends a live-reload signal where supported (D-Bus
to KDE/zathura, `SIGUSR1` to kitty/cava, `hyprctl reload`, …).

Templates and post-hook patterns are adapted from
[noctalia-shell][noctalia], retuned for matugen 4.x.

[matugen]: https://github.com/InioX/matugen
[noctalia]: https://github.com/noctalia-dev/noctalia-shell

## How it works

```
Right-click image
    ↓
Generate → Light / Dark   (Dolphin service menu)
    ↓
~/.local/bin/matugen-generate.sh <mode> <image>
    ↓
plasma-apply-wallpaperimage          ← sets KDE wallpaper
matugen image --mode <mode>          ← generates all themes
    ↓
For each enabled template, matugen runs its post_hook:
    kde-apply-scheme.py    → merges into kdeglobals, signals KDE apps via D-Bus
    gtk-refresh.py         → ensures @import in gtk.css, sets gsettings color-scheme
    template-apply.sh kitty   → kitty +kitten themes --reload-in=all matugen
    template-apply.sh alacritty → adds import to alacritty.toml
    template-apply.sh fuzzel  → adds include= to fuzzel.ini
    template-apply.sh pywalfox <mode> → pywalfox update; pywalfox <mode>
    ...
```

### Auto-detection

You don't pick which integrations to enable. The installer reads
[`config/templates.tsv`](config/templates.tsv) and only wires up apps whose
config dir actually exists. Re-run `./install.sh` after installing a new app
and it'll be picked up automatically.

Two integrations are *always* installed: the KDE color scheme (the point of
katugen) and the pywalfox cache.

## Requirements

- **KDE Plasma 6** (Plasma 5 should also work — the service menu spec is the same)
- **matugen ≥ 4.x** — `yay -S matugen-bin` on Arch
- `realpath`, `python3` (stdlib only by default; `jeepney` if you want the
  faster D-Bus path)
- *Optional:* `plasma-apply-wallpaperimage`, `gsettings` / `dconf`,
  `notify-send`, `pywalfox`

## Install

```sh
git clone https://github.com/notmugi/Katugen.git
cd katugen
./install.sh
```

The installer is idempotent — re-run it any time. It only overwrites files
whose content actually differs, backing up the old version to
`*.bak-YYYYmmddHHMMSS`.

Where things go:

```
~/.config/matugen/templates/                       (all template files)
~/.config/matugen/config.toml                      (generated; only your installed apps)
~/.local/bin/matugen-generate.sh                   (the generator script)
~/.local/share/katugen/template-apply.sh           (post-hook applier)
~/.local/share/katugen/python/*.py                 (KDE + GTK helpers)
~/.local/share/kio/servicemenus/matugen-generate.desktop   (Dolphin menu)
```

## Per-app notes

Most apps are handled automatically by post-hooks — you don't need to touch
them. A handful need a one-time prerequisite:

- **Firefox** — install the [pywalfox add-on](https://github.com/Frewacom/pywalfox-native)
  and run `pywalfox install` once. After that katugen runs
  `pywalfox update && pywalfox <mode>` on every regeneration.
- **Spicetify** — install Spotify and the Comfy spicetify theme. katugen
  overwrites `~/.config/spicetify/Themes/Comfy/color.ini` and runs
  `spicetify -q apply --no-restart`.
- **Steam** — install the Material Steam skin separately; katugen writes
  its colors file into the skin's `colors/` directory.
- **Wezterm** — needs an existing `~/.config/wezterm/wezterm.lua` with
  `local config = wezterm.config_builder()` and `return config`.
- **Zen Browser** — katugen stages CSS into `~/.cache/katugen/zen-browser/`
  and the post-hook injects an `@import` into every active profile's
  `chrome/userChrome.css` and `userContent.css`.

For everything else (kitty, foot, ghostty, alacritty, fuzzel, walker, yazi,
cava, btop, niri, sway, hyprland, labwc, mango, scroll, vicinae, KDE, GTK,
Qt, BetterDiscord, Vesktop, Vencord, …) the post-hooks handle config
integration and live-reload automatically.

## Uninstall

```sh
./uninstall.sh           # removes generator, service menu, helper dir
./uninstall.sh --purge   # also removes ~/.config/matugen/{config.toml,templates}
```

Generated outputs (`~/.local/share/color-schemes/matugen.colors`,
`~/.config/gtk-3.0/matugen.css`, …) are never removed — delete those manually
for a fully clean slate. The post-hooks **do not unwind** their config edits;
the `include`/`@import` lines they wrote stay until you remove them by hand.

## Customizing

- **Add a new app** → drop a matugen-syntax template into `templates/`, add a
  row to `config/templates.tsv` (`id  template_relpath  marker_dir
  output_path  post_hook`), re-run `./install.sh`.
- **Change a template** → edit under `templates/` and re-run.
- **Change a post-hook** → edit `scripts/template-apply.sh` and re-run.

Template registry format: see comments at the top of
[`config/templates.tsv`](config/templates.tsv).

Template syntax reference: [matugen template docs][mtmpl].

[mtmpl]: https://github.com/InioX/matugen/blob/main/docs/configuration/templates.md

## Troubleshooting

- **Menu doesn't appear in Dolphin** — run `kbuildsycoca6 --noincremental`,
  or log out and back in.
- **`matugen` errors about "multiple source colors"** — the generator script
  already passes `--prefer saturation`; keep that flag if you customize.
- **An app didn't refresh** — check `~/.cache/matugen-generate.log` for the
  post-hook output. The post-hook for that app may need an additional
  one-time setup step (see *Per-app notes*).
- **KDE doesn't refresh** — verify `jeepney` or `dbus-send` is available;
  `kde-apply-scheme.py` uses one of them to signal `notifyChange` to all KDE
  apps.

## Credits

- Templates, post-hook patterns, and the KDE + GTK helper scripts adapted
  from [noctalia-shell][noctalia] by Ly-sec.
- matugen by [InioX][matugen].
- Dolphin service-menu pattern adapted from
  [this r/kde post](https://www.reddit.com/r/kde/comments/1tprakb/kde_plasma_6_i_automated_material_you_colors/)
  by u/Narcrop_.

## License

MIT.
