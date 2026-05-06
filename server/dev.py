import os
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Fix static/ relative path to be resolved relative to reward_tool_plus/
os.chdir(BASE_DIR)
sys.path.insert(0, BASE_DIR)

from routers.main import app

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8018)
    