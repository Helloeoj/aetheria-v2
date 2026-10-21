"""Small Windows process helpers. No injection, debugger attachment or game-memory reads."""
from __future__ import annotations
import ctypes
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import struct
import sys

HIDDEN = 0x08000000 if sys.platform == 'win32' else 0


def make_icon(path):
    """Small code-drawn application glyph; no image dependencies or game-asset changes."""
    size = 64
    pixels, mask = bytearray(), bytearray()
    for y in reversed(range(size)):
        row_mask = bytearray(size // 8)
        for x in range(size):
            dx, dy = x - 31.5, y - 31.5
            radius = (dx * dx + dy * dy) ** .5
            color = (11, 17, 28, 255)
            if radius > 30:
                color = (0, 0, 0, 0)
                row_mask[x // 8] |= 1 << (7 - x % 8)
            elif 26 < radius < 29:
                color = (105, 188, 255, 255)
            elif abs(dx) + abs(dy) < 18:
                color = (113, 220, 192, 255) if dy < 0 else (105, 188, 255, 255)
            elif abs(dx) < 1 or abs(dy) < 1:
                color = (35, 60, 85, 255)
            red, green, blue, alpha = color
            pixels.extend((blue, green, red, alpha))
        mask.extend(row_mask)
    image = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, len(pixels), 0, 0, 0, 0) + pixels + mask
    icon = struct.pack('<HHH', 0, 1, 1) + struct.pack('<BBBBHHII', size, size, 0, 0, 1, 32, len(image), 22) + image
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(icon)
    return path


class ProcessWatch:
    """Retain the original process handle so PID reuse cannot masquerade as a running game."""
    def __init__(self, pid):
        self.pid = int(pid)
        self.handle = None
        if sys.platform == 'win32':
            self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            self.kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
            self.kernel.OpenProcess.restype = w.HANDLE
            self.kernel.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
            self.kernel.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
            self.kernel.CloseHandle.argtypes = [w.HANDLE]
            self.handle = self.kernel.OpenProcess(0x1000 | 0x100000, False, self.pid)

    def poll(self):
        if sys.platform == 'win32' and self.handle:
            # A real exit code of 259 is legal; test the signaled handle before interpreting it.
            if self.kernel.WaitForSingleObject(self.handle, 0) == 0x102:
                return True, None
            code = w.DWORD()
            ok = self.kernel.GetExitCodeProcess(self.handle, ctypes.byref(code))
            return False, int(code.value) if ok else None
        import adc
        return adc.alive(self.pid), None

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


def godot_pids():
    if sys.platform != 'win32':
        return set()

    class Entry(ctypes.Structure):
        _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('pid', w.DWORD),
                    ('heap', ctypes.c_size_t), ('module', w.DWORD), ('threads', w.DWORD),
                    ('parent', w.DWORD), ('priority', w.LONG), ('flags', w.DWORD), ('name', w.WCHAR * 260)]

    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateToolhelp32Snapshot.argtypes = [w.DWORD, w.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = w.HANDLE
    kernel.Process32FirstW.argtypes = [w.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes = [w.HANDLE, ctypes.POINTER(Entry)]
    kernel.CloseHandle.argtypes = [w.HANDLE]
    handle = kernel.CreateToolhelp32Snapshot(2, 0)
    if handle == ctypes.c_void_p(-1).value:
        return set()
    result = set()
    try:
        entry = Entry()
        entry.dwSize = ctypes.sizeof(Entry)
        valid = kernel.Process32FirstW(handle, ctypes.byref(entry))
        while valid:
            if entry.name.lower().startswith('godot') and entry.name.lower().endswith('.exe'):
                result.add(int(entry.pid))
            valid = kernel.Process32NextW(handle, ctypes.byref(entry))
    finally:
        kernel.CloseHandle(handle)
    return result


def engine_processes():
    """Called only when a Godot PID appears, not by launching a shell on every poll."""
    if sys.platform != 'win32':
        return []
    script = "Get-CimInstance Win32_Process -Filter \"Name LIKE 'Godot%.exe'\" | Select-Object ProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress"
    result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                            capture_output=True, text=True, errors='replace', timeout=12, creationflags=HIDDEN)
    if result.returncode or not result.stdout.strip():
        return []
    value = json.loads(result.stdout.lstrip('\ufeff'))
    return value if isinstance(value, list) else [value]


def split_command(command):
    if not command:
        return []
    if sys.platform != 'win32':
        import shlex
        return shlex.split(command)
    shell = ctypes.WinDLL('shell32', use_last_error=True)
    shell.CommandLineToArgvW.argtypes = [w.LPCWSTR, ctypes.POINTER(ctypes.c_int)]
    shell.CommandLineToArgvW.restype = ctypes.POINTER(w.LPWSTR)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    count = ctypes.c_int()
    array = shell.CommandLineToArgvW(command, ctypes.byref(count))
    if not array:
        return []
    try:
        return [array[i] for i in range(count.value)]
    finally:
        kernel.LocalFree(array)


def is_game(command, project):
    args = split_command(command)
    if '--editor' in args or '-e' in args or '--project-manager' in args:
        return False
    try:
        index = args.index('--path')
        return Path(args[index + 1]).resolve() == Path(project).resolve()
    except (ValueError, IndexError, OSError):
        return False


def installed_engine():
    configured = os.environ.get('GODOT')
    if configured and Path(configured).is_file():
        return configured
    # One known installation folder, not an expensive disk-wide search.
    candidates = list((Path.home() / 'Desktop' / 'Game Dev').glob('Godot*/*console.exe'))
    return str(sorted(candidates)[-1]) if candidates else ''


def game_executable(engine):
    # Official Windows *_console.exe is a forwarding wrapper, not the game process.
    path = Path(engine)
    if path.name.lower().endswith('_console.exe'):
        sibling = path.with_name(path.name[:-12] + '.exe')
        if sibling.is_file():
            return str(sibling)
    return str(path)


class SingleInstance:
    def __init__(self, identity):
        self.handle, self.exists = None, False
        if sys.platform == 'win32':
            self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            self.kernel.CreateMutexW.argtypes = [ctypes.c_void_p, w.BOOL, w.LPCWSTR]
            self.kernel.CreateMutexW.restype = w.HANDLE
            self.kernel.CloseHandle.argtypes = [w.HANDLE]
            self.handle = self.kernel.CreateMutexW(None, False, 'Local\\AetheriaSentinel-' + identity)
            self.exists = ctypes.get_last_error() == 183

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None
