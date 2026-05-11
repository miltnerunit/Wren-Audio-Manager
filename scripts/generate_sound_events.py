#!/usr/bin/env python3
"""
Generates SoundEvent.swift and SoundEvent.kt from SoundEventList.csv.

Run from the repo root:
    python3 scripts/generate_sound_events.py
"""

import csv
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
CSV_PATH = REPO_ROOT / "SoundEventList.csv"
SWIFT_OUT = REPO_ROOT / "SoundTest_Swift" / "SoundTest" / "SoundEvent.swift"
KOTLIN_OUT = REPO_ROOT / "SoundTest_Android" / "app" / "src" / "main" / "java" / "com" / "soundtest" / "app" / "SoundEvent.kt"
KOTLIN_PACKAGE = "com.soundtest.app"

REQUIRED_COLUMNS = {"Filename", "Loop?", "Max Voices", "Variation Mode", "Variation Count", "Variation Suffix"}
DEFAULT_MAX_VOICES = 3


def parse_bool(val):
    return val.strip().upper() in ("TRUE", "YES", "1")


def parse_int(val, default):
    try:
        return int(val.strip())
    except (ValueError, AttributeError):
        return default


def parse_separator(suffix):
    """Extract separator string from suffix pattern: '_1' → '_', '1' → '', '01' → ''"""
    suffix = suffix.strip()
    if not suffix:
        return "_"
    i = len(suffix) - 1
    while i >= 0 and suffix[i].isdigit():
        i -= 1
    return suffix[: i + 1]


def to_case_name(base):
    """Ensure Swift enum case names start with a lowercase letter."""
    if not base:
        return base
    return base[0].lower() + base[1:]


def swift_case_list(cases, prefix="        case "):
    """Format a list of case names as a Swift multi-case pattern, aligned to the opening 'case'."""
    continuation = ",\n" + " " * len(prefix)
    return continuation.join(f".{c}" for c in cases)


def swift_string_switch(events_with_value, default_value, prop_type="String"):
    """Generate a switch that returns a string, using default for the majority value."""
    by_val = {}
    for case_name, val in events_with_value:
        by_val.setdefault(val, []).append(case_name)
    if len(by_val) == 1:
        return None, list(by_val.keys())[0]  # one-liner
    default_val = max(by_val, key=lambda k: len(by_val[k]))
    return by_val, default_val


def to_kotlin_name(base):
    """Convert camelCase/PascalCase to SCREAMING_SNAKE_CASE."""
    s = re.sub(r'([a-z])([A-Z])', r'\1_\2', base)
    s = re.sub(r'([a-zA-Z])(\d)', r'\1_\2', s)
    return s.upper()


def kt_case_list(cases):
    """Format Kotlin when-branch cases: first on same line, rest indented below."""
    return ",\n        ".join(cases)


def generate_kotlin(events, seen_categories):
    lines = [
        "// AUTO-GENERATED — do not edit directly.",
        "// Source of truth: SoundEventList.csv",
        "// Regenerate:  python3 scripts/generate_sound_events.py",
        "",
        f"package {KOTLIN_PACKAGE}",
        "",
        "",
        "// MARK: - Variation Mode",
        "",
        "enum class VariationMode {",
        "    SEQUENTIAL,",
        "    RANDOM",
        "}",
        "",
        "",
        "// MARK: - Sound Events",
        "",
        "enum class SoundEvent(val rawValue: String) {",
        "",
    ]

    # Cases grouped by category
    current_category = None
    cases_list = []
    for e in events:
        cat = e["category"]
        if cat != current_category:
            if current_category is not None:
                lines.append("")
            current_category = cat
            if cat:
                lines.append(f"    // {cat}")
        kt_name = to_kotlin_name(e["raw_value"])
        cases_list.append(kt_name)
        lines.append(f'    {kt_name}("{e["raw_value"]}"),')

    # Replace last trailing comma with semicolon
    lines[-1] = lines[-1][:-1] + ";"

    lines += ["", "", "    // MARK: - Configuration", ""]

    # fileExtension
    exts = {e["ext"] for e in events}
    if len(exts) == 1:
        lines.append(f'    val fileExtension: String get() = "{exts.pop()}"')
    else:
        by_ext = {}
        for e in events:
            by_ext.setdefault(e["ext"], []).append(to_kotlin_name(e["raw_value"]))
        default_ext = max(by_ext, key=lambda k: len(by_ext[k]))
        lines += ["    val fileExtension: String get() = when (this) {"]
        for ext, cases in by_ext.items():
            if ext == default_ext:
                continue
            lines.append(f'        {kt_case_list(cases)} -> "{ext}"')
        lines += [f'        else -> "{default_ext}"', "    }"]
    lines.append("")

    # maxVoices
    by_voices = {}
    for e in events:
        by_voices.setdefault(e["max_voices"], []).append(to_kotlin_name(e["raw_value"]))
    if len(by_voices) == 1:
        lines.append(f"    val maxVoices: Int get() = {list(by_voices)[0]}")
    else:
        default_v = DEFAULT_MAX_VOICES if DEFAULT_MAX_VOICES in by_voices else max(by_voices, key=lambda k: len(by_voices[k]))
        lines += ["    val maxVoices: Int get() = when (this) {"]
        for v in sorted(by_voices):
            if v == default_v:
                continue
            lines.append(f"        {kt_case_list(by_voices[v])} -> {v}")
        lines += [f"        else -> {default_v}", "    }"]
    lines.append("")

    # loops
    looping = [to_kotlin_name(e["raw_value"]) for e in events if e["loops"]]
    if not looping:
        lines.append("    val loops: Boolean get() = false")
    else:
        lines += [
            "    val loops: Boolean get() = when (this) {",
            f"        {kt_case_list(looping)} -> true",
            "        else -> false",
            "    }",
        ]
    lines.append("")

    # variationCount
    by_count = {}
    for e in events:
        by_count.setdefault(e["variation_count"], []).append(to_kotlin_name(e["raw_value"]))
    if len(by_count) == 1:
        lines.append(f"    val variationCount: Int get() = {list(by_count)[0]}")
    else:
        lines += ["    val variationCount: Int get() = when (this) {"]
        for count in sorted(by_count, reverse=True):
            if count == 1:
                continue
            lines.append(f"        {kt_case_list(by_count[count])} -> {count}")
        lines += ["        else -> 1", "    }"]
    lines.append("")

    # variationMode
    sequential = [to_kotlin_name(e["raw_value"]) for e in events if e["variation_mode"] == "sequential"]
    if not sequential:
        lines.append("    val variationMode: VariationMode get() = VariationMode.RANDOM")
    else:
        lines += [
            "    val variationMode: VariationMode get() = when (this) {",
            f"        {kt_case_list(sequential)} -> VariationMode.SEQUENTIAL",
            "        else -> VariationMode.RANDOM",
            "    }",
        ]
    lines.append("")

    # variationSeparator
    by_sep = {}
    for e in events:
        if e["variation_count"] > 1:
            by_sep.setdefault(e["separator"], []).append(to_kotlin_name(e["raw_value"]))
    if not by_sep or (len(by_sep) == 1 and "_" in by_sep):
        lines.append('    val variationSeparator: String get() = "_"')
    else:
        default_sep = "_"
        lines += ["    val variationSeparator: String get() = when (this) {"]
        for sep, cases in by_sep.items():
            if sep == default_sep:
                continue
            lines.append(f'        {kt_case_list(cases)} -> "{sep}"')
        lines += [f'        else -> "{default_sep}"', "    }"]
    lines.append("")

    # category
    by_cat = {}
    for e in events:
        by_cat.setdefault(e["category"], []).append(to_kotlin_name(e["raw_value"]))
    if len(by_cat) == 1:
        cat = list(by_cat.keys())[0]
        lines.append(f'    val category: String get() = "{cat}"')
    else:
        default_cat = max(by_cat, key=lambda k: len(by_cat[k]))
        lines += ["    val category: String get() = when (this) {"]
        for cat, cases in by_cat.items():
            if cat == default_cat:
                continue
            lines.append(f'        {kt_case_list(cases)} -> "{cat}"')
        lines += [f'        else -> "{default_cat}"', "    }"]
    lines.append("")

    # displayName — exhaustive, no else, so compiler catches missing cases
    lines += ["    val displayName: String get() = when (this) {"]
    for e in events:
        kt_name = to_kotlin_name(e["raw_value"])
        lines.append(f'        {kt_name} -> "{e["display_name"]}"')
    lines += ["    }", ""]

    # companion object — ordered categories
    cats_literal = ", ".join(f'"{c}"' for c in seen_categories)
    lines += [
        "    companion object {",
        f"        val categories: List<String> = listOf({cats_literal})",
        "    }",
    ]

    lines += ["}", ""]

    KOTLIN_OUT.parent.mkdir(parents=True, exist_ok=True)
    KOTLIN_OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"✓ Generated {KOTLIN_OUT.relative_to(REPO_ROOT)}  ({len(events)} events)")


def main():
    if not CSV_PATH.exists():
        print(f"Error: {CSV_PATH} not found", file=sys.stderr)
        sys.exit(1)

    events = []
    seen_categories = []

    with open(CSV_PATH, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        headers = {h.strip() for h in (reader.fieldnames or [])}
        missing = REQUIRED_COLUMNS - headers
        if missing:
            print(f"Warning: CSV missing columns: {missing}", file=sys.stderr)

        for row in reader:
            row = {k.strip(): v for k, v in row.items() if k}
            filename = row.get("Filename", "").strip()
            if not filename:
                continue
            if "." not in filename:
                print(f"Warning: skipping '{filename}' — no extension", file=sys.stderr)
                continue

            base, _, ext = filename.rpartition(".")
            variation_mode = row.get("Variation Mode", "").strip().lower()
            variation_count = parse_int(row.get("Variation Count", ""), 1)
            suffix_raw = row.get("Variation Suffix", "").strip()
            category = row.get("Category", "").strip()
            trigger = row.get("Trigger", "").strip()

            if not variation_mode:
                variation_count = 1
                separator = ""
            else:
                separator = parse_separator(suffix_raw)

            if category and category not in seen_categories:
                seen_categories.append(category)

            case_name = to_case_name(base)
            display_name = trigger if trigger else case_name

            events.append({
                "case_name": case_name,
                "raw_value": base,
                "ext": ext,
                "loops": parse_bool(row.get("Loop?", "FALSE")),
                "max_voices": parse_int(row.get("Max Voices", ""), DEFAULT_MAX_VOICES),
                "variation_mode": variation_mode or "random",
                "variation_count": variation_count,
                "separator": separator,
                "category": category,
                "display_name": display_name,
            })

    if not events:
        print("Error: no events found in CSV", file=sys.stderr)
        sys.exit(1)

    lines = [
        "// AUTO-GENERATED — do not edit directly.",
        "// Source of truth: SoundEventList.csv",
        "// Regenerate:  python3 scripts/generate_sound_events.py",
        "",
        "",
        "// MARK: - Variation Mode",
        "",
        "enum VariationMode {",
        "    case sequential",
        "    case random",
        "}",
        "",
        "",
        "// MARK: - Sound Events",
        "",
        "enum SoundEvent: String, CaseIterable, Identifiable {",
        "",
        "    var id: String { rawValue }",
        "",
    ]

    # Cases — grouped by category with MARK headers
    current_category = None
    for e in events:
        cat = e["category"]
        if cat != current_category:
            if current_category is not None:
                lines.append("")
            current_category = cat
            if cat:
                lines.append(f"    // MARK: {cat}")
        case, raw = e["case_name"], e["raw_value"]
        if case == raw:
            lines.append(f"    case {case}")
        else:
            lines.append(f'    case {case} = "{raw}"')

    lines += ["", "", "    // MARK: - Configuration", ""]

    # fileExtension — one liner if uniform
    exts = {e["ext"] for e in events}
    if len(exts) == 1:
        lines.append(f'    var fileExtension: String {{ "{exts.pop()}" }}')
    else:
        by_ext = {}
        for e in events:
            by_ext.setdefault(e["ext"], []).append(e["case_name"])
        default_ext = max(by_ext, key=lambda k: len(by_ext[k]))
        lines += ["    var fileExtension: String {", "        switch self {"]
        for ext, cases in by_ext.items():
            if ext == default_ext:
                continue
            lines.append(f'        case {swift_case_list(cases)}: return "{ext}"')
        lines += [f'        default: return "{default_ext}"', "        }", "    }"]
    lines.append("")

    # maxVoices
    by_voices = {}
    for e in events:
        by_voices.setdefault(e["max_voices"], []).append(e["case_name"])
    if len(by_voices) == 1:
        lines.append(f"    var maxVoices: Int {{ {list(by_voices)[0]} }}")
    else:
        default_v = DEFAULT_MAX_VOICES if DEFAULT_MAX_VOICES in by_voices else max(by_voices, key=lambda k: len(by_voices[k]))
        lines += ["    var maxVoices: Int {", "        switch self {"]
        for v in sorted(by_voices):
            if v == default_v:
                continue
            lines.append(f"        case {swift_case_list(by_voices[v])}: return {v}")
        lines += [f"        default: return {default_v}", "        }", "    }"]
    lines.append("")

    # loops
    looping = [e["case_name"] for e in events if e["loops"]]
    if not looping:
        lines.append("    var loops: Bool { false }")
    else:
        lines += [
            "    var loops: Bool {",
            "        switch self {",
            f"        case {swift_case_list(looping)}: return true",
            "        default: return false",
            "        }",
            "    }",
        ]
    lines.append("")

    # variationCount
    by_count = {}
    for e in events:
        by_count.setdefault(e["variation_count"], []).append(e["case_name"])
    if len(by_count) == 1:
        lines.append(f"    var variationCount: Int {{ {list(by_count)[0]} }}")
    else:
        lines += ["    var variationCount: Int {", "        switch self {"]
        for count in sorted(by_count, reverse=True):
            if count == 1:
                continue
            lines.append(f"        case {swift_case_list(by_count[count])}: return {count}")
        lines += ["        default: return 1", "        }", "    }"]
    lines.append("")

    # variationMode
    sequential = [e["case_name"] for e in events if e["variation_mode"] == "sequential"]
    if not sequential:
        lines.append("    var variationMode: VariationMode { .random }")
    else:
        lines += [
            "    var variationMode: VariationMode {",
            "        switch self {",
            f"        case {swift_case_list(sequential)}: return .sequential",
            "        default: return .random",
            "        }",
            "    }",
        ]
    lines.append("")

    # variationSeparator
    by_sep = {}
    for e in events:
        if e["variation_count"] > 1:
            by_sep.setdefault(e["separator"], []).append(e["case_name"])
    if not by_sep or (len(by_sep) == 1 and "_" in by_sep):
        lines.append('    var variationSeparator: String { "_" }')
    else:
        default_sep = "_"
        lines += ["    var variationSeparator: String {", "        switch self {"]
        for sep, cases in by_sep.items():
            if sep == default_sep:
                continue
            lines.append(f'        case {swift_case_list(cases)}: return "{sep}"')
        lines += [f'        default: return "{default_sep}"', "        }", "    }"]
    lines.append("")

    # category
    by_cat = {}
    for e in events:
        by_cat.setdefault(e["category"], []).append(e["case_name"])
    if len(by_cat) == 1:
        cat = list(by_cat.keys())[0]
        lines.append(f'    var category: String {{ "{cat}" }}')
    else:
        default_cat = max(by_cat, key=lambda k: len(by_cat[k]))
        lines += ["    var category: String {", "        switch self {"]
        for cat, cases in by_cat.items():
            if cat == default_cat:
                continue
            lines.append(f'        case {swift_case_list(cases)}: return "{cat}"')
        lines += [f'        default: return "{default_cat}"', "        }", "    }"]
    lines.append("")

    # displayName
    by_name = {}
    for e in events:
        by_name.setdefault(e["display_name"], []).append(e["case_name"])
    default_name = max(by_name, key=lambda k: len(by_name[k]))
    lines += ["    var displayName: String {", "        switch self {"]
    for name, cases in by_name.items():
        if name == default_name:
            continue
        lines.append(f'        case {swift_case_list(cases)}: return "{name}"')
    lines += [f'        default: return "{default_name}"', "        }", "    }"]
    lines.append("")

    # categories — ordered list matching CSV row order
    cats_literal = ", ".join(f'"{c}"' for c in seen_categories)
    lines.append(f"    static let categories: [String] = [{cats_literal}]")
    lines.append("")

    lines += ["}", ""]

    SWIFT_OUT.parent.mkdir(parents=True, exist_ok=True)
    SWIFT_OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"✓ Generated {SWIFT_OUT.relative_to(REPO_ROOT)}  ({len(events)} events)")

    generate_kotlin(events, seen_categories)


if __name__ == "__main__":
    main()
