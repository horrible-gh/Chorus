SELECT * FROM chat_participants
WHERE room_id = %s AND status = 'active'
ORDER BY joined_at, participant_id
