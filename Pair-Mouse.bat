@echo off
rem ============================================================
rem  Pair-Mouse.bat - single-file launcher and script
rem  Re-pairs a Logitech LIGHTSPEED mouse with this PC's receiver.
rem  Requires Python 3. The hidapi package is installed automatically.
rem  Everything below the PYSTART marker line is Python code.
rem ============================================================
setlocal
title Logitech LIGHTSPEED Pairing
chcp 65001 >nul
cd /d "%~dp0"

rem --- Remove the "downloaded from the internet" block (Mark of the Web) ---
set "PM_TARGET=%~f0"
dir /r "%~f0" 2>nul | find ":Zone.Identifier" >nul && powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath $env:PM_TARGET" >nul 2>nul

rem --- Start Menu shortcut (Ctrl+Alt+X) - created once, skipped if it exists ---
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Pair Mouse.lnk"
if exist "%LNK%" goto :lnk_done
set "PM_LNK=%LNK%"
set "PM_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:PM_LNK); $s.TargetPath=$env:PM_TARGET; $s.WorkingDirectory=$env:PM_DIR; $s.Hotkey='CTRL+ALT+X'; $s.Description='Re-pair Logitech LIGHTSPEED mouse'; $s.Save()" >nul 2>nul
if exist "%LNK%" echo  [OK] Start Menu shortcut created - hotkey: Ctrl+Alt+X
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
Pair-Mouse.bat - Re-pair a Logitech LIGHTSPEED mouse with a receiver, without G HUB.

Single-file script: the .bat part at the top launches the Python code below.

Opens pairing mode on a LIGHTSPEED receiver over HID++ 1.0 (register 0xB2), the
same operation G HUB performs when you click "Begin Pairing". If the receiver
already has a device paired, the existing pairing is removed first.

Typical use: one mouse, two receivers (e.g. desktop + laptop). Run it on the
computer you want to switch the mouse to.

Requires Python 3 (the hidapi package is installed automatically on first run).

On first run it also removes the "downloaded from the internet" block from this
file and creates a Start Menu shortcut "Pair Mouse" with the hotkey Ctrl+Alt+X.
(To remove the shortcut: delete "Pair Mouse.lnk" from your Start Menu "Programs" folder.)

Command-line options (all optional):
    Pair-Mouse.bat                 re-pair the mouse with this computer's receiver
    Pair-Mouse.bat --verbose       also show raw HID++ messages (debugging)
    Pair-Mouse.bat --ascii         plain [OK]/[X] symbols instead of Unicode
    Pair-Mouse.bat --pid 0xC539    specify the receiver PID manually
    Pair-Mouse.bat --long          use long HID++ messages instead of short ones
    Pair-Mouse.bat list            list Logitech HID interfaces (diagnostics)

Notes:
    - The mouse is bound to one receiver at a time; pairing it here releases it
      from the receiver on the other computer.
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
PAIR_SECONDS = 60
RECEIVER_PIDS = {0xC539, 0xC53A, 0xC53D, 0xC53F, 0xC541, 0xC545, 0xC547, 0xC54D, 0xC52B}

ERRORS = {
    0x01: "invalid sub-ID (message format not accepted by the receiver)",
    0x02: "invalid register address",
    0x03: "invalid value",
    0x04: "connection failed",
    0x05: "too many devices (receiver is full: a device is already paired)",
    0x06: "device already exists",
    0x07: "receiver busy",
    0x08: "unknown device",
    0x09: "resource error",
    0x0A: "request unavailable",
    0x0B: "invalid parameter value",
    0x0C: "wrong PIN code",
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


def header():
    print()
    print(f" {paint('Logitech LIGHTSPEED Pairing', BOLD)}")
    print(f" {paint('-' * 27, DIM)}")


def status_line(text):
    sys.stdout.write("\r " + paint(text, YELLOW) + "      ")
    sys.stdout.flush()


def clear_status_line():
    sys.stdout.write("\r" + " " * 60 + "\r")
    sys.stdout.flush()


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


def cmd_list():
    for d in hid.enumerate(VID, 0):
        print(
            f"pid=0x{d['product_id']:04X} usage_page=0x{d['usage_page']:04X} "
            f"usage=0x{d['usage']:04X} iface={d.get('interface_number')} "
            f"{d.get('product_string')!r}"
        )


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
    sub, addr = msg[2], msg[3]
    if sub == 0x8F:
        code = msg[5]
        return f"error on register 0x{msg[4]:02x}: 0x{code:02x} = {ERRORS.get(code, 'unknown')}"
    if sub == 0x80:
        return f"receiver acknowledged register 0x{addr:02x}"
    if sub == 0x4A:
        if addr & 0x01:
            return "pairing window OPEN"
        return f"pairing window CLOSED (status code: {msg[4]})"
    if sub == 0x41:
        return "device connection state changed"
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


def error_code(msgs, register):
    for m in msgs:
        if len(m) > 5 and m[2] == 0x8F and m[4] == register:
            return m[5]
    return None


def open_lock(handles, use_long):
    set_register(handles, 0xB2, [0x01, 0x00, PAIR_SECONDS], use_long)
    return error_code(collect(handles, 1.0), 0xB2)


def close_all(handles):
    for h, _d in handles:
        try:
            h.close()
        except Exception:
            pass


def wait_for_pairing(handles):
    """Show a countdown. Returns True (paired), False (receiver reported failure), None (no confirmation)."""
    deadline = time.time() + PAIR_SECONDS
    result = None
    while time.time() < deadline + 3 and result is None:
        remaining = max(0, int(deadline - time.time() + 0.99))
        status_line(f"Waiting for the mouse...  {remaining:2d}s")
        for msg in collect(handles, 0.25):
            if len(msg) > 4 and msg[2] == 0x4A and not (msg[3] & 0x01):
                result = msg[4] == 0  # pairing window closed; 0 = no error
                break
            if len(msg) > 4 and msg[2] == 0x41 and not (msg[4] & 0x40):
                result = True  # a device connected with an established link
                break
    clear_status_line()
    return result


# ----------------------------------------------------------------------------
# Main flow
# ----------------------------------------------------------------------------
def cmd_pair(pid_filter, use_long):
    header()
    ifaces = vendor_interfaces(pid_filter)
    if not ifaces:
        die(
            "No receiver found.",
            "Plug in the receiver and close G HUB. Still failing? Run:  Pair-Mouse.bat list",
        )

    handles = []
    for d in ifaces:
        h = hid.device()
        try:
            h.open_path(d["path"])
            h.set_nonblocking(1)
            handles.append((h, d))
        except OSError:
            pass
    if not handles:
        die("Could not access the receiver.", "Close G HUB and other Logitech software, then try again.")

    ok(f"Receiver found (PID 0x{ifaces[0]['product_id']:04X})")

    set_register(handles, 0x00, [0x00, 0x09, 0x00], use_long)  # enable receiver notifications
    collect(handles, 0.5)

    err = open_lock(handles, use_long)
    if err == 0x05:
        warn("Receiver already has a mouse paired - removing the old pairing...")
        set_register(handles, 0xB2, [0x03, 0x01, 0x00], use_long)  # unpair slot 1
        collect(handles, 1.5)
        err = open_lock(handles, use_long)
    if err is not None:
        close_all(handles)
        die(
            "Could not start pairing mode.",
            f"Receiver error 0x{err:02x}: {ERRORS.get(err, 'unknown')}  (run with --verbose for details)",
        )

    ok("Pairing mode started")
    info(f"Switch the mouse {paint('OFF and ON', BOLD)} now (power switch on the underside)")
    print()

    result = wait_for_pairing(handles)

    set_register(handles, 0xB2, [0x02, 0x00, 0x00], use_long)  # close the pairing window if still open
    close_all(handles)

    if result is True:
        ok(paint("Mouse paired successfully!", GREEN))
        hint("Move the mouse to verify.")
    elif result is False:
        fail("Pairing failed (the receiver reported an error).")
        hint("Try again - switch the mouse off and on right after the prompt.")
    else:
        warn("No confirmation received.")
        hint("If the mouse works, you're all set. Otherwise run this again.")
    print()


def main():
    global VERBOSE
    p = argparse.ArgumentParser(description="Re-pair a Logitech LIGHTSPEED mouse with a receiver without G HUB")
    p.add_argument("action", nargs="?", default="pair", choices=["list", "pair"])
    p.add_argument("--pid", type=lambda x: int(x, 0), default=None, help="receiver PID, e.g. 0xC539")
    p.add_argument("--long", action="store_true", help="use long HID++ messages instead of short ones")
    p.add_argument("--verbose", action="store_true", help="show raw HID++ messages")
    p.add_argument("--ascii", action="store_true", help="use plain ASCII symbols instead of Unicode")
    args = p.parse_args()

    VERBOSE = args.verbose
    init_console(args.ascii)
    if args.action == "list":
        cmd_list()
    else:
        cmd_pair(args.pid, args.long)


if __name__ == "__main__":
    main()
