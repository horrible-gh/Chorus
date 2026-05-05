INSERT INTO worker_leases (
    lease_id, task_id, job_id, worker_id, status, acquired_at,
    expires_at, released_at, trace_id
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
