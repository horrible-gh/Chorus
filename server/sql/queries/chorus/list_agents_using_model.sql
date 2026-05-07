SELECT agent_id, display_name FROM agent_presets
WHERE default_runner = %s AND default_model = %s AND status = 'active'
