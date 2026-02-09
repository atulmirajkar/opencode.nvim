#!/bin/bash
set -e

echo "════════════════════════════════════════"
echo "OpenCode.nvim - Running Tests"
echo "════════════════════════════════════════"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
if [ -z "$TMUX" ]; then
  echo -e "${YELLOW}⚠️  WARNING: Not in tmux session${NC}"
  echo "   Some tests will be skipped"
  echo "   Run 'tmux' first for full test coverage"
  echo ""
fi

# Check if nvim is available
if ! command -v nvim &> /dev/null; then
  echo "❌ ERROR: nvim not found in PATH"
  exit 1
fi

# Run unit tests
echo "→ Running unit tests (tmux_util_spec.lua)..."
echo ""
if nvim --headless -u tests/minimal_init.lua \
  -c "luafile tests/tmux_util_spec.lua" \
  2>&1; then
  echo ""
  echo -e "${GREEN}✓ Unit tests passed${NC}"
else
  echo ""
  echo "❌ Unit tests failed"
  exit 1
fi

echo ""
echo "────────────────────────────────────────"
echo ""

# Run integration tests
echo "→ Running integration tests (orphan_cleanup_integration_spec.lua)..."
echo ""
if nvim --headless -u tests/minimal_init.lua \
  -c "luafile tests/orphan_cleanup_integration_spec.lua" \
  2>&1; then
  echo ""
  echo -e "${GREEN}✓ Integration tests passed${NC}"
else
  echo ""
  echo "❌ Integration tests failed"
  exit 1
fi

echo ""
echo "════════════════════════════════════════"
echo -e "${GREEN}✅ All test suites completed successfully${NC}"
echo "════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  ✓ Unit tests (tmux_util)"
echo "  ✓ Integration tests (orphan cleanup)"
echo ""
