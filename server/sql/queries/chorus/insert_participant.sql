INSERT INTO chat_participants (
    participant_id, room_id, participant_type, user_id, agent_id,
    display_name, status, joined_at, left_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
