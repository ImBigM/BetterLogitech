@echo off
rem ============================================================
rem  Unpair-Mouse.bat - single-file launcher and script
rem  Removes all linked devices from this PC's Logitech LIGHTSPEED receiver.
rem  Requires Python 3. The hidapi package is installed automatically.
rem  Everything below the PYSTART marker line is Python code.
rem ============================================================
setlocal
title Logitech LIGHTSPEED Unlink
chcp 65001 >nul
cd /d "%~dp0"

rem --- Remove the "downloaded from the internet" block (Mark of the Web) ---
set "PM_TARGET=%~f0"
dir /r "%~f0" 2>nul | find ":Zone.Identifier" >nul && powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath $env:PM_TARGET" >nul 2>nul

rem --- Start Menu shortcut (Ctrl+Alt+C) - created once, skipped if it exists ---
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Unpair Mouse.lnk"
if exist "%LNK%" goto :lnk_done
set "PM_LNK=%LNK%"
set "PM_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:PM_LNK); $s.TargetPath=$env:PM_TARGET; $s.WorkingDirectory=$env:PM_DIR; $s.Hotkey='CTRL+ALT+C'; $s.Description='Unpair Logitech LIGHTSPEED mouse'; $s.Save()" >nul 2>nul
if exist "%LNK%" echo  [OK] Start Menu shortcut created - hotkey: Ctrl+Alt+C
:lnk_done

rem --- Find Python ---
set "PY=python"
where python >nul 2>nul || set "PY=py"
where %PY% >nul 2>nul
if errorlevel 1 (
    echo.
    echo  [X] Python was not found.
    echo      Install it from https://www.python.org/downloads/ and run this again.
    echo.
    pause
    exit /b 1
)

rem --- Install the HID library on first run ---
%PY% -c "import hid" >nul 2>nul
if errorlevel 1 (
    echo.
    echo  Installing required package ^(hidapi^) - first run only...
    %PY% -m pip install --quiet hidapi
)

rem --- Run the Python code embedded below this script ---
%PY% -c "import sys;sys.argv=sys.argv[1:];exec(open(sys.argv[0],encoding='utf-8').read().split('#PYSTART\n',1)[1])" "%~f0" %*
echo.
pause
exit /b

#PYSTART
"""
Unpair-Mouse.bat - Remove all linked devices from a Logitech LIGHTSPEED receiver.

Single-file script: the .bat part at the top launches the Python code below.

Sends the HID++ 1.0 "unpair" command (register 0xB2) for every pairing slot of
the receiver connected to this computer. Afterwards the receiver is empty and
the mouse can be paired again.

Requires Python 3 (the hidapi package is installed automatically on first run).

On first run it also removes the "downloaded from the internet" block from this
file and creates a Start Menu shortcut "Unpair Mouse" with the hotkey Ctrl+Alt+C.
(To remove the shortcut: delete "Unpair Mouse.lnk" from your Start Menu "Programs" folder.)

Command-line options (all optional):
    Unpair-Mouse.bat               runs immediately, no confirmation
    Unpair-Mouse.bat --verbose     also show raw HID++ messages (debugging)
    Unpair-Mouse.bat --ascii       plain [OK]/[X] symbols instead of Unicode
    Unpair-Mouse.bat --pid 0xC539  specify the receiver PID manually
    Unpair-Mouse.bat --long        use long HID++ messages instead of short ones

Notes:
    - The mouse stops working on this computer until it is paired again.
    - Based on the publicly documented HID++ 1.0 protocol (as implemented in
      Solaar). Unofficial; not affiliated with or endorsed by Logitech.
      Use at your own risk.
"""
import argparse
import os
import sys
import time

try:
    import hid
except ImportError:
    sys.exit("Missing dependency. Install it with:  pip install hidapi")

VID = 0x046D
VENDOR_PAGE = 0xFF00
MAX_SLOTS = 6  # Unifying receivers have up to 6 slots; LIGHTSPEED receivers typically 1
RECEIVER_PIDS = {0xC539, 0xC53A, 0xC53D, 0xC53F, 0xC541, 0xC545, 0xC547, 0xC54D, 0xC52B}

ERRORS = {
    0x01: "invalid sub-ID (message format not accepted by the receiver)",
    0x02: "invalid register address",
    0x03: "invalid value",
    0x05: "too many devices",
    0x07: "receiver busy",
    0x08: "unknown device (empty slot)",
    0x0A: "request unavailable",
}

# ----------------------------------------------------------------------------
# Console output (colors, symbols)
# ----------------------------------------------------------------------------
VERBOSE = False
USE_COLOR = False
SYM = {"ok": "✔", "go": "➜", "warn": "!", "fail": "✖"}

GREEN, RED, YELLOW, CYAN, DIM, BOLD, RESET = (
    "\033[92m", "\033[91m", "\033[93m", "\033[96m", "\033[90m", "\033[1m", "\033[0m",
)


def init_console(ascii_only):
    global USE_COLOR, SYM
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if os.name == "nt":
        os.system("")  # enables ANSI escape sequences in the Windows console
    USE_COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    if ascii_only:
        SYM = {"ok": "[OK]", "go": ">", "warn": "!", "fail": "[X]"}


def paint(text, color):
    return f"{color}{text}{RESET}" if USE_COLOR else text


def ok(msg):
    print(f" {paint(SYM['ok'], GREEN)} {msg}")


def info(msg):
    print(f" {paint(SYM['go'], CYAN)} {msg}")


def warn(msg):
    print(f" {paint(SYM['warn'], YELLOW)} {msg}")


def fail(msg):
    print(f" {paint(SYM['fail'], RED)} {msg}")


def hint(msg):
    print(f"   {paint(msg, DIM)}")


def die(msg, extra=None):
    fail(msg)
    if extra:
        hint(extra)
    print()
    sys.exit(1)


def header(title):
    print()
    print(f" {paint(title, BOLD)}")
    print(f" {paint('-' * len(title), DIM)}")


# ----------------------------------------------------------------------------
# HID++ helpers
# ----------------------------------------------------------------------------
def hexs(data):
    return " ".join(f"{b:02x}" for b in data)


def vendor_interfaces(pid_filter=None):
    found = []
    for d in hid.enumerate(VID, 0):
        if d["usage_page"] != VENDOR_PAGE:
            continue
        pid = d["product_id"]
        if pid_filter is not None:
            if pid != pid_filter:
                continue
        elif pid not in RECEIVER_PIDS:
            continue
        found.append(d)
    return found


def open_interfaces(ifaces):
    handles = []
    for d in ifaces:
        h = hid.device()
        try:
            h.open_path(d["path"])
            h.set_nonblocking(1)
            handles.append((h, d))
        except OSError:
            pass
    return handles


def close_all(handles):
    for h, _d in handles:
        try:
            h.close()
        except Exception:
            pass


def set_register(handles, register, params, use_long=False):
    """Send an HID++ 1.0 SET_REGISTER request (short message by default)."""
    params = bytes(params)
    if use_long:
        msg = (bytes([0x11, 0xFF, 0x80, register]) + params).ljust(20, b"\x00")
    else:
        msg = (bytes([0x10, 0xFF, 0x80, register]) + params).ljust(7, b"\x00")
    for h, _d in handles:
        try:
            h.write(list(msg))
        except (OSError, ValueError):
            pass  # this interface does not accept this report format; expected


def describe(msg):
    if len(msg) < 6 or msg[0] not in (0x10, 0x11):
        return None
    if msg[2] == 0x8F:
        code = msg[5]
        return f"error on register 0x{msg[4]:02x}: 0x{code:02x} = {ERRORS.get(code, 'unknown')}"
    if msg[2] == 0x80:
        return f"receiver acknowledged register 0x{msg[3]:02x}"
    return None


def collect(handles, seconds):
    """Read incoming messages for the given duration (printed only with --verbose)."""
    out = []
    end = time.time() + seconds
    while time.time() < end:
        got = False
        for h, _d in handles:
            data = h.read(32)
            if data:
                got = True
                msg = bytes(data)
                out.append(msg)
                text = describe(msg)
                if VERBOSE and text:
                    print(f"   {paint(f'{text}   [{hexs(msg)}]', DIM)}")
        if not got:
            time.sleep(0.02)
    return out


def slot_acknowledged(msgs):
    return any(len(m) > 3 and m[2] == 0x80 and m[3] == 0xB2 for m in msgs)


# ----------------------------------------------------------------------------
# Main flow
# ----------------------------------------------------------------------------
def main():
    global VERBOSE
    p = argparse.ArgumentParser(description="Remove all linked devices from a Logitech LIGHTSPEED receiver")
    p.add_argument("--pid", type=lambda x: int(x, 0), default=None, help="receiver PID, e.g. 0xC539")
    p.add_argument("--long", action="store_true", help="use long HID++ messages instead of short ones")
    p.add_argument("--verbose", action="store_true", help="show raw HID++ messages")
    p.add_argument("--ascii", action="store_true", help="use plain ASCII symbols instead of Unicode")
    args = p.parse_args()

    VERBOSE = args.verbose
    init_console(args.ascii)
    header("Logitech LIGHTSPEED Unlink")

    ifaces = vendor_interfaces(args.pid)
    if not ifaces:
        die(
            "No receiver found.",
            "Plug in the receiver and close G HUB. If it still fails, try:  --pid 0x....",
        )
    handles = open_interfaces(ifaces)
    if not handles:
        die("Could not access the receiver.", "Close G HUB and other Logitech software, then try again.")

    ok(f"Receiver found (PID 0x{ifaces[0]['product_id']:04X})")

    set_register(handles, 0x00, [0x00, 0x09, 0x00], args.long)  # enable receiver notifications
    collect(handles, 0.5)

    accepted = 0
    for slot in range(1, MAX_SLOTS + 1):
        set_register(handles, 0xB2, [0x03, slot, 0x00], args.long)  # unpair this slot
        if slot_acknowledged(collect(handles, 0.5)):
            accepted += 1
    close_all(handles)

    print()
    if accepted:
        ok(paint("Linked devices removed from the receiver.", GREEN))
        hint("The receiver is now empty. You can pair your mouse again.")
    else:
        fail("The receiver did not accept the unlink command.")
        hint("Run with --verbose for details.")
        print()
        sys.exit(1)
    print()


if __name__ == "__main__":
    main()
