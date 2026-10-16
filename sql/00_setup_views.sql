-- Step 0: the analysis-ready view. Run by scripts/setup_db.py after scripts/build_pseudonyms.py.
-- Bots are excluded by the join to pseudonyms (only humans have one); Discord system rows
-- are kept but flagged with is_conversational = false.

DROP MATERIALIZED VIEW IF EXISTS human_messages;
CREATE MATERIALIZED VIEW human_messages AS
SELECT
    m.id,
    m.type,
    (m.type IN ('Default', 'Reply')) AS is_conversational,
    m.author_id,                -- internal joins only, never exported
    p.pseudonym,
    p.is_included_member,
    m.content,
    m.timestamp,
    m.timestamp_edited,
    m.is_pinned,
    m.reply_to_id,
    m.forwarded_message_id,
    m.mentions AS mentions_raw, -- internal joins only, never exported
    mp.mentions_pseudo          -- safe to export: pseudonyms only, no ids/text
FROM messages m
JOIN pseudonyms p ON p.author_id = m.author_id
LEFT JOIN LATERAL (
    SELECT jsonb_agg(COALESCE(mp2.pseudonym, 'unmapped_mention')) AS mentions_pseudo
    FROM jsonb_array_elements(COALESCE(m.mentions, '[]'::jsonb)) elem
    LEFT JOIN pseudonyms mp2 ON mp2.author_id = (elem->>'id')::bigint
) mp ON true;

CREATE UNIQUE INDEX idx_human_messages_id ON human_messages (id);
CREATE INDEX idx_human_messages_pseudonym ON human_messages (pseudonym);
CREATE INDEX idx_human_messages_timestamp ON human_messages (timestamp);
CREATE INDEX idx_human_messages_reply_to ON human_messages (reply_to_id)
    WHERE reply_to_id IS NOT NULL;
