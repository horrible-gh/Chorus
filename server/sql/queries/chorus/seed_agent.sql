INSERT OR IGNORE INTO agent_presets (
    agent_id, owner_user_id, display_name, role_name, description,
    default_runner, default_model, default_grade, system_prompt,
    pinned_context, settings_json, status, created_at, updated_at
) VALUES (%s, 'system', %s, %s, %s, 'copilot', %s, %s, '', NULL, %s, 'active', %s, %s)
