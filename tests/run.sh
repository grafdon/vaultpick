#!/bin/sh
# shellcheck disable=SC2016 # fzf commands are compared literally
# Tests for vaultpick. rbw, the clipboard tools and fzf are replaced by the
# stand-ins in tests/stubs*, so no real vault or clipboard is touched.
#
#   tests/run.sh                    run with every POSIX shell that is installed
#   TEST_SHELLS='dash' tests/run.sh  run with the given shells only
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
real_fzf=$(command -v fzf 2>/dev/null || :)
esc=$(printf '\033')
results=$(mktemp)
trap 'rm -f "$results"' EXIT

pass() { printf 'ok\n' >>"$results"; }
fail() {
	printf 'FAIL\n' >>"$results"
	printf '  FAIL [%s] %s\n' "$shell_name" "$1" >&2
	[ $# -lt 2 ] || printf '%s\n' "$2" | sed 's/^/       /' | head -n 12 >&2
}
is() { # description, actual, expected
	if [ "$2" = "$3" ]; then pass; else fail "$1" "got:      $2
expected: $3"; fi
}
contains() { # description, text, needle
	case "$2" in *"$3"*) pass ;; *) fail "$1" "missing '$3' in: $2" ;; esac
}
lacks() { # description, text, needle
	case "$2" in *"$3"*) fail "$1" "unexpected '$3' in: $2" ;; *) pass ;; esac
}
plain() { sed "s/$esc\[[0-9;]*m//g"; }
id() { printf '00000000-0000-4000-8000-%012d' "$1"; }
line_of() { grep "^$(id "$1")	" "$STUB_FZF_OUT" | cut -f 2 | plain; }
# Control characters other than the tab and newline that structure the list
controls() { tr -d '\t\n' | LC_ALL=C tr -cd '\000-\037\177' | wc -c | tr -d ' '; }

suite() {
	tmp=$(mktemp -d)
	# shellcheck disable=SC1091
	. "$root/tests/env.sh"
	PATH="$root/tests/stubs-fzf:$PATH"
	export STUB_FZF_OUT="$tmp/list" COLUMNS=140 VAULTPICK_ASCII=0 WAYLAND_DISPLAY=test
	unset DISPLAY TERMUX_VERSION STUB_FZF_VERSION STUB_FZF_REAL STUB_WL_OLD 2>/dev/null || :
	history="$XDG_STATE_HOME/vaultpick/history"
	# shellcheck disable=SC2086 # "busybox sh" is two words
	vp() { $shell "$root/vaultpick" "$@"; }

	# --- the list ---
	err=$(vp 2>&1)
	is 'closing the list exits 0' "$?" 0
	is 'a first run is silent' "$err" ''
	is 'one line per entry' "$(wc -l <"$STUB_FZF_OUT" | tr -d ' ')" 12
	is 'every line is id <tab> text' "$(awk -F '\t' 'NF != 2' "$STUB_FZF_OUT" | wc -l | tr -d ' ')" 0
	is 'sorted by folder, then name' "$(sed -n 1p "$STUB_FZF_OUT" | cut -f 1)" "$(id 10)"
	is 'no recent marker without history' "$(grep -c '↺' "$STUB_FZF_OUT")" 0
	is 'TOTP marker from the rbw cache' "$(grep -c '● totp' "$STUB_FZF_OUT")" 4
	contains 'first URL host plus count' "$(line_of 3)" 'banking.example.com +1'
	contains 'www. is dropped from the host' "$(line_of 10)" ' streaming.example '
	contains 'columns are aligned' "$(line_of 1)" '  GitHub                      octo-demo                       ● totp  github.com                  dev'
	contains 'key bar names the enter action' "$(plain <"$STUB_FZF_OUT.args")" ' enter  password'
	contains 'fzf uses sh for its commands' "$(tr '\n' ' ' <"$STUB_FZF_OUT.args")" '--with-shell sh -c '

	# --- recently used first ---
	mkdir -p "${history%/*}"
	printf '%s\n' "$(id 5)" gone-entry "$(id 7)" >"$history"
	vp
	is 'most recent entry first' "$(sed -n 1p "$STUB_FZF_OUT" | cut -f 1)" "$(id 5)"
	is 'then the one before, deleted IDs skipped' "$(sed -n 2p "$STUB_FZF_OUT" | cut -f 1)" "$(id 7)"
	is 'recent entries are marked' "$(grep -c '↺' "$STUB_FZF_OUT")" 2
	is 'the rest follows unmarked' "$(sed -n 3p "$STUB_FZF_OUT" | cut -f 1)" "$(id 10)"
	VAULTPICK_RECENT=1 vp
	is 'VAULTPICK_RECENT limits the block' "$(grep -c '↺' "$STUB_FZF_OUT")" 1
	VAULTPICK_RECENT=0 vp
	is 'VAULTPICK_RECENT=0 turns it off' "$(grep -c '↺' "$STUB_FZF_OUT")" 0
	rm -f "$history"

	# --- options ---
	vp -o apple id
	args=$(cat "$STUB_FZF_OUT.args")
	contains 'the query is passed on' "$args" '--query
apple id'
	contains '-o makes enter copy the TOTP code' "$args" 'enter:transform-footer("$_VAULTPICK_SELF" __copy totp {1})'
	contains '-o is shown in the key bar' "$(printf '%s' "$args" | plain)" ' enter  totp'
	vp -e
	contains '-e makes enter edit' "$(cat "$STUB_FZF_OUT.args")" 'enter:become("$_VAULTPICK_SELF" __edit {1})'
	out=$(vp -h)
	contains '-h shows the usage' "$out" 'vaultpick [query]'
	contains '-h shows the whole header' "$out" 'Requires rbw'
	contains '-h mentions the setup check' "$out" 'vaultpick -c'
	lacks '-h stops before the code' "$out" 'set -eu'
	contains '-V shows the version' "$(vp -V)" 'vaultpick 0.'
	vp --nonsense 2>/dev/null
	is 'unknown options are rejected' "$?" 1
	out=$(STUB_FZF_VERSION=0.44.0 vp 2>&1)
	is 'an old fzf is rejected' "$?" 1
	contains 'with a clear message' "$out" 'fzf 0.63 or newer is needed, found 0.44'

	# --- look ---
	NO_COLOR=1 vp
	is 'NO_COLOR: no escape sequences in the list' "$(grep -c "$esc" "$STUB_FZF_OUT")" 0
	is 'NO_COLOR: none in the fzf arguments' "$(grep -c "$esc" "$STUB_FZF_OUT.args")" 0
	NO_COLOR=1 VAULTPICK_ASCII=1 vp
	is 'ASCII mode: no fancy glyphs' "$(grep -v 'Züri' "$STUB_FZF_OUT" | LC_ALL=C grep -c '[^ -~	]')" 0
	contains 'ASCII mode: plain fzf frame' "$(cat "$STUB_FZF_OUT.args")" '--no-unicode'
	VAULTPICK_THEME=nope vp 2>/dev/null
	is 'unknown themes are rejected' "$?" 1
	COLUMNS=60 vp
	is 'narrow terminal: columns shrink' "$(line_of 1 | cut -c 1-24)" '  GitHub       octo-demo'
	contains 'narrow terminal: long values are cut' "$(line_of 3)" 'Example Ba…'
	vp
	contains 'default layout shows the entry name' "$(line_of 11)" '  jane   '
	VAULTPICK_PASS_LAYOUT=1 vp
	contains 'pass layout shows the domain folder' "$(line_of 11)" '  forum.example.org           jane  '

	# --- themes: ctrl-t and the remembered choice ---
	saved="$XDG_CONFIG_HOME/vaultpick/theme"
	vp
	contains 'ctrl-t is bound' "$(cat "$STUB_FZF_OUT.args")" 'ctrl-t:become("$_VAULTPICK_SELF" __theme {q})'
	contains 'ctrl-t is in the key bar' "$(plain <"$STUB_FZF_OUT.args")" ' ^t  theme'
	NO_COLOR=1 vp
	lacks 'NO_COLOR: no theme key' "$(cat "$STUB_FZF_OUT.args")" 'ctrl-t'
	_VAULTPICK_ACTION=totp vp __theme 'apple id'
	args=$(cat "$STUB_FZF_OUT.args")
	is 'ctrl-t saves the next theme' "$(cat "$saved")" amber
	contains 'ctrl-t switches the colours' "$args" '#ffc720'
	contains 'ctrl-t keeps the query' "$args" '--query
apple id'
	contains 'ctrl-t keeps the action' "$args" 'enter:transform-footer("$_VAULTPICK_SELF" __copy totp {1})'
	contains 'ctrl-t names the theme in the status line' "$(printf '%s' "$args" | plain)" ' ✓ THEME   amber '
	vp __theme ''
	is 'ctrl-t again: the one after' "$(cat "$saved")" mocha
	contains 'an empty query stays empty' "$(cat "$STUB_FZF_OUT.args")" '--query
'
	vp __theme -o
	is 'ctrl-t a third time' "$(cat "$saved")" latte
	contains 'a query that looks like an option stays a query' "$(cat "$STUB_FZF_OUT.args")" '--query
-o'
	echo tokyonight >"$saved"
	vp __theme ''
	is 'ctrl-t goes round after the last theme' "$(cat "$saved")" ansi
	vp
	lacks 'the theme note is shown once' "$(cat "$STUB_FZF_OUT.args")" 'THEME'
	echo amber >"$saved"
	VAULTPICK_THEME=mocha vp
	contains 'the saved theme wins over VAULTPICK_THEME' "$(cat "$STUB_FZF_OUT.args")" '#ffc720'
	contains 'check: names the saved theme' "$(vp --check)" 'look: theme amber (picked with ctrl-t)'
	echo 'no such theme' >"$saved"
	VAULTPICK_THEME=mocha vp
	contains 'a broken theme file is ignored' "$(cat "$STUB_FZF_OUT.args")" '#cba6f7'
	contains 'palette: hex becomes an RGB sequence' "$(cat "$STUB_FZF_OUT")" "${esc}[38;2;205;214;244m"
	rm -f "$saved"
	: >"$tmp/blocker"
	XDG_CONFIG_HOME="$tmp/blocker" vp __theme ''
	contains 'a theme that cannot be saved: says so' "$(plain <"$STUB_FZF_OUT.args")" 'could not save the theme'

	# --- hostile entry data ---
	RBW_STUB_VAULT="$root/tests/fixtures/hostile.json" NO_COLOR=1 vp
	is 'hostile data: still one line per entry' "$(wc -l <"$STUB_FZF_OUT" | tr -d ' ')" 2
	is 'hostile data: still one tab per line' "$(awk -F '\t' 'NF != 2' "$STUB_FZF_OUT" | wc -l | tr -d ' ')" 0
	is 'hostile data: control characters removed' "$(controls <"$STUB_FZF_OUT")" 0
	is 'hostile data: C1 controls removed' "$(grep -c "$(printf '\302\233')" "$STUB_FZF_OUT")" 0
	out=$(RBW_STUB_VAULT="$root/tests/fixtures/hostile.json" NO_COLOR=1 vp __preview "$(id 1)")
	is 'hostile data: clean preview' "$(printf '%s' "$out" | controls)" 0
	out=$(RBW_STUB_VAULT="$root/tests/fixtures/hostile.json" NO_COLOR=1 vp __copy password "$(id 1)")
	is 'hostile data: clean status line' "$(printf '%s' "$out" | controls)" 0

	# --- copying ---
	out=$(vp __copy password "$(id 1)")
	is 'password is on the clipboard' "$(cat "$STUB_CLIP")" 'demo-pw-github'
	contains 'marked sensitive under Wayland' "$(cat "$STUB_CLIP.flags")" '--sensitive'
	contains 'status line: what' "$out" 'PASSWORD'
	contains 'status line: which entry' "$out" 'GitHub'
	contains 'status line: hint' "$out" 'clears in 45 s, kept out of clipboard history'
	lacks 'status line never shows the value' "$out" 'demo-pw'
	is 'the entry is remembered' "$(sed -n 1p "$history")" "$(id 1)"
	# shellcheck disable=SC2012 # the mode string is all we want
	is 'history is private' "$(ls -l "$history" | cut -c 1-10)" '-rw-------'
	out=$(STUB_WL_OLD=1 vp __copy password "$(id 2)")
	is 'old wl-copy without --sensitive still copies' "$(cat "$STUB_CLIP")" 'demo-pw-gitlab'
	lacks 'and does not claim to hide it' "$out" 'kept out'
	vp __copy totp "$(id 1)" >/dev/null
	is 'TOTP code is on the clipboard' "$(cat "$STUB_CLIP")" '123456'
	is 'used entries move to the front, once' "$(tr '\n' ' ' <"$history")" "$(id 1) $(id 2) "
	out=$(vp __copy totp "$(id 4)")
	contains 'entry without TOTP: says so' "$out" 'no totp in this entry'
	is 'entry without TOTP: clipboard untouched' "$(cat "$STUB_CLIP")" '123456'
	is 'entry without TOTP: not remembered' "$(grep -c "$(id 4)" "$history")" 0
	contains 'entry without username: says so' "$(vp __copy username "$(id 9)")" 'no username in this entry'
	vp __copy username "$(id 12)" >/dev/null
	is 'non-ASCII values survive' "$(cat "$STUB_CLIP")" 'jäne'
	contains 'VAULTPICK_CLEAR=0 keeps the value' "$(VAULTPICK_CLEAR=0 vp __copy password "$(id 1)")" 'not cleared automatically'

	# --- other clipboard tools, and clearing ---
	for tool in wayland xclip xsel macos termux; do
		STUB_CLIP="$tmp/clip-$tool" VAULTPICK_CLIPBOARD=$tool VAULTPICK_CLEAR=1 vp __copy password "$(id 3)" >/dev/null
		is "$tool: copies" "$(cat "$tmp/clip-$tool")" 'demo-pw-bank'
	done
	STUB_CLIP="$tmp/clip-other" VAULTPICK_CLEAR=1 vp __copy password "$(id 3)" >/dev/null
	printf 'something else' >"$tmp/clip-other"
	out=$(STUB_CLIP="$tmp/clip-wsl" VAULTPICK_CLIPBOARD=wsl vp __copy password "$(id 3)")
	is 'wsl: copies' "$(cat "$tmp/clip-wsl")" 'demo-pw-bank'
	contains 'wsl: honest about not clearing' "$out" 'not cleared automatically'
	: >"$RBW_STUB_LOG"
	out=$(VAULTPICK_CLIPBOARD=rbw vp __copy totp "$(id 1)")
	contains 'rbw fallback: rbw copies' "$(cat "$RBW_STUB_LOG")" "code --clipboard $(id 1)"
	contains 'rbw fallback: says so' "$out" 'via rbw'
	VAULTPICK_CLIPBOARD=nope vp __copy password "$(id 1)" >/dev/null 2>&1
	is 'unknown clipboard tool is rejected' "$?" 1
	sleep 3
	for tool in wayland xclip xsel macos termux; do
		is "$tool: cleared after the timeout" "$(cat "$tmp/clip-$tool")" ''
	done
	is 'a clipboard changed meanwhile is left alone' "$(cat "$tmp/clip-other")" 'something else'

	# --- setup check and first run ---
	out=$(vp --check)
	is 'check: all good exits 0' "$?" 0
	contains 'check: rbw' "$out" 'ok    rbw 0.0.0'
	contains 'check: fzf' "$out" 'ok    fzf 0.74'
	contains 'check: account' "$out" 'ok    rbw account is configured'
	contains 'check: unlocked' "$out" 'ok    vault is unlocked'
	contains 'check: clipboard' "$out" 'ok    clipboard: wl-copy, cleared after 45 s, kept out of the clipboard history'
	contains 'check: TOTP markers' "$out" 'ok    TOTP markers: available'
	contains 'check: verdict' "$out" 'Everything needed is in place.'
	lacks 'check: says nothing about the account' "$out" 'example.com'
	out=$(STUB_FZF_VERSION=0.44.0 vp -c)
	is 'check: old fzf exits 1' "$?" 1
	contains 'check: old fzf is named' "$out" 'FAIL  fzf 0.44 is too old, 0.63 or newer is needed'
	out=$(RBW_STUB_CONFIG='{"email": null, "base_url": null, "pinentry": "sh"}' vp --check)
	is 'check: no account exits 1' "$?" 1
	contains 'check: no account, with the fix' "$out" '      rbw login'
	out=$(RBW_STUB_CONFIG='{"email": "a@example.com", "pinentry": "no-such-pinentry"}' vp --check)
	is 'check: missing pinentry exits 1' "$?" 1
	contains 'check: missing pinentry is named' "$out" "FAIL  pinentry program 'no-such-pinentry' not found"
	contains 'check: unknown account data is a warning' "$out" 'warn  TOTP markers: rbw cache not found'
	out=$(RBW_STUB_LOCKED=1 vp --check)
	is 'check: a locked vault is fine' "$?" 0
	contains 'check: locked vault is named' "$out" 'ok    logged in, vault is locked'
	out=$(VAULTPICK_CLIPBOARD=rbw vp --check)
	is 'check: rbw clipboard is only a warning' "$?" 0
	contains 'check: rbw clipboard warning' "$out" 'warn  clipboard: no clipboard tool found'
	contains 'check: old wl-clipboard' "$(STUB_WL_OLD=1 vp --check)" 'warn  wl-clipboard 2.2 or newer'
	VAULTPICK_CLIPBOARD=nope vp --check >/dev/null
	is 'check: unknown clipboard tool exits 1' "$?" 1
	out=$(RBW_STUB_CONFIG='{"email": null}' vp 2>&1)
	is 'first run without an account exits 1' "$?" 1
	contains 'first run: says how to set up rbw' "$out" 'rbw config set email you@example.com'
	out=$(RBW_STUB_UNLOCK_FAIL=1 vp 2>&1)
	is 'failed unlock exits 1' "$?" 1
	contains 'failed unlock: points to rbw login and --check' "$out" 'vaultpick --check'

	# --- preview, show, edit ---
	out=$(vp __preview "$(id 3)" | plain)
	contains 'preview: name and user' "$out" 'Example Bank  1234567  finance  ● totp'
	contains 'preview: every URL' "$out" 'https://www.example.com/bank'
	lacks 'preview: no secrets' "$out" 'demo-pw'
	contains 'show prints the entry' "$(vp __show "$(id 8)")" 'Username: jane'
	is 'show remembers the entry' "$(sed -n 1p "$history")" "$(id 8)"
	contains 'edit hands over to rbw' "$(vp __edit "$(id 7)")" 'would edit Home router'

	# --- the real fzf accepts our options (themes, binds, layout) ---
	if [ -n "$real_fzf" ] && "$real_fzf" --version | awk -F '[. ]' '{ exit !($1 > 0 || $2 >= 63) }'; then
		for theme in ansi amber mocha latte dracula gruvbox nord onedark rosepine solarized tokyonight none; do
			if [ "$theme" = none ]; then export NO_COLOR=1; else export VAULTPICK_THEME=$theme; fi
			out=$(STUB_FZF_REAL="$real_fzf" vp github 2>&1)
			contains "real fzf accepts the options ($theme)" "$out" "$(id 1)"
			unset NO_COLOR VAULTPICK_THEME
		done
	else
		printf '  skip [%s] real fzf 0.63+ not found\n' "$shell_name" >&2
	fi

	rm -rf "$tmp"
}

set -- sh dash bash 'busybox sh'
[ -z "${TEST_SHELLS:-}" ] || {
	# shellcheck disable=SC2086 # a space-separated list of shells
	set -- $TEST_SHELLS
}
ran=0
for shell in "$@"; do
	command -v "${shell%% *}" >/dev/null 2>&1 || continue
	shell_name=$shell
	ran=$((ran + 1))
	(suite)
done

# The real macOS clipboard, on CI only: it would overwrite a developer's clipboard.
if [ -n "${CI:-}" ] && [ "$(uname -s)" = Darwin ]; then
	shell_name='macOS clipboard'
	(
		tmp=$(mktemp -d)
		original_path=$PATH
		# shellcheck disable=SC1091
		. "$root/tests/env.sh"
		mkdir "$tmp/bin"
		ln -s "$root/tests/stubs/rbw" "$tmp/bin/rbw"
		PATH="$tmp/bin:$original_path"
		export RBW_STUB_VAULT="$root/tests/fixtures/vault.json" # the symlink hides the default
		out=$(VAULTPICK_CLEAR=2 sh "$root/vaultpick" __copy password "$(id 1)")
		contains 'real pbcopy: status line' "$out" 'clears in 2 s'
		is 'real pbcopy: copies' "$(pbpaste)" 'demo-pw-github'
		sleep 4
		is 'real pbcopy: cleared after the timeout' "$(pbpaste)" ''
		rm -rf "$tmp"
	)
fi

failed=$(grep -c FAIL "$results")
total=$(wc -l <"$results" | tr -d ' ')
printf '%s checks in %s shell(s), %s failed\n' "$total" "$ran" "$failed"
[ "$failed" -eq 0 ] && [ "$total" -gt 0 ]
