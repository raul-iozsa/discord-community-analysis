-- Step 5: when did each member's activity fall away for good?
--
-- PRE-REGISTRATION: written before looking at any output. Shortened later;
-- the rule and the prediction are unchanged.
--
-- (1) Rule. For each member: monthly message counts on a complete calendar
--     grid (zero months filled in), a trailing 3-month mean, and the member's
--     peak trailing 3-month mean. Change point = the first month whose
--     trailing mean is below 50% of that peak and never recovers above it.
--     Sensitivity afterwards at 40% and 60%.
-- (2) Excluded: user_20, user_21 and user_26 (two confirmed departures and
--     one dormant member), reported separately.
-- (3) Tournament check: if change points pile up just after a tournament
--     ends (2021-07-11, 2022-12-18, 2024-07-14, 2026-07-19), rule that out
--     before claiming a shared cause.
-- (4) Prediction: Steps 1, 3 and 4 found the room thinning evenly, so change
--     points should CLUSTER rather than spread.

-- QUERY: member_month_activity
-- Messages per member per month on a complete grid (zero months filled in).
WITH months AS (
    SELECT generate_series(
        date_trunc('month', (SELECT min(timestamp) FROM human_messages WHERE is_conversational)),
        date_trunc('month', (SELECT max(timestamp) FROM human_messages WHERE is_conversational)),
        INTERVAL '1 month')::date AS month
),
members AS (
    SELECT DISTINCT pseudonym FROM human_messages
    WHERE is_conversational AND is_included_member
),
pre2023 AS (
    SELECT pseudonym, count(*) AS msgs_before_2023
    FROM human_messages
    WHERE is_conversational AND is_included_member AND timestamp < DATE '2023-01-01'
    GROUP BY pseudonym
),
counts AS (
    SELECT
        date_trunc('month', timestamp)::date AS month,
        pseudonym,
        count(*) AS messages
    FROM human_messages
    WHERE is_conversational AND is_included_member
    GROUP BY month, pseudonym
)
SELECT
    mo.month,
    me.pseudonym,
    COALESCE(c.messages, 0) AS messages,
    (me.pseudonym IN ('user_20', 'user_21', 'user_26')) AS is_known_departure,
    (COALESCE(p.msgs_before_2023, 0) >= 1000
     AND me.pseudonym NOT IN ('user_20', 'user_21', 'user_26')) AS is_analysis_member
FROM months mo
CROSS JOIN members me
LEFT JOIN counts c ON c.month = mo.month AND c.pseudonym = me.pseudonym
LEFT JOIN pre2023 p ON p.pseudonym = me.pseudonym
ORDER BY me.pseudonym, mo.month;

-- QUERY: member_first_last_month
-- Each member's first and last month with a message.
SELECT
    pseudonym,
    date_trunc('month', min(timestamp))::date AS first_month,
    date_trunc('month', max(timestamp))::date AS last_month,
    count(*) AS lifetime_messages
FROM human_messages
WHERE is_conversational AND is_included_member
GROUP BY pseudonym
ORDER BY lifetime_messages DESC;

-- QUERY: server_month_totals
-- Server messages per month.
SELECT
    date_trunc('month', timestamp)::date AS month,
    count(*) AS messages,
    count(DISTINCT pseudonym) AS members_posting,
    count(DISTINCT timestamp::date) AS days_observed,
    count(*)::float / count(DISTINCT timestamp::date) AS messages_per_day
FROM human_messages
WHERE is_conversational
GROUP BY month
ORDER BY month;

-- QUERY: member_month_text
-- Characters per member per month, for the sensitivity check.
SELECT
    pseudonym,
    date_trunc('month', timestamp)::date AS month,
    sum(char_length(coalesce(content, ''))) AS chars,
    sum(char_length(regexp_replace(coalesce(content, ''), 'https?://\S+', '', 'g'))) AS chars_no_urls
FROM human_messages
WHERE is_conversational
GROUP BY pseudonym, month
ORDER BY pseudonym, month;
