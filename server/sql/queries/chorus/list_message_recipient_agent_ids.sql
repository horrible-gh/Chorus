SELECT recipient_agent_id FROM message_recipients
WHERE message_id = %s AND recipient_agent_id IS NOT NULL
ORDER BY created_at, message_recipient_id
