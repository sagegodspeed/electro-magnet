# Electro Magnet icon

Original artwork generated with the built-in imagegen tool on 2026-10-06. The design uses three window panels and a return arrow to represent remembering and restoring an arrangement. The transparent exterior surrounds a blue rounded icon plate. No text or third-party logo is included.

- `ElectroMagnet-source-v1.png`: untouched generated source, 1254 × 1254 pixels, RGBA.
- `ElectroMagnet-1024.png`: 1024 × 1024 PNG export with alpha preserved.
- `ElectroMagnet.icns`: standard macOS icon package containing ten representations from 16 to 1024 pixels.
- `prompt.txt`: exact generation prompt; built-in imagegen mode, no API key or CLI fallback.

The ICNS was compiled and unpacked with Apple's `iconutil`; all ten exported dimensions and alpha channels were checked. The 64-pixel representation was visually inspected.

`Tools/build-app.sh` copies the ICNS into the app's Resources directory and sets `CFBundleIconFile`. The menu-bar symbol remains the native monochrome system symbol. The working installed app is left unchanged; the new icon will appear when a future build is installed.

This is flattened raster artwork. A future Icon Composer version would need separate layers and appearance variants; this file is not presented as a layered Liquid Glass icon.
