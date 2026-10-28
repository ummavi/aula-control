# Plain F108 wireless lighting protocol

This reference describes the tested plain F108 through its 2.4 GHz receiver. Fields observed on this firmware must not be treated as a specification for every AULA keyboard. F108 Pro uses a different controller and is outside this implementation.

## Device selection

The HID manager matches vendor `0x3554`, product `0xFA09`, and primary usage page `0xFF02`. The tested vendor interface has usage 2. The connection opens without seizing ordinary keyboard input. A complete snapshot must contain the identity prefix `03 00 00 00 01 BA` and the expected data lengths before an Apply can proceed.

The tested full identity was `03 00 00 00 01 BA 01 00 00 00`. These bytes are a model/firmware identifier, not evidence that another unit with the same USB IDs supports every field below.

## Report format

Each output and input report contains 20 bytes:

| Offset | Meaning |
| --- | --- |
| 0 | Report ID `13` |
| 1 | Command |
| 2 | Number of pages |
| 3 | Zero-based page index |
| 4 | Payload length, up to 14 bytes; the high nibble can select a bank |
| 5–18 | Payload, with unused bytes zero in generated reports |
| 19 | Sum of bytes 0–18, modulo 256 |

The current writer uses bank 0. Read requests use page count 1, page index 0, and a zero length. For example, a configuration read begins `13 44 01 00` and has checksum `58`.

Read responses must have valid checksums, consistent page counts, and one page for every index. Padding beyond a short page's declared length is excluded from data comparisons. No missing bytes are fabricated.

| Command | Direction | Data |
| --- | --- | --- |
| `44` | Read | 128-byte configuration, ending `5A A5` |
| `49` | Read | 490 palette bytes |
| `41` | Read | 504 key-map bytes, 126 entries of four bytes |
| `05` | Read | Device identity; a separate status report may follow |
| `42` | Read | 378 per-key color bytes |
| `04` | Write | 128-byte configuration in 10 pages |
| `09` | Write | 512-byte main palette in 37 pages |
| `02` | Write | 378 per-key color bytes in 27 pages |

An incoming `0A` status report can expose battery percentage when its checked fields identify that payload. The app does not issue `0A` as a save command. It does not write key maps, reset the keyboard, or update firmware.

## Main lighting configuration

Configuration byte 9 is 1 for Paint mode and 0 for built-in main effects. Byte 10 selects the effect. For modes 1–18, parameters start at:

```text
brightness offset = 58 + 2 × (effect − 1)
flags offset      = brightness offset + 1
```

Brightness is 0–4. The flags byte stores speed 0–4 in the high nibble and color selector 0–7 in the low nibble. Selectors 0–6 choose RGB entries from that effect's palette row; 7 selects multicolor. Custom RGB Apply writes entry 0 and selects 0. Rainbow, Windmill, Waterfall, and Blossom use their own spectra in this interface.

| ID | UI effect | ID | UI effect |
| --- | --- | --- | --- |
| 1 | Solid | 10 | Snake |
| 2 | Breathing | 11 | Neon stream |
| 3 | Rainbow | 12 | Reactive |
| 4 | Flash away | 13 | Sine wave |
| 5 | Raindrops | 14 | Scanning |
| 6 | Color wheel | 15 | Windmill |
| 7 | Ripples | 16 | Waterfall |
| 8 | Starlight | 17 | Blossom |
| 9 | Fading trail | 18 | Storm |
| 21 | Paint keys | 0 | Main lights off |

The ordering follows the plain F108 OEM configuration. Not every animated effect's physical appearance has been checked; preview names and animation models are not a firmware emulator.

Ordinary main Apply changes only bytes 9, 10, and the selected effect's two parameter bytes. In particular, it preserves debounce at byte 3, the profile selector at byte 11, auxiliary fields, and other configuration data.

## Main palette

Read and write sizes differ. A palette read yields 490 bytes. A write reconstructs the OEM 512-byte buffer:

| Byte range | Write contents |
| --- | --- |
| 0–20 | Reserved zeros |
| 21–419 | 19 rows of seven RGB triples |
| 420–505 | Reserved zeros |
| 506–507 | Marker `5A A5` |
| 508–511 | Reserved zeros |

For a built-in effect 1–18 and selector 0–6:

```text
RGB offset = 21 × effect + 3 × selector
```

Channels are red, green, blue. Other main color entries are retained. Do not copy the entire read buffer directly into the write buffer: reserved regions can contain nonzero data. The canonical writer clears those regions. It does not preserve the additional read rows after byte 419.

Built-in Apply sends **configuration `04` followed by palette `09`**. This matches the inspected OEM apply routine and the tested sequence. An older palette-before-configuration implementation could return matching data while visible parameters remained stale. A matching echo or read response is insufficient evidence of active LED state.

## Per-key colors and LED positions

Command `02` sends three planes of 126 bytes: all red values, then all green values, then all blue values. It has exactly 378 bytes, with no extra marker or trailer. Missing color entries are black. Configuration follows the planes, selecting effect 21 and profile byte 9 equal to 1.

LED positions are decoded from the device's own four-byte key-map entries:

- `00 00 00 usage` identifies an ordinary USB keyboard usage.
- A single modifier bit in the second byte maps to usages 224–231.
- Entry type `0D` represents Fn using an internal sentinel.
- Entry type `02` combines the final two bytes into a consumer usage.

The 108 displayed keycaps map to entries in the 126-position device matrix. Positions without a physical displayed key can still exist in the map. The application reads this matrix and never writes it.

## Auxiliary lighting

Both auxiliary zones reside in the configuration rather than the main custom-RGB writer:

| Zone | Effect | Color selector | Brightness | Speed |
| --- | --- | --- | --- | --- |
| Side strips | 18 | 19 | 20 | 21 |
| Bar above arrows | 28 | 29 | 30 | 31 |

Effects are 0 Off, 1 moving Rainbow, 2 Color cycle, and 3 Solid. The bar additionally supports 4 Breathing. Color selectors are 0 red, 1 green, 2 blue, 3 yellow, 4 magenta, 5 cyan, 6 white, and 7 multicolor. The UI exposes seven fixed colors; arbitrary auxiliary RGB is not established. Brightness and speed fields use 0–4.

These brightness/speed offsets were identified by native Fn changes on the tested keyboard. The generic OEM side-light serializer interchanges the final two fields relative to this firmware; copying it without hardware comparisons would produce the wrong controls here.

Auxiliary Apply sends **configuration `04` only**. It merges only user-edited controls into a fresh snapshot, preserving later native Fn changes in other controls. Verification checks the complete configuration and confirms that the palette, key map, and per-key data were unchanged.

## Transfer handling and restoration

Writes run serially on the UI model's worker queue. Input reports arrive on a separate HID dispatch queue with a condition-protected inbox. The HID client requests 256 report buffers of 64 bytes to accommodate palette bursts. Ordinary keyboard input reports are discarded.

Reads retry up to six times and retain consistent pages between attempts. A different overlapping payload or page count discards the earlier assembly. Writes require an exact packet echo and retry the same page up to three times before stopping. Writes pause 20 ms per page; reads pause 30 ms before requesting. Missing replies do not prove that the keyboard is asleep.

Every Apply first reads a complete snapshot and saves a local backup. Preparation failures send no settings. Transfer and verification failures are reported separately. If several zones are applied and a later one fails, the app reports which earlier zones completed.

Restoration checks identity, backs up the current state, writes the saved configuration and color data, and checks read-back. For built-in effects it restores per-key data first, then configuration, then the canonical palette. Paint and Off restoration write the palette, then per-key data, and finish with configuration. Restoring a backup replaces the **entire saved configuration**, including auxiliary and other configuration fields. It leaves key mappings untouched and canonicalizes palette padding.

## Sources

- [Official plain F108 driver](https://aulagear.com/blogs/software/aula-f108-driver): OEM configuration, serializer layout, and apply order.
- [Official plain F108 manual](https://aulagear.com/blogs/manuals/aula-f108-manual): native lighting shortcuts.
- [Aula-Manager](https://github.com/free-soldier28/Aula-Manager): initial shared wireless framing reference; its attribution is retained.
- [F99 Pro protocol notes](https://github.com/dnviti/aula-x99-pro-driver-linux/blob/master/PROTOCOL.md): related read-command reference, not authority for F108-specific offsets.

No proprietary driver executable, manual PDF, or device dump is included in this repository.
