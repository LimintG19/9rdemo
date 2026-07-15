#!/usr/bin/env python3
import os
import sys
import time
import hashlib
import subprocess
import tempfile
from datetime import datetime
from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.utils import EntryNotFoundError

# ==================== 环境变量配置 ====================
REPO_ID         = os.environ.get("HF_DATASET_REPO")
TOKEN           = os.environ.get("HF_TOKEN")
DB_PATH         = os.environ.get("DB_PATH", "/app/server/data/freeapi.db")
BACKUP_MODE     = os.environ.get("BACKUP_MODE", "scheduled").lower()
BACKUP_INTERVAL = int(os.environ.get("BACKUP_INTERVAL", "300"))
CHECK_INTERVAL  = int(os.environ.get("REALTIME_CHECK_INTERVAL", "30"))
MIN_INTERVAL    = int(os.environ.get("MIN_BACKUP_INTERVAL", "60"))
KEEP_BACKUPS    = int(os.environ.get("KEEP_BACKUPS", "10"))

DB_FILENAME = os.path.basename(DB_PATH)  # "freeapi.db"

api = HfApi(token=TOKEN) if TOKEN else None


def log(msg: str):
    print(f"[BackupManager] {msg}", flush=True)


def find_db_file():
    """
    探测实际的数据库文件位置。
    """
    candidates = [
        DB_PATH,
        f"/app/server/data/{DB_FILENAME}",
        f"/app/data/{DB_FILENAME}",
        f"/app/server/dist/data/{DB_FILENAME}",
        os.path.join(os.getcwd(), "server", "data", DB_FILENAME),
        os.path.join(os.getcwd(), "data", DB_FILENAME),
        os.path.join(os.getcwd(), DB_FILENAME),
    ]

    for path in candidates:
        if path and os.path.isfile(path):
            log(f"Found database at: {path}")
            return path

    # 目录扫描
    for root_dir in ["/app", "/app/server", os.getcwd()]:
        if os.path.isdir(root_dir):
            for root, dirs, files in os.walk(root_dir):
                if DB_FILENAME in files:
                    path = os.path.join(root, DB_FILENAME)
                    log(f"Found database by scan at: {path}")
                    return path

    return None


def get_file_stat(path: str):
    if not os.path.exists(path):
        return None
    st = os.stat(path)
    return (st.st_size, st.st_mtime)


def create_consistent_snapshot(src: str, dst: str) -> bool:
    """
    使用 sqlite3 .backup 创建一致性快照，避免并发冲突。
    正确语法: .backup <dst> （不需要 to 关键字）
    """
    try:
        result = subprocess.run(
            ["sqlite3", src, f".backup {dst}"],
            capture_output=True, text=True, timeout=30, check=True
        )
        if result.returncode == 0:
            return True
    except FileNotFoundError:
        log("sqlite3 CLI not found, falling back to file copy")
    except Exception as e:
        log(f"sqlite3 .backup warning: {e}, falling back to file copy")

    try:
        import shutil
        shutil.copy2(src, dst)
        return True
    except Exception as e:
        log(f"File copy failed: {e}")
        return False


def restore() -> bool:
    """
    从 Dataset 恢复数据库：
    1. 列出所有历史备份 freeapi.db.YYYYMMDD_HHMMSS
    2. 按时间戳排序，取最新
    3. 下载并重命名为 freeapi.db
    """
    if not REPO_ID or not TOKEN:
        log("HF_DATASET_REPO or HF_TOKEN not set, skip restore")
        return False

    data_dir = os.path.dirname(DB_PATH)
    os.makedirs(data_dir, exist_ok=True)

    try:
        files = api.list_repo_files(repo_id=REPO_ID, repo_type="dataset")
        backups = [f for f in files if f.startswith(f"{DB_FILENAME}.") and len(f) > len(DB_FILENAME)]
        
        if not backups:
            log("No existing backup found in dataset, starting fresh")
            return False

        backups.sort()
        latest_backup = backups[-1]
        log(f"Found latest backup: {latest_backup}")

        # 下载到 data_dir
        downloaded = hf_hub_download(
            repo_id=REPO_ID,
            filename=latest_backup,
            repo_type="dataset",
            local_dir=data_dir,
            token=TOKEN,
            local_dir_use_symlinks=False
        )
        
        # 原子替换为 freeapi.db
        target = os.path.join(data_dir, DB_FILENAME)
        os.replace(downloaded, target)
        log(f"Restored database from {latest_backup} to {target}")
        return True

    except Exception as e:
        log(f"Restore failed: {e}")
        return False


def upload_file(local_path: str, remote_name: str) -> bool:
    if not api or not REPO_ID:
        return False
    try:
        api.upload_file(
            path_or_fileobj=local_path,
            path_in_repo=remote_name,
            repo_id=REPO_ID,
            repo_type="dataset",
            commit_message=f"Backup {remote_name} @ {datetime.now().isoformat()}"
        )
        return True
    except Exception as e:
        log(f"Upload failed for {remote_name}: {e}")
        return False


def cleanup_old_backups():
    """
    清理旧备份：
    - 删除 legacy 主文件 freeapi.db（我们不再使用它）
    - 保留最新的 KEEP_BACKUPS 个历史版本
    """
    if not api or not REPO_ID or KEEP_BACKUPS <= 0:
        return

    try:
        files = api.list_repo_files(repo_id=REPO_ID, repo_type="dataset")
        
        # 删除旧的主文件（如果存在）
        if DB_FILENAME in files:
            try:
                api.delete_file(
                    path_in_repo=DB_FILENAME,
                    repo_id=REPO_ID,
                    repo_type="dataset",
                    commit_message="Remove legacy main db file"
                )
                log(f"Removed legacy main file: {DB_FILENAME}")
            except Exception as e:
                log(f"Failed to remove legacy file: {e}")
        
        # 清理历史版本
        backups = [f for f in files if f.startswith(f"{DB_FILENAME}.") and len(f) > len(DB_FILENAME)]
        backups.sort()

        if len(backups) <= KEEP_BACKUPS:
            return

        to_delete = backups[:-KEEP_BACKUPS]
        for f in to_delete:
            try:
                api.delete_file(
                    path_in_repo=f,
                    repo_id=REPO_ID,
                    repo_type="dataset",
                    commit_message=f"Auto cleanup: remove {f}"
                )
                log(f"Cleaned up old backup: {f}")
            except Exception as e:
                log(f"Failed to delete {f}: {e}")
    except Exception as e:
        log(f"Cleanup scan failed: {e}")


def do_backup() -> bool:
    """
    执行备份：只上传带时间戳的历史版本，不再重复上传 freeapi.db
    """
    actual_db = find_db_file()
    if not actual_db:
        log("Database file not found, skip backup")
        return False

    # 创建一致性快照
    fd, snapshot = tempfile.mkstemp(suffix=".db", prefix="freellmapi_")
    os.close(fd)

    try:
        if not create_consistent_snapshot(actual_db, snapshot):
            return False

        # 生成时间戳文件名，直接上传
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        hist_name = f"{DB_FILENAME}.{ts}"
        
        if upload_file(snapshot, hist_name):
            log(f"Uploaded backup: {hist_name}")
            cleanup_old_backups()
            return True
        return False

    finally:
        try:
            os.unlink(snapshot)
        except Exception:
            pass


def scheduled_daemon():
    log(f"Scheduled mode started (interval: {BACKUP_INTERVAL}s)")
    while True:
        time.sleep(BACKUP_INTERVAL)
        log("Scheduled backup triggered")
        do_backup()


def realtime_daemon():
    log(f"Realtime mode started (check: {CHECK_INTERVAL}s, min interval: {MIN_INTERVAL}s)")
    last_stat = None
    last_backup_time = 0

    while True:
        time.sleep(CHECK_INTERVAL)

        actual_db = find_db_file()
        if not actual_db:
            continue

        curr_stat = get_file_stat(actual_db)
        if curr_stat is None:
            continue

        if last_stat is not None and curr_stat != last_stat:
            now = time.time()
            if now - last_backup_time >= MIN_INTERVAL:
                log("Database change detected, triggering backup...")
                if do_backup():
                    last_backup_time = now
            else:
                log("Change detected but within min interval, skipped")

        last_stat = curr_stat


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "daemon"

    if cmd == "restore":
        restore()
    elif cmd == "backup":
        do_backup()
    elif cmd == "daemon":
        if BACKUP_MODE == "realtime":
            realtime_daemon()
        else:
            scheduled_daemon()
    else:
        log(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()