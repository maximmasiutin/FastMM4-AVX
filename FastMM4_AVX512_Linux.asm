; This file enables AVX-512 code for FastMM4-AVX on Linux (System V AMD64 ABI).
; Use "nasm -Ox -f elf64 FastMM4_AVX512_Linux.asm -o FastMM4_AVX512_Linux.o" to compile
; You can get The Netwide Assembler (NASM) from http://www.nasm.us/

; This file is a part of FastMM4-AVX.
; - Copyright (C) 2017-2020 Ritlabs, SRL. All rights reserved.
; - Copyright (C) 2020-2021 Maxim Masiutin. All rights reserved.
; - Copyright (C) 2025 Maxim Masiutin. All rights reserved.
; Written by Maxim Masiutin <maxim@masiutin.com>

; FastMM4-AVX is a fork of the Fast Memory Manager 4.992 by Pierre le Riche

; FastMM4-AVX is released under a dual license, and you may choose to use it
; under either the Mozilla Public License 2.0 (MPL 2.1, available from
; https://www.mozilla.org/en-US/MPL/2.0/) or the GNU Lesser General Public
; License Version 3, dated 29 June 2007 (LGPL 3, available from
; https://www.gnu.org/licenses/lgpl.html).

; ============================================================================
; CALLING CONVENTION DIFFERENCE:
; ============================================================================
; Windows x64:  rcx=1st, rdx=2nd, r8=3rd, r9=4th (caller saves xmm0-5)
; Linux AMD64:  rdi=1st, rsi=2nd, rdx=3rd, rcx=4th (caller saves xmm0-7)
;
; This file uses Linux System V AMD64 ABI:
;   rdi = source pointer (was rcx in Windows version)
;   rsi = destination pointer (was rdx in Windows version)
;   rdx = size (for MoveX32LpAvx512WithErms, was r8 in Windows version)
; ============================================================================

; This code uses zmm26 - zmm31 registers to avoid AVX-SSE transition penalty.
; These registers (zmm16 - zmm31) have no non-VEX counterpart. According to the
; advice of Agner Fog, there is no state transition and no penalty for mixing
; zmm16 - zmm31 with non-VEX SSE code. By using these registers (zmm16 - zmm31)
; rather than zmm0-xmm15 we save us from calling "vzeroupper".
; Source:
; https://stackoverflow.com/questions/43879935/avoiding-avx-sse-vex-transition-penalties/54587480#54587480


%define	EVEXR512N0	zmm31
%define	EVEXR512N1	zmm30
%define	EVEXR512N2	zmm29
%define	EVEXR512N3	zmm28
%define	EVEXR512N4	zmm27
%define	EVEXR512N5	zmm26
%define	EVEXR256N0	ymm31
%define	EVEXR256N1	ymm30
%define	EVEXR256N2	ymm29
%define	EVEXR256N3	ymm28
%define	EVEXR256N4	ymm27
%define	EVEXR256N5	ymm26
%define	EVEXR128N0	xmm31
%define	EVEXR128N1	xmm30
%define	EVEXR128N2	xmm29
%define	EVEXR128N3	xmm28
%define	EVEXR128N4	xmm27
%define	EVEXR128N5	xmm26


section	.text

	global		Move24AVX512
	global		Move56AVX512
	global		Move88AVX512
	global		Move120AVX512
	global		Move152AVX512
	global		Move184AVX512
	global		Move216AVX512
	global		Move248AVX512
	global		Move280AVX512
	global		Move312AVX512
	global		Move344AVX512
	global		MoveX32LpAvx512WithErms

	%use		smartalign
	ALIGNMODE	p6, 32	; p6 NOP strategy, and jump over the NOPs only if they're 32B or larger.

; ============================================================================
; Linux versions using System V AMD64 ABI: rdi=src, rsi=dst
; ============================================================================

	align		16
Move24AVX512:
	; rdi = source, rsi = destination
	vmovdqa64	EVEXR128N0, [rdi]
	mov		rax, [rdi+10h]
	vmovdqa64	[rsi], EVEXR128N0
	mov		[rsi+10h], rax
	vpxord		EVEXR128N0, EVEXR128N0, EVEXR128N0
	ret

Move56AVX512:
	; rdi = source, rsi = destination
	vmovdqa64	EVEXR256N0, [rdi+00h]
	vmovdqa64	EVEXR128N1, [rdi+20h]
	mov		rax, [rdi+30h]
	vmovdqa64	[rsi+00h], EVEXR256N0
	vmovdqa64	[rsi+20h], EVEXR128N1
	mov		[rsi+30h], rax
	vpxord		EVEXR256N0, EVEXR256N0, EVEXR256N0
	vpxord		EVEXR128N1, EVEXR128N1, EVEXR128N1
	ret

	align		16
Move88AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi]
	vmovdqa64	EVEXR128N1, [rdi+40h]
	mov		rax, [rdi+50h]
	vmovdqu64	[rsi], EVEXR512N0
	vmovdqa64	[rsi+40h], EVEXR128N1
	mov		[rsi+50h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR128N1,EVEXR128N1,EVEXR128N1
	ret

	align		16
Move120AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi]
	vmovdqa64	EVEXR256N1, [rdi+40h]
	vmovdqa64	EVEXR128N2, [rdi+60h]
	mov		rax, [rdi + 70h]
	vmovdqu64	[rsi], EVEXR512N0
	vmovdqa64	[rsi+40h], EVEXR256N1
	vmovdqa64	[rsi+60h], EVEXR128N2
	mov		[rsi+70h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR256N1,EVEXR256N1,EVEXR256N1
	vpxord		EVEXR128N2,EVEXR128N2,EVEXR128N2
	ret

	align		16
Move152AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqa64	EVEXR128N2, [rdi+80h]
	mov		rax, [rdi+90h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqa64	[rsi+80h], EVEXR128N2
	mov		[rsi+90h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR128N2,EVEXR128N2,EVEXR128N2
	ret

	align		16
Move184AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqa64	EVEXR256N2, [rdi+80h]
	vmovdqa64	EVEXR128N3, [rdi+0A0h]
	mov		rax, [rdi+0B0h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqa64	[rsi+80h], EVEXR256N2
	vmovdqa64	[rsi+0A0h],EVEXR128N3
	mov		[rsi+0B0h],rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR256N2,EVEXR256N2,EVEXR256N2
	vpxord		EVEXR128N3,EVEXR128N3,EVEXR128N3
	ret

	align		16
Move216AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqu64	EVEXR512N2, [rdi+80h]
	vmovdqa64	EVEXR128N3, [rdi+0C0h]
	mov		rax, [rdi+0D0h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqu64	[rsi+80h], EVEXR512N2
	vmovdqa64	[rsi+0C0h], EVEXR128N3
	mov		[rsi+0D0h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR512N2,EVEXR512N2,EVEXR512N2
	vpxord		EVEXR128N3,EVEXR128N3,EVEXR128N3
	ret

	align		16
Move248AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqu64	EVEXR512N2, [rdi+80h]
	vmovdqa64	EVEXR256N3, [rdi+0C0h]
	vmovdqa64	EVEXR128N4, [rdi+0E0h]
	mov		rax, [rdi+0F0h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqu64	[rsi+80h], EVEXR512N2
	vmovdqa64	[rsi+0C0h], EVEXR256N3
	vmovdqa64	[rsi+0E0h], EVEXR128N4
	mov		[rsi+0F0h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR512N2,EVEXR512N2,EVEXR512N2
	vpxord		EVEXR256N3,EVEXR256N3,EVEXR256N3
	vpxord		EVEXR128N4,EVEXR128N4,EVEXR128N4
	ret

	align		16
Move280AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqu64	EVEXR512N2, [rdi+80h]
	vmovdqu64	EVEXR512N3, [rdi+0C0h]
	vmovdqa64	EVEXR128N4, [rdi+100h]
	mov		rax, [rdi+110h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqu64	[rsi+80h], EVEXR512N2
	vmovdqu64	[rsi+0C0h], EVEXR512N3
	vmovdqa64	[rsi+100h], EVEXR128N4
	mov		[rsi+110h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR512N2,EVEXR512N2,EVEXR512N2
	vpxord		EVEXR512N3,EVEXR512N3,EVEXR512N3
	vpxord		EVEXR128N4,EVEXR128N4,EVEXR128N4
	ret

	align		16
Move312AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqu64	EVEXR512N2, [rdi+80h]
	vmovdqu64	EVEXR512N3, [rdi+0C0h]
	vmovdqa64	EVEXR256N4, [rdi+100h]
	vmovdqa64	EVEXR128N5, [rdi+120h]
	mov		rax, [rdi+130h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqu64	[rsi+80h], EVEXR512N2
	vmovdqu64	[rsi+0C0h], EVEXR512N3
	vmovdqa64	[rsi+100h], EVEXR256N4
	vmovdqa64	[rsi+120h], EVEXR128N5
	mov		[rsi+130h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR512N2,EVEXR512N2,EVEXR512N2
	vpxord		EVEXR512N3,EVEXR512N3,EVEXR512N3
	vpxord		EVEXR256N4,EVEXR256N4,EVEXR256N4
	vpxord		EVEXR128N5,EVEXR128N5,EVEXR128N5
	ret

	align		16
Move344AVX512:
	; rdi = source, rsi = destination
	vmovdqu64	EVEXR512N0, [rdi+00h]
	vmovdqu64	EVEXR512N1, [rdi+40h]
	vmovdqu64	EVEXR512N2, [rdi+80h]
	vmovdqu64	EVEXR512N3, [rdi+0C0h]
	vmovdqu64	EVEXR512N4, [rdi+100h]
	vmovdqa64	EVEXR128N5, [rdi+140h]
	mov		rax, [rdi+150h]
	vmovdqu64	[rsi+00h], EVEXR512N0
	vmovdqu64	[rsi+40h], EVEXR512N1
	vmovdqu64	[rsi+80h], EVEXR512N2
	vmovdqu64	[rsi+0C0h], EVEXR512N3
	vmovdqu64	[rsi+100h], EVEXR512N4
	vmovdqa64	[rsi+140h], EVEXR128N5
	mov		[rsi+150h], rax
	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1
	vpxord		EVEXR512N2,EVEXR512N2,EVEXR512N2
	vpxord		EVEXR512N3,EVEXR512N3,EVEXR512N3
	vpxord		EVEXR512N4,EVEXR512N4,EVEXR512N4
	vpxord		EVEXR128N5,EVEXR128N5,EVEXR128N5
	ret


	align		16
MoveX32LpAvx512WithErms:
	; Linux System V AMD64 ABI: rdi=src, rsi=dst, rdx=size
	; Note: Linux already uses rdi/rsi for rep movsb, no need to save/restore

; Make the counter negative based: The last 8 bytes are moved separately

	mov		eax, 8
	sub		rdx, rax
	add		rdi, rdx
	add		rsi, rdx
	neg		rdx
	jns		@MoveLast8Linux

	cmp		rdx, -2048	; According to the Intel Manual, rep movsb outperforms AVX copy on blocks of 2048 bytes and above
	jg		@DontDoRepMovsbLinux

	align		4

@DoRepMovsbLinux:
	; Linux already uses rdi=dest, rsi=src for rep movsb - but reversed!
	; rep movsb expects rsi=src, rdi=dst, but our API has rdi=src, rsi=dst
	; So we need to swap them
	push		rdi
	push		rsi
	lea		r10, [rdi+rdx]	; r10 = original src + offset
	lea		r11, [rsi+rdx]	; r11 = original dst + offset
	mov		rsi, r10	; rsi = source for rep movsb
	mov		rdi, r11	; rdi = destination for rep movsb
	neg		rdx
	add		rdx, rax
	mov		rcx, rdx
	cld
	rep		movsb
	pop		rsi
	pop		rdi
	jmp		@exitLinux

	align		16

@DontDoRepMovsbLinux:
	cmp		rdx, -(128+64)
	jg		@SmallAvxMoveLinux

	mov		eax, 128

	sub		rdi, rax
	sub		rsi, rax
	add		rdx, rax


	lea		r9, [rsi+rdx]
	test		r9b, 63
	jz		@Avx512BigMoveDestAlignedLinux

; destination is already 32-bytes aligned, so we just align by 64 bytes
	vmovdqa64	EVEXR256N0, [rdi+rdx]
	vmovdqa64	[rsi+rdx], EVEXR256N0
	add		rdx, 20h

	align		16

@Avx512BigMoveDestAlignedLinux:
	vmovdqu64	EVEXR512N0, [rdi+rdx+00h]
	vmovdqu64	EVEXR512N1, [rdi+rdx+40h]
	vmovdqa64	[rsi+rdx+00h], EVEXR512N0
	vmovdqa64	[rsi+rdx+40h], EVEXR512N1
	add		rdx, rax
	js		@Avx512BigMoveDestAlignedLinux

	sub		rdx, rax
	add		rdi, rax
	add		rsi, rax

	align		16

@SmallAvxMoveLinux:

@MoveLoopAvxLinux:
; Move a 16 byte block
	vmovdqa64	EVEXR128N0, [rdi+rdx]
	vmovdqa64	[rsi+rdx], EVEXR128N0

; Are there another 16 bytes to move?
	add		rdx, 16
	js		@MoveLoopAvxLinux

	vpxord		EVEXR512N0,EVEXR512N0,EVEXR512N0
	vpxord		EVEXR512N1,EVEXR512N1,EVEXR512N1

	align		8
@MoveLast8Linux:
; Do the last 8 bytes
	mov		rax, [rdi+rdx]
	mov		[rsi+rdx], rax
@exitLinux:
	ret

; Mark stack as non-executable for security (prevents linker warning)
section .note.GNU-stack noalloc noexec nowrite progbits
