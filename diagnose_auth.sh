#!/usr/bin/env bash
set -euo pipefail

# Usage: ./diagnose_auth.sh <project_slug> <api_domain>

if [ $# -lt 2 ]; then
  echo "Usage: $0 <project_slug> <api_domain>"
  echo "Example: $0 araisupabase sbapi.agence-xr.io"
  exit 1
fi

PROJECT="$1"
API_DOMAIN="$2"
PROJECT_STACK="sb-${PROJECT}"
DOCKER_DIR="/opt/supabase/projects/${PROJECT}/supabase/docker"

if [[ ! -d "$DOCKER_DIR" ]]; then
  echo "❌ Project directory not found: $DOCKER_DIR"
  exit 1
fi

cd "$DOCKER_DIR"

echo "=========================================="
echo "🔍 Supabase Authentication Diagnostics"
echo "=========================================="
echo ""

# 1. Check if .env exists and has required auth vars
echo "1️⃣ Checking .env configuration..."
if [[ ! -f .env ]]; then
  echo "   ❌ .env file not found!"
  exit 1
fi

for var in JWT_SECRET ANON_KEY SERVICE_ROLE_KEY GOTRUE_JWT_SECRET GOTRUE_API_EXTERNAL_URL SITE_URL; do
  val=$(grep "^${var}=" .env | cut -d= -f2- || true)
  if [[ -z "$val" ]]; then
    echo "   ❌ Missing: $var"
  else
    echo "   ✅ $var: ${val:0:50}..."
  fi
done
echo ""

# 2. Check if auth container is running
echo "2️⃣ Checking auth container status..."
auth_status=$(docker compose -p "$PROJECT_STACK" ps auth --format json 2>/dev/null | grep -o '"State":"[^"]*"' | cut -d'"' -f4 || echo "not found")
if [[ "$auth_status" == "running" ]]; then
  echo "   ✅ Auth container is running"
else
  echo "   ❌ Auth container status: $auth_status"
  docker compose -p "$PROJECT_STACK" ps auth
fi
echo ""

# 3. Check auth container environment
echo "3️⃣ Checking auth container environment..."
required_auth_vars="GOTRUE_JWT_SECRET GOTRUE_API_EXTERNAL_URL GOTRUE_SITE_URL GOTRUE_DB_DRIVER"
for var in $required_auth_vars; do
  val=$(docker compose -p "$PROJECT_STACK" exec -T auth env 2>/dev/null | grep "^${var}=" | cut -d= -f2- || true)
  if [[ -z "$val" ]]; then
    echo "   ❌ Missing in container: $var"
  else
    echo "   ✅ $var: ${val:0:50}..."
  fi
done
echo ""

# 4. Check auth logs for errors
echo "4️⃣ Checking auth container logs (last 30 lines)..."
docker compose -p "$PROJECT_STACK" logs --tail=30 auth
echo ""

# 5. Test auth endpoint directly
echo "5️⃣ Testing auth endpoint from inside Kong..."
auth_health=$(docker compose -p "$PROJECT_STACK" exec -T kong wget -q -O- http://auth:9999/health 2>&1 || echo "FAILED")
if [[ "$auth_health" == *"FAILED"* ]]; then
  echo "   ❌ Auth health check failed from inside Kong"
  echo "   Response: $auth_health"
else
  echo "   ✅ Auth health check passed: $auth_health"
fi
echo ""

# 6. Test auth endpoint from public URL
echo "6️⃣ Testing public auth endpoint..."
ANON_KEY=$(grep "^ANON_KEY=" .env | cut -d= -f2-)
signup_test=$(curl -sf -X POST "https://${API_DOMAIN}/auth/v1/signup" \
  -H "apikey: ${ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}' 2>&1 || echo "FAILED")

if [[ "$signup_test" == *"FAILED"* ]]; then
  echo "   ❌ Public auth endpoint not responding"
  echo "   Response: ${signup_test:0:200}"
else
  echo "   ✅ Public auth endpoint responded"
  echo "   Response: ${signup_test:0:200}"
fi
echo ""

# 7. Check Kong routing for auth
echo "7️⃣ Checking Kong configuration for auth routes..."
kong_config=$(docker compose -p "$PROJECT_STACK" exec -T kong kong config db_export /dev/stdout 2>/dev/null | grep -A5 "auth" || echo "Could not fetch Kong config")
if [[ "$kong_config" == *"Could not"* ]]; then
  echo "   ⚠️  Could not fetch Kong config"
else
  echo "   Kong config (auth-related):"
  echo "$kong_config" | head -20
fi
echo ""

# 8. Check database connection from auth
echo "8️⃣ Checking auth database connectivity..."
db_test=$(docker compose -p "$PROJECT_STACK" exec -T auth sh -c 'wget -q -O- http://127.0.0.1:9999/health' 2>&1 || echo "FAILED")
if [[ "$db_test" == *"FAILED"* ]]; then
  echo "   ❌ Auth cannot reach its own health endpoint"
else
  echo "   ✅ Auth health endpoint working: $db_test"
fi
echo ""

echo "=========================================="
echo "📋 Summary & Recommendations"
echo "=========================================="
echo ""
echo "Common auth issues and fixes:"
echo "1. JWT_SECRET mismatch → Ensure GOTRUE_JWT_SECRET matches JWT_SECRET in .env"
echo "2. Wrong external URL → Check GOTRUE_API_EXTERNAL_URL points to https://${API_DOMAIN}/auth/v1"
echo "3. CORS issues → Check GOTRUE_URI_ALLOW_LIST includes your frontend domain"
echo "4. Database not initialized → Auth needs 'auth' schema in Postgres"
echo "5. Kong routing → Auth service should be proxied at /auth/v1/*"
echo ""
echo "To fix, try:"
echo "   cd $DOCKER_DIR"
echo "   docker compose -p $PROJECT_STACK restart auth"
echo "   docker compose -p $PROJECT_STACK logs -f auth"
