from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from slowapi import Limiter
from slowapi.util import get_remote_address
import os
import LogAssist.log as logger

limiter = Limiter(key_func=get_remote_address)

router = APIRouter()

# Privacy policy file path
PRIVACY_POLICY_DIR = "res/privacy_policy"


@router.get("/")
@router.get("")
async def get_privacy_policy(request: Request, lang: str = "en"):
    """
    Privacy policy retrieval API
    - lang: language code (en, ko, ja, etc.)
    - Returns text content
    """
    logger.debug(f"[PrivacyPolicy] privacy policy request - lang: {lang}")

    # Validate language code (default: en)
    allowed_langs = ["en", "ko", "ja", "zh"]
    if lang not in allowed_langs:
        logger.debug(f"[PrivacyPolicy] ⚠️ unsupported language - lang: {lang}, using default (en)")
        lang = "en"

    # Build file path
    file_path = os.path.join(PRIVACY_POLICY_DIR, f"privacy_policy_{lang}.txt")

    # Check file existence
    if not os.path.exists(file_path):
        logger.debug(f"[PrivacyPolicy] ❌ file not found - {file_path}, trying default (en)")
        file_path = os.path.join(PRIVACY_POLICY_DIR, "privacy_policy_en.txt")

        if not os.path.exists(file_path):
            logger.error(f"[PrivacyPolicy] ❌ default file also missing - {file_path}")
            raise HTTPException(status_code=404, detail="Privacy policy not found")

    # Read text file
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            text_content = f.read()
        logger.debug(f"[PrivacyPolicy] ✅ file read complete - {file_path}")
        return Response(content=text_content, media_type="text/plain; charset=utf-8", status_code=200)
    except Exception as e:
        logger.error(f"[PrivacyPolicy] ❌ file read failed - {e}")
        raise HTTPException(status_code=500, detail="Failed to load privacy policy")
