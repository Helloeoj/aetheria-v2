"""Lifetime boundary for processes Sentinel owns; never attaches to existing game processes."""
import ctypes
from ctypes import wintypes as w
import os
import signal
import threading


class ProcessGroup:
    def __init__(self, process):
        self.process, self.handle = process, None
        self.lock=threading.Lock()
        if os.name != 'nt':
            return
        class Basic(ctypes.Structure):
            _fields_ = [('process_time',ctypes.c_int64),('job_time',ctypes.c_int64),('flags',w.DWORD),
                        ('minimum',ctypes.c_size_t),('maximum',ctypes.c_size_t),('active',w.DWORD),
                        ('affinity',ctypes.c_size_t),('priority',w.DWORD),('scheduling',w.DWORD)]
        class IO(ctypes.Structure):
            _fields_ = [(name,ctypes.c_uint64) for name in ('read_ops','write_ops','other_ops','read_bytes','write_bytes','other_bytes')]
        class Extended(ctypes.Structure):
            _fields_ = [('basic',Basic),('io',IO),('process_memory',ctypes.c_size_t),('job_memory',ctypes.c_size_t),
                        ('peak_process',ctypes.c_size_t),('peak_job',ctypes.c_size_t)]
        self.kernel = ctypes.WinDLL('kernel32',use_last_error=True)
        self.kernel.CreateJobObjectW.argtypes=[ctypes.c_void_p,w.LPCWSTR]
        self.kernel.CreateJobObjectW.restype=w.HANDLE
        self.kernel.SetInformationJobObject.argtypes=[w.HANDLE,ctypes.c_int,ctypes.c_void_p,w.DWORD]
        self.kernel.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE]
        self.kernel.CloseHandle.argtypes=[w.HANDLE]
        handle=self.kernel.CreateJobObjectW(None,None)
        limits=Extended()
        limits.basic.flags=0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not handle or not self.kernel.SetInformationJobObject(handle,9,ctypes.byref(limits),ctypes.sizeof(limits)) or not self.kernel.AssignProcessToJobObject(handle,w.HANDLE(int(process._handle))):
            if handle: self.kernel.CloseHandle(handle)
            process.kill()
            process.wait(timeout=5)
            raise OSError('Windows could not establish the owned process lifetime boundary.')
        self.handle=handle

    def close(self):
        with self.lock:
            handle=self.handle
            self.handle=None
        if handle:
            self.kernel.CloseHandle(handle)
        elif os.name != 'nt':
            try: os.killpg(self.process.pid,signal.SIGKILL)
            except ProcessLookupError: pass
