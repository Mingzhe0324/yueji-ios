import unittest

from report_test_failures import report


class FailureReportTests(unittest.TestCase):
    def test_swift_compilation_error_is_not_labelled_as_test_assertion(self):
        log = '/Users/builder/clone/YueJi/ReimbursementViews.swift:41:9: error: cannot convert value\n  source line\n  ^\n** TEST BUILD FAILED **'
        result = report(log)
        self.assertIn('Native build/compiler errors:', result)
        self.assertIn('ReimbursementViews.swift:41:9', result)
        self.assertIn('source line', result)
        self.assertNotIn('Native XCTest assertion failures:', result)
        self.assertNotIn('No Swift XCTest assertion', result)

    def test_unlocated_coloured_and_xcode_errors_are_visible(self):
        for error in ['error: Unable to find module dependency',
                      'xcodebuild: error: SDK is unavailable',
                      'clang: fatal error: missing header',
                      '\x1b[31merror:\x1b[0m filename used twice']:
            with self.subTest(error=error):
                result = report(error + '\n** TEST BUILD FAILED **')
                self.assertIn('Native build/compiler errors:', result)
                self.assertNotIn('\x1b', result)

    def test_native_assertions_keep_their_own_section(self):
        log = '/Users/builder/clone/YueJiUITests/TransactionFormTests.swift:263: error: -[YueJiUITests.TransactionFormTests testFirstAddItem] : XCTAssertTrue failed'
        result = report(log)
        self.assertIn('Native XCTest assertion failures:', result)
        self.assertNotIn('Native build/compiler errors:', result)

    def test_compiler_error_cannot_be_reported_as_success(self):
        result = report('error: compilation failed\n** ALL NATIVE SUITES SUCCEEDED **')
        self.assertIn('Native build/compiler errors:', result)
        self.assertNotIn('Native tests succeeded', result)

    def test_failed_test_build_without_diagnostics_is_explicit(self):
        result = report('** TEST BUILD FAILED **\n** ALL NATIVE SUITES SUCCEEDED **')
        self.assertIn('Native test build failed', result)
        self.assertNotIn('Native tests succeeded', result)

    def test_swift_compiler_assertion_keeps_the_failing_source_context(self):
        log = '''Assertion failed: (Querying VarDecl type), function evaluate.
Stack dump:
0. Program arguments: swift-frontend -frontend -c lots-of-files
3. While evaluating request TypeCheckPrimaryFileRequest(source_file "ReimbursementViews.swift")
4. While evaluating request TypeCheckFunctionBodyRequest(ReimbursementDetailView.undoReceipt())
5. While type-checking expression RangeText="Task {
    } catch { error = error.localizedDescription }
}"
8. While evaluating request InterfaceTypeRequest(error@ReimbursementViews.swift:211:21)
Stack dump without symbol names:
** TEST BUILD FAILED **
** ALL NATIVE SUITES SUCCEEDED **'''
        result = report(log)
        self.assertIn('Swift compiler crash:', result)
        self.assertIn('undoReceipt()', result)
        self.assertIn('ReimbursementViews.swift:211:21', result)
        self.assertNotIn('lots-of-files', result)
        self.assertNotIn('Native tests succeeded', result)
        self.assertNotIn('No Swift XCTest', result)


if __name__ == '__main__':
    unittest.main()
