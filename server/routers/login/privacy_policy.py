from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from slowapi import Limiter
from slowapi.util import get_remote_address
import os
import LogAssist.log as logger

limiter = Limiter(key_func=get_remote_address)

router = APIRouter()

# 개인정보 처리방침 파일 경로
PRIVACY_POLICY_DIR = "res/privacy_policy"


@router.get("/")
@router.get("")
async def get_privacy_policy(request: Request, lang: str = "en"):
    """
    개인정보 처리방침 조회 API
    - lang: 언어 코드 (en, ko, ja 등)
    - 텍스트 반환
    """
    logger.debug(f"[PrivacyPolicy] 개인정보 처리방침 요청 - lang: {lang}")

    # 언어 코드 검증 (기본값: en)
    allowed_langs = ["en", "ko", "ja", "zh"]
    if lang not in allowed_langs:
        logger.debug(f"[PrivacyPolicy] ⚠️ 지원하지 않는 언어 - lang: {lang}, 기본값(en) 사용")
        lang = "en"

    # 파일 경로 생성
    file_path = os.path.join(PRIVACY_POLICY_DIR, f"privacy_policy_{lang}.txt")

    # 파일 존재 확인
    if not os.path.exists(file_path):
        logger.debug(f"[PrivacyPolicy] ❌ 파일 없음 - {file_path}, 기본값(en) 시도")
        file_path = os.path.join(PRIVACY_POLICY_DIR, "privacy_policy_en.txt")

        if not os.path.exists(file_path):
            logger.error(f"[PrivacyPolicy] ❌ 기본 파일도 없음 - {file_path}")
            raise HTTPException(status_code=404, detail="Privacy policy not found")

    # 텍스트 파일 읽기
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            text_content = f.read()
        logger.debug(f"[PrivacyPolicy] ✅ 파일 읽기 완료 - {file_path}")
        return Response(content=text_content, media_type="text/plain; charset=utf-8", status_code=200)
    except Exception as e:
        logger.error(f"[PrivacyPolicy] ❌ 파일 읽기 실패 - {e}")
        raise HTTPException(status_code=500, detail="Failed to load privacy policy")
