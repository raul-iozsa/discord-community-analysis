-- Step 3: posting hours, weekends, seasons, reply speed and reply share by year.
-- Hours use Europe/Bucharest wall-clock time.

-- QUERY: circadian_hour_year
-- Messages by hour of day, per year.
WITH per_hour AS (
    SELECT
        EXTRACT(YEAR  FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        EXTRACT(HOUR  FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS hour,
        count(*) AS messages
    FROM human_messages
    WHERE is_conversational
    GROUP BY year, hour
)
SELECT
    year,
    hour,
    messages,
    messages::float / sum(messages) OVER (PARTITION BY year) AS share_of_year
FROM per_hour
ORDER BY year, hour;

-- QUERY: member_median_hour_year
-- Median posting hour per member per year, on a clock that starts at 07:00 (the quietest hour) so midnight doesn't split the day.
WITH rotated AS (
    SELECT
        EXTRACT(YEAR FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        pseudonym,
        (EXTRACT(HOUR FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int - 7 + 24) % 24
            AS rotated_hour
    FROM human_messages
    WHERE is_conversational AND is_included_member
)
SELECT
    year,
    pseudonym,
    count(*) AS messages,
    (percentile_cont(0.5) WITHIN GROUP (ORDER BY rotated_hour) + 7)::numeric % 24
        AS median_hour_local
FROM rotated
GROUP BY year, pseudonym
HAVING count(*) >= 100
ORDER BY year, pseudonym;

-- QUERY: weekend_share_year
-- Share of messages sent on weekends.
WITH tagged AS (
    SELECT
        EXTRACT(YEAR FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        (timestamp AT TIME ZONE 'Europe/Bucharest')::date AS day,
        EXTRACT(DOW FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int IN (0, 6) AS is_weekend
    FROM human_messages
    WHERE is_conversational
)
SELECT
    year,
    count(*) FILTER (WHERE is_weekend)       AS weekend_messages,
    count(*) FILTER (WHERE NOT is_weekend)   AS weekday_messages,
    count(*)                                 AS total_messages,
    count(*) FILTER (WHERE is_weekend)::float / count(*) AS weekend_share,
    count(DISTINCT day) FILTER (WHERE is_weekend)     AS weekend_days_observed,
    count(DISTINCT day) FILTER (WHERE NOT is_weekend) AS weekday_days_observed,
    (count(*) FILTER (WHERE is_weekend))::float
        / NULLIF(count(DISTINCT day) FILTER (WHERE is_weekend), 0)     AS weekend_msgs_per_day,
    (count(*) FILTER (WHERE NOT is_weekend))::float
        / NULLIF(count(DISTINCT day) FILTER (WHERE NOT is_weekend), 0) AS weekday_msgs_per_day
FROM tagged
GROUP BY year
ORDER BY year;

-- QUERY: seasonality_month_year
-- Messages per day by month and year.
WITH per_month AS (
    SELECT
        EXTRACT(YEAR  FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        EXTRACT(MONTH FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS month,
        count(*) AS messages,
        count(DISTINCT (timestamp AT TIME ZONE 'Europe/Bucharest')::date) AS days_observed
    FROM human_messages
    WHERE is_conversational
    GROUP BY year, month
)
SELECT
    year,
    month,
    messages,
    days_observed,
    messages::float / days_observed AS messages_per_day,
    (messages::float / days_observed)
        / sum(messages::float / days_observed) OVER (PARTITION BY year)
        AS share_of_year_rate
FROM per_month
ORDER BY year, month;

-- QUERY: reply_latency_year
-- Time from a message to its reply.
WITH pairs AS (
    SELECT
        EXTRACT(YEAR FROM r.timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        EXTRACT(EPOCH FROM (r.timestamp - p.timestamp)) AS latency_sec
    FROM human_messages r
    JOIN human_messages p ON p.id = r.reply_to_id
    WHERE r.is_conversational AND p.is_conversational
      AND r.timestamp >= p.timestamp          -- guard against clock oddities
),
gaps AS (
    SELECT
        EXTRACT(YEAR FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        EXTRACT(EPOCH FROM (timestamp - lag(timestamp) OVER (ORDER BY timestamp)))
            AS gap_sec
    FROM human_messages
    WHERE is_conversational
),
lat AS (
    SELECT
        year,
        count(*) AS reply_pairs,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY latency_sec) AS p25_latency_sec,
        percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_sec) AS median_reply_latency_sec,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY latency_sec) AS p75_latency_sec,
        avg((latency_sec <=  60)::int) AS share_replied_under_60s,
        avg((latency_sec <= 300)::int) AS share_replied_under_5min
    FROM pairs GROUP BY year
),
gp AS (
    SELECT
        year,
        percentile_cont(0.50) WITHIN GROUP (ORDER BY gap_sec) AS median_gap_sec
    FROM gaps WHERE gap_sec IS NOT NULL AND gap_sec >= 0 GROUP BY year
)
SELECT
    l.year,
    l.reply_pairs,
    l.p25_latency_sec,
    l.median_reply_latency_sec,
    l.p75_latency_sec,
    l.share_replied_under_60s,
    l.share_replied_under_5min,
    g.median_gap_sec,
    l.median_reply_latency_sec / NULLIF(g.median_gap_sec, 0) AS latency_to_gap_ratio
FROM lat l
JOIN gp g ON g.year = l.year
ORDER BY l.year;

-- QUERY: reply_interposed_year
-- Messages posted between a message and its reply. Unlike seconds, this doesn't depend on how busy the room is.
WITH seq AS (
    SELECT
        id,
        timestamp,
        reply_to_id,
        row_number() OVER (ORDER BY timestamp, id) AS seq_no
    FROM human_messages
    WHERE is_conversational
),
pairs AS (
    SELECT
        EXTRACT(YEAR FROM r.timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        (r.seq_no - p.seq_no - 1) AS messages_interposed
    FROM seq r
    JOIN seq p ON p.id = r.reply_to_id
    WHERE r.seq_no > p.seq_no
)
SELECT
    year,
    count(*) AS reply_pairs,
    percentile_cont(0.25) WITHIN GROUP (ORDER BY messages_interposed) AS p25_interposed,
    percentile_cont(0.50) WITHIN GROUP (ORDER BY messages_interposed) AS median_interposed,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY messages_interposed) AS p75_interposed,
    avg((messages_interposed = 0)::int)  AS share_replied_immediately,
    avg((messages_interposed <= 5)::int) AS share_within_5_messages
FROM pairs
GROUP BY year
ORDER BY year;

-- QUERY: weekend_premium_quarter
-- Weekend vs weekday messages per day, by quarter.
WITH tagged AS (
    SELECT
        EXTRACT(YEAR    FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS year,
        EXTRACT(QUARTER FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS quarter,
        (timestamp AT TIME ZONE 'Europe/Bucharest')::date AS day,
        EXTRACT(DOW FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int IN (0, 6) AS is_weekend
    FROM human_messages
    WHERE is_conversational
)
SELECT
    year,
    quarter,
    year + (quarter - 1) / 4.0 AS time_index,
    count(*) AS messages,
    count(DISTINCT day) AS days_observed,
    count(*)::float / count(DISTINCT day) AS messages_per_day,
    (count(*) FILTER (WHERE is_weekend))::float
        / NULLIF(count(DISTINCT day) FILTER (WHERE is_weekend), 0) AS weekend_msgs_per_day,
    (count(*) FILTER (WHERE NOT is_weekend))::float
        / NULLIF(count(DISTINCT day) FILTER (WHERE NOT is_weekend), 0) AS weekday_msgs_per_day,
    ((count(*) FILTER (WHERE is_weekend))::float
        / NULLIF(count(DISTINCT day) FILTER (WHERE is_weekend), 0))
    / NULLIF((count(*) FILTER (WHERE NOT is_weekend))::float
        / NULLIF(count(DISTINCT day) FILTER (WHERE NOT is_weekend), 0), 0) AS weekend_premium
FROM tagged
GROUP BY year, quarter
HAVING count(DISTINCT day) >= 80    -- drop ramp-up/partial quarters
ORDER BY year, quarter;

-- QUERY: reply_share_year
-- Share of messages sent as explicit replies.
SELECT
    EXTRACT(YEAR FROM timestamp)::int AS year,
    count(*) AS total_messages,
    count(*) FILTER (WHERE reply_to_id IS NOT NULL) AS reply_messages,
    count(*) FILTER (WHERE reply_to_id IS NOT NULL)::float / count(*) AS reply_share
FROM human_messages
WHERE is_conversational
GROUP BY year
ORDER BY year;

-- QUERY: hour_by_month
-- Median posting hour by calendar month.
SELECT
    EXTRACT(MONTH FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int AS month,
    count(*) AS messages,
    (percentile_cont(0.5) WITHIN GROUP (
        ORDER BY (EXTRACT(HOUR FROM timestamp AT TIME ZONE 'Europe/Bucharest')::int - 7 + 24) % 24
     ) + 7)::numeric % 24 AS median_hour_local
FROM human_messages
WHERE is_conversational
  AND EXTRACT(YEAR FROM timestamp)::int BETWEEN 2021 AND 2025   -- full years only
GROUP BY month
ORDER BY month;

-- QUERY: reply_share_month
-- Reply share by month.
SELECT
    to_char(timestamp, 'YYYY-MM') AS month,
    count(*) AS total_messages,
    count(*) FILTER (WHERE reply_to_id IS NOT NULL) AS reply_messages,
    count(*) FILTER (WHERE reply_to_id IS NOT NULL)::float / count(*) AS reply_share
FROM human_messages
WHERE is_conversational
GROUP BY month
HAVING count(*) >= 500
ORDER BY month;

-- QUERY: member_year_replies
-- Messages and replies per member per year.
SELECT
    EXTRACT(YEAR FROM timestamp)::int AS year,
    pseudonym,
    count(*) AS messages,
    count(*) FILTER (WHERE reply_to_id IS NOT NULL) AS replies
FROM human_messages
WHERE is_conversational
GROUP BY year, pseudonym
ORDER BY year, pseudonym;
