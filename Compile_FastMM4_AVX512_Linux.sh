#!/bin/bash
# Compile FastMM4_AVX512_Linux.asm for Linux ELF64 format
# Requires NASM (Netwide Assembler)

nasm -Ox -Ov -f elf64 FastMM4_AVX512_Linux.asm -o FastMM4_AVX512_Linux.o

if [ $? -eq 0 ]; then
    echo "FastMM4_AVX512_Linux.o compiled successfully"
else
    echo "Compilation failed"
    exit 1
fi
