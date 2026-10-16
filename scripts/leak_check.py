"""Scans the repository's text files, notebooks and Tableau workbook (not images) for real names
and Discord IDs from the private mapping.

Exits 1 on any Discord ID. Name hits are printed for a person to check, since some names are
ordinary words.
"""
import csv
import html
import os
import re
import sys
import zipfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPPING = os.path.join(REPO_ROOT, "mapping_private", "name_mapping.csv")

EXCLUDED_DIRS = {"mapping_private", "z other stuff", "private", "__pycache__",
                 ".ipynb_checkpoints", ".git"}
SKIP_EXT = {".png", ".jpg", ".jpeg", ".xlsx", ".pyc"}


def load_identifiers():
    if not os.path.exists(MAPPING):
        sys.exit(f"no mapping at {MAPPING} -- run scripts/build_pseudonyms.py first.")
    rows = list(csv.DictReader(open(MAPPING, encoding="utf-8")))
    names = {r["display_name"].strip() for r in rows if r["display_name"].strip()}
    names |= {r["original_discord_username"].strip() for r in rows
              if r["original_discord_username"].strip()}
    ids = {r["author_id"].strip() for r in rows if r["author_id"].strip()}
    return names, ids


def publishable_files():
    for root, dirs, fnames in os.walk(REPO_ROOT):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for fn in fnames:
            if os.path.splitext(fn)[1].lower() in SKIP_EXT:
                continue
            yield os.path.join(root, fn)


def read_text(path):
    lower = path.lower()
    if lower.endswith(".docx"):
        with zipfile.ZipFile(path) as z:
            xml = z.read("word/document.xml").decode("utf-8", "replace")
        return html.unescape(re.sub(r"<[^>]+>", " ", xml))
    if lower.endswith(".twbx"):
        with zipfile.ZipFile(path) as z:
            return "\n".join(z.read(n).decode("utf-8", "replace")
                             for n in z.namelist() if n.endswith(".twb"))
    return open(path, encoding="utf-8", errors="replace").read()


def main():
    names, ids = load_identifiers()
    name_re = {n: re.compile(rf"\b{re.escape(n)}\b", re.I) for n in names}
    snowflake_re = re.compile(r"\b\d{17,19}\b")

    files = list(publishable_files())
    print(f"scanning {len(files)} publishable files against {len(names)} names "
          f"and {len(ids)} author ids\n")

    id_hits, name_hits = [], []
    for path in files:
        rel = os.path.relpath(path, REPO_ROOT)
        try:
            text = read_text(path)
        except OSError as err:
            print(f"  ! unreadable: {rel} ({err})")
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for hit in snowflake_re.findall(line):
                if hit in ids:
                    id_hits.append((rel, lineno, hit, line.strip()[:100]))
            for name, rx in name_re.items():
                if rx.search(line):
                    name_hits.append((rel, lineno, name, line.strip()[:100]))

    print(f"DISCORD ID HITS: {len(id_hits)}")
    for rel, lineno, hit, line in id_hits:
        print(f"  {rel}:{lineno}  {hit}\n      {line}")

    print(f"\nNAME HITS: {len(name_hits)} (check by hand; many are common words)")
    by_name = {}
    for rel, lineno, name, line in name_hits:
        by_name.setdefault(name, []).append((rel, lineno, line))
    for name in sorted(by_name, key=lambda n: -len(by_name[n])):
        rels = {r for r, _, _ in by_name[name]}
        print(f"  {name:<16} {len(by_name[name]):>4} hits in {len(rels)} file(s)")
        for rel, lineno, line in by_name[name][:3]:
            print(f"      {rel}:{lineno}  {line[:88]}")

    if id_hits:
        sys.exit(f"\nFAILED: {len(id_hits)} real Discord id(s) in publishable files.")
    print("\nNo Discord ids found. Check the name hits above before publishing.")


if __name__ == "__main__":
    main()
