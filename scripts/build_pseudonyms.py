"""Builds the pseudonyms table (user_01 = most messages) and the private name mapping.

Run before scripts/setup_db.py. The mapping is written to mapping_private/, which is never committed.
"""
import csv
import os
import psycopg2

INCLUSION_FLOOR = 1000  # lifetime messages

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPPING_PATH = os.path.join(REPO_ROOT, "mapping_private", "name_mapping.csv")


def main():
    conn = psycopg2.connect(host="localhost", port=5432, dbname="postgres", user="postgres",
                            options="-c timezone=Europe/Bucharest")
    cur = conn.cursor()

    cur.execute("""
        SELECT a.author_id, a.display_name, a.original_name, count(m.id) AS lifetime_msgs
        FROM authors a
        JOIN messages m ON m.author_id = a.author_id
        WHERE a.is_bot = false
        GROUP BY a.author_id, a.display_name, a.original_name
        ORDER BY lifetime_msgs DESC, a.author_id
    """)
    rows = cur.fetchall()
    print(f"{len(rows)} human authors found")

    # CASCADE drops human_messages too; scripts/setup_db.py rebuilds it.
    cur.execute("DROP TABLE IF EXISTS pseudonyms CASCADE")
    cur.execute("""
        CREATE TABLE pseudonyms (
            author_id BIGINT PRIMARY KEY,
            pseudonym TEXT UNIQUE NOT NULL,
            lifetime_message_count INT NOT NULL,
            is_included_member BOOLEAN NOT NULL
        )
    """)

    mapping_rows = []
    for i, (author_id, display_name, original_name, lifetime_msgs) in enumerate(rows, start=1):
        pseudonym = f"user_{i:02d}"
        is_included = lifetime_msgs >= INCLUSION_FLOOR
        cur.execute(
            "INSERT INTO pseudonyms (author_id, pseudonym, lifetime_message_count, is_included_member) "
            "VALUES (%s,%s,%s,%s)",
            (author_id, pseudonym, lifetime_msgs, is_included),
        )
        mapping_rows.append((pseudonym, display_name, original_name, author_id, lifetime_msgs, is_included))

    conn.commit()

    os.makedirs(os.path.dirname(MAPPING_PATH), exist_ok=True)
    with open(MAPPING_PATH, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "pseudonym", "display_name", "original_discord_username",
            "author_id", "lifetime_message_count",
            f"is_included_member (>={INCLUSION_FLOOR} msgs)",
        ])
        w.writerows(mapping_rows)

    print(f"pseudonyms table rebuilt: {len(mapping_rows)} rows")
    print(f"private mapping written: {MAPPING_PATH}")

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
