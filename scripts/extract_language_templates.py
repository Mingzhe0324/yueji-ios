"""Extract app-owned English UI templates. Never evaluate Swift interpolation.

Run with tree_sitter and tree_sitter_swift installed. --migrate wraps interpolated
English arguments so their runtime values never become translation input.
"""
from pathlib import Path
import argparse
import json
import re
import tree_sitter
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
PARSER = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))


def descendants(node):
    pending = [node]
    while pending:
        item = pending.pop()
        yield item
        pending.extend(reversed(item.named_children))


def literal(source, node):
    if node.type != "line_string_literal":
        return None
    raw = source[node.start_byte:node.end_byte].decode("utf-8")
    replacements = []
    count = 0
    for child in node.children:
        if child.type == "interpolated_expression":
            replacements.append((child.start_byte - node.start_byte - 2,
                                 child.end_byte - node.start_byte + 1, f"⟦{count}⟧"))
            count += 1
    encoded = raw.encode("utf-8")
    for start, end, value in reversed(replacements):
        encoded = encoded[:start] + value.encode("utf-8") + encoded[end:]
    raw = encoded.decode("utf-8")
    raw = re.sub(r"\\u\{([a-fA-F0-9]+)\}", lambda m: chr(int(m[1], 16)), raw)
    try:
        return json.loads(raw)
    except ValueError as exc:
        raise ValueError(f"Unsupported Swift literal: {raw}") from exc


def extract(migrate=False):
    templates = set()
    for file in sorted((ROOT / "YueJi").glob("*.swift")):
        source = file.read_bytes()
        tree = PARSER.parse(source)
        assert not tree.root_node.has_error, file
        edits = []
        for node in descendants(tree.root_node):
            if node.type == "call_expression" and node.named_children:
                callee = node.named_children[0]
                if source[callee.start_byte:callee.end_byte] != b"tr":
                    continue
                suffix = next((c for c in node.named_children if c.type == "call_suffix"), None)
                args = next((c for c in suffix.named_children if c.type == "value_arguments"), None) if suffix else None
                values = [c for c in args.named_children if c.type == "value_argument"] if args else []
                if len(values) != 3:
                    continue
                english = values[1].named_children[-1]
                if english.type == "call_expression" and source[english.start_byte:english.start_byte+15] == b"LocalizedPhrase":
                    english = next(c for c in descendants(english) if c.type == "line_string_literal")
                value = literal(source, english)
                if value is not None:
                    templates.add(value)
                    if migrate and "⟦" in value and english == values[1].named_children[-1]:
                        edits.append((english.start_byte, english.end_byte))
            # Legacy app-owned status/error dictionaries in Language.swift.
            if file.name == "Language.swift" and node.type == "tuple_expression":
                strings = [c for c in descendants(node) if c.type == "line_string_literal"]
                if len(strings) == 2:
                    templates.add(literal(source, strings[0]))
        for start, end in sorted(edits, reverse=True):
            source = source[:start] + b"LocalizedPhrase(" + source[start:end] + b")" + source[end:]
        if edits:
            file.write_bytes(source)
    templates.discard(None)
    templates.discard("")
    return sorted(templates)


if __name__ == "__main__":
    args = argparse.ArgumentParser()
    args.add_argument("--migrate", action="store_true")
    args.add_argument("--check", action="store_true")
    options = args.parse_args()
    result = extract(options.migrate)
    target = ROOT / "YueJi/AppLanguageTemplates.json"
    output = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if options.check:
        assert target.read_text(encoding="utf-8") == output, "Regenerate AppLanguageTemplates.json"
    else:
        target.write_text(output, encoding="utf-8")
    print(f"PASS: {len(result)} app-owned templates; runtime interpolation excluded")
