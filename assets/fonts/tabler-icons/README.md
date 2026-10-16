# Tabler Icons (outline)

- Font: `tabler-icons.ttf`, the default outline set (2 px stroke) from the npm package **@tabler/icons-webfont 3.49.0**
  (https://registry.npmjs.org/@tabler/icons-webfont/-/icons-webfont-3.49.0.tgz, `dist/fonts/tabler-icons.ttf`;
  upstream: https://github.com/tabler/tabler-icons, release v3.49.0).
- Package sha1 (matches the registry): e80dafb28a9e65d99914fdf1fd25df4d50ac577f
- `tabler-icons.ttf` sha256: d291676dc4c28b386552753bf16cf2bef0e93e5543f8e0b5c5d72c0da41ae1bc (1827912 bytes)
- Licence: MIT, Copyright (c) 2020-2026 Paweł Kuna (`LICENSE` here is the package's own file). Unlike a commercial font, this one may live in the repo.
- Font family name: `tabler-icons`. In fontconfig patterns (fuzzel --font) the hyphen must be escaped: `tabler\-icons`.
- Installed by install.sh to ~/.local/share/fonts/hyprdeb/. Another installed font (Material Icons) uses some of the same private-use
  codepoints, so always name the family explicitly; never rely on fallback.
- `icons.map`: only the icons hyprdeb uses (name, codepoint), not the full 5247-entry map.
