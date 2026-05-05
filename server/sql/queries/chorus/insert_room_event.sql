INSERT INTO room_events (
    event_id, room_id, event_type, actor_user_id, actor_agent_id,
    payload_json, text, created_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
