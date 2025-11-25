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
**RESTRICTED:** Release mode only (`-O4` optimization)

**Do NOT add tests with:**
- `-dDEBUG` flag
- `-dFullDebugMode` flag

**Reason:** Debug modes require external DLLs (e.g., `FastMM_FullDebugMode.dll`) that are not available in Windows CI environments. Windows debug testing should be performed locally during development.

**Allowed on Windows CI:**
- Release builds with various configuration options (alignment, threading, synchronization)
- Compilation validation for Windows 32-bit and 64-bit
- Functional testing with release-optimized builds only