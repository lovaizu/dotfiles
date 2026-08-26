"""Run the extracted merger the way setup.sh runs it, in a throwaway dir."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MERGE = os.environ.get("MERGE_FILE", os.path.join(REPO, "lib", "merge.py"))
PY = os.environ.get("MERGE_PY", "/usr/bin/python3")
WORK = os.path.join(HERE, os.environ.get("MERGE_WORK", "work"))


def run(fmt, src_text, dst_text, backup="", dst_name=None, py=None):
    os.makedirs(WORK, exist_ok=True)
    d = tempfile.mkdtemp(dir=WORK, prefix="case.")
    src = os.path.join(d, "src." + fmt)
    dst = os.path.join(d, dst_name or ("dst." + fmt))
    with open(src, "w", encoding="utf-8", newline="") as f:
        f.write(src_text)
    if dst_text is not None:
        with open(dst, "w", encoding="utf-8", newline="") as f:
            f.write(dst_text)
    env = dict(os.environ, MERGE_BACKUP=backup)
    p = subprocess.run([py or PY, MERGE, fmt, src, dst], capture_output=True,
                       text=True, env=env)
    out = None
    if os.path.exists(dst):
        with open(dst, "rb") as f:
            out = f.read().decode("utf-8", "replace")
    return p.returncode, p.stdout, p.stderr, out, d


def clean():
    shutil.rmtree(WORK, ignore_errors=True)
