#!/usr/bin/env python3
"""Check call-frame directives in FastMM4 Pascal assembler routines.

The checker is deliberately symbolic: it compares the conditional-compilation
path of every CALL with the paths of .NOFRAME, NOSTACKFRAME and .PARAMS instead
of treating mutually exclusive Windows/Unix or Delphi/FreePascal branches as
one routine.
"""

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


DIRECTIVE_RE = re.compile(
    r"\{\$(IFDEF|IFNDEF|IFOPT|IF|ELSEIF|ELSE|ENDIF|IFEND)\b\s*([^}]*)\}",
    re.I,
)
DECL_RE = re.compile(
    r"^\s*(?:(?:class|constructor|destructor)\s+)?(?:procedure|function)\s+([^;(]+)",
    re.I,
)
CALL_RE = re.compile(r"^\s*(?:@*\w+:\s*)?call\s+([^\s;{]+)", re.I)
NOFRAME_RE = re.compile(r"^\s*\.noframe\s*$", re.I)
PARAMS_RE = re.compile(r"^\s*\.params\s+(\d+)\s*$", re.I)
SYMBOL_GUARD_RE = re.compile(
    r"^(not\s+)?(?:defined\s*\(\s*(\w+)\s*\)|(\w+))$", re.I
)
ASM_START_RE = re.compile(r"^\s*asm\s*(//.*|\{[^$].*)?$", re.I)
NOSTACK_LINE_RE = re.compile(r"^\s*nostackframe\s*;?\s*$", re.I)
ASM_END_RE = re.compile(r"^\s*end;\s*(//.*|\{[^$].*)?$", re.I)

type Condition = dict[str, bool]
type Counts = dict[str, int]
SOURCE_SUFFIXES = {".asm", ".dpr", ".inc", ".lpr", ".pas", ".pp"}

UNREACHABLE: Condition = {"UNREACHABLE": True}

IMPLICATIONS: tuple[tuple[Condition, Condition], ...] = (
    (UNREACHABLE, {"32BIT": True, "64BIT": True}),
    ({"32BIT": True}, {"64BIT": False}),
    ({"64BIT": True}, {"32BIT": False}),
    ({"32BIT": False}, {"64BIT": True}),
    ({"64BIT": False}, {"32BIT": True}),
    ({"WIN32": True}, {"32BIT": True}),
    ({"WIN64": True}, {"64BIT": True}),
    ({"CPU32": True}, {"32BIT": True}),
    ({"CPU64": True}, {"64BIT": True}),
    ({"FPC64BIT": True}, {"FPC": True, "64BIT": True}),
    ({"ENABLEAVX": True}, {"64BIT": True}),
    ({"ENABLEAVX512": True}, {"64BIT": True}),
    ({"FPC": True, "64BIT": True}, {"FPC64BIT": True}),
    ({"64BIT": False}, {"FPC64BIT": False}),
    ({"FPC": False}, {"FPC64BIT": False}),
    ({"FPC64BIT": False, "UNIX": False}, {"ALLOWASMNOFRAME": True}),
    (
        {"ALLOWASMNOFRAME": True},
        {"FPC64BIT": False, "UNIX": False, "ALLOWASMPARAMS": True},
    ),
    ({"ALLOWASMPARAMS": True}, {"ALLOWASMNOFRAME": True}),
    ({"UNIX": True}, {"WINDOWS": False}),
    ({"WINDOWS": True}, {"UNIX": False}),
    ({"CHECKPAUSEANDSWITCHTOTHREADFORASMVERSION": True}, {"32BIT": True}),
    ({"USEORIGINALFASTMM4_LOCKMEDIUMBLOCKSASM": True}, {"32BIT": True}),
)


def read_source(path: Path) -> str:
    """Decode a Pascal-family source without losing legacy single-byte text."""
    data = path.read_bytes()
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("latin-1")


@dataclass
class Marker:
    """A relevant assembly marker and its conditional-compilation path."""
    line: int
    condition: Condition
    text: str


@dataclass
class AsmRoutine:
    """Calls and frame directives collected from one assembler routine."""
    name: str
    declaration_line: int
    asm_line: int
    end_line: int = 0
    calls: list[Marker] = field(default_factory=list)
    noframes: list[Marker] = field(default_factory=list)
    params: list[Marker] = field(default_factory=list)


@dataclass
class Branch:
    """One active conditional-compilation branch and the guards before it."""
    prior: list[Condition]
    guard: Condition
    current: Condition


def guard_condition(kind: str, value: str) -> Condition:
    """Return the symbolic condition one directive guard asserts.

    IFDEF X, IF Defined(X), IF X and the ELSEIF forms of the same symbol map
    to one key, so a repeated guard is recognised as such; IFNDEF X and
    IF not Defined(X) assert the symbol false. Any other expression stays
    opaque under an EXPR: key.
    """
    value = " ".join(value.strip().split())
    kind = kind.upper()
    if kind in {"IFDEF", "IFNDEF"}:
        symbols = value.split()
        key = symbols[0].upper() if symbols else "EXPR:<EMPTY>"
        return {key: kind == "IFDEF"}
    if kind != "IFOPT":
        match = SYMBOL_GUARD_RE.match(value)
        if match:
            symbol = (match.group(2) or match.group(3)).upper()
            return {symbol: match.group(1) is None}
    return {"EXPR:" + value.upper(): True}


def merged_condition(stack: list[Branch]) -> Condition:
    """Combine the active conditions from all nested branches."""
    result: Condition = {}
    for branch in stack:
        for key, state in branch.current.items():
            if result.get(key, state) is not state:
                return dict(UNREACHABLE)
            result[key] = state
    return result


def negated_prior(branch: Branch) -> Condition:
    """Negate the guard of every earlier sibling branch."""
    return {
        key: not state
        for previous in branch.prior
        for key, state in previous.items()
    }


def switch_branch(stack: list[Branch], kind: str, value: str) -> None:
    """Switch the current conditional to ELSE or ELSEIF when one is open."""
    if not stack:
        return
    branch = stack[-1]
    branch.prior.append(branch.guard)
    branch.guard = guard_condition(kind, value) if kind == "ELSEIF" else {}
    negated = negated_prior(branch)
    if any(negated.get(key) is (not state) for key, state in branch.guard.items()):
        branch.current = dict(UNREACHABLE)
        return
    branch.current = negated
    branch.current.update(branch.guard)


def apply_directive(stack: list[Branch], kind: str, value: str) -> None:
    """Apply one conditional-compilation directive to the symbolic stack."""
    kind = kind.upper()
    if kind in {"IFDEF", "IFNDEF", "IFOPT", "IF"}:
        guard = guard_condition(kind, value)
        stack.append(Branch([], guard, dict(guard)))
    elif kind in {"ELSEIF", "ELSE"}:
        switch_branch(stack, kind, value)
    elif kind in {"ENDIF", "IFEND"} and stack:
        stack.pop()


def apply_implication(
    result: Condition, premise: Condition, consequence: Condition
) -> tuple[bool, bool]:
    """Apply one implication, returning validity and whether state was added."""
    if not all(result.get(key) is state for key, state in premise.items()):
        return True, False
    if any(key in result and result[key] is not state for key, state in consequence.items()):
        return False, False
    additions = {key: state for key, state in consequence.items() if key not in result}
    result.update(additions)
    return True, bool(additions)


def close_constraints(condition: Condition) -> Condition | None:
    """Expand known platform implications, rejecting contradictions."""
    result = dict(condition)

    changed = True
    while changed:
        changed = False
        for premise, consequence in IMPLICATIONS:
            valid, implication_changed = apply_implication(result, premise, consequence)
            if not valid:
                return None
            changed = changed or implication_changed
    return result


def compatible(*conditions: Condition) -> bool:
    """Return whether all symbolic conditions can hold simultaneously."""
    combined: Condition = {}
    for condition in conditions:
        for key, state in condition.items():
            if key in combined and combined[key] != state:
                return False
            combined[key] = state
    return close_constraints(combined) is not None


def record_asm_line(
    routine: AsmRoutine, line: str, number: int, condition: Condition
) -> bool:
    """Record markers from one assembler line and report routine completion."""
    call_match = CALL_RE.match(line)
    if call_match:
        routine.calls.append(Marker(number, condition, call_match.group(1)))
    if NOFRAME_RE.match(line):
        routine.noframes.append(Marker(number, condition, ".noframe"))
    params_match = PARAMS_RE.match(line)
    if params_match:
        routine.params.append(Marker(number, condition, params_match.group(1)))
    if ASM_END_RE.match(line):
        routine.end_line = number
        return True
    return False


@dataclass
class CommentState:
    """Whether a brace or parenthesis comment is open across lines."""
    brace: bool = False
    paren: bool = False


def strip_comments(line: str, state: CommentState) -> str:
    """Remove Pascal comments from a line, keeping {$...} directives.

    The compiler ignores a directive inside a comment, so `// {$IFDEF Foo}`
    must not move the symbolic stack, and it treats `{ note } call X` as a
    call, so a leading comment must not hide the instruction. Brace and
    (* *) comments may span lines; the state carries that between calls.
    A string literal is replaced by an empty one, so directive-shaped text
    inside it is never read, and a (*$...*) directive is rewritten to the
    {$...} form the directive expression reads.
    """
    kept: list[str] = []
    position = 0
    while position < len(line):
        if state.brace or state.paren:
            closer = "}" if state.brace else "*)"
            end = line.find(closer, position)
            if end < 0:
                break
            state.brace = state.paren = False
            position = end + len(closer)
            continue
        if line.startswith("//", position):
            break
        if line.startswith("(*$", position):
            end = line.find("*)", position + 3)
            if end >= 0:
                kept.append("{$" + line[position + 3 : end] + "}")
                position = end + 2
                continue
        if line.startswith("(*", position):
            state.paren = True
            position += 2
            continue
        if line.startswith("{$", position):
            end = line.find("}", position + 1)
            if end < 0:
                kept.append(line[position:])
                break
            kept.append(line[position : end + 1])
            position = end + 1
            continue
        if line[position] == "'":
            end = position + 1
            while end < len(line):
                if line[end] == "'":
                    if line.startswith("''", end):
                        end += 2
                        continue
                    break
                end += 1
            kept.append("''")
            position = end + 1
            continue
        if line[position] == "{":
            state.brace = True
            position += 1
            continue
        kept.append(line[position])
        position += 1
    return "".join(kept)


def split_directives(line: str) -> list[tuple[str, re.Match[str] | None]]:
    """Split a line into text segments, each paired with the directive after it.

    A directive and an instruction may share a line, as in
    {$IFDEF 64BIT} call Callee {$ENDIF}, so each segment is read under the
    condition in force at its own position rather than the line's start.
    """
    segments: list[tuple[str, re.Match[str] | None]] = []
    position = 0
    for directive in DIRECTIVE_RE.finditer(line):
        segments.append((line[position : directive.start()], directive))
        position = directive.end()
    segments.append((line[position:], None))
    return segments


def parse_source(text: str) -> list[AsmRoutine]:
    """Parse assembler routines and the conditional paths of frame markers."""
    lines = text.splitlines()
    stack: list[Branch] = []
    routines: list[AsmRoutine] = []
    declaration = "<global>"
    declaration_line = 0
    declaration_nostack: Marker | None = None
    active: AsmRoutine | None = None

    comment_state = CommentState()
    for number, raw_line in enumerate(lines, 1):
        line = strip_comments(raw_line, comment_state)
        for segment, directive in split_directives(line):
            condition = merged_condition(stack)
            declared = DECL_RE.match(segment) if active is None else None
            if declared:
                declaration = declared.group(1).strip()
                declaration_line = number
                declaration_nostack = None
            if active is None and declaration_nostack is None and (
                NOSTACK_LINE_RE.match(segment)
                or (declared and "nostackframe" in segment.lower())
            ):
                declaration_nostack = Marker(number, dict(condition), "nostackframe")
            if active is None and ASM_START_RE.match(segment):
                active = AsmRoutine(declaration, declaration_line, number)
                if declaration_nostack is not None:
                    active.noframes.append(declaration_nostack)
                routines.append(active)
            elif active is not None and record_asm_line(
                active, segment, number, dict(merged_condition(stack))
            ):
                active = None
            if directive is not None:
                apply_directive(stack, directive.group(1), directive.group(2))

    return routines


def count_call(call: Marker, counts: Counts) -> None:
    """Increment every architecture on which a call can be reached."""
    targets = (
        ("x86_calls", {"32BIT": True}),
        ("x64_delphi_calls", {"64BIT": True, "FPC": False, "UNIX": False}),
        ("x64_fpc_calls", {"64BIT": True, "FPC": True, "FPC64BIT": True}),
    )
    for name, target in targets:
        if compatible(call.condition, target):
            counts[name] += 1


def covered(condition: Condition, markers: list[Marker], depth: int = 0) -> bool:
    """Return whether every configuration of a condition carries a marker."""
    closed = close_constraints(condition)
    if closed is None:
        return True
    for marker in markers:
        if all(closed.get(key) is state for key, state in marker.condition.items()):
            return True
    if depth >= 16:
        return False
    for marker in markers:
        for key in marker.condition:
            if key not in closed:
                return all(
                    covered({**condition, key: state}, markers, depth + 1)
                    for state in (True, False)
                )
    return False


def validate_call(call: Marker, routine: AsmRoutine, source: Path) -> list[str]:
    """Validate leaf and Win64 Delphi frame rules for one assembly call."""
    errors = [
        f"{source}:{call.line}: {routine.name}: {call.text} is reachable "
        f"with {noframe.text} from line {noframe.line}"
        for noframe in routine.noframes
        if compatible(call.condition, noframe.condition)
    ]
    x64_delphi = {"64BIT": True, "FPC": False, "UNIX": False}
    if compatible(call.condition, x64_delphi) and not covered(
        {**x64_delphi, **call.condition}, routine.params
    ):
        errors.append(
            f"{source}:{call.line}: {routine.name}: Win64 Delphi call "
            f"{call.text} has no compatible .params frame"
        )
    return errors


def validate_routine(routine: AsmRoutine, source: Path, counts: Counts) -> list[str]:
    """Validate every call and frame directive in one assembler routine."""
    errors: list[str] = []
    for call in routine.calls:
        count_call(call, counts)
        errors.extend(validate_call(call, routine, source))
    errors.extend(
        f"{source}:{noframe.line}: {routine.name}: {noframe.text} is an "
        "x64-only frame directive reachable in a 32-bit branch"
        for noframe in routine.noframes
        if compatible(noframe.condition, {"32BIT": True})
    )
    return errors


def validate(text: str, source: Path) -> tuple[list[str], Counts]:
    """Validate one source and return diagnostics plus reachable-call counts."""
    counts = {"x86_calls": 0, "x64_delphi_calls": 0, "x64_fpc_calls": 0}
    errors: list[str] = []
    for routine in parse_source(text):
        errors.extend(validate_routine(routine, source, counts))
    return errors, counts


def self_test() -> tuple[list[str], int]:
    """Run embedded regression fixtures, returning failures and the case count."""
    cases = {
        "valid_leaf": """
procedure Leaf; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
  xor eax, eax
{$ENDIF}
end;
""",
        "valid_framed": """
procedure Caller; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmParams}
.params 1
{$ENDIF}
  call Callee
{$ENDIF}
end;
""",
        "valid_exclusive": """
procedure Dispatch; assembler; {$IFDEF fpc64BIT} nostackframe; {$ENDIF}
asm
{$IFDEF 64BIT}
{$IFNDEF unix}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
{$ELSE}
  jmp Fallback
{$ENDIF}
{$ENDIF}
end;
""",
        "valid_win32_pic": """
procedure GetSomething; assembler;
asm
{$IFDEF WIN32}
  call GetGOT
{$ENDIF}
end;
""",
        "valid_elseif_chain": """
procedure Chain; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ELSEIF Foo}
  nop
{$ELSE}
  call Callee
{$ENDIF}
{$ENDIF}
end;
""",
        "valid_repeated_guard": """
procedure Repeated; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
{$ELSEIF 64BIT}
  call Callee
{$ENDIF}
end;
""",
        "valid_nested_contradiction": """
procedure Nested; assembler;
asm
{$IFNDEF 64BIT}
{$IFDEF 64BIT}
  call Callee
{$ENDIF}
{$ENDIF}
end;
""",
        "valid_params_both_branches": """
procedure Both; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmParams}
{$IFDEF Foo}
.params 1
{$ELSE}
.params 2
{$ENDIF}
{$ENDIF}
  call Callee
{$ENDIF}
end;
""",
        "invalid_params_partial_guard": """
procedure Partial; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmParams}
{$IFDEF Foo}
.params 1
{$ENDIF}
{$ENDIF}
  call Callee
{$ENDIF}
end;
""",
        "invalid_params_other_branch": """
procedure Split; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmParams}
{$IFDEF Foo}
.params 1
{$ELSE}
  call Callee
{$ENDIF}
{$ENDIF}
{$ENDIF}
end;
""",
        "invalid_noframe_call": """
procedure Bad; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
  call Callee
{$ENDIF}
end;
""",
        "invalid_labeled_call": """
procedure BadLabel; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
@Retry: call Callee
{$ENDIF}
end;
""",
        "invalid_double_at_label_call": """
procedure BadLocalLabel; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
@@Retry: call Callee
{$ENDIF}
end;
""",
        "invalid_inline_directive_call": """
procedure BadInline; assembler;
asm
{$IFDEF 64BIT}{$IFDEF AllowAsmNoframe} .noframe {$ENDIF}{$ENDIF}
{$IFDEF 64BIT} call Callee {$ENDIF}
end;
""",
        "valid_inline_directive_params": """
procedure GoodInline; assembler;
asm
{$IFDEF 64BIT}{$IFDEF AllowAsmParams} .params 2 {$ENDIF} call Callee {$ENDIF}
end;
""",
        "valid_repeated_defined_guard": """
procedure GoodDefined; assembler;
asm
{$IFDEF 64BIT}
  nop
{$ELSEIF Defined(64BIT)}
.noframe
{$ENDIF}
{$IFNDEF 64BIT}
  call Callee
{$ENDIF}
end;
""",
        "invalid_asm_start_inline_directive": """
procedure BadStart; assembler;
asm {$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
  call Callee
{$ENDIF}
end;
""",
        "invalid_asm_after_directive": """
procedure BadLeading; assembler;
{$IFDEF 64BIT} asm
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
  call Callee
end; {$ENDIF}
""",
        "invalid_nostack_continuation": """
procedure BadFpcLater;
assembler;
{$IFDEF fpc64BIT} nostackframe; {$ENDIF}
asm
{$IFDEF 64BIT}
  call Callee
{$ENDIF}
end;
""",
        "invalid_comment_before_call": """
procedure BadComment; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
  { invoke helper } call Callee
{$ENDIF}
end;
""",
        "invalid_commented_directive": """
procedure BadCommented; assembler;
asm
{$IFDEF 64BIT}
// {$IFDEF Foo}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
(* {$ELSE} *)
  call Callee
// {$ENDIF}
{$ENDIF}
end;
""",
        "invalid_directive_in_string": """
procedure BadString; assembler;
asm
{$IFDEF 64BIT}
{$IFDEF AllowAsmNoframe}
.noframe
{$ENDIF}
  db 'it''s {$IFNDEF 64BIT}'
  call Callee
{$ENDIF}
end;
""",
        "invalid_paren_directive": """
procedure BadParen; assembler;
asm
{$IFDEF 64BIT}
(*$IFDEF Foo*)
{$IFDEF AllowAsmParams}
.params 2
{$ENDIF}
(*$ELSE*)
  call Callee
(*$ENDIF*)
{$ENDIF}
end;
""",
        "invalid_declaration_after_directive": """
{$IFDEF FPC64BIT} procedure BadDecl; assembler; nostackframe; {$ENDIF}
asm
{$IFDEF FPC64BIT}
  call Callee
{$ENDIF}
end;
""",
        "invalid_nostack_call": """
procedure BadFpc; assembler; {$IFDEF fpc64BIT} nostackframe; {$ENDIF}
asm
{$IFDEF 64BIT}
  call Callee
{$ENDIF}
end;
""",
    }
    failures: list[str] = []
    for name, source_text in cases.items():
        errors, _ = validate(source_text, Path(name + ".pas"))
        expected_error = name.startswith("invalid_")
        if bool(errors) != expected_error:
            failures.append(
                f"self-test {name}: expected_error={expected_error}, errors={errors}"
            )
    return failures, len(cases)


def discover_sources(requested: list[Path]) -> tuple[list[Path], list[str]]:
    """Expand files and checkout directories to sources, naming missing paths."""
    sources: list[Path] = []
    missing: list[str] = []
    for item in requested:
        if item.is_file():
            sources.append(item)
            continue
        if not item.is_dir():
            missing.append(str(item))
            continue
        for candidate in sorted(item.rglob("*")):
            if candidate.suffix.lower() not in SOURCE_SUFFIXES:
                continue
            candidate_text = read_source(candidate)
            comment_state = CommentState()
            if any(
                CALL_RE.match(segment)
                for line in candidate_text.splitlines()
                for segment, _ in split_directives(strip_comments(line, comment_state))
            ):
                sources.append(candidate)
    return sources, missing


def validate_sources(sources: list[Path]) -> tuple[list[str], Counts]:
    """Validate discovered sources and combine their diagnostics and counts."""
    errors: list[str] = []
    totals = {"x86_calls": 0, "x64_delphi_calls": 0, "x64_fpc_calls": 0}
    for source in sources:
        source_errors, counts = validate(read_source(source), source)
        errors.extend(source_errors)
        for name in totals:
            totals[name] += counts[name]
    return errors, totals


def main() -> int:
    """Discover requested sources, validate them, and print one CI result."""
    script_dir = Path(__file__).resolve().parent
    default_repo = script_dir.parent
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "sources",
        nargs="*",
        type=Path,
        help="Pascal source files, or a checkout containing FastMM4.pas",
    )
    args = parser.parse_args()
    errors, self_test_count = self_test()
    requested = args.sources or [default_repo]
    sources, missing = discover_sources(requested)
    if missing:
        parser.error("not a file or directory: " + ", ".join(missing))
    if not sources:
        parser.error("no FastMM4 Pascal sources found")

    source_errors, totals = validate_sources(sources)
    errors.extend(source_errors)
    if errors:
        print("Assembly call-frame check FAILED:")
        for error in errors:
            print("-", error)
        return 1
    print(
        "Assembly call frames OK: "
        f"files={len(sources)}, "
        f"x86 calls={totals['x86_calls']}, "
        f"Win64 Delphi calls={totals['x64_delphi_calls']}, "
        f"Win64 FreePascal calls={totals['x64_fpc_calls']}; "
        f"{self_test_count} self-tests passed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
