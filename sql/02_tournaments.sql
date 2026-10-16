-- Step 2: does the community still respond to football tournaments?
-- Each window is compared with the 28 days before it, and with the same dates in 2023 and 2025.

-- QUERY: daily_volume
-- Messages and distinct posters per day.
SELECT
    timestamp::date AS day,
    count(*) AS messages,
    count(DISTINCT pseudonym) AS distinct_members
FROM human_messages
WHERE is_conversational
GROUP BY day
ORDER BY day;

-- QUERY: event_windows
-- Tournament windows and their matched controls.
SELECT * FROM (VALUES
    ('Euro 2020',        'tournament', 2021, DATE '2021-06-11', DATE '2021-07-11'),
    ('World Cup 2022',    'tournament', 2022, DATE '2022-11-20', DATE '2022-12-18'),
    ('Euro 2024',         'tournament', 2024, DATE '2024-06-14', DATE '2024-07-14'),
    ('World Cup 2026',    'tournament', 2026, DATE '2026-06-11', DATE '2026-07-19'),
    ('Euro 2020 dates, 2023', 'control', 2023, DATE '2023-06-11', DATE '2023-07-11'),
    ('Euro 2024 dates, 2023', 'control', 2023, DATE '2023-06-14', DATE '2023-07-14'),
    ('World Cup 2026 dates, 2023', 'control', 2023, DATE '2023-06-11', DATE '2023-07-19'),
    ('Euro 2020 dates, 2025', 'control', 2025, DATE '2025-06-11', DATE '2025-07-11'),
    ('Euro 2024 dates, 2025', 'control', 2025, DATE '2025-06-14', DATE '2025-07-14'),
    ('World Cup 2026 dates, 2025', 'control', 2025, DATE '2025-06-11', DATE '2025-07-19'),
    ('World Cup 2022 dates, 2023', 'control',    2023, DATE '2023-11-20', DATE '2023-12-18'),
    ('World Cup 2022 dates, 2025', 'control',    2025, DATE '2025-11-20', DATE '2025-12-18')
) AS t(event, kind, year, start_date, end_date);

-- QUERY: event_metrics
-- Baseline (28 days before) vs during, for every window. Days with no messages count as zero.
WITH events AS (
    SELECT * FROM (VALUES
        ('Euro 2020',        'tournament', 2021, DATE '2021-06-11', DATE '2021-07-11'),
        ('World Cup 2022',    'tournament', 2022, DATE '2022-11-20', DATE '2022-12-18'),
        ('Euro 2024',         'tournament', 2024, DATE '2024-06-14', DATE '2024-07-14'),
        ('World Cup 2026',    'tournament', 2026, DATE '2026-06-11', DATE '2026-07-19'),
        ('Euro 2020 dates, 2023', 'control', 2023, DATE '2023-06-11', DATE '2023-07-11'),
        ('Euro 2024 dates, 2023', 'control', 2023, DATE '2023-06-14', DATE '2023-07-14'),
        ('World Cup 2026 dates, 2023', 'control', 2023, DATE '2023-06-11', DATE '2023-07-19'),
        ('Euro 2020 dates, 2025', 'control', 2025, DATE '2025-06-11', DATE '2025-07-11'),
        ('Euro 2024 dates, 2025', 'control', 2025, DATE '2025-06-14', DATE '2025-07-14'),
        ('World Cup 2026 dates, 2025', 'control', 2025, DATE '2025-06-11', DATE '2025-07-19'),
        ('World Cup 2022 dates, 2023', 'control',    2023, DATE '2023-11-20', DATE '2023-12-18'),
        ('World Cup 2022 dates, 2025', 'control',    2025, DATE '2025-11-20', DATE '2025-12-18')
    ) AS t(event, kind, year, start_date, end_date)
),
daily AS (
    SELECT timestamp::date AS day, count(*) AS messages,
           count(DISTINCT pseudonym) AS members
    FROM human_messages WHERE is_conversational GROUP BY day
),
during_days AS (
    SELECT e.event, g::date AS day
    FROM events e, generate_series(e.start_date, e.end_date, INTERVAL '1 day') g
),
baseline_days AS (
    SELECT e.event, g::date AS day
    FROM events e, generate_series(e.start_date - 28, e.start_date - 1, INTERVAL '1 day') g
),
during AS (
    SELECT d.event,
           count(*) AS days_during,
           avg(COALESCE(dv.messages, 0)) AS during_mean_per_day,
           max(COALESCE(dv.messages, 0)) AS during_peak_per_day,
           avg(COALESCE(dv.members, 0))  AS during_mean_members_per_day
    FROM during_days d LEFT JOIN daily dv ON dv.day = d.day
    GROUP BY d.event
),
during_distinct AS (
    SELECT d.event, count(DISTINCT h.pseudonym) AS during_distinct_members
    FROM during_days d
    JOIN human_messages h ON h.timestamp::date = d.day AND h.is_conversational
    GROUP BY d.event
),
during_distinct_28d AS (
    SELECT e.event, count(DISTINCT h.pseudonym) AS during_distinct_members_28d
    FROM events e
    JOIN human_messages h
      ON h.timestamp::date BETWEEN e.start_date AND e.start_date + 27
     AND h.is_conversational
    GROUP BY e.event
),
baseline AS (
    SELECT b.event,
           avg(COALESCE(dv.messages, 0)) AS baseline_mean_per_day,
           avg(COALESCE(dv.members, 0))  AS baseline_mean_members_per_day
    FROM baseline_days b LEFT JOIN daily dv ON dv.day = b.day
    GROUP BY b.event
),
baseline_distinct AS (
    SELECT b.event, count(DISTINCT h.pseudonym) AS baseline_distinct_members
    FROM baseline_days b
    JOIN human_messages h ON h.timestamp::date = b.day AND h.is_conversational
    GROUP BY b.event
)
SELECT
    e.event, e.kind, e.year, e.start_date, e.end_date,
    d.days_during,
    b.baseline_mean_per_day,
    d.during_mean_per_day,
    d.during_peak_per_day,
    d.during_mean_per_day / NULLIF(b.baseline_mean_per_day, 0) AS volume_multiplier,
    d.during_mean_per_day - b.baseline_mean_per_day            AS volume_lift_per_day,
    d.during_peak_per_day / NULLIF(b.baseline_mean_per_day, 0) AS peak_multiplier,
    b.baseline_mean_members_per_day,
    d.during_mean_members_per_day,
    d.during_mean_members_per_day / NULLIF(b.baseline_mean_members_per_day, 0)
        AS members_per_day_multiplier,
    bd.baseline_distinct_members,          -- 28 days
    d28.during_distinct_members_28d,       -- first 28 days, comparable with the baseline
    dd.during_distinct_members             -- full window, length-biased
FROM events e
JOIN during d           ON d.event  = e.event
JOIN baseline b         ON b.event  = e.event
LEFT JOIN during_distinct dd      ON dd.event  = e.event
LEFT JOIN during_distinct_28d d28 ON d28.event = e.event
LEFT JOIN baseline_distinct bd    ON bd.event  = e.event
ORDER BY e.start_date;

-- QUERY: event_time_series
-- Daily volume aligned on each window's first day.
WITH events AS (
    SELECT * FROM (VALUES
        ('Euro 2020',        'tournament', DATE '2021-06-11', DATE '2021-07-11'),
        ('World Cup 2022',    'tournament', DATE '2022-11-20', DATE '2022-12-18'),
        ('Euro 2024',         'tournament', DATE '2024-06-14', DATE '2024-07-14'),
        ('World Cup 2026',    'tournament', DATE '2026-06-11', DATE '2026-07-19'),
        ('Euro 2020 dates, 2023', 'control', DATE '2023-06-11', DATE '2023-07-11'),
        ('Euro 2024 dates, 2023', 'control', DATE '2023-06-14', DATE '2023-07-14'),
        ('World Cup 2026 dates, 2023', 'control', DATE '2023-06-11', DATE '2023-07-19'),
        ('Euro 2020 dates, 2025', 'control', DATE '2025-06-11', DATE '2025-07-11'),
        ('Euro 2024 dates, 2025', 'control', DATE '2025-06-14', DATE '2025-07-14'),
        ('World Cup 2026 dates, 2025', 'control', DATE '2025-06-11', DATE '2025-07-19'),
        ('World Cup 2022 dates, 2023', 'control',    DATE '2023-11-20', DATE '2023-12-18'),
        ('World Cup 2022 dates, 2025', 'control',    DATE '2025-11-20', DATE '2025-12-18')
    ) AS t(event, kind, start_date, end_date)
),
daily AS (
    SELECT timestamp::date AS day, count(*) AS messages
    FROM human_messages WHERE is_conversational GROUP BY day
),
baseline AS (
    SELECT e.event,
           avg(COALESCE(dv.messages, 0)) AS baseline_mean_per_day
    FROM events e
    CROSS JOIN LATERAL generate_series(e.start_date - 28, e.start_date - 1, INTERVAL '1 day') g
    LEFT JOIN daily dv ON dv.day = g::date
    GROUP BY e.event
)
SELECT
    e.event,
    e.kind,
    (g::date - e.start_date) AS day_offset,
    (e.end_date - e.start_date) AS event_length_days,
    g::date AS day,
    COALESCE(dv.messages, 0) AS messages,
    COALESCE(dv.messages, 0) / NULLIF(b.baseline_mean_per_day, 0) AS normalised_to_baseline
FROM events e
JOIN baseline b ON b.event = e.event
CROSS JOIN LATERAL generate_series(e.start_date - 28, e.start_date + 42, INTERVAL '1 day') g
LEFT JOIN daily dv ON dv.day = g::date
ORDER BY e.event, day_offset;

-- QUERY: member_event_activity
-- Each member's messages during each tournament and in the 28 days before it.
WITH events AS (
    SELECT * FROM (VALUES
        ('Euro 2020',      DATE '2021-06-11', DATE '2021-07-11'),
        ('World Cup 2022', DATE '2022-11-20', DATE '2022-12-18'),
        ('Euro 2024',      DATE '2024-06-14', DATE '2024-07-14'),
        ('World Cup 2026', DATE '2026-06-11', DATE '2026-07-19')
    ) AS t(event, start_date, end_date)
)
SELECT
    e.event,
    h.pseudonym,
    count(*) FILTER (WHERE h.timestamp::date BETWEEN e.start_date AND e.end_date) AS window_messages,
    (e.end_date - e.start_date + 1) AS window_days,
    count(*) FILTER (WHERE h.timestamp::date BETWEEN e.start_date - 28 AND e.start_date - 1) AS baseline_messages,
    28 AS baseline_days
FROM events e
JOIN human_messages h ON h.timestamp::date BETWEEN e.start_date - 28 AND e.end_date
WHERE h.is_conversational
GROUP BY e.event, h.pseudonym, e.start_date, e.end_date
ORDER BY e.event, h.pseudonym;
