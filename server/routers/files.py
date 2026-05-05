from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from modules.chat_manager import SERVER_DIR, STORE, now_iso

router = APIRouter()

UPLOAD_DIR = SERVER_DIR / "uploads"


@router.post("/upload")
async def upload_file(
    file: UploadFile = File(...),
    owner_user_id: str = Form(...),
):
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    file_id = STORE.next_id("ufile")
    extension = Path(file.filename or "").suffix
    stored_name = f"{file_id}{extension}"
    stored_path = UPLOAD_DIR / stored_name

    content = await file.read()
    stored_path.write_bytes(content)

    record = STORE.insert_uploaded_file(
        {
            "file_id": file_id,
            "owner_user_id": owner_user_id,
            "original_name": file.filename or stored_name,
            "stored_path": str(stored_path),
            "size_bytes": len(content),
            "mime_type": file.content_type,
            "status": "active",
            "expires_at": None,
            "created_at": now_iso(),
        }
    )
    return {
        "ok": True,
        "file_id": record["file_id"],
        "stored_path": record["stored_path"],
        "size_bytes": record["size_bytes"],
        "expires_at": record["expires_at"],
    }


@router.get("/{file_id}")
async def get_file_info(file_id: str):
    record = STORE.get_uploaded_file(file_id)
    if not record or record["status"] == "deleted":
        raise HTTPException(status_code=404, detail="FILE_NOT_FOUND")
    return {"ok": True, "file": record}


@router.delete("/{file_id}")
async def delete_file(file_id: str):
    record = STORE.get_uploaded_file(file_id)
    if not record or record["status"] == "deleted":
        raise HTTPException(status_code=404, detail="FILE_NOT_FOUND")
    STORE.update_uploaded_file(file_id, {"status": "deleted"})
    return {"ok": True, "file_id": file_id}
