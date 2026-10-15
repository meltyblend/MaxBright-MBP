# MaxBright

A tiny menu bar app that unlocks the full brightness of a MacBook Pro's Liquid Retina XDR display for everyday (SDR) content: text, apps, the desktop. That's normally capped at 500–600 nits, while the panel can sustain 1000 nits full-screen.

## Requirements

- MacBook Pro with a Liquid Retina XDR display (M1–M4 Pro/Max, 14" or 16"), or another EDR-capable display
- macOS 13 Ventura or later
- Xcode or the Command Line Tools (`xcode-select --install`) to build

## Build and install

```sh
./build.sh            # builds build/MaxBright.app
./build.sh install    # also copies it to /Applications and launches it
```

## Using it

Click the sun icon in the menu bar:

- **Switch**: turns the boost on or off.
- **Maximum brightness**: how far above the standard maximum to go, from +0% to +100%. Changes apply live. The panel shows the resulting white level in nits, read from the display driver.
- **Launch at login**: starts MaxBright when you log in.
- **Pause on battery power** / **Pause when battery is below 20%**: saves battery when unplugged.

### Brightness keys

With **Brightness keys go past maximum** on (the default), F1 and F2 work as one continuous brightness range:

- Below full system brightness, the keys work exactly as usual.
- At full system brightness, F2 (brightness up) turns the boost back on at its last level. Each further press raises it 10%, up to +100%.
- F1 (brightness down) lowers the boost 10% per press. When it reaches zero the boost turns off, and the next F1 lowers system brightness as usual.
- Hold ⌥⇧ for 2.5% steps.

A small indicator near the bottom of the screen shows the boost level and the resulting nits.

While the panel is in EDR mode, macOS drops brightness-key presses or changes the setting without dimming the screen. EDR mode includes the several seconds the panel takes to leave it after the boost turns off, and any time other HDR content is on screen. In that state MaxBright applies the brightness step itself, and the indicator shows the regular brightness level.

Reading the brightness keys needs **Accessibility** permission. MaxBright asks the first time it launches. If you dismissed the request, use **Grant access…** in the menu, or turn on MaxBright under System Settings › Privacy & Security › Accessibility. `./build.sh install` clears the old grant because each rebuild needs to be approved again.

### Keyboard shortcuts

These work from anywhere, with no permission needed:

| Shortcut | Action |
| --- | --- |
| ⌃⌥⌘B | Toggle the boost |
| ⌃⌥⌘= | Brighter (+10%) |
| ⌃⌥⌘− | Dimmer (−10%) |

## How it works

1. **Enter EDR mode.** MaxBright keeps a 1×1 point, fully transparent window on each XDR display. Its Metal layer asks for extended dynamic range (EDR) content. That makes macOS switch the panel into EDR mode, the same way it does for HDR video. The backlight is then driven past the SDR limit and "headroom" above SDR white becomes available.
2. **Scale the gamma table.** It multiplies the display's gamma (transfer) table by the boost factor. In EDR mode the table can go above 1.0, so SDR white is drawn brighter than SDR white normally is.
3. **Stay within headroom.** The boost is always capped at the display's current EDR headroom, so highlights never clip. Headroom shrinks as system brightness rises and when the panel is warm, and MaxBright follows it twice a second.
4. **Recover from resets.** If something resets the gamma table (wake from sleep, display changes, Night Shift), MaxBright notices and re-applies the boost.

When you turn the boost off or quit, the original gamma table is restored. If the app crashes, macOS restores it automatically.

## Caveats

- Running the panel at 1000 nits uses more power and makes the display warmer. macOS protects the panel by reducing headroom when it gets hot, and MaxBright follows it.
- Apps that also change gamma tables (f.lux, Lunar, Gamma Control) will fight with MaxBright. Use one at a time.
- HDR video is also scaled while the boost is on, so its brightest highlights may clip. Toggle off with ⌃⌥⌘B when watching HDR.
- Screenshots and screen recordings are unaffected.

## Uninstall

Quit MaxBright from its menu, then delete `/Applications/MaxBright.app`. To also clear its settings, run `defaults delete io.github.maxbright`.

## License

MIT. See [LICENSE](LICENSE).
