SELECT * FROM chat_rooms
WHERE owner_user_id = %s
  AND status != 'deleted'
ORDER BY updated_at DESC, created_at DESC
