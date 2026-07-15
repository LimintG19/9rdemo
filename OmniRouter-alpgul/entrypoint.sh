#!/bin/bash

# --- KATİ KURALLAR (Strict Mode) ---
set -euo pipefail

# ======================= Yapılandırma =======================
export DB_DIR="/app/data"
export REPO_ID="${REPO_ID:-alpgul/omniroute-storage}"
export HF_HOME="/tmp/.cache/huggingface"

# SQLite Üçlüsü: Ana dosya + Paylaşılan Bellek + Yazma Günlüğü
FILES=("storage.sqlite" "storage.sqlite-shm" "storage.sqlite-wal")
# ===========================================================

echo "[$(date +'%T')] --- OmniRoute /app/data Üçlü Yedekleme ---"

# 1. Dizin Kontrolü
mkdir -p "$DB_DIR"

# 2. HF Login Denetimi
if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "[HATA] HF_TOKEN eksik! Settings > Secrets kısmından ekleyin."
    exit 1
fi

echo "[Auth] Giriş yapılıyor..."
hf auth login --token "$HF_TOKEN" &> /dev/null

# 3. Restore (3 Dosyayı da Hub'dan İndir)
echo "[Restore] Hub'dan dosyalar kontrol ediliyor..."
for FILE in "${FILES[@]}"; do
    python3 -c "
from huggingface_hub import hf_hub_download
try:
    hf_hub_download(repo_id='$REPO_ID', filename='$FILE', repo_type='dataset', local_dir='$DB_DIR')
    print('√ $FILE yüklendi.')
except:
    pass
" || true
done

# 4. Arka Plan Senkronizasyonu (Test için 5 Saniye)
(
    LAST_COMBINED_HASH=""

    while true; do
        sleep 60
        CURRENT_COMBINED_HASH=""
        
        # Dosyaların durumunu kontrol et ve birleşik hash oluştur
        for FILE in "${FILES[@]}"; do
            FILE_PATH="${DB_DIR}/${FILE}"
            if [[ -f "$FILE_PATH" ]]; then
                FILE_HASH=$(md5sum "$FILE_PATH" | cut -d' ' -f1)
                CURRENT_COMBINED_HASH+="${FILE_HASH}"
            fi
        done

        # Değişiklik varsa toplu yükleme yap
        if [[ -n "$CURRENT_COMBINED_HASH" && "$CURRENT_COMBINED_HASH" != "$LAST_COMBINED_HASH" ]]; then
            echo "[Sync] Veri değişikliği algılandı, Hub güncelleniyor..."
            
            for FILE in "${FILES[@]}"; do
                FILE_PATH="${DB_DIR}/${FILE}"
                if [[ -f "$FILE_PATH" ]]; then
                    # Hata mesajlarını görmek için 2>/dev/null'u kaldırdık
                    python3 -c "from huggingface_hub import HfApi; HfApi().upload_file(path_or_fileobj='$FILE_PATH', path_in_repo='$FILE', repo_id='$REPO_ID', repo_type='dataset', commit_message='WAL Sync: $FILE')" || echo "! $FILE yüklenemedi."
                fi
            done
            
            LAST_COMBINED_HASH="$CURRENT_COMBINED_HASH"
            echo "[Sync] Başarılı: $(date +'%T')"
        fi
    done
) &

# 5. Uygulamayı Başlat
echo "[System] OmniRoute başlatılıyor (/app/data)..."
# İmajın kendi yapılandırmasına güveniyoruz, DATABASE_URL'i ezmiyoruz.
exec node server.js