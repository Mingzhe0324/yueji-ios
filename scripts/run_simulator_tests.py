"""Run required native suites sequentially, with bounded simulator startup and diagnostics."""
import argparse
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import threading
import time


INITIALIZATION_FAILURE = 'Failed to initialize for UI testing:'
TEST_CASE_EVENT = re.compile(r"Test Case '-\[([^\]]+)\]' (started|passed|failed)")
TEST_RUN_FINISHED = re.compile(r"^Test Suite 'All tests' (?:passed|failed) at ")


def stop_process(process, force, emit, process_group=False):
    """Stop our child without requiring permission to signal simulator services."""
    if process.poll() is not None:
        return
    if process_group and os.name == 'posix':
        try:
            os.killpg(process.pid, signal.SIGKILL if force else signal.SIGTERM)
            return
        except ProcessLookupError:
            return
        except OSError as error:
            emit(f'Process-group cleanup unavailable ({error}); stopping the owned child instead.\n')
    try:
        if force:
            process.kill()
        else:
            process.terminate()
    except ProcessLookupError:
        pass
    except OSError as error:
        emit(f'Owned-child cleanup unavailable ({error}); retaining the stage failure.\n')


def run_stage(command, log, timeout, grace=5, test_case_timeout=None, test_transition_timeout=180,
              test_finalization_timeout=600):
    """Stream output and bound execution/cleanup while preserving the stage failure."""
    def emit(line):
        print(line, end='', flush=True)
        log.write(line)
        log.flush()

    emit('\nRunning: ' + ' '.join(command) + '\n')
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding='utf-8', errors='replace',
                               start_new_session=os.name == 'posix')
    lines = queue.Queue()

    def read_output():
        try:
            for line in process.stdout:
                lines.put(line)
        finally:
            lines.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    started = time.monotonic()
    deadline = started + timeout
    active_test = None
    tests_started = False
    finalizing = False
    test_deadline = time.monotonic() + test_transition_timeout if test_case_timeout is not None else None
    forced_code = None
    termination_deadline = None
    exit_observed = False

    def stop(force=False):
        # simctl talks to OS-managed services; only stop our simctl client.
        stop_process(process, force, emit, process_group=Path(command[0]).name == 'xcodebuild')

    try:
        while True:
            if process.poll() is not None:
                # CoreSimulator services can inherit stdout beyond simctl's
                # lifetime. Drain delivered output without requiring their EOF.
                # Only the owned command's actual exit code determines success.
                if not exit_observed:
                    reader.join(timeout=1)
                    exit_observed = True
                if lines.empty():
                    break
            now = time.monotonic()
            if not exit_observed and forced_code is None and now >= deadline:
                emit(f'CI stage timed out after {timeout} seconds; native verification did not complete.\n')
                forced_code = 124
            if not exit_observed and forced_code is None and test_deadline is not None and now >= test_deadline:
                if finalizing:
                    detail = f'Xcode result finalization exceeded {test_finalization_timeout} seconds after tests ended'
                elif active_test is not None:
                    detail = f'Native test {active_test} exceeded {test_case_timeout} seconds'
                elif not tests_started:
                    detail = f'Native runner did not start tests within {test_transition_timeout} seconds'
                else:
                    detail = f'Native runner made no test transition within {test_transition_timeout} seconds'
                emit(f'CI stage timed out: {detail}; native verification did not complete.\n')
                forced_code = 124
            if forced_code is not None and termination_deadline is None:
                stop()
                termination_deadline = now + grace
            if termination_deadline is not None and now >= termination_deadline:
                stop(force=True)
                break
            try:
                line = lines.get(timeout=0.1)
            except queue.Empty:
                continue
            if line is None:
                continue
            emit(line)
            if test_case_timeout is not None:
                event = TEST_CASE_EVENT.search(line)
                if event:
                    name, status = event.groups()
                    if status == 'started' and active_test is None:
                        tests_started = True
                        finalizing = False
                        active_test = name
                        test_deadline = time.monotonic() + test_case_timeout
                    elif status in ('passed', 'failed') and name == active_test:
                        active_test = None
                        test_deadline = time.monotonic() + test_transition_timeout
                if TEST_RUN_FINISHED.search(line) and active_test is None and not finalizing:
                    finalizing = True
                    test_deadline = time.monotonic() + test_finalization_timeout
                    emit(f'CI tests ended; waiting up to {test_finalization_timeout} seconds for Xcode to finalize results and exit.\n')
            if INITIALIZATION_FAILURE in line and forced_code is None:
                emit('CI runner initialization failed; stopping instead of waiting for the job timeout.\n')
                forced_code = 65
        # Flush output already delivered by the reader before closing the log.
        while not lines.empty():
            line = lines.get_nowait()
            if line is not None:
                emit(line)
        code = forced_code if forced_code is not None else process.returncode
        emit(f'CI stage finished after {time.monotonic() - started:.1f} seconds (exit {code}).\n')
        return code
    finally:
        if process.poll() is None:
            stop(force=True)
        try:
            process.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            emit('Cleanup deadline reached; retaining the failed stage without waiting indefinitely.\n')
        reader.join(timeout=1)
        # Closing a pipe held by the reader can block if an OS service inherited it.
        if not reader.is_alive():
            process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    base = ['xcodebuild', '-project', 'YueJi.xcodeproj', '-scheme', 'YueJi',
            '-configuration', 'Debug',
            '-destination', f'platform=iOS Simulator,id={args.simulator}',
            '-derivedDataPath', 'build-simulator', '-parallel-testing-enabled', 'NO',
            'ONLY_ACTIVE_ARCH=YES',
            'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO']
    # Hosted Xcode can hang waiting for asynchronous simulator diagnostics after
    # all cases end. Keep xcresult/test attachments, but skip OS diagnostic dumps.
    test_options = ['-collect-test-diagnostics', 'never']
    stages = [
        # Build for the selected destination before running simulator services.
        # The project otherwise builds both arm64 and x86_64 on a cold runner.
        (base + ['build-for-testing', '-showBuildTimingSummary'], 600),
        # A hosted image's first boot may still be migrating LaunchServices data.
        (['xcrun', 'simctl', 'bootstatus', args.simulator, '-b'], 480),
        (base + test_options + ['test-without-building', '-only-testing:YueJiTests',
                 '-resultBundlePath', str(args.artifacts / 'UnitTestResults.xcresult')], 1200),
        # Keep the installed app/data, but give the UI runner a fresh simulator process.
        (['xcrun', 'simctl', 'shutdown', args.simulator], 60),
        (['xcrun', 'simctl', 'bootstatus', args.simulator, '-b'], 180),
        # Keep one UI runner and all tests. The latest run was still progressing
        # after 30 minutes; bound individual cases/transitions as well as the suite.
        (base + test_options + ['test-without-building', '-only-testing:YueJiUITests',
                 '-resultBundlePath', str(args.artifacts / 'UITestResults.xcresult')], 2400),
    ]
    with (args.artifacts / 'build-test.log').open('w', encoding='utf-8') as log:
        for command, timeout in stages:
            options = {'test_case_timeout': 900} if '-only-testing:YueJiUITests' in command else {}
            if '-only-testing:YueJiTests' in command:
                # Bound Xcode launch separately: a stalled hosted runner must not
                # consume the whole unit-suite allowance before tests even start.
                options = {'test_case_timeout': 300, 'test_transition_timeout': 300}
            code = run_stage(command, log, timeout, **options)
            if code:
                return code
        log.write('** ALL NATIVE SUITES SUCCEEDED **\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
