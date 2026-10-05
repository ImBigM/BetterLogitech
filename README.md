
# G903 LIGHTSPEED Pair / Unpair

## Quick Start

Want to use your favorite Logitech gaming mouse, the G903, with multiple computers without constantly unplugging and swapping receivers?

This tool lets you quickly pair your G903 with different computers

What you need:

1. Download python latest version
2. Buy one or more additional Logitech LIGHTSPEED receivers. You can find them on Amazon, eBay, AliExpress, and other online stores.
 (Make sure the receiver is compatible with the G903 / LIGHTSPEED. (Lightspeed G903 C-U0008 is the model))
3. Download Unpair-Mouse.bat and Pair-Mouse.bat (or just download the entire repository as a ZIP.
4. Run Pair-Mouse.bat and follow the instructions.
5. The tool will create a keyboard shortcut so you can start the pairing process without using the mouse. This is useful because the mouse may disconnect from the current receiver when it is re-paired to another one.
   
NOTE: Unpair the mouse or shut down the computer it is currently paired with, as the mouse will continue trying to connect to that computer.

## **🚨 Keyboard shortcuts:🚨**
**To pair: CTRL + ALT + X**  
**To unpair: CTRL + ALT + C**




## Description

The typical use case: one mouse, two receivers (for example a desktop and a laptop). Run the pairing tool on the computer you want to switch the mouse to, switch the mouse off and on, and you are done.

It sends the same HID++ 1.0 command that G HUB sends when you click "Begin Pairing".

## Contents

| File | What it does |
|---|---|
| `Pair-Mouse.bat` | Launcher for pairing. Installs dependencies, creates a Start Menu shortcut (`Ctrl+Alt+X`). |
| `Unpair-Mouse.bat` | Single-file tool that removes all devices linked to the receiver,creates a Start Menu shortcut (`Ctrl+Alt+C`). |


## Requirements

- Windows (the `.bat` launchers are Windows only)
- [Python 3](https://www.python.org/downloads/) available as `python` or `py`
- The [`hidapi`](https://pypi.org/project/hidapi/) package, which the launchers install automatically on first run
- A Logitech LIGHTSPEED receiver plugged into this computer
- G HUB and other Logitech software closed (they can keep the receiver open and block access)


### Switching the mouse between two computers

1. Plug the receiver into each computer (each computer has its own receiver).
2. On previous computer run `Unpair-Mouse.bat`
3. On the computer you want to use the mouse with, run `Pair-Mouse.bat`.
4. Switch the mouse off and on.

The mouse is bound to one receiver at a time, so pairing it on one computer releases it from the receiver on the other.

After that you can press `Ctrl+Alt+X` or `Ctrl+Alt+C`anywhere in Windows to start pairing or unpairing, or type "Pair Mouse"/"Unpair Mouse" in the Start menu.

Notes:

- Windows can take a few seconds to register a new hotkey. If it does not work right away, just wait 5 seconds.
Files downloaded from the internet are marked as blocked, so Windows shows *"The publisher could not be verified. Are you sure you want to run this software?"*
Both files also remove the block from itself after the first run.

## Usage in CMD

### Pairing

```
Pair-Mouse.bat                  pairs the mouse
Pair-Mouse.bat --verbose        show raw HID++ messages (debugging)
Pair-Mouse.bat --ascii          plain [OK]/[X] symbols instead of Unicode
Pair-Mouse.bat --pid 0xC539     specify the receiver PID manually
Pair-Mouse.bat --long           use long HID++ messages instead of short ones
```
### Unpairing
Removes every device linked to the receiver connected to this computer. The mouse stops working on this computer until you pair it again.

```
Unpair-Mouse.bat               unpairs the mouse
Unpair-Mouse.bat --verbose     show raw HID++ messages
Unpair-Mouse.bat --ascii       plain [OK]/[X] symbols
Unpair-Mouse.bat --pid 0xC539  specify the receiver PID manually
Unpair-Mouse.bat --long        use long HID++ messages
```

## Supported receivers

The tools look for Logitech (VID `0x046D`) receivers with one of these product IDs:

Developed and tested with a G903 and a receiver with PID `0xC539`. If your receiver has a different PID, find it with `python g903_pair.py list` and pass it with `--pid`.

## Troubleshooting

| Problem | What to try |
|---|---|
| `Python was not found` | Install Python 3 from python.org and run the bat again. |
| `No receiver found` | Plug in the receiver and close G HUB and other Logitech software. Run `python g903_pair.py list` to see what is detected, then use `--pid`. |
| `Could not access the receiver` | Another program has the receiver open. Close G HUB (also from the system tray) and try again. |
| `Could not start pairing mode` | Run with `--verbose` to see the receiver error. Try `--long`. |
| `Pairing failed` | Switch the mouse off and on right after the prompt appears, then run again. |
| `No confirmation received` | The receiver did not report the result. If the mouse works, you are done; otherwise run again. |
| Strange symbols in the output | Use `--ascii`. |
| `hidapi` fails to install | Run `python -m pip install hidapi` manually and check the error. |

## How it works

The receiver is controlled over HID++ 1.0 through register `0xB2`, using short (7 byte) messages by default or long (20 byte) messages with `--long`:

- `0x01` opens the pairing window (60 seconds)
- `0x02` closes it
- `0x03` unpairs a slot

Pairing first enables receiver notifications, then opens the pairing window. If the receiver reports that it is full (error `0x05`), slot 1 is unpaired and the window is opened again. The tool then waits for the receiver to report the new device. Unpairing sends the unlink command for every slot (1 to 6) and reports success if the receiver acknowledged it.

## Disclaimer

Unofficial. Based on the publicly documented HID++ 1.0 protocol as implemented in [Solaar](https://github.com/pwr-Solaar/Solaar). Not affiliated with or endorsed by Logitech. Use at your own risk.
