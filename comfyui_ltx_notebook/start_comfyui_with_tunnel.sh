#!/bin/bash
set -e

# SCRIPT_VERSION="2026-07-07-v6"

export PATH=/opt/venv/bin:/opt/rocm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export COMFY_PORT=${COMFY_PORT:-8188}
# Max seconds to wait for trycloudflare URL to appear in logs.
export TUNNEL_URL_TIMEOUT=${TUNNEL_URL_TIMEOUT:-90}
# 1 = fail fast if URL is not obtained; 0 = continue with local ComfyUI only.
export TUNNEL_REQUIRED=${TUNNEL_REQUIRED:-1}
# Fixed grace wait after URL appears (user-visible delay suggestion).
export PUBLIC_URL_GRACE_SECONDS=${PUBLIC_URL_GRACE_SECONDS:-10}

pkill -f 'python3 main.py --listen 0.0.0.0 --port 8188' || true
pkill -f 'cloudflared tunnel' || true

echo "[start] launching ComfyUI on 0.0.0.0:${COMFY_PORT}"
# echo "[start] script version: ${SCRIPT_VERSION}"
cd /comfyui_workspace/ComfyUI
unset DEFAULT_WORKFLOW
nohup python3 main.py --listen 0.0.0.0 --port "${COMFY_PORT}" > /tmp/comfyui.log 2>&1 &
COMFY_PID=$!
echo "$COMFY_PID" > /tmp/comfyui.pid
sleep 3

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "[error] cloudflared not found in PATH"
  kill "$COMFY_PID" >/dev/null 2>&1 || true
  exit 1
fi

echo "[start] launching Cloudflare Tunnel"
rm -f /tmp/tunnel.log
nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${COMFY_PORT}" > /tmp/tunnel.log 2>&1 &
TUNNEL_PID=$!
echo "$TUNNEL_PID" > /tmp/tunnel.pid

echo "[start] waiting for tunnel to initialize..."
PUBLIC_URL=""
for i in $(seq 1 "$TUNNEL_URL_TIMEOUT"); do
  sleep 1
  PUBLIC_URL=$(tr -d '\r' < /tmp/tunnel.log 2>/dev/null | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' | grep -Eo 'https://[^[:space:]]*trycloudflare\.com[^[:space:]]*' | head -1)
  if [[ "$PUBLIC_URL" =~ ^https://[a-zA-Z0-9.-]+\.trycloudflare\.com$ ]]; then
    break
  fi
  PUBLIC_URL=""
done

if [[ "$PUBLIC_URL" =~ ^https://[a-zA-Z0-9.-]+\.trycloudflare\.com$ ]]; then
  echo ""
  echo "========================================"
  echo "✓ Public URL: $PUBLIC_URL"
  echo "========================================"
  echo "[hint] Cloudflare edge may need a few seconds before first access."
  echo "[hint] Waiting ${PUBLIC_URL_GRACE_SECONDS}s, then you can open the URL."
  sleep "$PUBLIC_URL_GRACE_SECONDS"
  echo "[ready] You can open the public URL now."
else
  echo "[warn] Tunnel started but valid URL not found in ${TUNNEL_URL_TIMEOUT}s."
  echo "[warn] Last tunnel log lines:"
  tail -n 80 /tmp/tunnel.log || true
  if [ "$TUNNEL_REQUIRED" = "1" ]; then
    echo "[error] TUNNEL_REQUIRED=1 and no public URL was obtained. Exiting."
    kill "$TUNNEL_PID" >/dev/null 2>&1 || true
    kill "$COMFY_PID" >/dev/null 2>&1 || true
    exit 2
  else
    echo "[warn] Continuing because TUNNEL_REQUIRED=${TUNNEL_REQUIRED}."
  fi
fi

echo "[start] ComfyUI is running on http://127.0.0.1:${COMFY_PORT}"
echo "[start] Tunnel PID: $TUNNEL_PID"
echo "[start] ComfyUI PID: $COMFY_PID"
echo "[start] Logs: /tmp/comfyui.log (ComfyUI), /tmp/tunnel.log (Tunnel)"

wait "$COMFY_PID"
