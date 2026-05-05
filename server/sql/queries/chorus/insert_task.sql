INSERT INTO tasks (
    task_id, created_by_user_id, source, title, task_type, priority,
    status, assigned_agent_id, routing_id, assigned_runner, assigned_model,
    assigned_grade, attempt, max_attempts, input_json, constraints_json,
    result_json, failure_code, failure_text, next_run_at, last_progress_at,
    last_progress_message, created_at, updated_at, completed_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
