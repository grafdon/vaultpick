# shellcheck shell=sh disable=SC2154
# Sourced by the tests and the demo: a throwaway home with the stub rbw, the
# demo vault and a matching rbw cache (for the TOTP markers).
# Needs $root (repository) and $tmp (scratch directory).
PATH="$root/tests/stubs:$PATH"
export PATH
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
	XDG_CONFIG_HOME="$tmp/config"
export STUB_CLIP="$tmp/clipboard" RBW_STUB_LOG="$tmp/rbw.log"
unset _VAULTPICK_NOTE _VAULTPICK_ACTION RBW_PROFILE VAULTPICK_THEME VAULTPICK_RECENT VAULTPICK_CLEAR VAULTPICK_CLIPBOARD \
	VAULTPICK_ASCII VAULTPICK_PASS_LAYOUT NO_COLOR RBW_STUB_VAULT RBW_STUB_VERSION 2>/dev/null || :
mkdir -p "$HOME" "$XDG_CACHE_HOME/rbw"
: >"$STUB_CLIP"
jq '{entries: [.[] | {id, data: {Login: {totp: (if .data.totp then "2.encrypted" else null end)}}}]}' \
	"$root/tests/fixtures/vault.json" >"$XDG_CACHE_HOME/rbw/https%3A%2F%2Fvault.example.com:demo@example.com.json"
