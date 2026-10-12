# External asset inventory

This document inventories every asset the desktop environment references that
is **not** version-controlled in this repository. For each asset it records
where it lives, how the configuration references it, who supplies it, its
licensing status, and how to obtain or verify it.

None of these assets are committed to the repository. The reasons are given
per asset and fall into three categories:

- **Unverified licensing/provenance** — the file's license or origin cannot
  be established, so redistribution would be unsafe.
- **Size** — the asset is large (tens to hundreds of MB); binary blobs do not
  belong in this repository.
- **System-level location** — the asset belongs to `/usr/local/` or `/etc/`,
  requires root privileges, and is documented as a manual operation instead.

## Inventory summary

| Asset | Referenced by | Supplier | License | Decision |
|-------|---------------|----------|---------|----------|
| `wallpaper.png` | `configs/sway/config.d/10-wallpaper.conf` | user-provided (origin unknown) | **unverified** | manual placement |
| JetBrainsMono Nerd Font | `configs/alacritty/`, `configs/waybar/`, `configs/dunst/`, `configs/swaylock/` | ryanoasis/nerd-fonts | SIL OFL 1.1 (verified in font metadata) | upstream download |
| `Tokyonight-BL-MB-Dark-Moon` GTK theme | `configs/gtk/gtk-{3.0,4.0}/settings.ini` | Fausto-Korpsvart/Tokyonight-GTK-Theme | GPL-3.0 (verified) | upstream download |
| Papirus-Dark icons | `configs/gtk/gtk-{3.0,4.0}/settings.ini` | PapirusDevelopmentTeam | GPL-3.0-only AND CC-BY-SA-4.0 AND LGPL-3.0-or-later (verified) | package prerequisite |
| TokyoNight SDDM theme | `/etc/sddm.conf.d/99-tokyonight.conf` | derivative of Fedora `03-sway-fedora` + user edits | CC-BY-SA-3.0 AND MIT (upstream) | manual root operation |
| `tokyonight-login.png` | `/usr/local/share/sddm/themes/TokyoNight/theme.conf` | user-provided (origin unknown) | **unverified** | manual placement |

## 1. Desktop wallpaper

- **Exists on this host:** yes — `~/.local/share/backgrounds/wallpaper.png`
  (PNG, 3840×2160, ~1.5 MB, no embedded metadata identifying its source).
- **Referenced by:** `configs/sway/config.d/10-wallpaper.conf`:
  `output * bg ~/.local/share/backgrounds/wallpaper.png fill`
- **Supplier:** user-provided. Provenance is unknown; the PNG contains no
  `tEXt`/`iTXt` chunks.
- **License:** **unverified.** Do not redistribute.
- **Decision:** do not commit. Place the file manually.
- **Integrity reference** (sha256 of the copy on this host, for comparing
  your own copy):

  ```text
  7efbab6ecfb19b5236a3a8c13d7dda4913dd5f87a5572d5210d8ac8900bc7346  wallpaper.png
  ```

- **Manual installation:**

  ```bash
  mkdir -p ~/.local/share/backgrounds
  cp /path/to/your/wallpaper.png ~/.local/share/backgrounds/wallpaper.png
  sha256sum ~/.local/share/backgrounds/wallpaper.png   # compare with the hash above
  ```

- **Verification:** `ls -l ~/.local/share/backgrounds/wallpaper.png`
  The restoration script reports a warning during `--check`/`--apply` if this
  file is missing, because Sway would fail to apply the wallpaper without it.

## 2. JetBrainsMono Nerd Font

- **Exists on this host:** yes — `~/.local/share/fonts/JetBrainsMono/`
  (98 TTF files, ~233 MB).
- **Referenced by:**
  - `configs/alacritty/alacritty.toml` — `JetBrainsMono Nerd Font` (size 12)
  - `configs/waybar/style.css` — `font-family: "JetBrainsMono Nerd Font"`
  - `configs/dunst/dunstrc` — `font = JetBrainsMono Nerd Font 10`
  - `configs/swaylock/config` — `font="JetBrainsMono Nerd Font"` (size 18)
  - the SDDM theme's clock (`timeFont.family`)
- **Supplier:** [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts)
  (official release page: <https://github.com/ryanoasis/nerd-fonts/releases>).
- **License:** SIL Open Font License 1.1 — verified directly from the
  embedded `name` table of `JetBrainsMonoNerdFont-Regular.ttf` on this host.
  (The Nerd Fonts patcher is MIT; the embedded license metadata in the
  distributed font is OFL 1.1.)
- **Decision:** do not commit — ~233 MB of binaries. Download from the
  official upstream release.
- **Manual installation:**

  ```bash
  # Download the JetBrainsMono Nerd Font release archive from
  # https://github.com/ryanoasis/nerd-fonts/releases (asset:
  # JetBrainsMono.zip), then:
  mkdir -p ~/.local/share/fonts/JetBrainsMono
  unzip -o JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono
  fc-cache -f ~/.local/share/fonts/JetBrainsMono
  ```

- **Verification:**

  ```bash
  fc-match "JetBrainsMono Nerd Font"
  # expected: a JetBrainsMonoNerdFont-*.ttf path, e.g.
  # /home/you/.local/share/fonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf: "JetBrainsMono Nerd Font" "Regular"
  ```

  The restoration script warns if the family is not resolvable.

## 3. GTK theme — `Tokyonight-BL-MB-Dark-Moon`

- **Exists on this host:** yes — `~/.themes/Tokyonight-BL-MB-Dark-Moon/`
  (GTK 2/3/4, gnome-shell, cinnamon, metacity, xfwm4 variants).
- **Referenced by:** `configs/gtk/gtk-3.0/settings.ini` and
  `configs/gtk/gtk-4.0/settings.ini` (`gtk-theme-name`).
- **Supplier:** [Fausto-Korpsvart/Tokyonight-GTK-Theme](https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme)
  (archived October 2026, GPL-3.0). The theme name `Tokyonight-BL-MB-Dark-Moon`
  matches the upstream naming convention: BL = Borderless, MB = macOS Buttons,
  Dark-Moon = color variant.
- **License:** GPL-3.0 — verified from the upstream repository's `LICENSE`
  file and the GitHub repository metadata. The upstream `install.sh` supports
  the `-n` parameter to customize the theme name, confirming that
  `Tokyonight-BL-MB-Dark-Moon` is a renamed variant of the upstream theme.
- **Decision:** do not commit — the full theme package is large (multiple
  variants, hundreds of CSS/asset files). Download from the upstream source.
- **Note:** the theme's `index.theme` references `IconTheme=Tela-circle-Dark`
  and `CursorTheme=Tokyonight-BL-MB-cursors`; neither is installed on this
  host. The effective icon theme comes from gsettings (`Papirus-Dark`) and
  the effective cursor theme is the Adwaita default. GTK applications are not
  affected by the missing references because the gsettings values take
  precedence for icons, and the missing cursor theme falls back to the
  default.
- **Manual installation:**

  ```bash
  # Clone the upstream repository
  git clone https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme.git
  cd Tokyonight-GTK-Theme

  # Install only the Dark-Moon variant with the desired name
  ./install.sh --tweaks moon -t blue -c dark -n "Tokyonight-BL-MB-Dark-Moon"

  # Requires: gtk-murrine-engine (sudo dnf install gtk-murrine-engine)
  ```

  Alternatively, download a pre-built theme pack from
  [pling.com](https://www.pling.com/p/1681315/) and extract to `~/.themes/`.

- **Verification:** `ls -d ~/.themes/Tokyonight-BL-MB-Dark-Moon`
  The restoration script warns if this directory is missing.

## 4. Icon theme — Papirus-Dark

- **Exists on this host:** yes — `~/.local/share/icons/Papirus-Dark/`
  (~33 MB; the full `Papirus` set is ~376 MB).
- **Referenced by:** `configs/gtk/gtk-3.0/settings.ini` and
  `configs/gtk/gtk-4.0/settings.ini` (`gtk-icon-theme-name`), and by dconf
  (`org.gnome.desktop.interface icon-theme`).
- **Supplier:** [PapirusDevelopmentTeam/papirus-icon-theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme).
  Packaged for Fedora as `papirus-icon-theme` (verified in the Fedora
  package database for Fedora 44:
  <https://packages.fedoraproject.org/pkgs/papirus-icon-theme/papirus-icon-theme/>).
- **License:** GPL-3.0-only AND CC-BY-SA-4.0 AND LGPL-3.0-or-later
  (per the Fedora package metadata).
- **Decision:** do not commit — 33+ MB of icons. Install as a package.
  Because this is Fedora Sway Atomic (rpm-ostree), packages are layered and
  require a reboot; this is a **manual prerequisite**, never performed by the
  restoration script.
- **Manual installation (Fedora Sway Atomic):**

  ```bash
  sudo rpm-ostree install papirus-icon-theme
  sudo systemctl reboot
  ```

  Alternatively, on non-Atomic Fedora: `sudo dnf install papirus-icon-theme`.
  Or use the upstream installer from the Papirus GitHub repository.

- **Verification:** `ls -d /usr/share/icons/Papirus-Dark` (package install) or
  `ls -d ~/.local/share/icons/Papirus-Dark` (manual install).
  The restoration script warns if neither location exists.

## 5. SDDM TokyoNight theme

- **Exists on this host:** yes — `/usr/local/share/sddm/themes/TokyoNight/`.
- **Referenced by:** `/etc/sddm.conf.d/99-tokyonight.conf`
  (`Current=TokyoNight`, `ThemeDir=/usr/local/share/sddm/themes`).
- **Supplier:** derivative work — copied from Fedora's `03-sway-fedora`
  theme (present on this host at `/usr/share/sddm/themes/03-sway-fedora`,
  upstream: <https://gitlab.com/fedora/sigs/sway/sway-config-fedora>) and
  then customized. Upstream metadata: Fedora Sway SIG, License
  CC-BY-SA-3.0 AND MIT, based on the Maldives SDDM theme by Abdurrahman
  AVCI; chevron icons from Font Awesome by Dave Gandy; `rectangle.png` from
  the KDM ariya theme.
- **License:** the upstream theme is CC-BY-SA-3.0 AND MIT (a `LICENSE` file
  with the CC BY-SA 3.0 text ships in the theme directory). The custom
  `Main.qml` modifications on this host are the owner's own work.
- **Decision:** do not commit. System-level path, root privileges required,
  and the custom `Main.qml` is not version-controlled. Fully documented as a
  manual operation in [system/sddm/README.md](../system/sddm/README.md),
  which also records the exact customizations applied.

## 6. SDDM login wallpaper

- **Exists on this host:** yes — `/usr/local/share/backgrounds/tokyonight-login.png`
  (~30 KB).
- **Referenced by:** `/usr/local/share/sddm/themes/TokyoNight/theme.conf`:
  `background=/usr/local/share/backgrounds/tokyonight-login.png`
- **Supplier:** user-provided (origin unknown).
- **License:** **unverified.** Do not redistribute.
- **Decision:** do not commit. Manual placement as part of the SDDM
  installation procedure (see [system/sddm/README.md](../system/sddm/README.md)).
- **Integrity reference:**

  ```text
  e79af4a7f971efc53b8ba5912e305a470d73d93484d9f9472b0995b6d4db554f  tokyonight-login.png
  ```
