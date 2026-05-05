SELECT * FROM message_recipients
WHERE message_id = %s
ORDER BY created_at, message_recipient_id
