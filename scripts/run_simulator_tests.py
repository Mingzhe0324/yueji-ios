"""Run required native suites sequentially, with bounded simulator startup and diagnostics."""
import argparse
import os
from pathlib import Path
import queue
import signal
import subprocess
import threading
import time


INITIALIZATION_FAILURE = 'Failed to initialize for UI testing:'


def run_stage(command, log, timeout, grace=5):
    """Stream output; preserve nonzero exits and stop a failed runner's entire process group."""
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
    deadline = time.monotonic() + timeout
    forced_code = None
    termination_deadline = None
    output_finished = False

    def stop(sig):
        try:
            if os.name == 'posix':
                os.killpg(process.pid, sig)
            elif sig == signal.SIGTERM:
                process.terminate()
            else:
                process.kill()
        except ProcessLookupError:
            pass

    try:
        while True:
            if output_finished and process.poll() is not None:
                break
            now = time.monotonic()
            if forced_code is None and now >= deadline:
                emit(f'CI stage timed out after {timeout} seconds; native verification did not complete.\n')
                forced_code = 124
            if forced_code is not None and termination_deadline is None:
                stop(signal.SIGTERM)
                termination_deadline = now + grace
            if termination_deadline is not None and now >= termination_deadline:
                stop(getattr(signal, 'SIGKILL', signal.SIGTERM + 1))
                break
            try:
                line = lines.get(timeout=0.1)
            except queue.Empty:
                continue
            if line is None:
                output_finished = True
                continue
            emit(line)
            if INITIALIZATION_FAILURE in line and forced_code is None:
                emit('CI runner initialization failed; stopping instead of waiting for the job timeout.\n')
                forced_code = 65
        # Flush output already delivered by the reader before closing the log.
        while not lines.empty():
            line = lines.get_nowait()
            if line is not None:
                emit(line)
        return forced_code if forced_code is not None else process.returncode
    finally:
        if process.poll() is None:
            stop(getattr(signal, 'SIGKILL', signal.SIGTERM + 1))
        process.wait()
        reader.join(timeout=1)
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    base = ['xcodebuild', '-project', 'YueJi.xcodeproj', '-scheme', 'YueJi',
            '-destination', f'platform=iOS Simulator,id={args.simulator}',
            '-derivedDataPath', 'build-simulator', '-parallel-testing-enabled', 'NO',
            'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO']
    stages = [
        (['xcrun', 'simctl', 'bootstatus', args.simulator, '-b'], 180),
        (base + ['build-for-testing'], 600),
        (base + ['test-without-building', '-only-testing:YueJiTests',
                 '-resultBundlePath', str(args.artifacts / 'UnitTestResults.xcresult')], 900),
        # Keep the installed app/data, but give the UI runner a fresh simulator process.
        (['xcrun', 'simctl', 'shutdown', args.simulator], 60),
        (['xcrun', 'simctl', 'bootstatus', args.simulator, '-b'], 180),
        (base + ['test-without-building', '-only-testing:YueJiUITests',
                 '-resultBundlePath', str(args.artifacts / 'UITestResults.xcresult')], 900),
    ]
    with (args.artifacts / 'build-test.log').open('w', encoding='utf-8') as log:
        for command, timeout in stages:
            code = run_stage(command, log, timeout)
            if code:
                return code
        log.write('** ALL NATIVE SUITES SUCCEEDED **\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
