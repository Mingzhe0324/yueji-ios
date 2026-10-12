"""Surface XCTest assertions near the end of CI output; never mask a test failure."""
import argparse
from pathlib import Path
import re


def report(log: str) -> str:
    failures = [line for line in log.splitlines() if re.search(r'\.swift:\d+(?::\d+)?: error:', line)]
    bundles = re.findall(r"Test Suite '([^'\n]+\.xctest)' (passed|failed)[^\n]*\n\s*(Executed[^\n]*)", log)
    sections = []
    if failures:
        sections.append('Native XCTest assertion failures:\n' + '\n'.join(dict.fromkeys(failures)))
    elif '** TEST SUCCEEDED **' in log:
        sections.append('Native tests succeeded; no assertion failures were reported.')
    else:
        sections.append('No Swift XCTest assertion lines were found. Inspect build-test.log and TestResults.xcresult for build, launch or infrastructure errors.')
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
