# katugen

*matugen, but for KDE.*

Right-click any image in **Dolphin → Generate → Light/Dark** and your whole
desktop re-themes: KDE Plasma, Alacritty, kitty, foot, ghostty, wezterm,
starship, GTK 3/4, Qt 5/6, btop, helix, yazi, zathura, cava, BetterDiscord,
Vesktop, Vencord and friends, Zed, Emacs, Spicetify, Hyprland, Niri, Sway,
labwc, Mango, Scroll, Hyprtoolkit, fuzzel, walker, vicinae, Noctalia shell,
Zen Browser, Steam, Telegram Desktop, and Firefox via pywalfox.

For most apps katugen also **auto-edits the main config** (inserts the
`include`/`@import` line) and **fires the right live-reload signal** so you
don't have to restart anything.

Templates and post-hook patterns are adapted from
[noctalia-shell][noctalia], retuned for matugen 4.x.

[matugen]: https://github.com/InioX/matugen
[noctalia]: https://github.com/noctalia-dev/noctalia-shell

## Install

```sh
git clone https://github.com/notmugi/Katugen.git katugen
cd katugen
./install.sh
```

Re-run `./install.sh` any time — it's idempotent, and auto-picks-up apps you
install later. The installer only wires up apps whose config dir/file
actually exists on your system.

**Requires:** KDE Plasma 6, [matugen][matugen] 4.x (`yay -S matugen-bin`),
`realpath` (coreutils).

## Uninstall

```sh
./uninstall.sh           # remove generator + service menu + helpers
./uninstall.sh --purge   # also remove ~/.config/matugen/{config.toml,templates}
```

Generated theme files and the `include`/`@import` lines that post-hooks wrote
into your configs are **not** removed — clean those up by hand if you want a
fresh slate.

## Adding your own templates

Add a `[templates.foo]` block to `~/.config/matugen/config.toml` — that's it.
Template syntax is standard matugen; see the [matugen template docs][mtmpl].

Note: `./install.sh` regenerates `config.toml` from this project's registry,
so your custom entries get wiped on re-install. Only re-run install when you
need to pick up new built-in app support (or just save your blocks and paste
them back).

[mtmpl]: https://github.com/InioX/matugen/blob/main/docs/configuration/templates.md

## Per-app one-time setup

A handful of apps need a prerequisite before katugen can theme them. The rest
are fully automatic.

- **Firefox** — install [pywalfox][pywalfox], then run `pywalfox install` once.
- **Spicetify** — install Spotify + the Comfy theme. katugen overwrites
  Comfy's `color.ini`.
- **Steam** — install the Material Steam skin separately.
- **Wezterm** — your `wezterm.lua` must use `wezterm.config_builder()` and end with `return config`.

[pywalfox]: https://github.com/Frewacom/pywalfox-native

## Contributing — adding a new app

PRs welcome. To add support for a new app:

1. **Drop a matugen template** into `templates/`. Use any existing template
   as a reference for the syntax (`{{colors.primary.default.hex}}`, etc.).
   See [matugen template docs][mtmpl] for the full list of color names.

2. **Register the app** in the *Application registry* section of
   `install.sh`. The minimal form is:

   ```bash
   add_if "<marker>" <id> <template-relpath> "<output-path>" [<post-hook>]
   ```

   - `<marker>` — a file or directory that exists iff the user has the app
     (e.g. `~/.config/myapp` or `~/.config/myapp/config.toml`). Prefer a
     specific config file over a bare directory.
   - `<id>` — unique short name (matugen `[templates.<id>]` section).
   - `<template-relpath>` — path under `templates/`.
   - `<output-path>` — where matugen writes the rendered file. Keep `~`
     literal; matugen expands it at runtime.
   - `<post-hook>` (optional) — shell command run after each regeneration.
     Use `$APPLY_DST <app>` to call into `scripts/template-apply.sh`, or
     any shell command.

   Example:

   ```bash
   add_if "~/.config/myapp/config.toml" \
          myapp   myapp.toml   "~/.config/myapp/themes/matugen.toml" \
          "$APPLY_DST myapp"
   ```

3. **If your app needs config integration** (insert an `include` line, send
   a SIGUSR1, etc.) add a `myapp)` case to
   [`scripts/template-apply.sh`](scripts/template-apply.sh). It should be
   **idempotent** — running it twice must not produce duplicate lines.

4. **Test**:
   ```sh
   ./install.sh
   ~/.local/bin/matugen-generate.sh dark /path/to/test.jpg
   ```
   Re-run install three times and confirm "unchanged" each time.

5. **Open the PR.** Include in the description: app name + project URL,
   which Material You color names the template uses, and what (if anything)
   the post-hook does to the user's config.

## Troubleshooting

| Problem | Fix |
|---|---|
| Dolphin menu missing | `kbuildsycoca6 --noincremental` or log out/in |
| `matugen` "multiple source colors" | keep the `--prefer saturation` flag |
| App didn't refresh | check `~/.cache/matugen-generate.log` |
| KDE colors stuck | re-pick **Matugen** in *System Settings → Colors* once |

## Credits

Templates and helper scripts adapted from [noctalia-shell][noctalia] (GPLv3).
Matugen by [InioX][matugen]. Dolphin service-menu pattern from
[this r/kde post](https://www.reddit.com/r/kde/comments/1tprakb/kde_plasma_6_i_automated_material_you_colors/)
by u/Narcrop_.


## License

GPLv3. See [LICENSE](LICENSE).
