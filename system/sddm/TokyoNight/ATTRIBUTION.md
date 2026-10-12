# SDDM TokyoNight theme attribution

This theme is a derivative work based on Fedora's `03-sway-fedora` SDDM theme.

## Upstream

- **Project:** Fedora Sway SDDM theme
- **Source:** `/usr/share/sddm/themes/03-sway-fedora` on Fedora Sway Atomic
- **Upstream repository:** https://gitlab.com/fedora/sigs/sway/sway-config-fedora
- **Authors:** Fedora Sway SIG (original), Aleksei Bavshin (Fedora modifications)
- **License:** CC-BY-SA-3.0 AND MIT

## License

The upstream `Main.qml` is licensed under the MIT license. The full MIT license
text is included in the `Main.qml` file header (Copyright (c) 2013 Abdurrahman
AVCI, Copyright (c) 2024 Aleksei Bavshin).

The `metadata.desktop` declares `License=CC-BY-SA-3.0 AND MIT`, reflecting the
mixed provenance of the upstream theme (the Maldives SDDM theme by Abdurrahman
AVCI is CC-BY-SA-3.0; the Fedora modifications by Aleksei Bavshin are MIT).

## Custom modifications

The `Main.qml` in this directory is a modified version of the upstream
`/usr/share/sddm/themes/03-sway-fedora/Main.qml`. The customizations are:

- Clock: Tokyo Night foreground `#c0caf5`, font `JetBrainsMono Nerd Font`
- Login panel: replaced upstream `Image` rectangle with a `Rectangle` colored
  `#1a1b26`, `radius: 12`, `border.color: #414868`, `border.width: 1`, anchored
  to the right/bottom edges with 60 px margins
- Text colors: Tokyo Night palette (`#c0caf5` foreground, `#1a1b26` panel fill)
- Buttons: `color: #24283b`, `textColor: #c0caf5`, `borderColor: #414868`,
  `activeColor: #3d59a1`, `pressedColor: #1a1b26`, `radius: 7`
- `theme.conf`: `background=/usr/local/share/backgrounds/tokyonight-login.png`

These customizations are the repository owner's own work, derived from the
MIT-licensed upstream file.
