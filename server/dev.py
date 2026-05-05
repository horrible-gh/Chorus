import os
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# static/ 상대경로가 reward_tool_plus/ 기준으로 해석되도록 고정
os.chdir(BASE_DIR)
sys.path.insert(0, BASE_DIR)

from routers.main import app

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8018)
    