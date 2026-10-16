"""Builds, executes and verifies step notebooks: python scripts/run_notebook.py 01 02 03 04 05

A notebook passes only if every code cell parses, every code cell has output, and none errors.
"""
import ast
import json
import os
import subprocess
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARTS_DIR = os.path.join(REPO_ROOT, "outputs", "charts")


def parse_check(nb_path):
    nb = json.load(open(nb_path, encoding="utf-8"))
    bad = []
    for i, c in enumerate(nb["cells"]):
        if c["cell_type"] != "code":
            continue
        try:
            ast.parse("".join(c["source"]))
        except SyntaxError as e:
            bad.append((i, e))
    return bad


def verify(nb_path, started_at):
    nb = json.load(open(nb_path, encoding="utf-8"))
    code = [(i, c) for i, c in enumerate(nb["cells"]) if c["cell_type"] == "code"]
    no_output = [i for i, c in code if not c.get("outputs")]
    errored = [i for i, c in code
               if any(o.get("output_type") == "error" for o in c.get("outputs", []))]

    problems = []
    if no_output:
        problems.append(f"cells with NO output (did not execute): {no_output}")
    if errored:
        problems.append(f"cells with ERROR output: {errored}")
        for i, c in code:
            if i in errored:
                for o in c.get("outputs", []):
                    if o.get("output_type") == "error":
                        problems.append(f"  cell {i}: {o.get('ename')}: {o.get('evalue')}")

    stale = []
    if os.path.isdir(CHARTS_DIR):
        for f in sorted(os.listdir(CHARTS_DIR)):
            if f.endswith(".png") and os.path.getmtime(os.path.join(CHARTS_DIR, f)) < started_at:
                stale.append(f)
    return problems, stale, len(code)


def run(step):
    builder = os.path.join(REPO_ROOT, "scripts", f"build_notebook_{step}.py")
    nb_path = os.path.join(REPO_ROOT, "notebooks", f"{step}_" + {
        "01": "decomposition", "02": "tournaments", "03": "corroborating",
        "04": "network", "05": "changepoints",
    }[step] + ".ipynb")

    print(f"=== step {step} ===")
    subprocess.run([sys.executable, builder], check=True)

    bad = parse_check(nb_path)
    if bad:
        for i, e in bad:
            print(f"  FAIL cell {i} does not parse: {e}")
        raise SystemExit(f"step {step}: notebook has syntax errors, not executing")
    print("  parse check: OK")

    started_at = time.time()
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    subprocess.run([sys.executable, "-m", "jupyter", "nbconvert", "--to", "notebook",
                    "--execute", "--inplace", nb_path],
                   check=True, env=env, capture_output=True)

    problems, stale, n = verify(nb_path, started_at)
    for p in problems:
        print("  FAIL " + p)
    if stale:
        print(f"  note: {len(stale)} chart(s) not rewritten by this run "
              f"(fine if this step does not own them): {', '.join(stale)}")
    if problems:
        raise SystemExit(f"step {step}: verification failed")
    print(f"  executed and verified: {n} code cells, all with output, no errors")


if __name__ == "__main__":
    steps = sys.argv[1:] or ["01", "02"]
    for s in steps:
        run(s)
    print("\nall requested steps built, executed and verified.")
