"""运行真实的重启脚本，检查顺序、取消退出和参数传递。"""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('update-relaunch.sh')


class RelaunchTests(unittest.TestCase):
    def invoke(self, pid, wait, status=0):
        with tempfile.TemporaryDirectory(prefix='pop relaunch ') as folder:
            root = pathlib.Path(folder)
            args = root / 'arguments'
            opener = root / "fake 'open"
            opener.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARGUMENTS"\nexit "$STATUS"\n')
            opener.chmod(0o700)
            import os
            env = dict(os.environ, ARGUMENTS=str(args), STATUS=str(status))
            app = str(root / "Pop's app.app")
            result = subprocess.run(['/bin/sh', str(SCRIPT), str(pid), app, str(opener), str(wait),
                                     '--env', 'POP_PLUGIN_DATA_DIR=/tmp/data with spaces'],
                                    env=env, capture_output=True, text=True, timeout=5)
            return result, args.read_text().splitlines() if args.exists() else None, app

    def test_exited_parent_opens_new_instance_and_preserves_arguments(self):
        parent = subprocess.Popen(['true'])
        parent.wait()
        result, args, app = self.invoke(parent.pid, 5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args, ['-n', '--env', 'POP_PLUGIN_DATA_DIR=/tmp/data with spaces', app])
        self.assertLess(result.stdout.index('old_pid_exited'), result.stdout.index('open_finished status=0'))
        self.assertNotIn('POP_PLUGIN_DATA_DIR', result.stdout)

    def test_running_parent_timeout_never_opens(self):
        parent = subprocess.Popen(['sleep', '10'])
        try:
            result, args, _ = self.invoke(parent.pid, 1)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('old_pid_timeout', result.stdout)
            self.assertIsNone(args)
        finally:
            parent.terminate()
            parent.wait()

    def test_open_failure_preserves_exit_status(self):
        parent = subprocess.Popen(['true'])
        parent.wait()
        result, _, _ = self.invoke(parent.pid, 5, status=7)
        self.assertEqual(result.returncode, 7)
        self.assertIn('open_finished status=7', result.stdout)

    def test_parent_must_exit_before_open(self):
        parent = subprocess.Popen(['sleep', '0.3'])
        # 回收父进程，避免 Linux 僵尸 PID 使 kill -0 一直成功。
        import threading
        reaper = threading.Thread(target=parent.wait)
        reaper.start()
        result, args, _ = self.invoke(parent.pid, 10)
        reaper.join()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIsNotNone(args)
        self.assertIn('old_pid_exited', result.stdout)


if __name__ == '__main__':
    unittest.main()
