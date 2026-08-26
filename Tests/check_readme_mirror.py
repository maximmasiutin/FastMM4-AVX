#!/usr/bin/env python3
"""Check that README.md mirrors two prose regions in FastMM4.pas."""

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Line:
    """A normalized source line and its original one-based line number."""

    number: int
    text: str


def region(
    lines: list[str], start_pattern: str, end_pattern: str, label: str
) -> list[Line]:
    """Extract and whitespace-normalize a region between two regex anchors."""
    start_regex = re.compile(start_pattern)
    end_regex = re.compile(end_pattern)
    try:
        start = next(
            index + 1 for index, text in enumerate(lines) if start_regex.search(text)
        )
    except StopIteration as error:
        raise ValueError(f"anchor not found: {start_pattern} in {label}") from error

    try:
        end = next(
            index for index in range(start, len(lines)) if end_regex.search(lines[index])
        )
    except StopIteration as error:
        raise ValueError(f"anchor not found: {end_pattern} in {label}") from error
    return [
        Line(index + 1, normalized)
        for index in range(start, end)
        if (normalized := " ".join(lines[index].split()))
    ]


def compare(left: list[Line], right: list[Line], labels: tuple[str, str]) -> int:
    """Print a longest-common-subsequence diff and return its finding count."""
    rows, columns = len(left), len(right)
    lengths = [[0] * (columns + 1) for _ in range(rows + 1)]
    for row in range(rows - 1, -1, -1):
        for column in range(columns - 1, -1, -1):
            if left[row].text == right[column].text:
                lengths[row][column] = lengths[row + 1][column + 1] + 1
            else:
                lengths[row][column] = max(
                    lengths[row + 1][column], lengths[row][column + 1]
                )

    findings = 0
    row = column = 0
    while row < rows or column < columns:
        if (
            row < rows
            and column < columns
            and left[row].text == right[column].text
        ):
            row += 1
            column += 1
        elif column < columns and (
            row == rows
            or lengths[row][column + 1] >= lengths[row + 1][column]
        ):
            print(f"  only {labels[1]}:{right[column].number}: {right[column].text}")
            findings += 1
            column += 1
        else:
            print(f"  only {labels[0]}:{left[row].number}: {left[row].text}")
            findings += 1
            row += 1
    return findings


def main() -> int:
    """Compare both mirrored regions and return a CI-friendly status code."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="FastMM4-AVX checkout (defaults to the parent of Tests)",
    )
    repo = parser.parse_args().repo.resolve()
    try:
        pascal = (repo / "FastMM4.pas").read_text(encoding="utf-8-sig").splitlines()
        readme = (repo / "README.md").read_text(encoding="utf-8-sig").splitlines()
        specifications = (
            (
                "Changes",
                r"^Changes in FastMM4-AVX Compared",
                r"^## Changes in FastMM4-AVX Compared",
                r"^FastMM4-AVX Version History:",
            ),
            (
                "Version History",
                r"^FastMM4-AVX Version History:",
                r"^FastMM4-AVX Version History:",
                r"^(?!- |\s|$)",
            ),
        )
        total = 0
        for name, pascal_start, readme_start, end in specifications:
            differences = compare(
                region(pascal, pascal_start, end, "FastMM4.pas"),
                region(readme, readme_start, end, "README.md"),
                ("FastMM4.pas", "README.md"),
            )
            total += differences
            status = "mirrored" if differences == 0 else f"{differences} line(s) differ"
            print(f"region {name!r}: {status}")
    except (OSError, UnicodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    return int(total != 0)


if __name__ == "__main__":
    raise SystemExit(main())
