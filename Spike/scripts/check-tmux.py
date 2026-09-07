#!/usr/bin/env python3
"""Exercise tmux handoff in a disposable server, never the owner's sessions."""
import fcntl
import json
import os
import pty
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import uuid


def main():
    tmux = shutil.which('tmux')
    if not tmux:
        raise SystemExit('tmux is required')
    namespace = 'moshdeck-spike-' + uuid.uuid4().hex
    clients = []
    results = {}
    with tempfile.TemporaryDirectory(prefix='moshdeck-tmux-') as home:
        # This subprocess-only environment avoids user shell/tmux configuration.
        env = {'HOME': home, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'TERM': 'xterm-256color', 'LC_ALL': 'en_US.UTF-8'}
        base = [tmux, '-L', namespace, '-f', '/dev/null']

        def run(*args, check=True):
            return subprocess.run(base + list(args), env=env, check=check, capture_output=True, text=True).stdout.strip()

        def size(fd, cols, rows):
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))

        def attach(cols, rows):
            pid, fd = pty.fork()
            if pid == 0:
                size(0, cols, rows)
                os.execve(tmux, base + ['attach-session', '-t', '=work'], env)
            clients.append((pid, fd))
            return pid, fd

        def wait_for(predicate):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if predicate():
                    return
                time.sleep(0.05)
            raise AssertionError('tmux did not reach expected state')

        def pane():
            return run('display-message', '-p', '-t', 'work:0.0', '#{pane_pid}:#{pane_width}:#{pane_height}')

        def detach(client):
            pid, fd = client
            os.close(fd)  # Simulate a disappearing terminal, not a tmux command.
            os.waitpid(pid, 0)
            clients.remove(client)

        try:
            run('new-session', '-d', '-s', 'work', '-x', '100', '-y', '30', 'exec /bin/sleep 600')
            run('set-option', '-t', 'work', 'status', 'off')
            run('set-window-option', '-t', 'work:0', 'window-size', 'latest')
            initial_pid = pane().split(':')[0]
            mac = attach(120, 40)
            wait_for(lambda: pane().endswith(':120:40'))
            phone = attach(45, 20)
            os.write(phone[1], b'x')
            wait_for(lambda: pane().endswith(':45:20'))
            results['simultaneous_clients'] = len(run('list-clients', '-F', '#{client_name}').splitlines()) == 2
            os.write(mac[1], b'x')
            wait_for(lambda: pane().endswith(':120:40'))
            results['latest_follows_active_client'] = True
            detach(phone)
            results['phone_disconnect_preserves_pane'] = pane().split(':')[0] == initial_pid
            detach(mac)
            results['all_clients_disconnect_preserves_pane'] = pane().split(':')[0] == initial_pid
            phone = attach(45, 20)
            wait_for(lambda: pane().endswith(':45:20'))
            results['reattach_same_process'] = pane().split(':')[0] == initial_pid
            size(phone[1], 60, 24)
            wait_for(lambda: pane().endswith(':60:24'))
            results['resize_reaches_remote_pty'] = True
            missing = subprocess.run(base + ['has-session', '-t', '=missing'], env=env, capture_output=True)
            results['missing_target_fails'] = missing.returncode != 0
            assert all(results.values()), results
            print(json.dumps({'tmux': subprocess.check_output([tmux, '-V'], text=True).strip(), 'scope': 'local disposable PTYs; not iPhone, SSH, or iTerm2 validation', 'checks': results}, indent=2))
        finally:
            run('kill-server', check=False)
            for pid, fd in clients:
                os.close(fd)
                try:
                    os.waitpid(pid, 0)
                except ChildProcessError:
                    pass


if __name__ == '__main__':
    main()
