SELECT * FROM worker_leases
WHERE task_id = %s AND status = 'active'
ORDER BY expires_at DESC, lease_id
