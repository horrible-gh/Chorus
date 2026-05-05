INSERT INTO uploaded_files (
    file_id, owner_user_id, original_name, stored_path,
    size_bytes, mime_type, status, expires_at, created_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
