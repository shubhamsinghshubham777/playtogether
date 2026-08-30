#!/usr/bin/env bash
# ==============================================================================
# SyncTogether Development Ecosystem Controller
# ------------------------------------------------------------------------------
# Usage:
#   ./scripts/dev.sh                # Spin down old state, then spin whole ecosystem UP
#   ./scripts/dev.sh up [flags]     # Same as above (accepts -f, -b, -w, etc.)
#   ./scripts/dev.sh down           # Spin everything DOWN cleanly & free all ports
#   ./scripts/dev.sh status         # Check health of all ecosystem components
#   ./scripts/dev.sh test           # Run all 3 test suites (Flutter, pgTAP, Website)
#   ./scripts/dev.sh reset          # Reset local DB (re-run migrations & seed)
#   ./scripts/dev.sh logs [target]  # Tail background logs (website/functions/hookdeck)
#
# Flags:
#   --flutter, -f                   Launch primary Flutter client (Instance A)
#   --instance-b, -b                Launch secondary isolated Flutter client (Instance B)
#   --hookdeck, -w                  Start Hookdeck / Paddle webhook tunnel
# ==============================================================================

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PID_DIR="$REPO_ROOT/.temp"
mkdir -p "$PID_DIR"
FUNCTIONS_PID_FILE="$PID_DIR/functions.pid"
WEBSITE_PID_FILE="$PID_DIR/website.pid"
TUNNEL_PID_FILE="$PID_DIR/tunnel.pid"
LOGS_DIR="/tmp/synctogether-logs"
mkdir -p "$LOGS_DIR"

FUNCTIONS_LOG="$LOGS_DIR/functions.log"
WEBSITE_LOG="$LOGS_DIR/website.log"
TUNNEL_LOG="$LOGS_DIR/tunnel.log"

# Cloudflare Turnstile Always-Pass Testing Keys
TURNSTILE_TEST_SITE_KEY="1x00000000000000000000AA"
TURNSTILE_TEST_SECRET_KEY="1x0000000000000000000000000000000AA"

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper prints
info() { echo -e "${CYAN}ℹ ${NC}$1"; }
success() { echo -e "${GREEN}✔ ${NC}$1"; }
warn() { echo -e "${YELLOW}⚠ ${NC}$1"; }
error() { echo -e "${RED}✖ ${NC}$1"; }
banner() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}\n"; }

# ------------------------------------------------------------------------------
# Spin Down
# ------------------------------------------------------------------------------
spin_down() {
  banner "Spinning Down SyncTogether Ecosystem"

  # 1. Kill Webhook Tunnels (Hookdeck / Paddle CLI)
  info "Stopping webhook tunnels..."
  if [ -f "$TUNNEL_PID_FILE" ]; then
    PID=$(cat "$TUNNEL_PID_FILE")
    kill "$PID" 2>/dev/null || true
    rm -f "$TUNNEL_PID_FILE"
  fi
  pkill -f "hookdeck listen" 2>/dev/null || true
  pkill -f "paddle webhook:listen" 2>/dev/null || true

  # 2. Kill Next.js website dev server
  info "Stopping Next.js website server..."
  if [ -f "$WEBSITE_PID_FILE" ]; then
    PID=$(cat "$WEBSITE_PID_FILE")
    kill "$PID" 2>/dev/null || true
    rm -f "$WEBSITE_PID_FILE"
  fi
  pkill -f "next dev" 2>/dev/null || true
  pkill -f "next-server" 2>/dev/null || true

  # 3. Kill Supabase Edge Functions runtime
  info "Stopping Supabase Edge Functions runtime..."
  if [ -f "$FUNCTIONS_PID_FILE" ]; then
    PID=$(cat "$FUNCTIONS_PID_FILE")
    kill "$PID" 2>/dev/null || true
    rm -f "$FUNCTIONS_PID_FILE"
  fi
  pkill -f "supabase functions serve" 2>/dev/null || true

  # 4. Stop Supabase Docker Stack
  info "Stopping Supabase local containers..."
  supabase stop 2>/dev/null || true

  # 5. Stop running Flutter desktop app instances (SyncTogether / SyncTogether B)
  info "Checking for running desktop app instances..."
  pkill -f "SyncTogether B.app" 2>/dev/null || true
  pkill -f "SyncTogether.app/Contents/MacOS/SyncTogether" 2>/dev/null || true

  # 6. Cleanup any remaining listeners on dev ports
  info "Verifying ports are clean..."
  local ports=(3000 54321 54322 54323 54324 54327)
  for port in "${ports[@]}"; do
    local pids
    pids=$(lsof -ti :"$port" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      kill -9 $pids 2>/dev/null || true
    fi
  done

  success "All services & apps spun down cleanly."
}

# ------------------------------------------------------------------------------
# Check Prerequisites & Environment Files
# ------------------------------------------------------------------------------
check_prereqs() {
  info "Checking prerequisites..."

  # Docker check
  if ! docker info >/dev/null 2>&1; then
    error "Docker is not running. Please start Docker (or OrbStack) and try again."
    exit 1
  fi

  # Supabase CLI check
  if ! command -v supabase &>/dev/null; then
    error "Supabase CLI is not installed. Install via: brew install supabase/tap/supabase"
    exit 1
  fi

  # Node check
  if ! command -v npm &>/dev/null; then
    error "npm is not installed. Please install Node.js (v18+) and try again."
    exit 1
  fi

  # Check & seed .env files if missing
  if [ ! -f "$REPO_ROOT/.env" ]; then
    warn "Missing .env in root — creating from .env.example"
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
  fi

  if [ ! -f "$REPO_ROOT/supabase/.env" ]; then
    warn "Missing supabase/.env — creating from supabase/.env.example"
    cp "$REPO_ROOT/supabase/.env.example" "$REPO_ROOT/supabase/.env"
  fi

  if [ ! -f "$REPO_ROOT/supabase/functions/.env" ]; then
    warn "Missing supabase/functions/.env — creating from supabase/functions/.env.example"
    cp "$REPO_ROOT/supabase/functions/.env.example" "$REPO_ROOT/supabase/functions/.env"
  fi

  if [ ! -f "$REPO_ROOT/website/.env.local" ]; then
    warn "Missing website/.env.local — creating from website/.env.example"
    cp "$REPO_ROOT/website/.env.example" "$REPO_ROOT/website/.env.local"
  fi

  # Seed Cloudflare Turnstile always-pass test keys if still on placeholders
  if grep -q "TURNSTILE_SITE_KEY=0x4AAA" "$REPO_ROOT/.env" || grep -q "TURNSTILE_SITE_KEY=$" "$REPO_ROOT/.env"; then
    sed -i '' "s|TURNSTILE_SITE_KEY=.*|TURNSTILE_SITE_KEY=$TURNSTILE_TEST_SITE_KEY|" "$REPO_ROOT/.env"
  fi
  if grep -q "SUPABASE_AUTH_CAPTCHA_SECRET=0x4AAA" "$REPO_ROOT/supabase/.env" || grep -q "SUPABASE_AUTH_CAPTCHA_SECRET=$" "$REPO_ROOT/supabase/.env"; then
    sed -i '' "s|SUPABASE_AUTH_CAPTCHA_SECRET=.*|SUPABASE_AUTH_CAPTCHA_SECRET=$TURNSTILE_TEST_SECRET_KEY|" "$REPO_ROOT/supabase/.env"
  fi

  success "Prerequisites & environment files verified."
}

# ------------------------------------------------------------------------------
# Spin Up
# ------------------------------------------------------------------------------
spin_up() {
  local launch_flutter=false
  local launch_instance_b=false
  local launch_tunnel=false

  # Parse all flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --flutter|-f) launch_flutter=true ;;
      --instance-b|-b) launch_instance_b=true ;;
      --hookdeck|--tunnel|-w) launch_tunnel=true ;;
    esac
    shift
  done

  # Spin down previous instances first for a clean state
  spin_down
  check_prereqs

  banner "Spinning Up SyncTogether Ecosystem"

  # 1. Start Supabase Stack
  info "Starting Supabase local stack (PostgreSQL, Auth, Realtime, Storage, Studio)..."
  supabase start

  # Apply any pending migrations (e.g. from new branches/commits since last backup)
  info "Checking and applying any pending database migrations..."
  supabase migration up

  # Extract credentials from Supabase
  local env_status
  env_status=$(supabase status -o env 2>/dev/null || true)
  local anon_key
  anon_key=$(echo "$env_status" | grep "ANON_KEY=" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
  local service_role_key
  service_role_key=$(echo "$env_status" | grep "SERVICE_ROLE_KEY=" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
  local api_url="http://127.0.0.1:54321"
  local studio_url="http://127.0.0.1:54323"

  # Auto-sync local keys into .env and website/.env.local
  if [ -n "$anon_key" ]; then
    if grep -q "SUPABASE_PUBLISHABLE_KEY_LOCAL=" "$REPO_ROOT/.env"; then
      sed -i '' "s|SUPABASE_PUBLISHABLE_KEY_LOCAL=.*|SUPABASE_PUBLISHABLE_KEY_LOCAL=$anon_key|" "$REPO_ROOT/.env"
    fi
    if grep -q "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=" "$REPO_ROOT/website/.env.local"; then
      sed -i '' "s|NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=.*|NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$anon_key|" "$REPO_ROOT/website/.env.local"
    fi
  fi
  if [ -n "$service_role_key" ]; then
    if grep -q "SUPABASE_SERVICE_ROLE_KEY=" "$REPO_ROOT/website/.env.local"; then
      sed -i '' "s|SUPABASE_SERVICE_ROLE_KEY=.*|SUPABASE_SERVICE_ROLE_KEY=$service_role_key|" "$REPO_ROOT/website/.env.local"
    fi
  fi

  success "Supabase started & keys synchronized."

  # 2. Start Supabase Edge Functions
  info "Starting Supabase Edge Functions (livekit-token, media-share, cleanup-r2)..."
  nohup supabase functions serve --env-file "$REPO_ROOT/supabase/functions/.env" > "$FUNCTIONS_LOG" 2>&1 &
  echo $! > "$FUNCTIONS_PID_FILE"
  success "Edge Functions running (Log: $FUNCTIONS_LOG)"

  # 3. Start Next.js Website & Billing Portal
  info "Starting Next.js Website & Billing Portal..."
  if [ ! -d "$REPO_ROOT/website/node_modules" ]; then
    info "Installing website dependencies (npm install)..."
    (cd "$REPO_ROOT/website" && npm install --silent)
  fi
  (cd "$REPO_ROOT/website" && nohup npm run dev > "$WEBSITE_LOG" 2>&1 & echo $! > "$WEBSITE_PID_FILE")
  
  # Wait briefly for Next.js to start listening
  local count=0
  while ! lsof -i :3000 >/dev/null 2>&1 && [ $count -lt 15 ]; do
    sleep 1
    count=$((count+1))
  done
  success "Next.js Website running on http://localhost:3000 (Log: $WEBSITE_LOG)"

  # 4. Optional Webhook Tunnel (Hookdeck or Paddle CLI)
  local tunnel_name="None"
  if [ "$launch_tunnel" = true ]; then
    if command -v hookdeck &>/dev/null; then
      info "Starting Hookdeck webhook tunnel for Paddle -> http://localhost:3000/api/paddle/webhook..."
      nohup hookdeck listen 3000 synctogether-webhooks --path /api/paddle/webhook > "$TUNNEL_LOG" 2>&1 &
      echo $! > "$TUNNEL_PID_FILE"
      tunnel_name="Hookdeck"
      success "Hookdeck tunnel running (Log: $TUNNEL_LOG)"
    elif command -v paddle &>/dev/null; then
      info "Starting Paddle CLI webhook tunnel -> http://localhost:3000/api/paddle/webhook..."
      nohup paddle webhook:listen --url http://localhost:3000/api/paddle/webhook > "$TUNNEL_LOG" 2>&1 &
      echo $! > "$TUNNEL_PID_FILE"
      tunnel_name="Paddle CLI"
      success "Paddle CLI tunnel running (Log: $TUNNEL_LOG)"
    else
      warn "Neither Hookdeck nor Paddle CLI found. Install via 'brew install hookdeck/hookdeck/hookdeck' to tunnel webhooks."
    fi
  fi

  # 5. Dashboard Summary
  echo -e "\n${BOLD}${GREEN}✨ SyncTogether Development Ecosystem is LIVE! ✨${NC}\n"
  echo -e "  🌐 ${BOLD}Website & Billing:${NC}      http://localhost:3000"
  echo -e "  🗄️ ${BOLD}Supabase Studio:${NC}        $studio_url"
  echo -e "  ⚡ ${BOLD}Supabase API:${NC}           $api_url"
  echo -e "  📧 ${BOLD}Local Inbucket Mail:${NC}    http://127.0.0.1:54324"
  echo -e "  📜 ${BOLD}Edge Functions Log:${NC}     $FUNCTIONS_LOG"
  echo -e "  📜 ${BOLD}Website Dev Log:${NC}        $WEBSITE_LOG"
  if [ "$launch_tunnel" = true ] && [ "$tunnel_name" != "None" ]; then
    echo -e "  🪝 ${BOLD}Webhook Tunnel Log:${NC}    $TUNNEL_LOG ($tunnel_name)"
  fi
  echo -e "\n${BOLD}${CYAN}Available Dev Commands:${NC}"
  echo -e "  • Primary Flutter Client (A):  ${YELLOW}fvm flutter run -d macos${NC} (or ./scripts/dev.sh -f)"
  echo -e "  • Second Isolated Client (B):  ${YELLOW}./scripts/pt-instance-b.sh${NC} (or ./scripts/dev.sh -b)"
  echo -e "  • Run All Test Suites:         ${YELLOW}./scripts/dev.sh test${NC}"
  echo -e "  • Reset Local Database:        ${YELLOW}./scripts/dev.sh reset${NC}"
  echo -e "  • Spin Down Everything:        ${YELLOW}./scripts/dev.sh down${NC}"
  echo -e "  • View Realtime Logs:          ${YELLOW}./scripts/dev.sh logs${NC}\n"

  # Optional client launches
  if [ "$launch_instance_b" = true ]; then
    info "Launching secondary isolated instance (Instance B)..."
    ./scripts/pt-instance-b.sh &
  fi

  if [ "$launch_flutter" = true ]; then
    info "Launching primary Flutter client (Instance A)..."
    fvm flutter run -d macos
  fi
}

# ------------------------------------------------------------------------------
# Status
# ------------------------------------------------------------------------------
status() {
  banner "SyncTogether Ecosystem Status"

  # Supabase
  if docker ps --filter "name=supabase_db_synctogether" --format "{{.Names}}" | grep -q "supabase_db"; then
    success "Supabase Local Stack: RUNNING (Studio: http://127.0.0.1:54323)"
  else
    warn "Supabase Local Stack: STOPPED"
  fi

  # Functions
  if [ -f "$FUNCTIONS_PID_FILE" ] && ps -p "$(cat "$FUNCTIONS_PID_FILE")" > /dev/null 2>&1; then
    success "Edge Functions:       RUNNING (PID: $(cat "$FUNCTIONS_PID_FILE"))"
  else
    warn "Edge Functions:       STOPPED"
  fi

  # Website
  if lsof -i :3000 >/dev/null 2>&1; then
    success "Next.js Website:      RUNNING (http://localhost:3000)"
  else
    warn "Next.js Website:      STOPPED"
  fi

  # Webhook Tunnel
  if [ -f "$TUNNEL_PID_FILE" ] && ps -p "$(cat "$TUNNEL_PID_FILE")" > /dev/null 2>&1; then
    success "Webhook Tunnel:       RUNNING (PID: $(cat "$TUNNEL_PID_FILE"))"
  else
    info "Webhook Tunnel:       INACTIVE (pass --hookdeck on spin up to enable)"
  fi
  echo ""
}

# ------------------------------------------------------------------------------
# Test Runner (All 3 suites)
# ------------------------------------------------------------------------------
run_tests() {
  banner "Running SyncTogether Full Test Suite"

  info "1/3 Running Flutter Dart & Sync tests..."
  fvm flutter test

  info "2/3 Running Supabase Database & Security Policy tests (pgTAP)..."
  supabase test db

  info "3/3 Running Website & Paddle Webhook tests..."
  npm --prefix website test

  success "All test suites passed successfully!"
}

# ------------------------------------------------------------------------------
# DB Reset
# ------------------------------------------------------------------------------
reset_db() {
  banner "Resetting Local Database"
  info "Applying all migrations and re-seeding..."
  supabase db reset
  success "Database reset completed."
}

# ------------------------------------------------------------------------------
# Logs Viewer
# ------------------------------------------------------------------------------
view_logs() {
  local target="${1:-all}"
  if [[ "$target" == "website" || "$target" == "web" ]]; then
    tail -f "$WEBSITE_LOG"
  elif [[ "$target" == "functions" || "$target" == "func" ]]; then
    tail -f "$FUNCTIONS_LOG"
  elif [[ "$target" == "tunnel" || "$target" == "hookdeck" || "$target" == "hook" ]]; then
    tail -f "$TUNNEL_LOG"
  else
    echo -e "${CYAN}Tailing Website & Functions logs (Ctrl+C to exit)...${NC}\n"
    tail -f "$WEBSITE_LOG" "$FUNCTIONS_LOG"
  fi
}

# ------------------------------------------------------------------------------
# Main Dispatcher
# ------------------------------------------------------------------------------
COMMAND="${1:-up}"

case "$COMMAND" in
  up|start|restart)
    shift || true
    spin_up "$@"
    ;;
  down|stop)
    spin_down
    ;;
  status)
    status
    ;;
  test)
    run_tests
    ;;
  reset)
    reset_db
    ;;
  logs)
    shift
    view_logs "$@"
    ;;
  --flutter|-f|--instance-b|-b|--hookdeck|--tunnel|-w)
    spin_up "$@"
    ;;
  help|-h|--help)
    echo -e "SyncTogether Dev Ecosystem Script\n"
    echo -e "Usage:"
    echo -e "  ./scripts/dev.sh [command] [flags]\n"
    echo -e "Commands:"
    echo -e "  up | start | restart    (Default) Spin down existing instances, then spin all services up"
    echo -e "  down | stop             Spin down all local services, desktop apps, and free all ports"
    echo -e "  status                  Show running status of Supabase, Functions, Web app, Tunnel"
    echo -e "  test                    Run all test suites (Flutter Dart, Supabase pgTAP, Webhook)"
    echo -e "  reset                   Reset local database (re-applies all migrations and seed.sql)"
    echo -e "  logs [web|func|tunnel]  Tail real-time logs of background services"
    echo -e "  help                    Show this help message\n"
    echo -e "Flags (can be used with 'up' or standalone):"
    echo -e "  --flutter, -f           Launch primary Flutter desktop client"
    echo -e "  --instance-b, -b        Launch secondary isolated Flutter desktop client"
    echo -e "  --hookdeck, -w          Start Paddle webhook tunnel (Hookdeck or Paddle CLI)\n"
    ;;
  *)
    error "Unknown command: $1"
    echo "Run './scripts/dev.sh help' for usage."
    exit 1
    ;;
esac
