INSERT INTO chat_rooms (
    room_id, owner_user_id, title, mode, status, active_history_mode,
    base_summary_message_id, created_at, updated_at, archived_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
