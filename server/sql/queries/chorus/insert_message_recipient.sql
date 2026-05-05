INSERT INTO message_recipients (
    message_recipient_id, message_id, recipient_type, recipient_user_id,
    recipient_agent_id, created_at
) VALUES (%s, %s, %s, %s, %s, %s)
