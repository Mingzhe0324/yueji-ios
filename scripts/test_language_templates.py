"""Run with the same tree-sitter dependencies as the template generator."""
import unittest
import extract_language_templates as extractor


class TemplateTests(unittest.TestCase):
    def test_dynamic_values_are_never_template_text(self):
        cases = [
            (r'let x = "Shop \(merchant), amount \(amount)"', 'Shop ⟦0⟧, amount ⟦1⟧'),
            (r'let x = "\u{00e9} \(value)"', 'é ⟦0⟧'),
            ('let x = "Count \\(items.filter { $0 == "a" }.count)"', 'Count ⟦0⟧'),
        ]
        for source, expected in cases:
            with self.subTest(source=source):
                data = source.encode('utf-8')
                tree = extractor.PARSER.parse(data)
                self.assertFalse(tree.root_node.has_error)
                literal = next(node for node in extractor.descendants(tree.root_node)
                               if node.type == 'line_string_literal')
                self.assertEqual(extractor.literal(data, literal), expected)


if __name__ == '__main__':
    unittest.main()
