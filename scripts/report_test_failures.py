"""Surface native compilation errors and XCTest assertions; never mask failures."""
import argparse
from pathlib import Path
import re


def report(log: str) -> str:
    # Compiler diagnostics can be unlocated (e.g. a missing module), or contain
    # ANSI colour codes between the source location and diagnostic severity.
    log = re.sub(r'\x1b\[[0-9;]*m', '', log)
    lines = log.splitlines()
    diagnostic = re.compile(r'(?:\.(?:swift|m|mm|h|c|cpp):\d+(?::\d+)?|<unknown>:0):\s*(?:fatal )?error:|^\s*(?:(?:xcodebuild|clang|swift|swiftc):\s*)?(?:fatal )?error:')
    test_diagnostic = re.compile(r'Tests[/\\]|XCTAssert|XCTest|error:\s*-\[')
    failures, compilation = [], []
    for index, line in enumerate(lines):
        if not diagnostic.search(line):
            continue
        if test_diagnostic.search(line):
            failures.append(line)
        else:
            # Include the source/caret or module-search context alongside the
            # error, so the summary is useful without opening the entire log.
            compilation.append('\n'.join(lines[index:index + 3]))
    infrastructure = [line for line in lines if
                      'Failed to initialize for UI testing:' in line or 'CI stage timed out' in line]
    bundles = re.findall(r"Test Suite '([^'\n]+\.xctest)' (passed|failed)[^\n]*\n\s*(Executed[^\n]*)", log)
    sections = []
    if infrastructure:
        sections.append('Native runner/startup failures (UI verification incomplete):\n' + '\n'.join(dict.fromkeys(infrastructure)))
    if compilation:
        sections.append('Native build/compiler errors:\n' + '\n'.join(dict.fromkeys(compilation)))
    if failures:
        sections.append('Native XCTest assertion failures:\n' + '\n'.join(dict.fromkeys(failures)))
    elif not infrastructure and not compilation and '** TEST BUILD FAILED **' not in log and ('** ALL NATIVE SUITES SUCCEEDED **' in log or
                                 ('build-for-testing' not in log and '** TEST SUCCEEDED **' in log)):
        sections.append('Native tests succeeded; no assertion failures were reported.')
    elif not infrastructure and not compilation and '** TEST BUILD FAILED **' in log:
        sections.append('Native test build failed. No compiler diagnostic lines were captured in this summary; inspect the earlier build-test.log output.')
    elif not infrastructure and not compilation:
        sections.append('No Swift XCTest assertion lines were found. Inspect build-test.log and the .xcresult bundles for build, launch or infrastructure errors.')
    if bundles:
        sections.append('Test bundle summaries:\n' + '\n'.join(f'{name} {status}: {summary}' for name, status, summary in bundles))
    return '\n\n'.join(sections) + '\n'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not args.log.is_file():
        print('No build-test.log was produced; inspect the earlier build steps.')
        return
    summary = report(args.log.read_text(encoding='utf-8', errors='replace'))
    print(summary, end='')
    if args.output:
        args.output.write_text(summary, encoding='utf-8')


if __name__ == '__main__':
    main()
