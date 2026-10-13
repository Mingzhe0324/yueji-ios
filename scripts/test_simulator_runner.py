import io
import sys
import subprocess
import tempfile
from pathlib import Path
import time
import unittest
from unittest.mock import Mock, patch

from run_simulator_tests import main, run_stage, stop_process
from report_test_failures import report


class SimulatorRunnerTests(unittest.TestCase):
    def test_native_pipeline_builds_once_before_boot_and_requires_both_suites(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch('sys.argv', ['runner', '--simulator', 'test-device', '--artifacts', folder]), patch('run_simulator_tests.run_stage', return_value=0) as stage:
                self.assertEqual(main(), 0)
            commands = [call.args[0] for call in stage.call_args_list]
            self.assertIn('build-for-testing', commands[0])
            self.assertIn('bootstatus', commands[1])
            self.assertIn('-only-testing:YueJiTests', commands[2])
            self.assertIn('shutdown', commands[3])
            self.assertIn('bootstatus', commands[4])
            self.assertIn('-only-testing:YueJiUITests', commands[5])
            self.assertEqual(stage.call_args_list[5].kwargs['test_case_timeout'], 900)
            self.assertEqual(stage.call_args_list[2].kwargs, {})
            for command in (commands[0], commands[2], commands[5]):
                self.assertIn('ONLY_ACTIVE_ARCH=YES', command)
                self.assertEqual(command[command.index('-configuration') + 1], 'Debug')
            self.assertIn('** ALL NATIVE SUITES SUCCEEDED **', (Path(folder) / 'build-test.log').read_text())

    def test_build_failure_stops_before_simulator_and_does_not_report_success(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch('sys.argv', ['runner', '--simulator', 'test-device', '--artifacts', folder]), patch('run_simulator_tests.run_stage', return_value=124) as stage:
                self.assertEqual(main(), 124)
            self.assertEqual(stage.call_count, 1)
            self.assertNotIn('ALL NATIVE SUITES SUCCEEDED', (Path(folder) / 'build-test.log').read_text())

    def test_ui_failure_or_timeout_never_reports_native_success(self):
        for code in (65, 124):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as folder:
                with patch('sys.argv', ['runner', '--simulator', 'test-device', '--artifacts', folder]), patch('run_simulator_tests.run_stage', side_effect=[0, 0, 0, 0, 0, code]):
                    self.assertEqual(main(), code)
                self.assertNotIn('ALL NATIVE SUITES SUCCEEDED', (Path(folder) / 'build-test.log').read_text())

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

    def run_python(self, source, timeout=5, **options):
        log = io.StringIO()
        code = run_stage([sys.executable, '-u', '-c', source], log, timeout, grace=0.2, **options)
        return code, log.getvalue()

    def test_sequential_cases_each_receive_their_own_budget(self):
        source = """import time
for name, status in [('testOne', 'passed'), ('testTwo', 'failed')]:
    print(f"Test Case '-[YueJiUITests.TransactionFormTests {name}]' started.")
    time.sleep(0.4)
    print(f"Test Case '-[YueJiUITests.TransactionFormTests {name}]' {status} (0.4 seconds).")
raise SystemExit(65)
"""
        code, log = self.run_python(source, test_case_timeout=0.7, test_transition_timeout=2)
        self.assertEqual(code, 65)
        self.assertNotIn('timed out', log)

    def test_noisy_stuck_case_cannot_extend_its_budget(self):
        source = """import time
while True:
    print("Test Case '-[YueJiUITests.TransactionFormTests testStuck]' started.")
    print('Still checking accessibility')
    time.sleep(0.05)
"""
        code, log = self.run_python(source, test_case_timeout=0.3, test_transition_timeout=2)
        self.assertEqual(code, 124)
        self.assertIn('testStuck exceeded 0.3 seconds', report(log))

    def test_ui_startup_and_between_case_waits_are_bounded(self):
        for prefix in ('', "print(\"Test Case '-[Suite testOne]' started.\"); print(\"Test Case '-[Suite testOne]' passed (0 seconds).\"); "):
            with self.subTest(prefix=prefix):
                code, log = self.run_python('import time; ' + prefix + 'time.sleep(60)',
                                            test_case_timeout=2, test_transition_timeout=0.3)
                self.assertEqual(code, 124)
                self.assertIn('UI runner made no test transition', report(log))

    def test_case_transitions_do_not_extend_whole_suite_deadline(self):
        source = """import time
while True:
    print("Test Case '-[Suite testOne]' started.")
    print("Test Case '-[Suite testOne]' passed (0 seconds).")
    time.sleep(0.05)
"""
        code, log = self.run_python(source, timeout=0.5, test_case_timeout=2, test_transition_timeout=2)
        self.assertEqual(code, 124)
        self.assertIn('CI stage timed out after 0.5 seconds', log)

    def test_success_and_output_are_preserved(self):
        code, log = self.run_python("print('native output')")
        self.assertEqual(code, 0)
        self.assertIn('native output', log)

    def test_finalization_can_outlast_transition_budget(self):
        source = "import time; print(\"Test Suite 'All tests' passed at now.\"); time.sleep(0.6)"
        code, log = self.run_python(source, test_case_timeout=2,
                                    test_transition_timeout=0.3, test_finalization_timeout=2)
        self.assertEqual(code, 0)
        self.assertIn('waiting up to 2 seconds for Xcode', log)
        self.assertNotIn('timed out', log)

    def test_passed_suite_does_not_override_xcode_failure(self):
        code, _ = self.run_python("print(\"Test Suite 'All tests' passed at now.\"); raise SystemExit(65)",
                                  test_case_timeout=2)
        self.assertEqual(code, 65)

    def test_finalization_is_bounded_and_repeated_summaries_do_not_extend_it(self):
        source = "import time\nwhile True:\n print(\"Test Suite 'All tests' passed at now.\")\n time.sleep(0.05)"
        code, log = self.run_python(source, test_case_timeout=2,
                                    test_transition_timeout=2, test_finalization_timeout=0.3)
        self.assertEqual(code, 124)
        self.assertIn('Xcode result finalization exceeded', log)

    def test_whole_stage_limit_still_bounds_finalization(self):
        source = "import time; print(\"Test Suite 'All tests' failed at now.\"); time.sleep(60)"
        code, log = self.run_python(source, timeout=0.3, test_case_timeout=2,
                                    test_finalization_timeout=60)
        self.assertEqual(code, 124)
        self.assertIn('CI stage timed out after 0.3 seconds', log)

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
