SELECT * FROM agent_presets
WHERE status = %s
ORDER BY owner_user_id, display_name
