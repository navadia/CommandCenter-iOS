# Command Center logo: Sunrise List

The day's list with the sun coming up over it. Your mornings, cleared.

## Files

| File | Use |
|---|---|
| `symbol-color.svg` | Main mark on light backgrounds |
| `symbol-on-dark.svg` | Main mark on Night or other dark backgrounds |
| `symbol-black.svg` / `symbol-white.svg` | One-color versions (print, stamps, overlays) |
| `symbol-mono-coral.svg` | One-color in brand Coral |
| `lockup-color.svg` / `lockup-on-dark.svg` / `lockup-black.svg` | Mark + "Command Center" (text is outlined, no font needed) |
| `app-icon-light.svg` / `app-icon-dark.svg` | Rounded icon tiles for docs and mockups |
| `ios/AppIcon-light.png`, `-dark.png`, `-tinted.png` | 1024 px iOS icons (square; iOS rounds the corners) |
| `*-1024.png`, `*-2000.png` | Ready-made PNGs |
| `logo-sheet.png` | One-page overview |

## Colors

| Name | HEX | RGB | Role |
|---|---|---|---|
| Night | #1A1633 | 26 22 51 | Background, text |
| Amber | #FFB020 | 255 176 32 | Top of the sun gradient |
| Orange | #FF7A1A | 255 122 26 | App accent (buttons, links) |
| Coral | #FF5A4E | 255 90 78 | Base of the sun gradient |
| Cream | #FFF4E6 | 255 244 230 | Bars on dark, light backgrounds |

The type in the lockup is Inter Display SemiBold.

## Rules

- **Clear space:** keep one bar height empty around the mark on every side.
- **Minimum size:** symbol 16 px; lockup 120 px wide. Below 24 px use the symbol alone.
- **Backgrounds:** Night, Cream, white, or the Amber-to-Coral gradient (mark in white).
- **Gradient:** the sun runs Amber at the top to Coral at the base. Don't flip it or swap in blue.
- **Don't** stretch, rotate, re-space the bars, or add shadows. iOS adds its own glass.

## Notes

- **Bar spacing:** the gap between the bars is 16 units (out of 256), wider than the sketch, so the bars stay separate at 20 pt in Settings.
- **App icon:** the light icon is the default. iOS switches to the dark icon in Dark mode, and in Tinted mode it colors the grey version with your chosen tint.
