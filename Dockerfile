# FastMM4-AVX Test Docker Container
# =================================
# Build: docker build -t fastmm4-avx-tests .
# Run all tests: docker run --rm fastmm4-avx-tests
# Run specific config: docker run --rm fastmm4-avx-tests Release
# Run multiple: docker run --rm fastmm4-avx-tests Release Debug FullDebugMode
#
# Available configurations:
#   Release, Debug, FullDebugMode, Align16Bytes, Align32Bytes,
#   ForceSingleThreaded, DontUseASMVersion, AlwaysClearFreedMemory,
#   CriticalSectionSmall, CriticalSectionMedium, DisablePause

FROM ubuntu:22.04

LABEL maintainer="FastMM4-AVX"
LABEL description="Docker container for running FastMM4-AVX advanced tests"

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install FreePascal compiler and NASM for AVX-512 assembly
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    fpc \
    nasm \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for running tests
RUN useradd -m -u 1000 -s /bin/bash testuser

# Create working directory structure
WORKDIR /fastmm4-avx
RUN mkdir -p Tests/Advanced Tests/Simple

# Copy source files
COPY FastMM4.pas FastMM4Messages.pas FastMM4Options.inc ./
COPY FastMM4_AVX512_Linux.asm ./
COPY Tests/Advanced/AdvancedTest.dpr Tests/Advanced/run-tests.sh ./Tests/Advanced/

# Compile AVX-512 assembly for Linux ELF64 format
# FastMM4_AVX512_Linux.asm uses Linux System V AMD64 ABI (rdi, rsi, rdx)
RUN nasm -Ox -Ov -f elf64 FastMM4_AVX512_Linux.asm -o FastMM4_AVX512_Linux.o

# Convert line endings and make test scripts executable
RUN sed -i 's/\r$//' /fastmm4-avx/Tests/Advanced/run-tests.sh && chmod +x /fastmm4-avx/Tests/Advanced/run-tests.sh

# Change ownership to non-root user
RUN chown -R testuser:testuser /fastmm4-avx

# Set working directory to test location
WORKDIR /fastmm4-avx/Tests/Advanced

# Switch to non-root user
USER testuser

# Entry point - run tests script
ENTRYPOINT ["./run-tests.sh"]
