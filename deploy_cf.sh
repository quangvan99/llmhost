#!/usr/bin/env bash
set -euo pipefail

# ============================================
# cf_quangio.sh
# - Default deploy-dir: ~/cf-quangio
# - Docker-only init (login/create tunnel if needed)
# - Add subdomain mappings via --map host=target
#   * target can be:
#     - PORT (e.g. 8080) -> http://host.docker.internal:8080
#     - HOST:PORT (e.g. 192.168.14.2:8090) -> http://192.168.14.2:8090
#     - FULL URL (e.g. http://192.168.14.2:8090 or https://10.0.0.5:8443) -> kept as-is
# - Auto DNS route + restart tunnel
#
# New:
# - Handles orphan tunnel case (tunnel exists but missing <TUNNEL_ID>.json on this machine)
# - Adds --force-recreate to delete & recreate tunnel automatically
#
# Requirements:
#   - docker
#   - docker compose (plugin)
#
# Examples:
#   ./cf_quangio.sh --map cl.quang.io.vn=8080
#   ./cf_quangio.sh --map api.quang.io.vn=192.168.14.2:8090
#   ./cf_quangio.sh --map ui.quang.io.vn=https://10.0.0.5:8443
#   ./cf_quangio.sh --force-recreate --map cl.quang.io.vn=8080
# ./deploy_cf.sh \
#   --map m4dev.quang.io.vn=http://localhost:5173 \
#   --map m4.quang.io.vn=http://localhost:5174 \
#   --map clm.quang.io.vn=http://localhost:8080 \
#   --map storage.quang.io.vn=http://localhost:8999
# ============================================

# ---------- Defaults ----------
MACHINE_ID="${MACHINE_ID:-$(hostname -s)}"
TUNNEL_NAME="${TUNNEL_NAME:-quangio-${MACHINE_ID}}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/cf-quangio}"
CONTAINER_NAME="${CONTAINER_NAME:-cloudflared-quangio}"

SCHEME="${SCHEME:-http}"
HOST_TARGET="${HOST_TARGET:-host.docker.internal}"

# NEW: run container as the invoking user by default
RUN_UID="${RUN_UID:-$(id -u)}"
RUN_GID="${RUN_GID:-$(id -g)}"

NO_START="false"
NO_DNS="false"
FORCE_RECREATE="false"
# ----------------------------

usage() {
  cat <<EOF
Usage:
  $0 [--deploy-dir DIR] [--tunnel NAME] [--container NAME] [--no-dns] [--no-start] [--force-recreate]
     [--run-uid UID] [--run-gid GID]
     --map host=target [--map host=target ...]

Defaults:
  --deploy-dir       $DEPLOY_DIR
  --tunnel           $TUNNEL_NAME
  --container        $CONTAINER_NAME
  --run-uid          $RUN_UID
  --run-gid          $RUN_GID
  map target default ${SCHEME}://${HOST_TARGET}:<port> if target is just a port
EOF
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }

cf_run() {
  docker run --rm -i \
    -u "${RUN_UID}:${RUN_GID}" \
    -e TUNNEL_ORIGIN_CERT=/etc/cloudflared/cert.pem \
    -e HOME=/etc/cloudflared \
    -v "$DEPLOY_DIR:/etc/cloudflared:rw" \
    cloudflare/cloudflared:latest "$@"
}

cf_run_tty() {
  local tty_flag="-i"
  [ -t 0 ] && tty_flag="-it"
  docker run --rm $tty_flag \
    -u "${RUN_UID}:${RUN_GID}" \
    -e TUNNEL_ORIGIN_CERT=/etc/cloudflared/cert.pem \
    -e HOME=/etc/cloudflared \
    -v "$DEPLOY_DIR:/etc/cloudflared:rw" \
    cloudflare/cloudflared:latest "$@"
}




MAPS=()

# ---------- Arg parse ----------
if [ $# -eq 0 ]; then usage; exit 1; fi

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
    --tunnel) TUNNEL_NAME="$2"; shift 2 ;;
    --container) CONTAINER_NAME="$2"; shift 2 ;;
    --run-uid) RUN_UID="$2"; shift 2 ;;
    --run-gid) RUN_GID="$2"; shift 2 ;;
    --no-dns) NO_DNS="true"; shift ;;
    --no-start) NO_START="true"; shift ;;
    --force-recreate) FORCE_RECREATE="true"; shift ;;
    --map) MAPS+=("$2"); shift 2 ;;
    *)
      echo "Unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

if [ ${#MAPS[@]} -eq 0 ]; then
  echo "ERROR: Provide at least one --map host=target"
  usage
  exit 1
fi

# ---------- Checks ----------
require docker
docker compose version >/dev/null 2>&1 || { echo "Missing: docker compose"; exit 1; }

mkdir -p "$DEPLOY_DIR/cloudflared"

CF_DIR="$DEPLOY_DIR/cloudflared"
CONFIG_FILE="$CF_DIR/config.yml"
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"

echo "==> Tunnel:         $TUNNEL_NAME"
echo "==> Deploy dir:     $DEPLOY_DIR"
echo "==> Config:         $CONFIG_FILE"
echo "==> Container:      $CONTAINER_NAME"
echo "==> Maps:           ${MAPS[*]}"
echo "==> Force recreate: $FORCE_RECREATE"
echo "==> Container user: ${RUN_UID}:${RUN_GID}"
echo

# ---------- 1) Login if needed ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -s "$DEPLOY_DIR/cert.pem" ]; then
  echo "==> cert.pem exists, skipping download."
else
  [ -f "$DEPLOY_DIR/cert.pem" ] && rm -f "$DEPLOY_DIR/cert.pem"

  LOCAL_CERT=""
  for cand in "$SCRIPT_DIR/cert.pem" "$PWD/cert.pem"; do
    if [ -s "$cand" ]; then LOCAL_CERT="$cand"; break; fi
  done

  if [ -n "$LOCAL_CERT" ]; then
    echo "==> Using local cert.pem from: $LOCAL_CERT"
    cp "$LOCAL_CERT" "$DEPLOY_DIR/cert.pem"
  else
    echo "==> cert.pem not found, downloading from storage.quang.io.vn..."
    if ! wget -O "$DEPLOY_DIR/cert.pem" "https://storage.quang.io.vn/cert.pem"; then
      rm -f "$DEPLOY_DIR/cert.pem"
      echo "ERROR: Failed to download cert.pem" >&2
      exit 1
    fi
    if [ ! -s "$DEPLOY_DIR/cert.pem" ]; then
      rm -f "$DEPLOY_DIR/cert.pem"
      echo "ERROR: Downloaded cert.pem is empty" >&2
      exit 1
    fi
    echo "==> Downloaded cert.pem"
  fi
  chmod 600 "$DEPLOY_DIR/cert.pem"
fi

tunnel_exists() {
  cf_run tunnel list 2>/dev/null | grep -qE "(^|[[:space:]])${TUNNEL_NAME}([[:space:]]|$)"
}

get_tunnel_id() {
  cf_run tunnel list 2>/dev/null \
    | awk -v name="$TUNNEL_NAME" '$0 ~ (" "name" ") {print $1; exit}'
}

delete_tunnel() {
  echo "==> Deleting tunnel '$TUNNEL_NAME'..."

  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "    Stopping container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi

  local tid=""
  tid="$(get_tunnel_id || true)"

  if [ -n "$tid" ]; then
    echo "    Cleaning up stale connections for tunnel ID: $tid"
    cf_run_tty tunnel cleanup "$tid" || true
  fi

  echo "    Deleting tunnel (force)..."
  cf_run_tty tunnel delete -f "$TUNNEL_NAME" || true
}



# ---------- 2) Ensure tunnel exists (or recreate) ----------
echo "==> Ensure tunnel exists..."
if [ "$FORCE_RECREATE" = "true" ]; then
  if tunnel_exists; then
    delete_tunnel
  fi
  echo "    Creating tunnel '$TUNNEL_NAME'..."
  cf_run_tty tunnel create "$TUNNEL_NAME"
else
  if tunnel_exists; then
    echo "    Tunnel '$TUNNEL_NAME' already exists."
  else
    echo "    Creating tunnel '$TUNNEL_NAME'..."
    cf_run_tty tunnel create "$TUNNEL_NAME"
  fi
fi

# ---------- 3) Get tunnel ID ----------
echo "==> Getting tunnel ID..."
TUNNEL_ID="$(get_tunnel_id)"
if [ -z "${TUNNEL_ID:-}" ]; then
  echo "ERROR: Could not determine tunnel ID for '$TUNNEL_NAME'"
  exit 1
fi
echo "    Tunnel ID: $TUNNEL_ID"

CREDS_SRC="$DEPLOY_DIR/${TUNNEL_ID}.json"

if [ ! -f "$CREDS_SRC" ]; then
  echo "ERROR: Missing tunnel credentials: $CREDS_SRC"
  echo "Fix: re-run with --force-recreate OR copy ${TUNNEL_ID}.json into $DEPLOY_DIR"
  exit 1
fi

# Copy credentials into deploy folder
cp "$CREDS_SRC" "$CF_DIR/${TUNNEL_ID}.json"
chmod 600 "$CF_DIR/${TUNNEL_ID}.json"

# ---------- 4) Ensure config.yml exists ----------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "==> Creating initial config.yml..."
  cat > "$CONFIG_FILE" <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

ingress:
  - service: http_status:404
EOF
else
  tmp="$(mktemp)"
  awk -v tid="$TUNNEL_ID" '
/^tunnel:/ {print "tunnel: "tid; next}
/^credentials-file:/ {print "credentials-file: /etc/cloudflared/"tid".json"; next}
{print}
' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
fi

cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"

# config is not secret; make readable so any container user can read if needed
chmod 644 "$CONFIG_FILE"

# ---------- helpers to add/update ingress ----------
add_or_update_host() {  # unchanged
  local host="$1"
  local svc="$2"
  if grep -qE "^[[:space:]]*- hostname:[[:space:]]*$host[[:space:]]*$" "$CONFIG_FILE"; then
    python3 - "$CONFIG_FILE" "$host" "$svc" <<'PY'
import sys, re
path, host, svc = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, 'r', encoding='utf-8').read().splitlines(True)

out=[]
i=0
while i < len(lines):
    line = lines[i]
    out.append(line)
    m = re.match(r'^(\s*)-\s+hostname:\s*(.+?)\s*$', line)
    if m and m.group(2) == host:
        j=i+1
        replaced=False
        while j < len(lines):
            if re.match(r'^\s*-\s+hostname:\s*', lines[j]): break
            if re.match(r'^\s*-\s+service:\s*http_status:404', lines[j]): break
            if re.match(r'^\s*service:\s*', lines[j]):
                indent = re.match(r'^(\s*)', lines[j]).group(1)
                out.append(f"{indent}service: {svc}\n")
                j += 1
                replaced=True
                break
            out.append(lines[j])
            j += 1
        i = j
        if not replaced:
            out.append(f"    service: {svc}\n")
        continue
    i += 1

open(path, 'w', encoding='utf-8').write(''.join(out))
PY
  else
    awk -v host="$host" -v svc="$svc" '
/^[[:space:]]*- service: http_status:404[[:space:]]*$/ {
  print "  - hostname: " host
  print "    service: " svc
  print ""
}
{ print }
' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi
}

# ---------- 5) Apply maps ----------
echo "==> Updating ingress rules..."
HOSTS_TO_ROUTE=()

for item in "${MAPS[@]}"; do
  host="${item%%=*}"
  target="${item#*=}"

  if [[ "$target" =~ ^https?:// ]]; then
    svc="$target"
  elif [[ "$target" =~ ^[0-9]+$ ]]; then
    svc="${SCHEME}://${HOST_TARGET}:${target}"
  else
    svc="${SCHEME}://${target}"
  fi

  echo "    - $host  ->  $svc"
  add_or_update_host "$host" "$svc"
  HOSTS_TO_ROUTE+=("$host")
done

# ---------- 6) Route DNS ----------
if [ "$NO_DNS" != "true" ]; then
  echo "==> Routing DNS..."
  for h in "${HOSTS_TO_ROUTE[@]}"; do
    echo "    route: $h"
    cf_run_tty tunnel route dns "$TUNNEL_NAME" "$h"
  done
else
  echo "==> Skipping DNS routing (--no-dns)."
fi

# ---------- 7) Ensure docker-compose.yml exists (UPDATED) ----------
echo "==> Writing docker-compose.yml..."
cat > "$COMPOSE_FILE" <<EOF
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    user: "${RUN_UID}:${RUN_GID}"
    command: tunnel --config /etc/cloudflared/config.yml run
    volumes:
      - ./cloudflared:/etc/cloudflared:ro
    network_mode: host
EOF

# ---------- 8) Start / Restart ----------
if [ "$NO_START" != "true" ]; then
  echo "==> Starting (or updating) tunnel container..."
  cd "$DEPLOY_DIR"
  docker compose up -d
  docker restart "$CONTAINER_NAME" >/dev/null 2>&1 || true
  echo
  echo "==> Done. URLs:"
  for h in "${HOSTS_TO_ROUTE[@]}"; do
    echo "  - https://$h"
  done
  echo
  echo "Logs: docker logs -f ${CONTAINER_NAME}"
else
  echo "==> Skipping start (--no-start)."
  echo "Config updated at: $CONFIG_FILE"
fi
