#!/usr/bin/env bash
set -euo pipefail

# Usage: /root/supabase-script/script.sh <project_slug> <api_domain> <studio_domain>

[ $# -eq 3 ] || { echo "usage: $0 <project_slug> <api_domain> <studio_domain>"; exit 1; }
PROJECT="$1"; API_DOMAIN="$2"; STUDIO_DOMAIN="$3"

# Compose project name (used as namespace/prefix)
PROJECT_STACK="$(echo "sb-${PROJECT}" | tr -cd '[:alnum:]-_')"

ROOT_BASE="/opt/supabase/projects"
ROOT_DIR="${ROOT_BASE}/${PROJECT}"
REPO_DIR="${ROOT_DIR}/supabase"
DOCKER_DIR="${REPO_DIR}/docker"

command -v docker >/dev/null || { echo "docker not found"; exit 1; }
command -v git    >/dev/null || { echo "git not found"; exit 1; }
command -v python3>/dev/null || { echo "python3 not found"; exit 1; }

if [[ -d "${DOCKER_DIR}" ]]; then
  echo "project '${PROJECT}' already exists at ${DOCKER_DIR}"; exit 1
fi
mkdir -p "${ROOT_DIR}"

# ---------- Port management ----------
reserved_ports_from_overrides() {
  for f in /opt/supabase/projects/*/supabase/docker/docker-compose.override.yml; do
    [[ -f "$f" ]] || continue
    grep -Eo '127\.0\.0\.1:[0-9]+:[0-9]+' "$f" | cut -d: -f2 || true
  done | tr '\n' ' '
}
port_is_busy() {  # 0 = busy, 1 = free
  python3 - "$1" >/dev/null 2>&1 <<'PY' || return 0
import socket, sys
p=int(sys.argv[1]); s=socket.socket()
try: s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", p))
except OSError: raise SystemExit(1)
finally: s.close()
PY
  return 1
}
pick_free_port() {
  local base="${1:-}"; [[ -n "$base" ]] || { echo "pick_free_port: missing base port" >&2; exit 1; }
  local p="$base"; local reserved=" $(reserved_ports_from_overrides) "
  while :; do
    [[ "$reserved" == *" $p "* ]] && { p=$((p+1)); continue; }
    port_is_busy "$p" && { p=$((p+1)); continue; }
    printf '%s\n' "$p"; return 0
  done
}

echo "🔍 selecting ports…"
API_PORT=$(pick_free_port 8000)
ADMIN_PORT=$(pick_free_port $((API_PORT+1)))
STUDIO_PORT=$(pick_free_port 8300)
PG_PORT=$(pick_free_port 8432)
POOLER_PORT=$(pick_free_port 8543)
echo "✅ ports: api:${API_PORT} admin:${ADMIN_PORT} studio:${STUDIO_PORT} pg:${PG_PORT} pooler:${POOLER_PORT}"

# ---------- Clone supabase docker template ----------
echo "📦 cloning supabase repo…"
git clone --depth=1 https://github.com/supabase/supabase.git "${REPO_DIR}"

ccd "${DOCKER_DIR}"
cp -n .env.example .env || true

# make compose namespace-able: remove ALL hard-coded container_name
# (so -p "$PROJECT_STACK" prefixes containers per project)
find . -maxdepth 1 -name 'docker-compose*.yml' -print0 \
  | xargs -0 sed -Ei '/^[[:space:]]*container_name:[[:space:]]*/d'
  
# Persist compose project name for manual docker compose usage too
if grep -qE '^COMPOSE_PROJECT_NAME=' .env; then
  sed -i "s|^COMPOSE_PROJECT_NAME=.*|COMPOSE_PROJECT_NAME=${PROJECT_STACK}|" .env
else
  echo "COMPOSE_PROJECT_NAME=${PROJECT_STACK}" >> .env
fi

# ---------- Remove entire kong: ports: block (avoid 0.0.0.0:8000/8001 and 8443/8444) ----------
awk '
  BEGIN{in_kong=0; in_ports=0}
  /^[[:space:]]*kong:[[:space:]]*$/ {in_kong=1; print; next}
  in_kong && /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ && $0 !~ /^[[:space:]]*ports:/ { in_ports=0 }
  in_kong && /^[[:space:]]*ports:[[:space:]]*$/ {in_ports=1; next}
  in_kong && in_ports {
    if ($0 ~ /^[[:space:]]*-[[:space:]]*".*"$/ || $0 ~ /^[[:space:]]*-[[:space:]]*[0-9]/ || $0 ~ /^[[:space:]]*#/) next
    if ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/) { in_ports=0 } else { next }
  }
  {print}
' docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml

# ---------- Secrets & JWTs ----------
echo "🔐 generating secrets…"
JWT_SECRET="$(openssl rand -hex 32)"
POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
DASHBOARD_PASSWORD="$(openssl rand -base64 18 | tr -d '\n')"

if ! python3 -c "import jwt" 2>/dev/null; then
  echo "📦 installing PyJWT…"
  if command -v pip3 >/dev/null; then
    pip3 install -q --break-system-packages pyjwt
  else
    apt-get update -y >/dev/null
    apt-get install -y python3-pip >/dev/null
    pip3 install -q --break-system-packages pyjwt
  fi
fi

read -r ANON_JWT SERVICE_JWT <<EOF
$(python3 - <<PY
import jwt, time
secret = "${JWT_SECRET}"
now=int(time.time()); exp=now+60*60*24*365*10
def enc(role): return jwt.encode({"role":role,"iss":"supabase","iat":now,"exp":exp}, secret, algorithm="HS256")
print(enc("anon")); print(enc("service_role"))
PY
)
EOF

# ---------- .env writer ----------
set_env() {
  local k="$1" v="$2"
  if grep -qE "^${k}=" .env; then
    sed -i "s|^${k}=.*|${k}=${v}|" .env
  else
    echo "${k}=${v}" >> .env
  fi
}

echo "⚙️ writing .env…"
set_env POSTGRES_PASSWORD         "${POSTGRES_PASSWORD}"
set_env JWT_SECRET                "${JWT_SECRET}"
set_env ANON_KEY                  "${ANON_JWT}"
set_env SERVICE_ROLE_KEY          "${SERVICE_JWT}"
set_env DASHBOARD_USERNAME        "supabase"
set_env DASHBOARD_PASSWORD        "${DASHBOARD_PASSWORD}"

# External/public URLs
set_env SITE_URL                  "https://${API_DOMAIN}"
set_env PUBLIC_URL                "https://${API_DOMAIN}"
set_env SUPABASE_PUBLIC_URL       "https://${API_DOMAIN}"
set_env API_EXTERNAL_URL          "https://${API_DOMAIN}"
set_env GOTRUE_API_EXTERNAL_URL   "https://${API_DOMAIN}/auth/v1"
set_env GOTRUE_URI_ALLOW_LIST     "https://${API_DOMAIN},https://${STUDIO_DOMAIN}"

# Mailer/user flags
set_env GOTRUE_MAILER_AUTOCONFIRM "true"
set_env GOTRUE_DISABLE_SIGNUP     "false"

# Storage/Auth/PostgREST secrets + internal URLs
set_env PGRST_DB_SCHEMAS          "public,storage,graphql_public"
set_env PGRST_JWT_SECRET          "${JWT_SECRET}"
set_env STORAGE_JWT_SECRET        "${JWT_SECRET}"
set_env GOTRUE_JWT_SECRET         "${JWT_SECRET}"
set_env STORAGE_POSTGREST_URL     "http://rest:3000"
set_env STORAGE_DATABASE_URL      "postgresql://postgres:${POSTGRES_PASSWORD}@db:5432/postgres"

# Studio needs these to talk to the right API with valid tokens
set_env SUPABASE_ANON_KEY         "${ANON_JWT}"
set_env SUPABASE_SERVICE_KEY      "${SERVICE_JWT}"

# Storage volume perms
mkdir -p volumes/storage
chown -R 1000:1000 volumes/storage || true

# ---------- Compose override (loopback ports only; NO container_name anywhere) ----------
cat > docker-compose.override.yml <<YAML
services:
  kong:
    ports:
      - "127.0.0.1:${API_PORT}:8000"
      - "127.0.0.1:${ADMIN_PORT}:8001"
  studio:
    ports:
      - "127.0.0.1:${STUDIO_PORT}:3000"
  supavisor:
    ports:
      - "127.0.0.1:${POOLER_PORT}:6543"
  db:
    ports:
      - "127.0.0.1:${PG_PORT}:5432"
YAML

echo "🚀 starting containers…"
docker compose -p "$PROJECT_STACK" pull

# Sanity: kong must not publish 0.0.0.0 or 8443/8444
if docker compose -p "$PROJECT_STACK" config | sed -n '/kong:/,/^[a-z]/p' | grep -E '0\.0\.0\.0|[^0-9]8443[^0-9]|[^0-9]8444[^0-9]'; then
  echo "❌ kong still has unwanted host publishes. Aborting."; exit 1
fi

docker compose -p "$PROJECT_STACK" up -d

# Ensure Studio re-reads .env (loads SUPABASE_* keys)
docker compose -p "$PROJECT_STACK" up -d --force-recreate --no-deps studio

cat <<OUT

=========================================================
✅ Supabase project created

Project : ${PROJECT}
Folder  : ${ROOT_DIR}
Domains:
  API    : https://${API_DOMAIN}
  Studio : https://${STUDIO_DOMAIN}
Reverse proxies (WebSocket ON):
  ${API_DOMAIN}    → http://127.0.0.1:${API_PORT}
  ${STUDIO_DOMAIN} → http://127.0.0.1:${STUDIO_PORT}
Studio login:
  user     : supabase
  password : ${DASHBOARD_PASSWORD}
Postgres:
  host     : 127.0.0.1
  port     : ${PG_PORT}
  user     : postgres
  password : ${POSTGRES_PASSWORD}
Config saved: ${DOCKER_DIR}/.env
=========================================================
OUT
