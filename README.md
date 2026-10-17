# Controller Dot Customizer

Customize or hide the white controller reticle dot in WoW Forever (build 1.60.1+).

Since build 1.60.1 the game shows a small white dot (`GamepadReticle`) in controller mode.
This addon lets you style it your way, or turn it off completely.

## Features

- Turn the reticle off completely
- Shape: default, square, circle, plus (+), cross (x)
- Color picker
- Transparency, size and line thickness sliders
- Works in combat (uses `SetAlpha`, never `Hide()`)

## Usage

| Command | Effect |
| --- | --- |
| `/dot` | Open the settings window |
| `/dot off` | Hide the reticle |
| `/dot on` | Show the reticle |
| `/dot toggle` | Toggle the reticle |
| `/dot reset` | Restore defaults |
| `/dot debug` | Print reticle state (for bug reports) |

**Note:** do not run this together with other addons that hide the reticle (such as NoDot), or the settings will have no visible effect.

## License

MIT
