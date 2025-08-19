#!/usr/bin/env bash
# Test suite for commit-msg hook

set -euo pipefail

HOOK="./scripts/git-hooks/commit-msg"
TEMP_FILE="/tmp/test_commit_msg_$$"
PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

test_case() {
    local name="$1"
    local message="$2"
    local expected="$3"  # "pass" or "fail"
    
    echo -e "$message" > "$TEMP_FILE"
    
    if $HOOK "$TEMP_FILE" >/dev/null 2>&1; then
        actual="pass"
    else
        actual="fail"
    fi
    
    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} $name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $name (expected $expected, got $actual)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # Show the actual error for debugging
        $HOOK "$TEMP_FILE" 2>&1 | sed 's/^/    /' || true
    fi
}

echo "Testing commit-msg hook..."
echo

# Valid messages
test_case "Simple one-line commit" \
    "Fix bug in authentication flow" \
    "pass"

test_case "Multi-line with proper blank line" \
    "Add new feature for user dashboard\n\nThis adds a comprehensive dashboard that shows user statistics\nand activity history." \
    "pass"

test_case "With bullet points" \
    "Update dependencies\n\n- Upgrade React to v18\n- Fix security vulnerabilities\n- Remove deprecated packages" \
    "pass"

test_case "With template comments (should ignore #)" \
    "Fix memory leak in worker process\n\n# This is a comment\nActual body text here\n# Another comment" \
    "pass"

test_case "Merge commit (should skip validation)" \
    "Merge branch 'feature/new-api' into main" \
    "pass"

test_case "Revert commit (should skip validation)" \
    "Revert \"Breaking change that caused issues\"" \
    "pass"

# Invalid messages
test_case "Empty message" \
    "" \
    "fail"

test_case "Only comments (effectively empty)" \
    "# Just a comment\n# Another comment" \
    "fail"

test_case "Subject too long (>72 chars)" \
    "This is a really long commit message subject that exceeds the seventy-two character limit" \
    "fail"

test_case "Subject ends with period" \
    "Add new feature." \
    "fail"

test_case "Subject starts with lowercase" \
    "add new feature" \
    "fail"

test_case "Missing blank line between subject and body" \
    "Add new feature\nThis is the body without blank line separation" \
    "fail"

test_case "Body line too long" \
    "Add new feature\n\nThis is a body line that is way too long and exceeds the seventy-two character limit that we have established for commit message bodies" \
    "fail"

# Edge cases
test_case "Subject exactly 72 chars" \
    "This commit message subject is exactly seventy-two characters long now" \
    "pass"

test_case "Windows line endings (CRLF)" \
    "Fix bug in parser\r\n\r\nThis tests Windows line endings\r\n" \
    "pass"

test_case "Mixed line endings" \
    "Fix bug\n\r\nMixed endings here\r\n" \
    "pass"

test_case "Trailing empty lines (should be OK)" \
    "Fix bug\n\nBody text\n\n\n" \
    "pass"

test_case "URL in body (should allow >72 chars)" \
    "Add documentation\n\nSee: https://github.com/very/long/url/that/exceeds/seventy/two/characters/but/should/be/allowed" \
    "pass"

# Cleanup
rm -f "$TEMP_FILE"

echo
echo "========================================="
echo "Results: ${GREEN}$PASS_COUNT passed${NC}, ${RED}$FAIL_COUNT failed${NC}"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi