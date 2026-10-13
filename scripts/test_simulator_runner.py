import io
import sys
import subprocess
import time
import unittest
from unittest.mock import Mock, patch

from run_simulator_tests import run_stage, stop_process
from report_test_failures import report


class SimulatorRunnerTests(unittest.TestCase):
    def test_group_permission_denied_falls_back_to_owned_child(self):
        process = Mock(pid=123)
        process.poll.return_value = None
        with patch('run_simulator_tests.os.name', 'posix'), patch('run_simulator_tests.signal.SIGKILL', 9, create=True), patch('run_simulator_tests.os.killpg', create=True, side_effect=PermissionError('denied')):
            stop_process(process, True, Mock(), process_group=True)
        process.kill.assert_called_once()

    def test_simctl_cleanup_does_not_signal_service_process_group(self):
        process = Mock(pid=123)
        process.poll.return_value = None
        with patch('run_simulator_tests.os.killpg', create=True) as kill_group:
            stop_process(process, False, Mock())
        kill_group.assert_not_called()
        process.terminate.assert_called_once()

    def test_owned_child_permission_denied_is_reported_without_raising(self):
        process = Mock(pid=123)
        process.poll.return_value = None
        process.kill.side_effect = PermissionError('denied')
        emit = Mock()
        stop_process(process, True, emit)
        self.assertIn('retaining the stage failure', emit.call_args.args[0])

    def test_already_exited_process_is_not_signalled(self):
        process = Mock(pid=123)
        process.poll.return_value = 0
        stop_process(process, True, Mock(), process_group=True)
        process.kill.assert_not_called()

    def test_unstoppable_child_cleanup_is_bounded_and_keeps_timeout_code(self):
        process = Mock(pid=123, stdout=io.StringIO(''))
        process.poll.return_value = None
        process.terminate.side_effect = PermissionError('denied')
        process.kill.side_effect = PermissionError('denied')
        process.wait.side_effect = subprocess.TimeoutExpired('fake', 0.01)
        log = io.StringIO()
        with patch('run_simulator_tests.subprocess.Popen', return_value=process):
            code = run_stage(['fake'], log, timeout=0, grace=0.01)
        self.assertEqual(code, 124)
        process.wait.assert_called_once_with(timeout=0.01)
        self.assertIn('Cleanup deadline reached', log.getvalue())

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
