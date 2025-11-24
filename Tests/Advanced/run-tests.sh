#!/bin/bash
# FastMM4-AVX Advanced Test Runner
# Usage: ./run-tests.sh [config1] [config2] ...
# Example: ./run-tests.sh Release Debug
# Run all: ./run-tests.sh

set -e

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "FastMM4-AVX Advanced Test Suite"
echo "========================================"
echo "Working directory: $(pwd)"

# FastMM4_AVX512_Linux.asm provides Linux System V AMD64 ABI support for AVX-512
# The .o file should be compiled with: nasm -Ox -f elf64 FastMM4_AVX512_Linux.asm

# Define configurations
declare -A CONFIGS
CONFIGS["Release"]="-O4"
CONFIGS["Debug"]="-dDEBUG -g -O-"
CONFIGS["FullDebugMode"]="-dFullDebugMode -O4"
CONFIGS["Align16Bytes"]="-dAlign16Bytes -O4"
CONFIGS["Align32Bytes"]="-dAlign32Bytes -O4"
CONFIGS["ForceSingleThreaded"]="-dForceSingleThreaded -O4"
CONFIGS["DontUseASMVersion"]="-dDontUseASMVersion -O4"
CONFIGS["AlwaysClearFreedMemory"]="-dAlwaysClearFreedMemory -O4"
CONFIGS["CriticalSectionSmall"]="-dDontUseSmallBlocksLockedCriticalSection -O4"
CONFIGS["CriticalSectionMedium"]="-dDontUseMediumBlocksLockedCriticalSection -O4"
CONFIGS["DisablePause"]="-dDisablePauseAndSwitchToThread -O4"
CONFIGS["DisableAVX512"]="-dDisableAVX512 -O4"

# Determine which configs to run
if [ $# -eq 0 ]; then
    # Run all configs
    SELECTED=("Release" "Debug" "FullDebugMode" "Align16Bytes" "Align32Bytes" "ForceSingleThreaded" "DontUseASMVersion" "AlwaysClearFreedMemory")
else
    # Run specified configs
    SELECTED=("$@")
fi

PASSED=0
FAILED=0
FAILED_NAMES=""

for NAME in "${SELECTED[@]}"; do
    FLAGS="${CONFIGS[$NAME]}"
    if [ -z "$FLAGS" ]; then
        echo "[ERROR] Unknown configuration: $NAME"
        echo "Available: ${!CONFIGS[@]}"
        continue
    fi

    echo ""
    echo "----------------------------------------"
    echo "Testing: $NAME"
    echo "Flags: $FLAGS -dIgnoreMemoryAllocatedBefore"
    echo "----------------------------------------"

    # Compile
    if fpc -B -Mdelphi -Tlinux -Px86_64 $FLAGS -dIgnoreMemoryAllocatedBefore -dDisableMemoryLeakReporting AdvancedTest.dpr 2>&1; then
        # Run
        if ./AdvancedTest 2>&1; then
            echo "[CONFIG PASS] $NAME"
            ((PASSED++)) || true
        else
            echo "[CONFIG FAIL] $NAME - tests failed"
            ((FAILED++)) || true
            FAILED_NAMES="$FAILED_NAMES $NAME"
        fi
    else
        echo "[CONFIG FAIL] $NAME - compilation failed"
        ((FAILED++)) || true
        FAILED_NAMES="$FAILED_NAMES $NAME"
    fi
done

echo ""
echo "========================================"
echo "SUMMARY: $PASSED configs passed, $FAILED configs failed"
if [ -n "$FAILED_NAMES" ]; then
    echo "Failed configs:$FAILED_NAMES"
fi
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
