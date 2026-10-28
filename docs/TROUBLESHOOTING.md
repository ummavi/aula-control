# Troubleshooting

## The receiver cannot be opened

Connect the 2.4 GHz dongle and switch the keyboard to 2.4G. The app requires the supported vendor interface; Bluetooth typing and a USB charging cable do not provide that interface. Leave only one matching receiver connected.

If macOS reports `E00002E2` or asks for Input Monitoring:

1. Finish building, quit AULA Control, and place the final app bundle in a stable folder.
2. Open **System Settings → Privacy & Security → Input Monitoring**.
3. Enable AULA Control. If it is absent, click **+**, press **⌘⇧G**, and enter its installation folder.
4. Select `AULA Control.app`, click **Open**, enable it, and reopen the app.

`~/Applications` is your personal Applications folder. `/Applications` is the system-wide folder. If you copied the app into the first one, it will not appear in the second. Add the exact installed copy you intend to run.

An ad-hoc signed rebuild can invalidate an older grant. If an existing entry remains ineffective after reopening and toggling it, quit the app and reset **only this project's grant**:

```sh
tccutil reset ListenEvent org.aulacontrol.AulaControl
```

This removes the existing permission entry. Add the installed app with **+** afterward; do not wait for the old entry to reappear automatically. Do not reset all Input Monitoring permissions. Developer builds before the neutral project identifier used a different identifier and do not share the new build's grant.

Input Monitoring is needed for access to this HID interface. The app retains only vendor report `13` and discards normal typing input. It does not log keystrokes.

## The keyboard stops typing

Quit AULA Control and other keyboard configuration tools. If typing does not return, switch the keyboard off and back on, leaving it in 2.4G mode. If needed, unplug and reconnect the receiver. Avoid sending more settings while ordinary typing is unavailable.

One stoppage reported during development cleared after restarting the keyboard. Its cause has not been established or reproduced. Record whether the lights stayed on, whether quitting the app helped, and whether the same problem occurs with the app closed. A returned lighting configuration does not establish that normal typing is working. Do not use a factory reset, firmware update, or snapshot restoration as the first recovery step.

## The receiver returns incomplete data or does not reply

An incomplete response does not establish that the keyboard is asleep. Check the dongle, connection mode, and whether the keyboard is responsive, then retry **Read from keyboard** or Apply. Close other keyboard configuration tools while testing. If the issue persists, try a direct USB connection for the receiver rather than a hub and collect the exact error.

The app retries missing read pages and validates their consistency. A preparation failure says that no settings were sent. A transfer failure means some packets may have been sent; retry Apply to send the complete lighting setup. A verification failure means settings were sent but final returned data could not be confirmed.

## The app selection differs from the keyboard

Controls are drafts until Apply. Loading a preset changes the draft first. Physical Fn changes are picked up by **Read from keyboard**, not continuously. A failed initial connection leaves default controls visible; those defaults are not a measurement of the keyboard.

Read the keyboard after granting access or changing settings physically. The connection label reflects the last successful read. It is not a continuous link monitor.

## An effect changes but the color looks wrong

Use a standard swatch first. All seven full-scale RGB combinations were physically checked on the tested keyboard. Main presets and swatches send device values separately from their softer UI presentation colors. The hex field shows the actual RGB value sent; the swatch, selected chip, and preview use the display palette.

Pale RGB mixtures contain several bright channels and can appear near white on the LEDs. A former mint-green value `A6F2BA` produced that appearance through both Reactive and per-key lighting. Keeping the effect and brightness unchanged and changing only RGB to `00FF00` produced green. This distinction is not a calibrated conversion between screen color and physical light.

Rainbow and some other effects manage their own spectra. Side strips and the light bar offer built-in colors rather than arbitrary RGB editing. Paint mode uses each key's channel values for intensity instead of the main brightness field.

If receiver read-back matches but the physical result is still wrong, report both facts separately. Include the zone, effect, exact RGB or swatch, brightness, and whether the same behavior occurs after **Read from keyboard** and Apply. Do not assume an echo proves that the LEDs updated.

## Restoring a snapshot

Automatic backups are under `~/Library/Application Support/AULA Control/Backups`. Close other instances of the app before deliberately restoring one:

```sh
'build/AULA Control.app/Contents/MacOS/AulaControl' --restore-backup PATH
```

Restoration writes the complete saved configuration and color data, including auxiliary settings and other configuration fields. It checks identity and returned data and leaves key mappings untouched. Prefer changing a single lighting control in the UI when a full configuration restoration is unnecessary.

## Reporting a problem

Include the exact model, macOS version, app version, receiver connection mode, error text, and visible keyboard behavior. `--diagnose` is a read-only starting point. Remove personal paths from pasted output. Raw backups and the preset library contain more information than most reports need; do not attach them by default.
