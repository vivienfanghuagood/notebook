#!/bin/bash
# Spaces-aware ComfyUI launcher for the DO MI300x cluster.
#
# The original workshop script downloaded a "radeon-tunnel" client from a server
# on the old cluster (http://36.150.116.206:20080) to expose ComfyUI on a public
# node port. That server does not exist here. On this cluster the manager already
# publishes each instance's ports through its built-in reverse proxy at
#   <PUBLIC_BASE_URL>/spaces/<instance_id>/8188/
# and injects that URL into the pod as COMFY_PUBLIC_URL. We just start ComfyUI on
# 8188 and print that URL, keeping the notebook's "GREEN Public URL" contract.
set -e

export PATH=/opt/venv/bin:/opt/rocm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export COMFY_PORT=${COMFY_PORT:-8188}
COMFY_DIR=${COMFY_DIR:-/comfyui_workspace/ComfyUI}
COMFY_READY_TIMEOUT=${COMFY_READY_TIMEOUT:-120}

pkill -f "main.py --listen 0.0.0.0 --port ${COMFY_PORT}" || true

echo "[start] launching ComfyUI on 0.0.0.0:${COMFY_PORT}"
cd "$COMFY_DIR"
unset DEFAULT_WORKFLOW
nohup python3 main.py --listen 0.0.0.0 --port "${COMFY_PORT}" > /tmp/comfyui.log 2>&1 &
COMFY_PID=$!
echo $COMFY_PID > /tmp/comfyui.pid

echo "[start] waiting for ComfyUI to become ready..."
for i in $(seq 1 "$COMFY_READY_TIMEOUT"); do
  sleep 1
  if curl -fsS -o /dev/null "http://127.0.0.1:${COMFY_PORT}/" 2>/dev/null; then
    break
  fi
done

# COMFY_PUBLIC_URL is injected by the manager; fall back to ONECLICK_APP_URL.
PUBLIC_URL="${COMFY_PUBLIC_URL:-${ONECLICK_APP_URL:-}}"
echo ""
echo "========================================"
if [ -n "$PUBLIC_URL" ]; then
  echo "GREEN Public URL: $PUBLIC_URL"
else
  echo "[warn] Public URL env not set; open this instance's App URL (port 8188) from the Radeon Cloud console."
fi
echo "========================================"
echo "[start] ComfyUI PID: $COMFY_PID  |  logs: /tmp/comfyui.log"

wait $COMFY_PID
