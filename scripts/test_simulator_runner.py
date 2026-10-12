import io
import sys
import time
import unittest

from run_simulator_tests import run_stage
from report_test_failures import report


class SimulatorRunnerTests(unittest.TestCase):
    def run_python(self, source, timeout=5):
        log = io.StringIO()
        code = run_stage([sys.executable, '-u', '-c', source], log, timeout, grace=0.2)
        return code, log.getvalue()

    def test_success_and_output_are_preserved(self):
        code, log = self.run_python("print('native output')")
        self.assertEqual(code, 0)
        self.assertIn('native output', log)

    def test_test_failure_is_not_converted_to_success(self):
        code, _ = self.run_python('raise SystemExit(65)')
        self.assertEqual(code, 65)

    def test_stalled_initialization_stops_without_waiting_for_timeout(self):
        start = time.monotonic()
        code, log = self.run_python("import time; print('Failed to initialize for UI testing: Timed out waiting for AX loaded notification'); time.sleep(60)")
        self.assertEqual(code, 65)
        self.assertLess(time.monotonic() - start, 5)
        self.assertIn('AX loaded notification', report(log))

    def test_silent_hang_has_a_deadline(self):
        code, log = self.run_python('import time; time.sleep(60)', timeout=0.3)
        self.assertEqual(code, 124)
        self.assertIn('CI stage timed out', report(log))

    def test_unit_success_does_not_claim_ui_success(self):
        summary = report('Running: xcodebuild build-for-testing\n** TEST SUCCEEDED **\n')
        self.assertNotIn('Native tests succeeded', summary)
        self.assertIn('Native tests succeeded', report('** ALL NATIVE SUITES SUCCEEDED **'))


if __name__ == '__main__':
    unittest.main()
