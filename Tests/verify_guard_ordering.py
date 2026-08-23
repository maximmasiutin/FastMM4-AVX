#!/usr/bin/env python3
"""Reject security-guard ordering regressions in FastMM4.pas."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys


@dataclass(frozen=True)
class Rule:
    procedure: str
    architecture: str
    name: str
    start: str
    end: str
    guards: tuple[str, ...]
    guarded_use: str


# A conditional branch is protective only if it reads the flags its own
# compare or test just wrote, so nothing may sit between the two but comments,
# compiler directives and whitespace, all of which mask_comments blanks.
BRANCHES = ("jb ", "jae ", "ja ", "jnz ")

# A Pascal guard is protective only because its body leaves the routine, so
# the terminator is required as the last component, the way each assembly rule
# requires its rejecting branch.
EXIT = "Exit;"

SMALL_BOUNDS_PASCAL = (
    "if (NativeUInt(LPSmallBlockType) < NativeUInt(@SmallBlockTypes[0]))",
    "(NativeUInt(LPSmallBlockType) > NativeUInt(@SmallBlockTypes[NumSmallBlockTypes - 1]))",
    "mod SmallBlockTypeRecSize <> 0",
    EXIT)


def small_bounds_asm(accumulator: str, block_type: str, reject: str) -> tuple[str, ...]:
    """Every component of the assembly BlockType bounds and alignment guard.

    Naming each lea, compare and branch pins which comparison is which, so
    moving one bound out of sequence cannot be covered by the other matching.
    """
    return (
        f"lea {accumulator}, SmallBlockTypes",
        f"cmp {block_type}, {accumulator}",
        f"jb {reject}",
        f"lea {accumulator}, SmallBlockTypes[NumSmallBlockTypes * SmallBlockTypeRecSize]",
        f"cmp {block_type}, {accumulator}",
        f"jae {reject}",
        f"lea {accumulator}, SmallBlockTypes",
        f"neg {accumulator}",
        f"add {accumulator}, {block_type}",
        f"test {accumulator}, (SmallBlockTypeRecSize - 1)",
        f"jnz {reject}",
    )


RULES = (
    Rule("FastFreeMem", "Pascal", "pool pointer before BlockType read",
         "{Get a pointer to the block pool}", "{Validate that BlockType points within",
         ("if NativeUInt(LPSmallBlockPool) < $10000 then", EXIT),
         "LPSmallBlockType := LPSmallBlockPool^.BlockType;"),
    Rule("FastFreeMem", "Pascal", "small BlockType before clear",
         "LPSmallBlockType := LPSmallBlockPool^.BlockType;", "{Lock the block type}",
         SMALL_BOUNDS_PASCAL,
         "FillChar(APointer^, LPSmallBlockType^.BlockSize"),
    Rule("FastFreeMem", "Pascal", "medium size before clear",
         "{Guard: validate medium block size BEFORE", "Result := FreeMediumBlock(APointer);",
         # This one rejects with an else branch rather than an Exit, so the
         # else is the component that keeps the clear off the invalid path.
         ("if (LBlockSize < MinimumMediumBlockSize)",
          "(LBlockSize > (MediumBlockPoolSize - MediumBlockPoolHeaderSize))", "else"),
         "FillChar(APointer^, LBlockSize - BlockHeaderSize"),
    Rule("FastFreeMem", "32-bit ASM", "pool pointer before BlockType read",
         "jnz @NotSmallBlockInUse", "{Do we need to lock the block type?}",
         ("cmp edx, $10000", "jb @InvalidSmallBlock"),
         "mov ebx, TSmallBlockPoolHeader[edx].BlockType"),
    Rule("FastFreeMem", "32-bit ASM", "small BlockType before clear",
         "mov ebx, TSmallBlockPoolHeader[edx].BlockType", "{Do we need to lock the block type?}",
         small_bounds_asm("eax", "ebx", "@InvalidSmallBlock"),
         # The dereference of the validated BlockType is this load, not the
         # call that follows it, so the load is what the guards have to precede.
         "movzx edx, TSmallBlockType(ebx).BlockSize"),
    Rule("FastFreeMem", "32-bit ASM", "medium size before clear",
         "@FreeMediumBlock:", "{Free the medium block pointed to by eax",
         ("cmp edx, MinimumMediumBlockSize", "jb @InvalidMediumBlock",
          "cmp edx, MediumBlockPoolSize - MediumBlockPoolHeaderSize", "ja @InvalidMediumBlock"),
         "call System.@FillChar"),
    Rule("FastFreeMem", "64-bit ASM", "pool pointer before BlockType read",
         "jnz @NotSmallBlockInUse", "{Do we need to lock the block type?}",
         ("cmp rdx, $10000", "jb @InvalidSmallBlock"),
         "mov rbx, TSmallBlockPoolHeader[rdx].BlockType"),
    Rule("FastFreeMem", "64-bit ASM", "small BlockType before clear",
         "mov rbx, TSmallBlockPoolHeader[rdx].BlockType", "{Do we need to lock the block type?}",
         small_bounds_asm("rax", "rbx", "@InvalidSmallBlock"),
         "movzx edx, TSmallBlockType(rbx).BlockSize"),
    Rule("FastFreeMem", "64-bit ASM", "medium size before clear",
         "@FreeMediumBlock:", "{Free the medium block pointed to by rcx",
         ("cmp rdx, MinimumMediumBlockSize", "jb @InvalidMediumBlock",
          "cmp rdx, MediumBlockPoolSize - MediumBlockPoolHeaderSize", "ja @InvalidMediumBlock"),
         "call System.@FillChar"),
    Rule("FastReallocMem", "Pascal", "pool pointer before BlockType read",
         "{-----------------------------------Small block", "{Is it an upsize or a downsize?}",
         ("if NativeUInt(LBlockHeader) < $10000 then", EXIT),
         "LPSmallBlockType := PSmallBlockPoolHeader(LBlockHeader)^.BlockType;"),
    Rule("FastReallocMem", "Pascal", "small BlockType before size read",
         "LPSmallBlockType := PSmallBlockPoolHeader(LBlockHeader)^.BlockType;",
         "{Is it an upsize or a downsize?}",
         SMALL_BOUNDS_PASCAL,
         "LOldAvailableSize := LPSmallBlockType^.BlockSize"),
    Rule("FastReallocMem", "Pascal", "medium size before arithmetic",
         "{-------------------------------Medium block", "{Is the next block free?}",
         ("if (LOldAvailableSize < MinimumMediumBlockSize)",
          "(LOldAvailableSize > (MediumBlockPoolSize - MediumBlockPoolHeaderSize))", EXIT),
         "LOldBlockSize := LOldAvailableSize"),
    Rule("FastReallocMem", "32-bit ASM", "pool pointer before BlockType read",
         "jnz @NotASmallBlock", "{Is it an upsize or a downsize?}",
         ("cmp ecx, $10000", "jb @InvalidSmallReallocPtr"),
         "mov ebx, TSmallBlockPoolHeader[ecx].BlockType"),
    Rule("FastReallocMem", "32-bit ASM", "small BlockType before size read",
         "mov ebx, TSmallBlockPoolHeader[ecx].BlockType", "{Is it an upsize or a downsize?}",
         small_bounds_asm("eax", "ebx", "@InvalidSmallReallocPtr"),
         "movzx ecx, TSmallBlockType[ebx].BlockSize"),
    Rule("FastReallocMem", "32-bit ASM", "medium size before address arithmetic",
         "{-------------------------------Medium block", "{Subtract the block header size",
         ("cmp ecx, MinimumMediumBlockSize", "jb @InvalidMediumReallocPtr",
          "cmp ecx, MediumBlockPoolSize - MediumBlockPoolHeaderSize",
          "ja @InvalidMediumReallocPtr"),
         "lea edi, [eax + ecx]"),
    Rule("FastReallocMem", "64-bit ASM", "pool pointer before BlockType read",
         "jnz @NotASmallBlock", "{Is it an upsize or a downsize?}",
         ("cmp rcx, $10000", "jb @InvalidSmallReallocPtr"),
         "mov rbx, TSmallBlockPoolHeader[rcx].BlockType"),
    Rule("FastReallocMem", "64-bit ASM", "small BlockType before size read",
         "mov rbx, TSmallBlockPoolHeader[rcx].BlockType", "{Is it an upsize or a downsize?}",
         small_bounds_asm("rax", "rbx", "@InvalidSmallReallocPtr"),
         "movzx ecx, TSmallBlockType[rbx].BlockSize"),
    Rule("FastReallocMem", "64-bit ASM", "medium size before address arithmetic",
         "{-------------------------------Medium block", "{Subtract the block header size",
         ("cmp ecx, MinimumMediumBlockSize", "jb @InvalidMediumReallocPtr",
          "cmp ecx, MediumBlockPoolSize - MediumBlockPoolHeaderSize",
          "ja @InvalidMediumReallocPtr"),
         "lea rdi, [rsi + rcx]"),
)


def line_number(text: str, position: int) -> int:
    return text.count("\n", 0, position) + 1


def mask_comments(text: str) -> str:
    """Blank every Pascal comment, keeping each character's position.

    A guard commented out is a guard removed, so guards and guarded uses are
    matched against this text rather than the raw source. Positions are
    preserved, so an offset found here still names its line in the original.
    Scope anchors keep matching the raw source, since several of them are
    themselves comments.
    """
    out = list(text)
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char == "'":  # a quoted brace must not open a comment
            index += 1
            while index < length and text[index] != "'" and text[index] != "\n":
                index += 1
            index += 1
            continue
        closing = None
        if char == "{":
            closing = "}"
        elif text.startswith("(*", index):
            closing = "*)"
        elif text.startswith("//", index):
            closing = "\n"
        if closing is None:
            index += 1
            continue
        stop = text.find(closing, index + len(closing))
        stop = length if stop < 0 else stop + (0 if closing == "\n" else len(closing))
        for position in range(index, stop):
            if out[position] != "\n":
                out[position] = " "
        index = stop
    return "".join(out)


def check_rule(text: str, rule: Rule, base: int = 0, whole_text: str | None = None) -> str | None:
    start = text.find(rule.start)
    end = text.find(rule.end, start + len(rule.start)) if start >= 0 else -1
    scoped = start >= 0 and end >= 0
    active = mask_comments(text)
    use = active.find(rule.guarded_use, start, end) if scoped else -1

    # Each guard must appear after the one before it, so a component moved out
    # of sequence is reported rather than accepted because a later one matched.
    found: list[int] = []
    cursor = start
    for guard in rule.guards:
        at = active.find(guard, cursor, end) if scoped and cursor >= 0 else -1
        found.append(at)
        cursor = at + len(guard) if at >= 0 else -1

    # A rejecting branch must sit directly after the compare or test whose
    # flags it reads; anything else between the two writes flags of its own.
    detached = []
    for index, (guard, at) in enumerate(zip(rule.guards, found)):
        if index == 0 or not guard.startswith(BRANCHES) or at < 0:
            continue
        previous = found[index - 1]
        if previous >= 0 and active[previous + len(rule.guards[index - 1]):at].strip():
            detached.append(guard)

    if scoped and use >= 0 and not detached and all(at >= 0 and at < use for at in found):
        return None

    source_text = whole_text or text

    def position(offset: int) -> str:
        absolute = base + offset
        return "missing" if offset < 0 else f"line {line_number(source_text, absolute)}, byte {absolute}"

    lines = [f"FAIL {rule.procedure} [{rule.architecture}] {rule.name}",
             f"  scope-start {rule.start!r}: {position(start)}",
             f"  scope-end   {rule.end!r}: {position(end)}"]
    for guard, at in zip(rule.guards, found):
        note = " (detached from the check it branches on)" if guard in detached else ""
        lines.append(f"  guard       {guard!r}: {position(at)}{note}")
    lines.append(f"  guarded-use {rule.guarded_use!r}: {position(use)}")
    return "\n".join(lines)


def fixture_rule() -> Rule:
    return Rule("FixtureProcedure", "fixture", "guards in order before guarded use",
                "{fixture-start}", "{fixture-end}",
                ("ValidateBounds;", "ValidateAlignment;"), "GuardedUse;")


def run_fixture_tests(fixtures: Path) -> list[str]:
    errors: list[str] = []

    def read(name: str) -> str:
        return (fixtures / name).read_text(encoding="utf-8")

    if failure := check_rule(read("valid.pas"), fixture_rule()):
        errors.append("valid fixture was rejected:\n" + failure)
    if check_rule(read("invalid.pas"), fixture_rule()) is None:
        errors.append("invalid fixture was accepted; its guards sit after the guarded use")
    # Two guards, both before the guarded use, in the wrong order relative to
    # each other, which is what a verifier ignoring inter-guard order accepts.
    if check_rule(read("reordered.pas"), fixture_rule()) is None:
        errors.append("reordered fixture was accepted; its two guards are in the wrong order")
    # One guard present in the text but commented out, which the compiler drops.
    if check_rule(read("commented.pas"), fixture_rule()) is None:
        errors.append("commented fixture was accepted; one of its guards is commented out")
    return errors


def source_sections(text: str) -> dict[tuple[str, str], tuple[str, int]]:
    free_signature = "function FastFreeMem(APointer: Pointer)"
    free_start = text.index(free_signature)
    free_start = text.index(free_signature, free_start + len(free_signature))
    realloc_start = text.index("function FastReallocMem(", free_start)
    realloc_end = text.index("{Allocates a block and fills it with zeroes}", realloc_start)

    def partition(procedure: str, start: int, end: int, asm_else: str,
                  x86_start: str, x64_start: str) -> dict[tuple[str, str], tuple[str, int]]:
        asm = text.index(asm_else, start, end)
        x86 = text.index(x86_start, asm, end)
        x64 = text.index(x64_start, x86, end)
        return {
            (procedure, "Pascal"): (text[start:asm], start),
            (procedure, "32-bit ASM"): (text[x86:x64], x86),
            (procedure, "64-bit ASM"): (text[x64:end], x64),
        }

    sections = partition("FastFreeMem", free_start, realloc_start,
                         "{$ELSE FastFreememNeedAssemberCode}", "{$IFDEF 32BIT}", "{$ELSE 32BIT}")
    sections.update(partition("FastReallocMem", realloc_start, realloc_end,
                              "{$ELSE FastReallocMemNeedAssemberCode}", "{$IFDEF 32BIT}",
                              "{-----------------64-bit BASM FastReallocMem"))
    return sections


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path,
                        help="FastMM4.pas (defaults to the repository root copy)")
    args = parser.parse_args()
    tests_dir = Path(__file__).resolve().parent
    source = args.source or tests_dir.parent / "FastMM4.pas"
    text = source.read_text(encoding="utf-8-sig")
    errors = run_fixture_tests(tests_dir / "guard_order_fixtures")
    sections = source_sections(text)
    for rule in RULES:
        section, base = sections[(rule.procedure, rule.architecture)]
        if failure := check_rule(section, rule, base, text):
            errors.append(failure)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    guards = sum(len(rule.guards) for rule in RULES)
    print(f"Guard ordering OK: {len(RULES)} source rules, {guards} guard components; "
          "valid, invalid, reordered and commented fixtures verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
