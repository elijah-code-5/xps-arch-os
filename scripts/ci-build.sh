#!/usr/bin/env bash
# Runs inside an Arch Linux container started by the GitHub workflow (you never run this).
#   /repo = this repository, /work = big scratch disk, results go to /repo/out and /repo/release
set -euo pipefail
cd /repo

warn() { echo "::warning::$*"; }

pacman -Syu --noconfirm archiso git python sudo base-devel cmake ollama p7zip curl

EXTRAS=/work/extras
mkdir -p "$EXTRAS/whisper" "$EXTRAS/ollama" out release

# --- Speech-to-text engine (whisper.cpp), built so it runs on any CPU (no AVX2 requirement) ---
if git clone --depth 1 https://github.com/ggml-org/whisper.cpp /work/whisper.cpp \
   && cmake -S /work/whisper.cpp -B /work/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF \
        -DGGML_F16C=OFF -DGGML_AVX512=OFF -DWHISPER_BUILD_TESTS=OFF \
   && cmake --build /work/whisper.cpp/build -j"$(nproc)" --target whisper-cli; then
    install -m 755 /work/whisper.cpp/build/bin/whisper-cli "$EXTRAS/whisper-cli"
    cp "$EXTRAS/whisper-cli" release/whisper-cli
    echo "whisper-cli built: $(du -h "$EXTRAS/whisper-cli" | cut -f1)"
else
    warn "could not build whisper.cpp; voice typing will be missing from this image"
fi

if curl -fL --retry 3 -o "$EXTRAS/whisper/ggml-base.en.bin" \
     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin \
   && [ "$(stat -c %s "$EXTRAS/whisper/ggml-base.en.bin")" -gt 100000000 ]; then
    echo "speech model downloaded"
else
    rm -f "$EXTRAS/whisper/ggml-base.en.bin"
    warn "could not download the speech model"
fi

# --- Offline AI assistant model (ollama) ------------------------------------------------------
export OLLAMA_MODELS="$EXTRAS/ollama" OLLAMA_HOST=127.0.0.1:11434 HOME=/root
ollama serve >/work/ollama.log 2>&1 &
OLLAMA_PID=$!
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:11434/ >/dev/null && break; sleep 1; done
ollama pull qwen2.5:1.5b || { warn "could not download the assistant model"; tail -5 /work/ollama.log; }
kill "$OLLAMA_PID" 2>/dev/null || true
wait "$OLLAMA_PID" 2>/dev/null || true
du -sh "$EXTRAS"/* 2>/dev/null || true

# --- Build the ISO -----------------------------------------------------------------------------
pacman -Sy --noconfirm
cp -r /usr/share/archiso/configs/releng /work/profile
XPS_EXTRAS="$EXTRAS" bash scripts/apply-overlay.sh /work/profile

mkarchiso -v -w /work/archiso-work -o /repo/out /work/profile
ISO=$(ls /repo/out/*.iso)
SIZE=$(stat -c %s "$ISO")
echo "ISO size: $((SIZE / 1048576)) MiB"

# GitHub releases accept files up to 2 GiB. Bigger images are cut into 1900 MB pieces that
# 7-Zip joins back with one double-click (open the .001 file and press Extract).
if [ "$SIZE" -gt 1992294400 ]; then
    7z a -v1900m -mx0 "/repo/release/$(basename "$ISO" .iso).7z" "$ISO"
else
    cp "$ISO" release/
fi
ls -lh /repo/out /repo/release
