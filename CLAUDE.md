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

Git is installed at `S:\ProgramFiles\Git\cmd\git.exe`
Note: `S:\ProgramFiles\Git\cmd` is in the system PATH.

## GitHub CLI Location

GitHub CLI (gh) is installed at `S:\ProgramFiles\GitHubCli\gh.exe`
Note: Use `gh api` for operations that don't require local git integration.

## Trivy Security Scanner

Trivy is installed at `S:\ProgramFiles\Utils\trivy.exe`
Version: 0.67.2

Use Trivy to scan for:
- Stored secrets in code
- Vulnerabilities in dependencies
- Container and Dockerfile security issues

## SonarQube Scanner

SonarQube CLI client is installed at `C:\Program Files\SonarScanner\bin\sonar-scanner.bat`

### Fetching SonarQube Analysis Data

To fetch analysis results from SonarQube server using PowerShell with authentication:

**Method that works:**
1. Create a PowerShell script file (in fastmm4-avx-reports directory)
2. Use the authentication token from sonar-project.properties
3. Build Basic Auth header from token
4. Use Invoke-WebRequest with the Authorization header

**Example PowerShell script:**
```powershell
$token = 'sqp_217faf19d5b374e99568bcf8c19a1eee1de62b8f'
$pair = $token + ':'
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{Authorization = "Basic $base64"}

# Fetch metrics
$metricsUrl = 'http://localhost:9000/api/measures/component?component=FastMM4-AVX&metricKeys=bugs,vulnerabilities,code_smells,security_hotspots,coverage,duplicated_lines_density,ncloc,complexity,sqale_index,reliability_rating,security_rating,sqale_rating'
$metrics = Invoke-WebRequest -Uri $metricsUrl -Headers $headers -UseBasicParsing
$metrics.Content | Out-File -FilePath "C:\q\FastMM4-AVX\fastmm4-avx-reports\sonarqube-metrics.json" -Encoding UTF8

# Fetch issues
$issuesUrl = 'http://localhost:9000/api/issues/search?componentKeys=FastMM4-AVX&resolved=false&ps=500'
$issues = Invoke-WebRequest -Uri $issuesUrl -Headers $headers -UseBasicParsing
$issues.Content | Out-File -FilePath "C:\q\FastMM4-AVX\fastmm4-avx-reports\sonarqube-issues.json" -Encoding UTF8

# Fetch quality gate status
$qgUrl = 'http://localhost:9000/api/qualitygates/project_status?projectKey=FastMM4-AVX'
$qg = Invoke-WebRequest -Uri $qgUrl -Headers $headers -UseBasicParsing
$qg.Content | Out-File -FilePath "C:\q\FastMM4-AVX\fastmm4-avx-reports\sonarqube-quality-gate.json" -Encoding UTF8
```

**Execute with:**
```bash
powershell.exe -ExecutionPolicy Bypass -File "C:\q\FastMM4-AVX\fastmm4-avx-reports\fetch-sonarqube-data.ps1"
```

**Key Points:**
- Use string concatenation ($token + ':') instead of string interpolation to avoid PowerShell parsing issues with colon
- Use Basic Auth with token as username and empty password
- Save output files to fastmm4-avx-reports directory
- Use -UseBasicParsing to avoid HTML parsing dependencies

## Recent Security Audit Updates

The comprehensive security audit (`fastmm4-avx-reports/SECURITY_AUDIT.md`) has been updated to reflect the latest findings from both internal analysis and external issue reports (from the original `pleriche/FastMM4` GitHub repository).

**Key updates include:**

*   **Integer Overflow in Large Block Allocation (Critical):** This issue is now confirmed as **FIXED** as of 2025-11-26.
*   **New High Severity Issue:** "FPU-related Memory Corruption during Reallocation" (GitHub Issue #85) has been identified and confirmed as **VULNERABLE** in 32-bit builds.
*   **Multiple Medium and Low Severity Issues:** Several new issues related to application crashes, synchronization problems, and 64-bit type mismatches have been identified and documented.

Refer to `fastmm4-avx-reports/SECURITY_AUDIT.md` for the full, detailed report on all identified vulnerabilities, their impact, and recommended fixes.

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
- When you use Bash command to run Windows executable, use quotes and the full path name, e.g. S:\ProgramFiles\Utils\trivy.exe should become "S:\\ProgramFiles\\Utils\\trivy.exe".


## Code Quality and Security Analysis

FastMM4-AVX undergoes comprehensive code quality and security analysis using industry-standard tools:

### SonarQube Analysis (Latest Scan: 2025-11-29)
- **Quality Gate Status:** PASSED
- **Bugs:** 0
- **Vulnerabilities:** 0
- **Security Hotspots:** 0
- **Code Smells:** 10 (all minor, 25 minutes to resolve)
- **Code Duplication:** 0.0%
- **Quality Ratings:** A (Reliability), A (Security), A (Maintainability)

The analysis found zero security vulnerabilities, zero bugs, and no code duplication. All detected issues are minor code formatting concerns (tabs vs spaces, trailing whitespace, Dockerfile optimization suggestions) with LOW impact on maintainability. Total technical debt is only 25 minutes.

For detailed analysis results, see `fastmm4-avx-reports/sonarqube-analysis-report.md`.

### Security Scanning
The project is regularly scanned for security vulnerabilities using:
- **Trivy:** Container and dependency vulnerability scanning
- **SonarQube:** Static code analysis for security vulnerabilities and code quality
- **GitHub Actions:** Automated security testing on every commit

All security scans show zero HIGH or CRITICAL vulnerabilities.

