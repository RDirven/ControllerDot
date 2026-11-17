# Controller Dot Customizer

Customize or hide the white controller reticle dot in WoW Forever (build 1.60.1+).

Since build 1.60.1 the game shows a small white dot (`GamepadReticle`) in controller mode.
This addon lets you style it your way, or turn it off completely.

## Features

- Turn the reticle off completely (hidden by default; use `/dot on` or the settings window to show it)
- Shape: default, square, diamond, circle, plus (+), cross (x), crosshair (plus with a gap)
- Color picker, plus optional color by target: red for hostile, yellow for neutral, green for friendly
- Optional black outline (0-4 px) so the dot stays visible on bright backgrounds
- Show the reticle always, only in combat, only out of combat, or only with a target
- Transparency, size and line thickness sliders
- Settings page under Options > AddOns, plus a small movable window (`/dot`) that leaves the screen center free so you can see the reticle while editing
- Works in combat (uses `SetAlpha`, never `Hide()`)

## Usage

| Command | Effect |
| --- | --- |
| `/dot` | Open the small settings window |
| `/dot options` | Open the page in the Blizzard options window |
| `/dot off` | Hide the reticle |
| `/dot on` | Show the reticle |
| `/dot toggle` | Toggle the reticle |
| `/dot show always\|combat\|outofcombat\|target` | Choose when the reticle is shown |
| `/dot reset` | Restore the style settings (the reticle stays on or off as you set it) |
| `/dot debug` | Print reticle state (for bug reports) |

"Show when" only has an effect while the reticle is turned on. In the settings, left-click a shape or "show when" button for the next value and right-click for the previous one. The outline only applies to custom shapes, not to the default shape.

**Note:** do not run this together with other addons that hide the reticle (such as NoDot), or the settings will have no visible effect.

## License

MIT
