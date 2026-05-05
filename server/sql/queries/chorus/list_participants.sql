SELECT * FROM chat_participants
WHERE room_id = %s
ORDER BY joined_at, participant_id
