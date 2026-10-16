-- Step 4: who replies to whom, early (2021-22) vs late (2024-26).
-- Both ends of every edge are members above the 1,000-message floor; self-replies are excluded.

-- QUERY: reply_edges
-- Replies from each member to each other member, per period.
WITH periods AS (
    SELECT * FROM (VALUES
        ('early', DATE '2021-01-01', DATE '2022-12-31'),
        ('mid',   DATE '2023-01-01', DATE '2023-12-31'),
        ('late',  DATE '2024-01-01', DATE '2026-08-09')
    ) AS t(period, start_date, end_date)
)
SELECT
    p.period,
    r.pseudonym AS source,
    m.pseudonym AS target,
    count(*) AS weight
FROM human_messages r
JOIN human_messages m ON m.id = r.reply_to_id
JOIN periods p ON r.timestamp::date BETWEEN p.start_date AND p.end_date
WHERE r.is_conversational AND m.is_conversational
  AND r.is_included_member AND m.is_included_member
  AND r.pseudonym <> m.pseudonym
GROUP BY p.period, r.pseudonym, m.pseudonym
ORDER BY p.period, weight DESC;

-- QUERY: period_totals
-- Messages and replies per period.
WITH periods AS (
    SELECT * FROM (VALUES
        ('early', DATE '2021-01-01', DATE '2022-12-31'),
        ('mid',   DATE '2023-01-01', DATE '2023-12-31'),
        ('late',  DATE '2024-01-01', DATE '2026-08-09')
    ) AS t(period, start_date, end_date)
)
SELECT
    p.period,
    p.start_date,
    p.end_date,
    (p.end_date - p.start_date + 1) AS days,
    count(*) FILTER (WHERE h.is_included_member) AS messages_included_members,
    count(*) AS messages_all_humans,
    count(*) FILTER (WHERE h.reply_to_id IS NOT NULL) AS reply_messages,
    count(*) FILTER (WHERE h.reply_to_id IS NOT NULL)::float / count(*) AS reply_share,
    count(DISTINCT h.pseudonym) FILTER (WHERE h.is_included_member) AS members_posting
FROM human_messages h
JOIN periods p ON h.timestamp::date BETWEEN p.start_date AND p.end_date
WHERE h.is_conversational
GROUP BY p.period, p.start_date, p.end_date
ORDER BY p.start_date;

-- QUERY: mention_edges
-- Mentions between members, per period.
WITH periods AS (
    SELECT * FROM (VALUES
        ('early', DATE '2021-01-01', DATE '2022-12-31'),
        ('mid',   DATE '2023-01-01', DATE '2023-12-31'),
        ('late',  DATE '2024-01-01', DATE '2026-08-09')
    ) AS t(period, start_date, end_date)
)
SELECT
    p.period,
    h.pseudonym AS source,
    men.target,
    count(*) AS weight
FROM human_messages h
JOIN periods p ON h.timestamp::date BETWEEN p.start_date AND p.end_date
CROSS JOIN LATERAL jsonb_array_elements_text(COALESCE(h.mentions_pseudo, '[]'::jsonb)) AS men(target)
JOIN pseudonyms tp ON tp.pseudonym = men.target
WHERE h.is_conversational
  AND h.is_included_member
  AND tp.is_included_member
  AND men.target <> 'unmapped_mention'
  AND men.target <> h.pseudonym
GROUP BY p.period, h.pseudonym, men.target
ORDER BY p.period, weight DESC;

-- QUERY: member_period_activity
-- Messages per member per period.
WITH periods AS (
    SELECT * FROM (VALUES
        ('early', DATE '2021-01-01', DATE '2022-12-31'),
        ('mid',   DATE '2023-01-01', DATE '2023-12-31'),
        ('late',  DATE '2024-01-01', DATE '2026-08-09')
    ) AS t(period, start_date, end_date)
)
SELECT
    p.period,
    h.pseudonym,
    count(*) AS messages,
    count(*) FILTER (WHERE h.reply_to_id IS NOT NULL) AS replies_sent,
    count(*)::float / sum(count(*)) OVER (PARTITION BY p.period) AS share_of_period
FROM human_messages h
JOIN periods p ON h.timestamp::date BETWEEN p.start_date AND p.end_date
WHERE h.is_conversational AND h.is_included_member
GROUP BY p.period, h.pseudonym
ORDER BY p.period, messages DESC;

-- QUERY: member_posts_dayhour
-- Messages per member per date and hour, for the shared-schedule check.
WITH periods AS (
    SELECT * FROM (VALUES
        ('early', DATE '2021-01-01', DATE '2022-12-31'),
        ('late',  DATE '2024-01-01', DATE '2026-08-09')
    ) AS t(period, start_date, end_date)
)
SELECT
    p.period,
    h.pseudonym,
    h.timestamp::date AS day,
    EXTRACT(HOUR FROM h.timestamp)::int AS hour,
    count(*) AS messages
FROM human_messages h
JOIN periods p ON h.timestamp::date BETWEEN p.start_date AND p.end_date
WHERE h.is_conversational AND h.is_included_member
GROUP BY p.period, h.pseudonym, day, hour
ORDER BY p.period, h.pseudonym, day, hour;

-- QUERY: reply_edges_dayhour
-- reply_edges split by the date and hour of the reply.
WITH periods AS (
    SELECT * FROM (VALUES
        ('early', DATE '2021-01-01', DATE '2022-12-31'),
        ('late',  DATE '2024-01-01', DATE '2026-08-09')
    ) AS t(period, start_date, end_date)
)
SELECT
    p.period,
    r.pseudonym AS source,
    m.pseudonym AS target,
    r.timestamp::date AS day,
    EXTRACT(HOUR FROM r.timestamp)::int AS hour,
    count(*) AS replies
FROM human_messages r
JOIN human_messages m ON m.id = r.reply_to_id
JOIN periods p ON r.timestamp::date BETWEEN p.start_date AND p.end_date
WHERE r.is_conversational AND m.is_conversational
  AND r.is_included_member AND m.is_included_member
  AND r.pseudonym <> m.pseudonym
GROUP BY p.period, r.pseudonym, m.pseudonym, day, hour
ORDER BY p.period, r.pseudonym, m.pseudonym, day, hour;
