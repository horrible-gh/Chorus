SELECT * FROM messages
WHERE room_id = %s
ORDER BY created_at, message_id
