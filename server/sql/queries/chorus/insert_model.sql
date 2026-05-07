INSERT INTO model_registry (
    model_id, runner, model_name, grade, is_active, is_default,
    estimated_cost_rank, priority, max_context_tokens,
    provider_options_json, created_at, updated_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
