SELECT * FROM (
    SELECT * FROM messages
    WHERE room_id = %s AND message_id != %s AND history_state != 'excluded'
    ORDER BY created_at DESC, message_id DESC
    LIMIT %s
) ORDER BY created_at ASC, message_id ASC
