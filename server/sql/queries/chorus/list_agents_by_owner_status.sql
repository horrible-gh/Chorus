SELECT * FROM agent_presets
WHERE (owner_user_id = %s OR owner_user_id = 'system')
  AND status = %s
ORDER BY owner_user_id, display_name
