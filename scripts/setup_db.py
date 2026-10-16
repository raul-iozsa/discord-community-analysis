"""Rebuilds the human_messages view from sql/00_setup_views.sql. Run after scripts/build_pseudonyms.py."""
import os
import sys

import psycopg2

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQL_PATH = os.path.join(REPO_ROOT, "sql", "00_setup_views.sql")


def main():
    with open(SQL_PATH, encoding="utf-8") as f:
        sql = f.read()

    conn = psycopg2.connect(host="localhost", port=5432, dbname="postgres", user="postgres",
                            options="-c timezone=Europe/Bucharest")
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute(sql)

    cur.execute("SELECT count(*), count(*) FILTER (WHERE is_conversational) FROM human_messages")
    total, conversational = cur.fetchone()
    cur.execute("SELECT count(*) FROM pseudonyms")
    pseudonyms = cur.fetchone()[0]

    print(f"human_messages rebuilt: {total:,} rows "
          f"({conversational:,} conversational, {total - conversational} system)")
    print(f"pseudonyms: {pseudonyms} members")

    if total == 0:
        sys.exit("human_messages is empty -- is the raw archive loaded?")

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
