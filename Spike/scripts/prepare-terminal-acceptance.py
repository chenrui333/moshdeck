#!/usr/bin/env python3
"""Create a disposable, offline terminal/coding-task workspace; never attach it."""

from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(tempfile.mkdtemp(prefix="moshdeck-acceptance-"))
    files = {
        ".gitignore": "__pycache__/\n",
        "labels.py": '''def count_labels(labels):
    """Count nonempty labels, including duplicates."""
    return sum(bool(label.strip()) for label in labels)
''',
        "test_labels.py": '''import unittest
from labels import count_labels


class LabelTests(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(count_labels([]), 0)

    def test_whitespace(self):
        self.assertEqual(count_labels(["", "  ", "work"]), 1)

    def test_unicode(self):
        self.assertEqual(count_labels(["中文", "日本語", "👩🏽‍💻", "e\\u0301"]), 4)


if __name__ == "__main__":
    unittest.main()
''',
        "sample.txt": (
            "MoshDeck disposable terminal sample\n"
            "ASCII: 0O 1lI {} [] () / \\ | ~ `\n"
            "Chinese: 中文测试\nJapanese: 日本語\n"
            "Emoji: 👩🏽‍💻 🚀\nCombining: e\u0301 versus é\n"
            + "".join(f"line {i:03d}: inspect scrolling and resize\n" for i in range(1, 201))
        ),
        "TASK.md": '''# Disposable coding task

Add `normalize_labels(labels)` to `labels.py` without changing `count_labels`.
Trim surrounding whitespace, drop empty strings, preserve Unicode, and remove
exact duplicates while retaining first-seen order. Matching is case-sensitive.
Add unit tests for empty input, whitespace, duplicates, order and Unicode.
Run `python3 -m unittest -v` and explain the result.

This workspace has no network or third-party package requirement. Use it only
for terminal acceptance; do not modify another repository or infrastructure.
''',
    }
    for name, text in files.items():
        (root / name).write_text(text, encoding="utf-8")
    subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
    subprocess.run(
        ["git", "-C", str(root), "commit", "-q", "-s", "-m", "test: seed terminal acceptance workspace"],
        check=True,
    )
    subprocess.run(["python3", "-m", "unittest", "-v"], cwd=root, check=True)
    print(f"Workspace: {root}")
    print("No tmux session or coding agent was started. Existing sessions are unchanged.")


if __name__ == "__main__":
    main()
