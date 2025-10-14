#!/usr/bin/env bash
set -euo pipefail

# Usage: /root/supabase-script/script.sh <project_slug> <api_domain> <studio_domain> [smtp_host] [smtp_port] [smtp_user] [smtp_pass] [smtp_sender_name]

if [[ $# -lt 3 ]] || [[ $# -eq 4 ]] || [[ $# -eq 5 ]] || [[ $# -eq 6 ]] || [[ $# -gt 8 ]]; then
  echo "usage: $0 <project_slug> <api_domain> <studio_domain> [smtp_host smtp_port smtp_user smtp_pass smtp_sender_name]"
  echo ""
  echo "SMTP parameters are optional but must all be provided together (or none at all)"
  echo "Example with SMTP:"
  echo "  $0 myproject api.example.com studio.example.com smtp.ionos.fr 465 user@example.com 'password' 'My App'"
  exit 1
fi

PROJECT="$1"; API_DOMAIN="$2"; STUDIO_DOMAIN="$3"

# Optional SMTP parameters
SMTP_HOST="${4:-}"
SMTP_PORT="${5:-587}"
SMTP_USER="${6:-}"
SMTP_PASS="${7:-}"
SMTP_SENDER_NAME="${8:-Supabase}"

# Validate SMTP: either all provided or none
if [[ -n "$SMTP_HOST" ]] && [[ -z "$SMTP_USER" || -z "$SMTP_PASS" ]]; then
  echo "❌ Error: If SMTP host is provided, smtp_user and smtp_pass are required"
  exit 1
fi

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

cd "${DOCKER_DIR}"
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

# Generate JWTs - capture each on separate lines
ANON_JWT=$(python3 - <<PY
import jwt, time
secret = "${JWT_SECRET}"
now=int(time.time()); exp=now+60*60*24*365*10
print(jwt.encode({"role":"anon","iss":"supabase","iat":now,"exp":exp}, secret, algorithm="HS256"))
PY
)

SERVICE_JWT=$(python3 - <<PY
import jwt, time
secret = "${JWT_SECRET}"
now=int(time.time()); exp=now+60*60*24*365*10
print(jwt.encode({"role":"service_role","iss":"supabase","iat":now,"exp":exp}, secret, algorithm="HS256"))
PY
)

# Debug: verify JWTs were generated
echo "🔍 Generated JWTs:"
echo "   ANON_JWT length: ${#ANON_JWT}"
echo "   SERVICE_JWT length: ${#SERVICE_JWT}"
if [[ -z "$ANON_JWT" ]] || [[ -z "$SERVICE_JWT" ]]; then
  echo "❌ JWT generation failed!"
  echo "   ANON_JWT: ${ANON_JWT:0:50}..."
  echo "   SERVICE_JWT: ${SERVICE_JWT:0:50}..."
  exit 1
fi

# ---------- Helper functions ----------
# URL-encode special characters for use in connection strings
url_encode() {
  python3 - "$1" <<'PY'
import urllib.parse, sys
print(urllib.parse.quote(sys.argv[1], safe=''), end='')
PY
}

set_env() {
  local k="$1" v="$2"
  if grep -qE "^${k}=" .env; then
    # Delete the old line and append the new one to avoid sed escaping issues
    sed -i "/^${k}=/d" .env
    echo "${k}=${v}" >> .env
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
if [[ -n "$SMTP_HOST" ]]; then
  echo "📧 configuring SMTP (${SMTP_HOST}:${SMTP_PORT})…"
  set_env GOTRUE_MAILER_AUTOCONFIRM         "false"
  set_env GOTRUE_SMTP_HOST                  "${SMTP_HOST}"
  set_env GOTRUE_SMTP_PORT                  "${SMTP_PORT}"
  set_env GOTRUE_SMTP_USER                  "${SMTP_USER}"
  set_env GOTRUE_SMTP_PASS                  "${SMTP_PASS}"
  set_env GOTRUE_SMTP_ADMIN_EMAIL           "${SMTP_USER}"
  set_env GOTRUE_SMTP_SENDER_NAME           "${SMTP_SENDER_NAME}"
  set_env GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED "true"
  set_env GOTRUE_MAILER_EXTERNAL_HOSTS      "${API_DOMAIN}"
else
  echo "📧 SMTP not configured - using auto-confirm mode"
  set_env GOTRUE_MAILER_AUTOCONFIRM "true"
fi
set_env GOTRUE_DISABLE_SIGNUP     "false"

# Storage/Auth/PostgREST secrets + internal URLs
set_env PGRST_DB_SCHEMAS          "public,storage,graphql_public"
set_env PGRST_JWT_SECRET          "${JWT_SECRET}"
set_env STORAGE_JWT_SECRET        "${JWT_SECRET}"
set_env GOTRUE_JWT_SECRET         "${JWT_SECRET}"
set_env GOTRUE_SITE_URL           "https://${API_DOMAIN}"
set_env STORAGE_POSTGREST_URL     "http://rest:3000"

# URL-encode postgres password for connection string
POSTGRES_PASSWORD_ENCODED=$(url_encode "${POSTGRES_PASSWORD}")
set_env STORAGE_DATABASE_URL      "postgresql://postgres:${POSTGRES_PASSWORD_ENCODED}@db:5432/postgres"

# Studio needs these to talk to the right API with valid tokens
set_env SUPABASE_ANON_KEY         "${ANON_JWT}"
set_env SUPABASE_SERVICE_KEY      "${SERVICE_JWT}"
# Make Studio pick up the correct API & keys even if env block is ignored
set_env SUPABASE_URL                  "https://${API_DOMAIN}"
set_env NEXT_PUBLIC_SUPABASE_URL      "https://${API_DOMAIN}"
set_env NEXT_PUBLIC_SUPABASE_ANON_KEY "${ANON_JWT}"
set_env NEXT_PUBLIC_SUPABASE_SERVICE_KEY "${SERVICE_JWT}"

# Storage volume perms
mkdir -p volumes/storage
chown -R 1000:1000 volumes/storage || true

# ---------- Compose override (loopback ports only; NO container_name anywhere) ----------
cat > docker-compose.override.yml <<'YAML'
version: "3.8"
services:
  kong:
    ports:
      - "127.0.0.1:API_PORT_PLACEHOLDER:8000"
      - "127.0.0.1:ADMIN_PORT_PLACEHOLDER:8001"

  studio:
    ports:
      - "127.0.0.1:STUDIO_PORT_PLACEHOLDER:3000"
    environment:
      SUPABASE_PUBLIC_URL: "https://API_DOMAIN_PLACEHOLDER"
      SUPABASE_URL: "https://API_DOMAIN_PLACEHOLDER"
      NEXT_PUBLIC_SUPABASE_URL: "https://API_DOMAIN_PLACEHOLDER"
      SUPABASE_ANON_KEY: "ANON_JWT_PLACEHOLDER"
      SUPABASE_SERVICE_KEY: "SERVICE_JWT_PLACEHOLDER"
      NEXT_PUBLIC_SUPABASE_ANON_KEY: "ANON_JWT_PLACEHOLDER"
      NEXT_PUBLIC_SUPABASE_SERVICE_KEY: "SERVICE_JWT_PLACEHOLDER"

  auth:
    environment:
      GOTRUE_SITE_URL: "https://API_DOMAIN_PLACEHOLDER"
      GOTRUE_API_EXTERNAL_URL: "https://API_DOMAIN_PLACEHOLDER/auth/v1"
      GOTRUE_URI_ALLOW_LIST: "https://API_DOMAIN_PLACEHOLDER,https://STUDIO_DOMAIN_PLACEHOLDER"
      GOTRUE_MAILER_AUTOCONFIRM: "SMTP_AUTOCONFIRM_PLACEHOLDER"
      GOTRUE_MAILER_EXTERNAL_HOSTS: "API_DOMAIN_PLACEHOLDER"
      GOTRUE_SMTP_HOST: "SMTP_HOST_PLACEHOLDER"
      GOTRUE_SMTP_PORT: "SMTP_PORT_PLACEHOLDER"
      GOTRUE_SMTP_USER: "SMTP_USER_PLACEHOLDER"
      GOTRUE_SMTP_PASS: "SMTP_PASS_PLACEHOLDER"
      GOTRUE_SMTP_ADMIN_EMAIL: "SMTP_USER_PLACEHOLDER"
      GOTRUE_SMTP_SENDER_NAME: "SMTP_SENDER_NAME_PLACEHOLDER"

  supavisor:
    ports:
      - "127.0.0.1:POOLER_PORT_PLACEHOLDER:6543"

  db:
    ports:
      - "127.0.0.1:PG_PORT_PLACEHOLDER:5432"
YAML

# Replace placeholders with actual values (use @ as delimiter to avoid issues with / in JWTs)
sed -i "s@API_PORT_PLACEHOLDER@${API_PORT}@g" docker-compose.override.yml
sed -i "s@ADMIN_PORT_PLACEHOLDER@${ADMIN_PORT}@g" docker-compose.override.yml
sed -i "s@STUDIO_PORT_PLACEHOLDER@${STUDIO_PORT}@g" docker-compose.override.yml
sed -i "s@POOLER_PORT_PLACEHOLDER@${POOLER_PORT}@g" docker-compose.override.yml
sed -i "s@PG_PORT_PLACEHOLDER@${PG_PORT}@g" docker-compose.override.yml
sed -i "s@API_DOMAIN_PLACEHOLDER@${API_DOMAIN}@g" docker-compose.override.yml
sed -i "s@STUDIO_DOMAIN_PLACEHOLDER@${STUDIO_DOMAIN}@g" docker-compose.override.yml

# For JWTs, escape special characters to avoid sed issues
ANON_JWT_ESCAPED=$(printf '%s\n' "$ANON_JWT" | sed 's/[&/\]/\\&/g')
SERVICE_JWT_ESCAPED=$(printf '%s\n' "$SERVICE_JWT" | sed 's/[&/\]/\\&/g')
sed -i "s@ANON_JWT_PLACEHOLDER@${ANON_JWT_ESCAPED}@g" docker-compose.override.yml
sed -i "s@SERVICE_JWT_PLACEHOLDER@${SERVICE_JWT_ESCAPED}@g" docker-compose.override.yml

# SMTP placeholders - use | as delimiter to avoid conflicts with @ in email addresses
if [[ -n "$SMTP_HOST" ]]; then
  SMTP_PASS_ESCAPED=$(printf '%s\n' "$SMTP_PASS" | sed 's/[&/\|]/\\&/g')
  SMTP_USER_ESCAPED=$(printf '%s\n' "$SMTP_USER" | sed 's/[&/\|]/\\&/g')
  SMTP_SENDER_ESCAPED=$(printf '%s\n' "$SMTP_SENDER_NAME" | sed 's/[&/\|]/\\&/g')
  sed -i "s|SMTP_AUTOCONFIRM_PLACEHOLDER|false|g" docker-compose.override.yml
  sed -i "s|SMTP_HOST_PLACEHOLDER|${SMTP_HOST}|g" docker-compose.override.yml
  sed -i "s|SMTP_PORT_PLACEHOLDER|${SMTP_PORT}|g" docker-compose.override.yml
  sed -i "s|SMTP_USER_PLACEHOLDER|${SMTP_USER_ESCAPED}|g" docker-compose.override.yml
  sed -i "s|SMTP_PASS_PLACEHOLDER|${SMTP_PASS_ESCAPED}|g" docker-compose.override.yml
  sed -i "s|SMTP_SENDER_NAME_PLACEHOLDER|${SMTP_SENDER_ESCAPED}|g" docker-compose.override.yml
else
  # Remove SMTP env vars if not configured
  sed -i "s|SMTP_AUTOCONFIRM_PLACEHOLDER|true|g" docker-compose.override.yml
  sed -i "/SMTP_HOST_PLACEHOLDER/d" docker-compose.override.yml
  sed -i "/SMTP_PORT_PLACEHOLDER/d" docker-compose.override.yml
  sed -i "/SMTP_USER_PLACEHOLDER/d" docker-compose.override.yml
  sed -i "/SMTP_PASS_PLACEHOLDER/d" docker-compose.override.yml
  sed -i "/SMTP_SENDER_NAME_PLACEHOLDER/d" docker-compose.override.yml
fi

echo "🔍 Debug: Checking SERVICE_JWT replacement:"
grep "SERVICE_KEY:" docker-compose.override.yml | head -2

# Verify override file is valid YAML and contains our env vars
if ! grep -q "SUPABASE_SERVICE_KEY:" docker-compose.override.yml; then
  echo "❌ docker-compose.override.yml is missing SUPABASE_SERVICE_KEY!"
  cat docker-compose.override.yml
  exit 1
fi

# Debug: show what we wrote to the override
echo "✅ docker-compose.override.yml created"
echo "🔍 Verifying Studio env block in override:"
grep -A 8 "studio:" docker-compose.override.yml | grep -E "SUPABASE_SERVICE_KEY|SUPABASE_ANON_KEY" || {
  echo "❌ Keys not found in override file!"
  cat docker-compose.override.yml
  exit 1
}

echo "🚀 starting containers…"
docker compose -p "$PROJECT_STACK" pull

# Sanity: kong must not publish 0.0.0.0 or 8443/8444
if docker compose -p "$PROJECT_STACK" config | sed -n '/kong:/,/^[a-z]/p' | grep -E '0\.0\.0\.0|[^0-9]8443[^0-9]|[^0-9]8444[^0-9]'; then
  echo "❌ kong still has unwanted host publishes. Aborting."; exit 1
fi

docker compose -p "$PROJECT_STACK" up -d

# Ensure Studio re-reads .env (loads SUPABASE_* keys)
echo "🔄 recreating Studio to apply final env…"
docker compose -p "$PROJECT_STACK" up -d --force-recreate --no-deps studio

# Debug: check what docker compose resolved for Studio
echo "🔍 Checking what docker compose config resolved for Studio environment:"
docker compose -p "$PROJECT_STACK" config | grep -A 30 "studio:" | grep -E "SUPABASE_SERVICE_KEY|SUPABASE_ANON_KEY" || {
  echo "⚠️  Keys not in docker compose config output!"
}

# ---------- Wait for services to be ready ----------
echo "⏳ waiting for services to be ready…"
max_wait=60
elapsed=0
while [[ $elapsed -lt $max_wait ]]; do
  if docker compose -p "$PROJECT_STACK" exec -T kong wget -q -O- http://rest:3000/rest/v1/ >/dev/null 2>&1; then
    echo "✅ PostgREST is ready"
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
if [[ $elapsed -ge $max_wait ]]; then
  echo "⚠️  PostgREST did not respond within ${max_wait}s, continuing anyway…"
fi

# ---------- Validate Studio environment ----------
echo "🔍 validating Studio environment…"
studio_env_ok=true
required_vars="SUPABASE_PUBLIC_URL SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_KEY"
for var in $required_vars; do
  val=$(docker compose -p "$PROJECT_STACK" exec -T studio env 2>/dev/null | grep "^${var}=" | cut -d= -f2- || true)
  if [[ -z "$val" ]]; then
    echo "❌ Studio env missing: ${var}"
    studio_env_ok=false
  else
    echo "✅ Studio env set: ${var}=${val:0:40}..."
  fi
done

# Verify keys match
studio_anon=$(docker compose -p "$PROJECT_STACK" exec -T studio env 2>/dev/null | grep '^SUPABASE_ANON_KEY=' | cut -d= -f2- || true)
if [[ "$studio_anon" != "$ANON_JWT" ]]; then
  echo "❌ Studio ANON_KEY mismatch!"
  echo "   Expected: ${ANON_JWT:0:40}..."
  echo "   Got:      ${studio_anon:0:40}..."
  studio_env_ok=false
fi

if [[ "$studio_env_ok" == "false" ]]; then
  echo ""
  echo "❌ Studio environment validation failed!"
  echo "   This means Studio will not be able to communicate with the API."
  echo "   Try recreating the Studio container manually:"
  echo "   cd ${DOCKER_DIR} && docker compose -p ${PROJECT_STACK} up -d --force-recreate studio"
  exit 1
fi

# ---------- Health check: Storage bucket list via public domain ----------
echo "🏥 testing Storage API via public domain…"
# Wait a bit for Kong to be ready
sleep 5

storage_test=$(curl -sf -H "Authorization: Bearer ${ANON_JWT}" \
  -H "apikey: ${ANON_JWT}" \
  "https://${API_DOMAIN}/storage/v1/bucket" 2>&1 || echo "FAILED")

if [[ "$storage_test" == *"FAILED"* ]] || [[ "$storage_test" != "["* ]]; then
  echo "❌ Storage health check failed!"
  echo "   URL: https://${API_DOMAIN}/storage/v1/bucket"
  echo "   Response: ${storage_test:0:200}"
  echo ""
  echo "Diagnostics:"
  echo "  1. Ensure Plesk reverse proxy is configured:"
  echo "     ${API_DOMAIN} → http://127.0.0.1:${API_PORT}"
  echo "  2. Check if Kong is listening:"
  docker compose -p "$PROJECT_STACK" ps kong
  echo "  3. Check Kong logs:"
  docker compose -p "$PROJECT_STACK" logs --tail=20 kong
  echo ""
  echo "⚠️  Continuing anyway, but Storage may not work in Studio UI."
else
  echo "✅ Storage API is healthy (returned bucket list)"
fi
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
OUT

if [[ -n "$SMTP_HOST" ]]; then
  cat <<OUT
SMTP:
  host     : ${SMTP_HOST}
  port     : ${SMTP_PORT}
  user     : ${SMTP_USER}
  sender   : ${SMTP_SENDER_NAME}
  status   : ✅ Email verification ENABLED
OUT
else
  cat <<OUT
SMTP:
  status   : ⚠️  Auto-confirm mode (no email verification)
OUT
fi

cat <<OUT
Config saved: ${DOCKER_DIR}/.env
=========================================================
OUT
