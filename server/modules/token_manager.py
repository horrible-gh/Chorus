from typing import List, Optional

from fastapi import HTTPException

from modules.chat_manager import STORE, now_iso


def _mask(value: str) -> str:
    prefix = value[:4] if len(value) >= 4 else value
    return prefix + "****"


def create_token(data: dict) -> dict:
    with STORE.transaction():
        token_id = STORE.next_id("tok")
        created_at = now_iso()
        token = {
            "token_id": token_id,
            "status": data.get("status", "active"),
            "created_at": created_at,
            "updated_at": created_at,
            **data,
        }
        result = STORE.insert_token(token)
    result["token_value"] = _mask(result["token_value"])
    return result


def list_tokens(owner_user_id: Optional[str] = None) -> List[dict]:
    tokens = STORE.list_tokens(owner_user_id=owner_user_id)
    for t in tokens:
        t["token_value"] = _mask(t["token_value"])
    return tokens


def _get_raw(token_id: str) -> dict:
    token = STORE.get_token(token_id)
    if not token:
        raise HTTPException(status_code=404, detail="TOKEN_NOT_FOUND")
    return token


def update_token(token_id: str, updates: dict) -> dict:
    with STORE.transaction():
        _get_raw(token_id)
        clean = {k: v for k, v in updates.items() if v is not None}
        clean["updated_at"] = now_iso()
        token = STORE.update_token(token_id, clean)
        if not token:
            raise HTTPException(status_code=404, detail="TOKEN_NOT_FOUND")
    token["token_value"] = _mask(token["token_value"])
    return token
