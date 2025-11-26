# FastMM4-AVX Project Overview for Claude

This document provides additional information and context for the Claude AI, supplementing the primary `GEMINI.md` overview.

## Build System - NASM Location

The NASM assembler is required for compiling AVX-512 assembly code. Its location on the Windows system is:
`C:\Program Files\NASM\nasm.exe`

## FreePascal Compiler (fpc.exe) 64-bit Capability

The `fpc.exe` compiler, typically found in `S:\ProgramFiles\FPC\3.2.2\bin\i386-win32\`, is capable of cross-compiling for 64-bit Windows targets using the `-Twin64 -Px86_64` flags. For example:
`S:\ProgramFiles\FPC\3.2.2\bin\i386-win32\fpc.exe -Twin64 -Px86_64 MyProgram.dpr`

## GitHub Actions and Docker Testing Policy

**IMPORTANT:** Testing policy differs between Linux and Windows CI environments.

### Linux CI (GitHub Actions & Docker)
**ALLOWED:** Full testing including debug modes
- `-dDEBUG` flag - **ALLOWED** (works without external DLLs on Linux)
- `-dFullDebugMode` flag - **ALLOWED** (works without external DLLs on Linux)
- All configuration options (alignment, threading, synchronization)
- Both Simple compilation tests and Advanced runtime tests

**Why:** Debug modes work natively on Linux without requiring external DLL dependencies.

### Windows CI (GitHub Actions)
**ALLOWED:** Both Release and Debug modes

**Allowed on Windows CI:**
- `-dDEBUG` flag - **ALLOWED** (no external DLL requirement)
- Release builds with `-O4` optimization
- Debug builds with `-g -O-` options
- All configuration options (alignment, threading, synchronization)
- Compilation validation for Windows 32-bit and 64-bit

**Do NOT use on Windows CI:**
- `-dFullDebugMode` flag - **NOT ALLOWED** (requires `FastMM_FullDebugMode.dll`)

**Reason:** FullDebugMode requires external DLLs that are not available in Windows CI environments. FullDebugMode testing should be performed locally during development.

## Git Location

Git is installed at `S:\ProgramFiles\Git\bin\git.exe`

## Running Shell Commands on Windows

**IMPORTANT:** When running shell commands on Windows from Claude Code:

### Use .bat Files for Complex Commands
The Bash tool has issues with backslashes and `&&` operators. Instead of trying to run complex commands directly:

1. **Create a .bat file** with the commands you need to run
2. **Execute the .bat file** using PowerShell's `Start-Process`

### Example Pattern That Works:
```powershell
powershell.exe -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','C:\\q\\FastMM4-AVX\\script.bat' -Wait -NoNewWindow -RedirectStandardOutput 'C:\\q\\FastMM4-AVX\\output.txt'; Get-Content 'C:\\q\\FastMM4-AVX\\output.txt'"
```

### .bat File Example:
```batch
@echo off
cd /d C:\q\FastMM4-AVX
S:\ProgramFiles\Git\bin\git.exe status
S:\ProgramFiles\Git\bin\git.exe add .
S:\ProgramFiles\Git\bin\git.exe commit -m "message"
```

### What Does NOT Work:
- Direct bash commands with Windows paths (backslashes get eaten)
- `cmd.exe /c "cd /d C:\path && command"` - the `&&` doesn't work reliably
- Calling .bat files directly from bash - paths get mangled
- Git commands without full path when git is not in PATH

### Key Points:
- Always use **double backslashes** (`\\`) in PowerShell string arguments
- Always use **full paths** to executables (like `S:\ProgramFiles\Git\bin\git.exe`)
- Use `-RedirectStandardOutput` to capture output from batch files
- The `cd /d` command in batch files properly changes both drive and directory