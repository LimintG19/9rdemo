#!/bin/bash
set -e
export REPO_ID="KarlPierson50/mcp-settings"
# ---------- 1. Environment ----------

DB_PATH="./data/webui.db"
SUM_NEW="./data/webui.db.sha256.new"
SUM_OLD="./data/webui.db.sha256"

mkdir -p ./data

# ---------- 2. Python dependency ----------
PYTHON_CMD="python3"
if ! command -v "$PYTHON_CMD" >/dev/null; then
    echo "Python not found – please install python3 on the system."
    exit 1
fi

# ---------- 3. Initial restore from Hugging Face ----------
restore_from_hf() {
    echo "Downloading webui.db from Hugging Face..."
    "$PYTHON_CMD" - <<'PY'
import os, sys
from huggingface_hub import HfApi
api = HfApi(token=os.getenv("HF_TOKEN"))
repo_id = os.getenv("REPO_ID")
path = "./data/webui.db"
try:
    api.hf_hub_download(repo_id=repo_id, filename="webui.db", repo_type="dataset",
                        local_dir="./data")
    if os.path.exists(path):
        print(f"Restore from HF successful - File found at {path}")
    else:
        print(f"Download completed but file not found at {path}")
        sys.exit(1)
except Exception as e:
    print(f"Download from HF failed: {e}")
    sys.exit(1)
PY
}

if [ -n "${HF_TOKEN:-}" ]; then
    if [ ! -f "$DB_PATH" ]; then
        restore_from_hf || echo "No existing file – a new one will be created later."
    fi
else
    echo "HF_TOKEN not set – skipping restore."
fi

# ---------- 4. SHA256 checksum ----------
generate_sum() { sha256sum "$1" > "$2"; }

# ---------- 5. Synchronization loop ----------
sync_loop() {
    while true; do
        echo "=== $(date '+%Y-%m-%d %H:%M:%S') – Starting sync ==="

        if [ -f "$DB_PATH" ]; then
            generate_sum "$DB_PATH" "$SUM_NEW"

            if [ ! -f "$SUM_OLD" ] || ! cmp -s "$SUM_NEW" "$SUM_OLD"; then
                echo "File changed → uploading to Hugging Face..."
                mv "$SUM_NEW" "$SUM_OLD"

                # ---- Upload via Python ----
                "$PYTHON_CMD" - <<'PY'
import os, sys, datetime
from huggingface_hub import HfApi
api = HfApi(token=os.getenv("HF_TOKEN"))
repo_id = os.getenv("REPO_ID")
db_path = "./data/webui.db"

try:
    api.upload_file(
        path_or_fileobj=db_path,
        path_in_repo="webui.db",
        repo_id=repo_id,
        repo_type="dataset",
        commit_message=f"Auto sync @ {datetime.datetime.utcnow().isoformat()} UTC"
    )
    print("Upload to HF successful")
except Exception as e:
    print(f"HF upload error: {e}")
PY

                # ---- Daily dated backup (00:00) ----
                HOUR=$(date +%H)
                if [ "$HOUR" = "00" ]; then
                    YEST=$(date -d "yesterday" '+%Y%m%d')
                    DAILY="webui_${YEST}.db"
                    echo "Daily backup → $DAILY"
                    "$PYTHON_CMD" - <<'PY'
import os, datetime
from huggingface_hub import HfApi
api = HfApi(token=os.getenv("HF_TOKEN"))
repo_id = os.getenv("REPO_ID")
src = "./data/webui.db"
dst = f"webui_{(datetime.date.today()-datetime.timedelta(days=1)):%Y%m%d}.db"
api.upload_file(
    path_or_fileobj=src,
    path_in_repo=dst,
    repo_id=repo_id,
    repo_type="dataset",
    commit_message=f"Daily backup {dst}"
)
print(f"Daily backup uploaded: {dst}")
PY
                fi
            else
                echo "No changes detected – skipping."
                rm -f "$SUM_NEW"
            fi
        else
            echo "webui.db not found – sync skipped."
        fi

        echo "Next check: $(date -d '+5 minutes' '+%Y-%m-%d %H:%M:%S')"
        sleep 300
    done
}

# ---------- 6. Run in background ----------
sync_loop &
echo "Sync running in background (PID: $!)"