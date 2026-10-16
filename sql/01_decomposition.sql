-- Step 1: is the decline fewer people, or the same people posting less?
-- Headline comparison: 2022 vs 2025, both full calendar years.

-- QUERY: yearly_totals
-- Messages per year and per day.
SELECT
    EXTRACT(YEAR FROM timestamp)::int AS year,
    count(*) AS total_messages,
    min(timestamp)::date AS first_message_date,
    max(timestamp)::date AS last_message_date,
    (max(timestamp)::date - min(timestamp)::date + 1) AS days_observed,
    count(*)::float / (max(timestamp)::date - min(timestamp)::date + 1) AS messages_per_day
FROM human_messages
WHERE is_conversational
GROUP BY year
ORDER BY year;

-- QUERY: active_members_per_year
-- Active = at least 12 messages that year.
WITH per_member_year AS (
    SELECT EXTRACT(YEAR FROM timestamp)::int AS year, pseudonym, count(*) AS msgs
    FROM human_messages
    WHERE is_conversational
    GROUP BY year, pseudonym
)
SELECT
    year,
    count(*) FILTER (WHERE msgs >= 1)   AS active_ge1,
    count(*) FILTER (WHERE msgs >= 12)  AS active_ge12,
    count(*) FILTER (WHERE msgs >= 100) AS active_ge100
FROM per_member_year
GROUP BY year
ORDER BY year;

-- QUERY: decomposition
-- Messages per day = active members x messages per active member per day.
WITH per_member_year AS (
    SELECT EXTRACT(YEAR FROM timestamp)::int AS year, pseudonym, count(*) AS msgs
    FROM human_messages
    WHERE is_conversational
    GROUP BY year, pseudonym
),
active_per_year AS (
    SELECT year, count(*) FILTER (WHERE msgs >= 12) AS active_members
    FROM per_member_year
    GROUP BY year
),
totals AS (
    SELECT
        EXTRACT(YEAR FROM timestamp)::int AS year,
        count(*) AS total_messages,
        (max(timestamp)::date - min(timestamp)::date + 1) AS days_observed
    FROM human_messages
    WHERE is_conversational
    GROUP BY year
)
SELECT
    t.year,
    t.total_messages,
    t.days_observed,
    t.total_messages::float / t.days_observed AS messages_per_day,
    a.active_members,
    t.total_messages::float / a.active_members AS messages_per_active_member,
    (t.total_messages::float / a.active_members) / t.days_observed AS messages_per_active_member_per_day
FROM totals t
JOIN active_per_year a ON a.year = t.year
ORDER BY t.year;

-- QUERY: member_lifecycle
-- First and last message per member.
SELECT
    pseudonym,
    bool_and(is_included_member) AS is_included_member,
    count(*) AS lifetime_message_count,
    min(timestamp)::date AS first_message_date,
    max(timestamp)::date AS last_message_date,
    count(DISTINCT EXTRACT(YEAR FROM timestamp)) AS distinct_years_with_activity,
    (max(timestamp)::date - min(timestamp)::date) AS lifetime_span_days
FROM human_messages
WHERE is_conversational
GROUP BY pseudonym
ORDER BY lifetime_message_count DESC;

-- QUERY: window_check
-- Every year cut to 1 Jan - 9 Aug, so the partial 2026 can be compared.
WITH bounds AS (
    SELECT
        y,
        make_date(y, 1, 1)  AS win_start,
        make_date(y, 8, 9)  AS win_end,
        (make_date(y, 8, 9) - make_date(y, 1, 1) + 1) AS win_days
    FROM generate_series(2020, 2026) AS y
),
windowed AS (
    SELECT EXTRACT(YEAR FROM timestamp)::int AS year, pseudonym
    FROM human_messages
    WHERE is_conversational AND to_char(timestamp, 'MM-DD') <= '08-09'
),
per_member AS (
    SELECT year, pseudonym, count(*) AS msgs
    FROM windowed GROUP BY year, pseudonym
)
SELECT
    b.y AS year,
    b.win_days,
    sum(pm.msgs) AS window_messages,
    sum(pm.msgs)::float / b.win_days AS window_messages_per_day,
    count(*) FILTER (WHERE pm.msgs >= 12) AS window_active_ge12,
    count(*) FILTER (WHERE pm.msgs >= 7)  AS window_active_ge7,
    (sum(pm.msgs)::float / NULLIF(count(*) FILTER (WHERE pm.msgs >= 12), 0)) / b.win_days
        AS window_msgs_per_active_member_per_day
FROM bounds b
JOIN per_member pm ON pm.year = b.y
GROUP BY b.y, b.win_days
ORDER BY b.y;

-- QUERY: cohort_decomposition
-- Members present by 2022 vs members who first posted later.
WITH cohort AS (
    SELECT
        pseudonym,
        min(timestamp)::date AS first_message_date,
        CASE WHEN min(timestamp) < date '2023-01-01' THEN 'founding' ELSE 'later' END AS cohort
    FROM human_messages
    WHERE is_conversational
    GROUP BY pseudonym
),
per_member_year AS (
    SELECT
        EXTRACT(YEAR FROM h.timestamp)::int AS year,
        h.pseudonym,
        c.cohort,
        count(*) AS msgs
    FROM human_messages h
    JOIN cohort c ON c.pseudonym = h.pseudonym
    WHERE h.is_conversational
    GROUP BY year, h.pseudonym, c.cohort
),
days AS (
    SELECT
        EXTRACT(YEAR FROM timestamp)::int AS year,
        (max(timestamp)::date - min(timestamp)::date + 1) AS days_observed
    FROM human_messages WHERE is_conversational GROUP BY year
)
SELECT
    p.year,
    p.cohort,
    d.days_observed,
    sum(p.msgs) AS total_messages,
    sum(p.msgs)::float / d.days_observed AS messages_per_day,
    count(*) FILTER (WHERE p.msgs >= 12) AS active_members,
    (sum(p.msgs)::float / NULLIF(count(*) FILTER (WHERE p.msgs >= 12), 0)) / d.days_observed
        AS messages_per_active_member_per_day
FROM per_member_year p
JOIN days d ON d.year = p.year
GROUP BY p.year, p.cohort, d.days_observed
ORDER BY p.year, p.cohort DESC;

-- QUERY: membership_events
-- Join events per member. Discord logs joins but not leaves.
WITH joins AS (
    SELECT
        pseudonym,
        count(*) AS join_count,
        min(timestamp)::date AS first_join_date,
        max(timestamp)::date AS last_join_date
    FROM human_messages
    WHERE type = 'GuildMemberJoin'
    GROUP BY pseudonym
),
posts AS (
    SELECT
        pseudonym,
        bool_and(is_included_member) AS is_included_member,
        count(*) AS lifetime_message_count,
        min(timestamp)::date AS first_post_date,
        max(timestamp)::date AS last_post_date
    FROM human_messages
    WHERE is_conversational
    GROUP BY pseudonym
)
SELECT
    p.pseudonym,
    p.is_included_member,
    p.lifetime_message_count,
    COALESCE(j.join_count, 0) AS join_count,
    GREATEST(COALESCE(j.join_count, 0) - 1, 0) AS min_departures_implied,
    j.first_join_date,
    j.last_join_date,
    p.first_post_date,
    p.last_post_date,
    (date '2026-08-09' - p.last_post_date) AS days_silent_at_export_end,
    (j.first_join_date = p.first_post_date) AS first_post_matches_join
FROM posts p
LEFT JOIN joins j ON j.pseudonym = p.pseudonym
ORDER BY p.lifetime_message_count DESC;

-- QUERY: member_year_text
-- Characters and words per member per year (media-only messages count as 0).
SELECT
    EXTRACT(YEAR FROM timestamp)::int AS year,
    pseudonym,
    count(*) AS messages,
    sum(char_length(coalesce(content, ''))) AS chars,
    sum(char_length(regexp_replace(coalesce(content, ''), 'https?://\S+', '', 'g'))) AS chars_no_urls,
    sum(CASE WHEN btrim(coalesce(content, '')) = '' THEN 0
             ELSE array_length(regexp_split_to_array(btrim(content), '\s+'), 1) END) AS words
FROM human_messages
WHERE is_conversational
GROUP BY year, pseudonym
ORDER BY year, pseudonym;

-- QUERY: yearly_text
-- Median message length per year.
SELECT
    EXTRACT(YEAR FROM timestamp)::int AS year,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY char_length(coalesce(content, ''))) AS median_chars
FROM human_messages
WHERE is_conversational
GROUP BY year
ORDER BY year;

-- QUERY: turns_year
-- Back-to-back messages by the same author within the gap count as one turn.
WITH o AS (
    SELECT
        EXTRACT(YEAR FROM timestamp)::int AS year,
        pseudonym,
        timestamp,
        char_length(coalesce(content, '')) AS chars,
        lag(pseudonym) OVER w AS prev_author,
        lag(timestamp) OVER w AS prev_ts
    FROM human_messages
    WHERE is_conversational
    WINDOW w AS (ORDER BY timestamp, id)
),
gaps AS (
    SELECT * FROM (VALUES (30), (60), (120)) AS t(gap_seconds)
)
SELECT
    o.year,
    g.gap_seconds,
    count(*) AS messages,
    count(*) FILTER (WHERE o.prev_author IS DISTINCT FROM o.pseudonym
                     OR o.timestamp - o.prev_ts > make_interval(secs => g.gap_seconds)) AS turns,
    sum(o.chars) AS chars
FROM o
CROSS JOIN gaps g
GROUP BY o.year, g.gap_seconds
ORDER BY o.year, g.gap_seconds;

-- QUERY: length_bands_year
-- Messages per year by length in characters.
SELECT
    EXTRACT(YEAR FROM timestamp)::int AS year,
    CASE WHEN n = 0 THEN 1 WHEN n <= 5 THEN 2 WHEN n <= 20 THEN 3 WHEN n <= 50 THEN 4
         WHEN n <= 100 THEN 5 WHEN n <= 200 THEN 6 ELSE 7 END AS band_order,
    CASE WHEN n = 0 THEN '0' WHEN n <= 5 THEN '1-5' WHEN n <= 20 THEN '6-20'
         WHEN n <= 50 THEN '21-50' WHEN n <= 100 THEN '51-100' WHEN n <= 200 THEN '101-200'
         ELSE '201+' END AS band,
    count(*) AS messages
FROM (
    SELECT timestamp, char_length(coalesce(content, '')) AS n
    FROM human_messages
    WHERE is_conversational
) x
GROUP BY year, band_order, band
ORDER BY year, band_order;

-- QUERY: media_year
-- Attachments, embeds, links and reactions. Reactions are undated, so they are grouped by the year of the message.
WITH h AS (
    SELECT id, EXTRACT(YEAR FROM timestamp)::int AS year, coalesce(content, '') AS content
    FROM human_messages
    WHERE is_conversational
),
att AS (SELECT DISTINCT message_id FROM attachments),
emb AS (SELECT DISTINCT message_id FROM embeds),
rx AS (SELECT message_id, count(*) AS n FROM reactions GROUP BY message_id)
SELECT
    h.year,
    count(*) AS messages,
    count(*) FILTER (WHERE att.message_id IS NOT NULL) AS with_attachment,
    count(*) FILTER (WHERE h.content ~ 'https?://') AS with_link,
    count(*) FILTER (WHERE att.message_id IS NOT NULL OR emb.message_id IS NOT NULL
                     OR h.content ~ 'https?://') AS with_any_media,
    coalesce(sum(rx.n), 0) AS reactions
FROM h
LEFT JOIN att ON att.message_id = h.id
LEFT JOIN emb ON emb.message_id = h.id
LEFT JOIN rx ON rx.message_id = h.id
GROUP BY h.year
ORDER BY h.year;
