INSERT INTO worker_runs (
    run_id, task_id, lease_id, worker_id, runner, model, grade, attempt,
    result_status, summary, artifact_paths_json, log_path, failure_code,
    failure_text, started_at, finished_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
