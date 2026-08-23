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
    guard: str
    guarded_use: str


RULES = (
    Rule("FastFreeMem", "Pascal", "small BlockType before clear", "{Get the block type}", "{Lock the block type}",
         "if (NativeUInt(LPSmallBlockType) < NativeUInt(@SmallBlockTypes[0]))", "FillChar(APointer^, LPSmallBlockType^.BlockSize"),
    Rule("FastFreeMem", "Pascal", "medium size before clear", "{Guard: validate medium block size BEFORE", "Result := FreeMediumBlock(APointer);",
         "if (LBlockSize < MinimumMediumBlockSize)", "FillChar(APointer^, LBlockSize - BlockHeaderSize"),
    Rule("FastFreeMem", "32-bit ASM", "small BlockType before clear", "cmp edx, $10000", "{Do we need to lock the block type?}",
         "test eax, (SmallBlockTypeRecSize - 1)", "call System.@FillChar"),
    Rule("FastFreeMem", "32-bit ASM", "medium size before clear", "@FreeMediumBlock:", "{Free the medium block pointed to by eax", 
         "cmp edx, MediumBlockPoolSize - MediumBlockPoolHeaderSize", "call System.@FillChar"),
    Rule("FastFreeMem", "64-bit ASM", "small BlockType before clear", "cmp rdx, $10000", "{Do we need to lock the block type?}",
         "test rax, (SmallBlockTypeRecSize - 1)", "call System.@FillChar"),
    Rule("FastFreeMem", "64-bit ASM", "medium size before clear", "@FreeMediumBlock:", "{Free the medium block pointed to by rcx", 
         "cmp rdx, MediumBlockPoolSize - MediumBlockPoolHeaderSize", "call System.@FillChar"),
    Rule("FastReallocMem", "Pascal", "small BlockType before size read", "{Get the block type}", "{Is it an upsize or a downsize?}",
         "if (NativeUInt(LPSmallBlockType) < NativeUInt(@SmallBlockTypes[0]))", "LOldAvailableSize := LPSmallBlockType^.BlockSize"),
    Rule("FastReallocMem", "Pascal", "medium size before arithmetic", "{-------------------------------Medium block", "{Is the next block free?}",
         "if (LOldAvailableSize < MinimumMediumBlockSize)", "LOldBlockSize := LOldAvailableSize"),
    Rule("FastReallocMem", "32-bit ASM", "small BlockType before size read", "cmp ecx, $10000", "{Is it an upsize or a downsize?}",
         "test eax, (SmallBlockTypeRecSize - 1)", "movzx ecx, TSmallBlockType[ebx].BlockSize"),
    Rule("FastReallocMem", "32-bit ASM", "medium size before address arithmetic", "{-------------------------------Medium block", "{Subtract the block header size",
         "cmp ecx, MediumBlockPoolSize - MediumBlockPoolHeaderSize", "lea edi, [eax + ecx]"),
    Rule("FastReallocMem", "64-bit ASM", "small BlockType before size read", "cmp rcx, $10000", "{Is it an upsize or a downsize?}",
         "test rax, (SmallBlockTypeRecSize - 1)", "movzx ecx, TSmallBlockType[rbx].BlockSize"),
    Rule("FastReallocMem", "64-bit ASM", "medium size before address arithmetic", "{-------------------------------Medium block", "{Subtract the block header size",
         "cmp ecx, MediumBlockPoolSize - MediumBlockPoolHeaderSize", "lea rdi, [rsi + rcx]"),
)


def line_number(text: str, position: int) -> int:
    return text.count("\n", 0, position) + 1


def check_rule(text: str, rule: Rule, base: int = 0, whole_text: str | None = None) -> str | None:
    start = text.find(rule.start)
    end = text.find(rule.end, start + len(rule.start)) if start >= 0 else -1
    guard = text.find(rule.guard, start, end) if start >= 0 and end >= 0 else -1
    use = text.find(rule.guarded_use, start, end) if start >= 0 and end >= 0 else -1
    if start >= 0 and end >= 0 and guard >= 0 and use >= 0 and guard < use:
        return None

    source_text = whole_text or text

    def position(offset: int) -> str:
        absolute = base + offset
        return "missing" if offset < 0 else f"line {line_number(source_text, absolute)}, byte {absolute}"

    return (f"FAIL {rule.procedure} [{rule.architecture}] {rule.name}\n"
            f"  scope-start {rule.start!r}: {position(start)}\n"
            f"  scope-end   {rule.end!r}: {position(end)}\n"
            f"  guard       {rule.guard!r}: {position(guard)}\n"
            f"  guarded-use {rule.guarded_use!r}: {position(use)}")


def fixture_rule() -> Rule:
    return Rule("FixtureProcedure", "fixture", "guard before guarded use",
                "{fixture-start}", "{fixture-end}", "ValidateGuard;", "GuardedUse;")


def run_fixture_tests(fixtures: Path) -> list[str]:
    errors: list[str] = []
    valid = (fixtures / "valid.pas").read_text(encoding="utf-8")
    invalid = (fixtures / "invalid.pas").read_text(encoding="utf-8")
    if failure := check_rule(valid, fixture_rule()):
        errors.append("valid fixture was rejected:\n" + failure)
    if check_rule(invalid, fixture_rule()) is None:
        errors.append("invalid fixture was accepted; its guard is deliberately reversed")
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
    print(f"Guard ordering OK: {len(RULES)} source rules; valid and invalid fixtures verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
