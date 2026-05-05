SELECT * FROM tasks
WHERE status = %s
ORDER BY created_at, task_id
