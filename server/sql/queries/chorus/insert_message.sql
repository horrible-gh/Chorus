INSERT INTO messages (
    message_id, room_id, sender_type, sender_user_id, sender_agent_id,
    visibility, content_type, text, delivery_mode, history_state,
    replaced_by_message_id, source_task_id, token_estimate, created_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
