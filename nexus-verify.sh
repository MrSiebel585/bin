#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/opt/offensive"
FRONTEND="$ROOT/gui/frontend"
BACKEND="$ROOT/gui/backend"
REPORT_DIR="$ROOT/reports/nexus-verification"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/verification-$TIMESTAMP.log"

START_SERVICES=false
FAILURES=0
WARNINGS=0

for arg in "$@"; do
    case "$arg" in
        --start) START_SERVICES=true ;;
        --help|-h)
            echo "Usage: $0 [--start]"
            echo "  Default: verify controller, modules, build and API routes"
            echo "  --start: additionally launch backend and frontend"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$REPORT_DIR"
exec > >(tee -a "$REPORT") 2>&1

ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; WARNINGS=$((WARNINGS+1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAILURES=$((FAILURES+1)); }

echo "=========================================="
echo " OFFENSIVECTL NEXUS — PHASE 1 VERIFICATION"
echo "=========================================="
echo "Date: $(date)"
echo "Root: $ROOT"
echo "Report: $REPORT"
echo

echo "=== 1. CONTROLLER INTEGRITY ==="

if [[ -L /usr/local/bin/offensivectl ]] &&
   [[ "$(readlink -f /usr/local/bin/offensivectl)" == "$ROOT/offensivectl" ]]; then
    ok "Global launcher points to workspace"
else
    fail "Global launcher does not point to workspace"
fi

if [[ -f /usr/local/libexec/offensivectl.real ]] &&
   cmp -s "$ROOT/offensivectl" /usr/local/libexec/offensivectl.real; then
    ok "Installed controller matches workspace"
else
    fail "Installed controller differs from workspace"
fi

echo
echo "=== 2. OFFENSIVECTL HEALTH ==="

DOCTOR_OUTPUT="$(mktemp)"
if "$ROOT/offensivectl" doctor >"$DOCTOR_OUTPUT" 2>&1; then
    cat "$DOCTOR_OUTPUT"
    if grep -q '^Failures: 0$' "$DOCTOR_OUTPUT"; then
        ok "Doctor reports zero failures"
    else
        warn "Doctor did not explicitly report zero failures"
    fi
else
    cat "$DOCTOR_OUTPUT"
    fail "Doctor command failed"
fi
rm -f "$DOCTOR_OUTPUT"

echo
echo "=== 3. FRONTEND BUILD ==="

if [[ -f "$FRONTEND/package.json" ]] &&
   command -v npm >/dev/null 2>&1; then
    if (cd "$FRONTEND" && npm run build); then
        ok "React/Vite production build passed"
    else
        fail "React/Vite production build failed"
    fi
else
    fail "Frontend package.json or npm missing"
fi

echo
echo "=== 4. FRONTEND API REFERENCES ==="

if [[ -f "$FRONTEND/src/main.jsx" ]]; then
    grep -nE '/api/|fetch\(' "$FRONTEND/src/main.jsx" || true
else
    fail "Frontend main.jsx missing"
fi

echo
echo "=== 5. BACKEND API ROUTES ==="

if [[ -f "$BACKEND/app/main.py" ]]; then
    grep -n -A 5 -B 2 \
        -E '@app\.(get|post|put|delete)' \
        "$BACKEND/app/main.py" || true
else
    fail "Backend main.py missing"
fi

echo
echo "=== 6. SERVICE LAUNCHERS ==="

for script in "$BACKEND/run.sh" "$FRONTEND/run.sh"; do
    if [[ -x "$script" ]]; then
        ok "Executable: $script"
    else
        fail "Missing or non-executable: $script"
    fi
done

echo
echo "=== 7. OPTIONAL SERVICE STARTUP ==="

if [[ "$START_SERVICES" == true ]]; then
    if [[ -x "$BACKEND/run.sh" && -x "$FRONTEND/run.sh" ]]; then
        echo "Starting backend and frontend..."
        echo "Services will run until Ctrl+C."

        (
            cd "$BACKEND"
            ./run.sh
        ) &
        BACKEND_PID=$!

        (
            cd "$FRONTEND"
            ./run.sh
        ) &
        FRONTEND_PID=$!

        cleanup() {
            echo
            echo "Stopping NEXUS launch processes..."
            kill "$BACKEND_PID" "$FRONTEND_PID" 2>/dev/null || true
            wait "$BACKEND_PID" "$FRONTEND_PID" 2>/dev/null || true
        }
        trap cleanup EXIT INT TERM

        wait -n "$BACKEND_PID" "$FRONTEND_PID" || true
    else
        fail "Cannot start services: launcher missing"
    fi
fi

echo
echo "=========================================="
echo " VERIFICATION SUMMARY"
echo "=========================================="
echo "Failures: $FAILURES"
echo "Warnings: $WARNINGS"
echo "Report: $REPORT"

if (( FAILURES > 0 )); then
    exit 1
fi

exit 0
