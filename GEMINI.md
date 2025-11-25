# FastMM4-AVX Project Overview

FastMM4-AVX is a high-performance memory manager for Pascal/Delphi applications with optimizations for modern CPUs. It's a fork of the original FastMM4 v4.993 by Pierre le Riche, enhanced with AVX/AVX2/AVX512 instructions, improved synchronization, and better multi-threading performance.

**Version:** 1.0.8 (24 November 2025)
**Base FastMM4 Version:** 4.993

## Key Features

-   Efficient synchronization with pause-based spin-wait loops and critical sections
-   AVX/AVX2/AVX512 support for faster memory copy operations
-   Enhanced REP MOVSB/STOSB (ERMS) and Fast Short REP MOVSB (FSRM) support
-   Improved memory alignment (8, 16, or 32 bytes)
-   Supports both Delphi and FreePascal compilers
-   Comprehensive debugging capabilities with FullDebugMode

## Primary Language

The project is primarily written in **Pascal (Delphi)**, with a significant amount of performance-critical code written in **x86-64 Assembly (NASM)**.

## Architecture & Code Structure

The project's architecture is highly modular and configurable, centered around a main Pascal unit (`FastMM4.pas`) and a configuration file (`FastMM4Options.inc`).

### Core Files

-   **FastMM4.pas**: Main memory manager implementation (~750KB, critical file)
-   **FastMM4Options.inc**: Configuration options and conditional compilation directives (start here to understand available options)
-   **FastMM4Messages.pas**: Localized error/status messages
-   **FastMM4_AVX512.asm**: AVX-512 optimized assembly routines for Windows (NASM syntax)
-   **FastMM4_AVX512_Linux.asm**: AVX-512 optimized assembly routines for Linux (System V AMD64 ABI)
-   **FastMMMemoryModule.pas**: Memory module utilities
-   **FastMM4DataCollector.pas**: Debug data collection
-   **FastMM4LockFreeStack.pas**: Lock-free stack implementation
-   **Translations/**: Localized versions of FastMM4Messages.pas for various languages

### Historic Files (DO NOT EDIT)

-   **FastMM4_Readme.txt**: Historic readme file from the original FastMM4 project. This file should NEVER be modified as it serves as a historical record of the original project.

### Memory Management Architecture

FastMM4-AVX uses a three-tier memory management system:
1.  **Small blocks** (<2.5KB) - Managed in pools with fixed-size allocators
2.  **Medium blocks** (<260KB) - Allocated from 1.25MB pools with double-linked free lists
3.  **Large blocks** (>260KB) - Direct VirtualAlloc from OS

### Synchronization Strategy

-   **Test-and-test-and-set** technique for spin-wait loops
-   Configurable critical sections vs. spin-locks via conditional defines
-   5000 pause iterations before falling back to SwitchToThread()
-   Individual locks for small blocks, medium blocks, and large blocks

### Platform Support

-   **Windows**: 32-bit and 64-bit (primary target)
-   **Linux**: 64-bit and 32-bit (via FreePascal)
-   **Compilers**: Delphi 4+, C++ Builder 4+, FreePascal/Lazarus

## Build System

### FreePascal Installation
FPC 3.2.2 is installed at `S:\ProgramFiles\FPC\3.2.2\`

**Add to PATH:**
```bash
set PATH=S:\ProgramFiles\FPC\3.2.2\bin\i386-win32;%PATH%
```

**Available compilers:**
-   `ppc386.exe` - Native 32-bit Windows compiler
-   `ppcrossx64.exe` - Cross-compiler for 64-bit Windows

**Target platforms:** i386-win32, x86_64-win64

### FreePascal (Primary)
The project uses FreePascal as the primary build system. Tests are located in the `Tests/` directory:

**Compile simple test:**
```bash
cd Tests/Simple
fpc -B -Mdelphi -Tlinux -Px86_64 -O4 SimpleTest.dpr    # Linux 64-bit
fpc -B -Mdelphi -Twin32 -Pi386 -O4 SimpleTest.dpr      # Windows 32-bit
fpc -B -Mdelphi -Twin64 -Px86_64 -O4 SimpleTest.dpr    # Windows 64-bit
```

**Run tests (Windows):**
```bash
cd Tests\Simple && SimpleTest.exe    # After compilation
```

**Run tests (Linux):**
```bash
cd Tests/Simple && ./SimpleTest    # After compilation
```

Note: `SimpleTest.dpr` is a minimal compilation test (includes only FastMM4 units). It validates that FastMM4 compiles correctly under various define combinations.

**Debug builds:**
```bash
fpc -B -Mdelphi -Tlinux -Px86_64 -dDEBUG -g -O- SimpleTest.dpr
fpc -B -Mdelphi -Tlinux -Px86_64 -dDEBUG -g -dFullDebugMode -O- SimpleTest.dpr
```
Note: Debug modes are tested in CI on Linux but not on Windows (Windows requires external DLLs).

### Assembly (AVX-512)
AVX-512 assembly code requires NASM:
```bash
nasm -Ox -Ov -f win64 FastMM4_AVX512.asm              # Windows
nasm -Ox -Ov -f elf64 FastMM4_AVX512_Linux.asm -o FastMM4_AVX512_Linux.o  # Linux
```

**Linux AVX-512 Support:**
-   `FastMM4_AVX512_Linux.asm` - Linux System V AMD64 ABI version (uses rdi, rsi, rdx)
-   `FastMM4_AVX512.asm` - Windows x64 ABI version (uses rcx, rdx, r8)

### Docker Testing (Linux)
A Docker container is available for running tests under Linux:
```bash
docker build -t fastmm4-avx-tests .
docker run --rm fastmm4-avx-tests                    # Run all configs
docker run --rm fastmm4-avx-tests Release Debug     # Run specific configs
```

**Testing Policy for GitHub Actions and Docker:**
- **Linux**: Tests both Release and Debug modes (including `-dDEBUG` and `-dFullDebugMode`)
  - Debug modes work on Linux without requiring external DLLs
  - Comprehensive testing across all build configurations
- **Windows**: Tests **Release mode only** (`-O4` optimization, no debug modes)
  - Debug modes require external DLLs (e.g., `FastMM_FullDebugMode.dll`) not available in CI
  - Windows debug testing should be performed locally during development
- CI validates compilation and functionality across various configuration options (alignment, threading, etc.)

**Available configurations:** Release, Debug, FullDebugMode, Align16Bytes, Align32Bytes, ForceSingleThreaded, DontUseASMVersion, AlwaysClearFreedMemory, DisableAVX512

**Test Results (Linux x86_64 via Docker, 2025-11-23):**
All 8 configurations pass (25 tests each, ForceSingleThreaded: 24 tests):

| Configuration | Tests | Alignment | Status |
|--------------|-------|-----------|--------|
| Release | 25/25 | 8-byte | PASS |
| Debug | 25/25 | 8-byte | PASS |
| FullDebugMode | 25/25 | 8-byte | PASS |
| Align16Bytes | 25/25 | 16-byte | PASS |
| Align32Bytes | 25/25 | 32-byte | PASS |
| ForceSingleThreaded | 24/24 | 8-byte | PASS |
| DontUseASMVersion | 25/25 | 8-byte | PASS |
| AlwaysClearFreedMemory | 25/25 | 8-byte | PASS |

See [Linux_AVX512_Test_Results.md](Linux_AVX512_Test_Results.md) for detailed results.

### CPU Feature Detection Testing

The `PrintCpuFeatures.dpr` program can be used to verify AVX-512 support:

```bash
cd Tests/Simple
fpc -B -Mdelphi -Tlinux -Px86_64 -O4 PrintCpuFeatures.dpr
./PrintCpuFeatures
```

**Compilation Results Comparison:**

| Build Configuration | AVX512 in Output | Full Output |
|-------------------|------------------|-------------|
| Normal (Release) | ✓ YES | AVX1, AVX2, **AVX512**, ERMS, FSRM |
| `-dDEBUG` | ✓ YES | AVX1, AVX2, **AVX512**, ERMS, FSRM |
| `-dFullDebugMode` | ✓ YES | AVX1, AVX2, **AVX512**, ERMS, FSRM |
| `-dDisableAVX512` | ✗ NO | AVX1, AVX2, ERMS, FSRM |

**Key Findings:**
-   AVX-512 detection works in all build modes (Release, DEBUG, FullDebugMode)
-   The `-dDisableAVX512` conditional define successfully disables AVX-512 support
-   CPU features are detected at runtime in all builds except when explicitly disabled at compile-time

### Delphi Projects
The repository contains various Delphi project files (.dpr/.dproj) for:
-   Demo applications in `Demos/`
-   Full debug mode DLL in `FullDebugMode DLL/`
-   Replacement BorlndMM DLL in `Replacement BorlndMM DLL/`
-   Test applications in `Tests/`

## Configuration Options

Key conditional defines in `FastMM4Options.inc`:

**Memory Alignment:**
-   `Align16Bytes` - 16-byte alignment for SSE
-   `Align32Bytes` - 32-byte alignment for AVX
-   **Note:** FastMM4-AVX supports alignments of 8, 16, and 32 bytes. All alignment options (including `Align32Bytes`) work correctly in both Release and DEBUG/FullDebugMode builds.
-   **64-byte alignment:** Not supported. However, AVX-512 code uses unaligned moves (`vmovdqu64`) for 512-bit operations, so 64-byte alignment is not required. The library only uses aligned moves (`vmovdqa64`) for 128-bit (16-byte) and 256-bit (32-byte) operations where alignment is guaranteed.

**AVX Control:**
-   `EnableAVX` - Enable AVX instructions (auto-detected)
-   `DisableAVX`, `DisableAVX1`, `DisableAVX2`, `DisableAVX512` - Disable specific AVX levels

**Synchronization:**
-   `SmallBlocksLockedCriticalSection` (default) - Use critical sections for small blocks
-   `DisablePauseAndSwitchToThread` - Force critical sections only
-   `ForceSingleThreaded` - Disable all threading support

**Debugging:**
-   `FullDebugMode` - Comprehensive debug mode with stack traces
-   `DEBUG` - Basic debug checks
-   `DisableMemoryLeakReporting` - Turn off leak detection
-   `RequireIDEPresenceForLeakReporting` - Only report leaks when IDE present

**Performance:**
-   `UseCustomFixedSizeMoveRoutines` (default) - Optimized fixed-size moves
-   `UseCustomVariableSizeMoveRoutines` (default) - Optimized variable-size moves
-   `EnableERMS` - Enhanced REP MOVSB/STOSB support
-   `EnableWaitPKG` - User-mode wait instructions (umonitor/umwait)

## Testing

The project has extensive CI/CD testing via GitHub Actions (`.github/workflows/main.yaml`):

**Test Structure:**
-   `Tests/Simple/` - Compilation validation tests
-   `Tests/Advanced/` - Comprehensive test suite (25 tests covering allocation, realloc, alignment, stress)
-   `Tests/Benchmark/` - Performance benchmarks (e.g., `Realloc.dpr`)
-   `Demos/` - Usage examples and demonstrations

**CI/CD Testing Policy:**
-   **Linux CI**: Tests both Release and Debug modes (including `-dDEBUG` and `-dFullDebugMode`)
    -   Debug modes work on Linux without external DLL dependencies
    -   Full test coverage across all build configurations
-   **Windows CI**: Tests **Release mode only** (`-O4` optimization)
    -   Debug modes require external DLLs (e.g., `FastMM_FullDebugMode.dll`) not available in CI
    -   Windows debug testing should be performed locally during development

**Running Advanced Tests:**
```bash
# Windows (32-bit)
ppc386.exe -B -Mdelphi -Twin32 -Pi386 -O4 -dIgnoreMemoryAllocatedBefore -dDisableMemoryLeakReporting Tests/Advanced/AdvancedTest.dpr
Tests\Advanced\AdvancedTest.exe

# Windows (64-bit) - requires AVX-512 assembly
nasm -Ox -Ov -f win64 FastMM4_AVX512.asm -o FastMM4_AVX512.obj
ppcrossx64.exe -B -Mdelphi -Twin64 -Px86_64 -O4 -dIgnoreMemoryAllocatedBefore -dDisableMemoryLeakReporting Tests/Advanced/AdvancedTest.dpr -oTests/Advanced/AdvancedTest64.exe
Tests\Advanced\AdvancedTest64.exe

# Linux (via Docker)
docker build -t fastmm4-avx-tests . && docker run --rm fastmm4-avx-tests
```

**Test Compilation Matrix (CI-validated defines):**

**Linux CI** tests all modes including:
-   `-dDEBUG`, `-dFullDebugMode` - Debug modes (work without external DLLs on Linux)
-   `-dAlign16Bytes`, `-dAlign32Bytes` - Memory alignment options
-   `-dDontUseCustomFixedSizeMoveRoutines`, `-dDontUseCustomVariableSizeMoveRoutines` - Disable optimized move routines
-   `-dForceSingleThreaded` - Single-threaded mode
-   `-dDisablePauseAndSwitchToThread` - Force critical sections only
-   `-dDontUseSmallBlocksLockedCriticalSection`, `-dDontUseMediumBlocksLockedCriticalSection`, `-dDontUseLargeBlocksLockedCriticalSection` - Lock mechanism options
-   `-dDontUseASMVersion` - Disable inline assembly
-   `-dDisableMemoryLeakReporting`, `-dRequireIDEPresenceForLeakReporting` - Leak reporting options
-   `-dDisableAVX512`, `-dDisableAsmCodeAlign` - AVX and code alignment options

**Windows CI** tests Release mode only with various options (alignment, threading, etc.) but excludes:
-   `-dDEBUG` - Requires debug runtime support
-   `-dFullDebugMode` - Requires `FastMM_FullDebugMode.dll` (not available in Windows CI)
-   Windows debug testing should be performed locally

## Usage Integration

**Basic Integration (Delphi):**
```pascal
uses
  FastMM4, // Must be first unit
  // ... other units
```

**Shared Memory (DLL + App):**
Define `ShareMM`, `ShareMMIfLibrary`, and `AttemptToUseSharedMM` in both DLL and application.

**Large Address Awareness:**
Add `{$SetPEFlags $20}` to .dpr file for >2GB address space support.

## Security & Memory Safety

FastMM4-AVX includes several security enhancements:
-   Memory block headers/footers in FullDebugMode catch overwrite bugs
-   Stack traces for allocation/deallocation debugging
-   Detection of freed object method calls
-   Interface usage detection on freed objects
-   Memory pattern filling to detect use-after-free

## Performance Considerations

**Multi-threading Benefits:**
-   Best performance gains seen under multi-threaded scenarios
-   Up to 2x speed improvement over original FastMM4 in high-contention situations
-   Single-threaded performance may be similar to original FastMM4

**AVX Trade-offs:**
-   AVX instructions provide modest memory copy speed improvements
-   May cause AVX-SSE transition penalties and reduced CPU frequency
-   Consider disabling AVX on CPUs with Fast Short REP MOVSB (Ice Lake+)

**Memory Overhead:**
-   Designed for 5% average, 10% maximum overhead per block
-   32-byte alignment increases overhead vs. 8-byte alignment
-   FullDebugMode significantly increases memory usage due to debug headers

## Security Audit Findings

See [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for the comprehensive security audit report.

**Summary:** 1 Critical, 2 High, 2 Medium, 1 Low severity issues identified.

### Critical Issues

1. **Integer Overflow in AllocateLargeBlock** - Size calculation can overflow when `ASize` approaches `NativeUInt.MaxValue`, causing undersized allocation and heap overflow (CVE-2017-17426 class).

### High Severity Issues

2. **Missing Safe-Unlinking** - `RemoveMediumFreeBlock` does not verify pointer integrity before unlinking, enabling classic "unlink attack" (fixed in glibc 2.3.6, 2005).

3. **No Double-Free Detection in Production** - Double-free detection only works in `FullDebugMode`. Production builds lack protection against this exploitation primitive.

### Medium Severity Issues

4. **No Safe-Linking for Free Lists** - Free list pointers are stored unprotected, unlike modern allocators (glibc 2.32+) that XOR pointers with ASLR-derived values.

5. **Information Disclosure** - Memory not cleared by default on alloc/free. Enable `AlwaysClearFreedMemory` for security-critical applications.

### Security Configuration

For security-critical deployments:
```pascal
{$DEFINE FullDebugMode}
{$DEFINE CheckHeapForCorruption}
{$DEFINE AlwaysClearFreedMemory}
{$DEFINE AssumeMultiThreaded}
```
