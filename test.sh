#!/usr/bin/env bash
# Self-contained test suite for janet-toml. Requires janet.
set -uo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.local/toolchains/janet/bin:$HOME/.local/bin:$PATH"
JANET="${JANET:-janet}"
command -v "$JANET" >/dev/null 2>&1 || { echo "FAIL: janet not found"; exit 1; }
./build.sh >/dev/null
TOML="./bin/janet-toml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); }
bad(){ fail=$((fail+1)); echo "FAIL: $1"; }
# assert exit code and a stdout substring
check(){ # name expected_exit expected_substring actual_exit actual_out
  local name="$1" want_rc="$2" want="$3" rc="$4" out="$5"
  if [ "$rc" != "$want_rc" ]; then bad "$name (exit $rc, want $want_rc)"; return; fi
  if [ -n "$want" ] && ! printf '%s' "$out" | grep -qF -- "$want"; then
    bad "$name (output missing '$want')"; return
  fi
  ok
}
# assert exit code and exact stdout
check_eq(){ # name expected_exit expected_out actual_exit actual_out
  local name="$1" want_rc="$2" want="$3" rc="$4" out="$5"
  if [ "$rc" != "$want_rc" ]; then bad "$name (exit $rc, want $want_rc)"; return; fi
  if [ "$out" != "$want" ]; then bad "$name (output '$out' != '$want')"; return; fi
  ok
}

cat > "$TMP/ok.toml" <<'EOF'
# a comprehensive valid file
title = "TOML Example"
[owner]
name = "Tom"
age = 30
[db]
ports = [8001, 8002]
enabled = true
ratio = 0.5
hex = 0xFF
[[products]]
name = "a"
[[products]]
name = "b"
EOF
out=$($TOML "$TMP/ok.toml"); rc=$?
check_eq "valid file: zero errors" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/dupkey.toml" <<'EOF'
[server]
port = 1
port = 2
EOF
out=$($TOML "$TMP/dupkey.toml"); rc=$?
check "duplicate key flagged" 1 'duplicate key "port" in [server]' "$rc" "$out"
check "duplicate key line number" 1 "ERROR line 3:" "$rc" "$out"
check "duplicate key summary" 1 "1 error(s)" "$rc" "$out"

cat > "$TMP/duphdr.toml" <<'EOF'
[server]
x = 1
[server]
y = 2
EOF
out=$($TOML "$TMP/duphdr.toml"); rc=$?
check "duplicate table header" 1 "duplicate table header [server]" "$rc" "$out"

cat > "$TMP/malformed.toml" <<'EOF'
[server]
this line has no separator
EOF
out=$($TOML "$TMP/malformed.toml"); rc=$?
check "malformed line flagged" 1 "expected '=' after key" "$rc" "$out"

cat > "$TMP/unterm.toml" <<'EOF'
x = "unterminated
EOF
out=$($TOML "$TMP/unterm.toml"); rc=$?
check "unterminated string" 1 "unterminated string" "$rc" "$out"

cat > "$TMP/badtoken.toml" <<'EOF'
val = notatoken
EOF
out=$($TOML "$TMP/badtoken.toml"); rc=$?
check "invalid value token" 1 'invalid value token "notatoken"' "$rc" "$out"

out=$($TOML "$TMP/nope.toml" 2>&1); rc=$?
check "missing file exits 2" 2 "cannot read file" "$rc" "$out"

out=$($TOML 2>&1); rc=$?
check "no args exits 2" 2 "usage:" "$rc" "$out"

out=$($TOML "$TMP/ok.toml" "$TMP/dupkey.toml" 2>&1); rc=$?
check "two args exits 2" 2 "usage:" "$rc" "$out"

cat > "$TMP/mlarr.toml" <<'EOF'
ports = [
  8001,
  8002,
]
EOF
out=$($TOML "$TMP/mlarr.toml"); rc=$?
check_eq "multiline array valid" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/untermarr.toml" <<'EOF'
ports = [1, 2
EOF
out=$($TOML "$TMP/untermarr.toml"); rc=$?
check "unterminated array" 1 "unterminated array" "$rc" "$out"

cat > "$TMP/comment.toml" <<'EOF'
key = 1 # inline comment
# full line comment
other = "a # b"  # hash inside string is not a comment
EOF
out=$($TOML "$TMP/comment.toml"); rc=$?
check_eq "comments handled" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/esc.toml" <<'EOF'
a = "tab\there"
b = "quote\"inside"
c = "back\\slash"
d = "unicode\u00E9"
EOF
out=$($TOML "$TMP/esc.toml"); rc=$?
check_eq "valid escapes" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/badesc.toml" <<'EOF'
a = "bad\qescape"
EOF
out=$($TOML "$TMP/badesc.toml"); rc=$?
check "invalid escape" 1 "invalid escape sequence" "$rc" "$out"

cat > "$TMP/literal.toml" <<'EOF'
path = 'C:\Users\no\escape'
EOF
out=$($TOML "$TMP/literal.toml"); rc=$?
check_eq "literal string" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/quotedkey.toml" <<'EOF'
"key with space" = 1
'literal-key' = 2
EOF
out=$($TOML "$TMP/quotedkey.toml"); rc=$?
check_eq "quoted keys" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/nested.toml" <<'EOF'
[a.b.c]
x = 1
[a.b]
y = 2
[a]
z = 3
EOF
out=$($TOML "$TMP/nested.toml"); rc=$?
check_eq "nested tables + late parent" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/aot.toml" <<'EOF'
[[x]]
name = "a"
[[x]]
name = "b"
EOF
out=$($TOML "$TMP/aot.toml"); rc=$?
check_eq "array of tables repeats" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/conflict.toml" <<'EOF'
[x]
a = 1
[[x]]
b = 2
EOF
out=$($TOML "$TMP/conflict.toml"); rc=$?
check "table/aot conflict" 1 "cannot redefine table [x] as array of tables" "$rc" "$out"

cat > "$TMP/floats.toml" <<'EOF'
a = 1e6
b = -2.5E-3
c = +1.0
d = 1_000
e = 0o755
f = 0b1010
EOF
out=$($TOML "$TMP/floats.toml"); rc=$?
check_eq "floats/exponents/underscores/bases" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/badbool.toml" <<'EOF'
x = True
EOF
out=$($TOML "$TMP/badbool.toml"); rc=$?
check "capitalized boolean invalid" 1 'invalid value token "True"' "$rc" "$out"

cat > "$TMP/badnum.toml" <<'EOF'
x = 1_
EOF
out=$($TOML "$TMP/badnum.toml"); rc=$?
check "trailing underscore invalid" 1 'invalid value token "1_"' "$rc" "$out"

printf '' > "$TMP/empty.toml"
out=$($TOML "$TMP/empty.toml"); rc=$?
check_eq "empty file" 0 "0 error(s)" "$rc" "$out"

printf '# only comments\n\n# nothing else\n' > "$TMP/onlycomments.toml"
out=$($TOML "$TMP/onlycomments.toml"); rc=$?
check_eq "comments-only file" 0 "0 error(s)" "$rc" "$out"

cat > "$TMP/rootdup.toml" <<'EOF'
a = 1
a = 2
EOF
out=$($TOML "$TMP/rootdup.toml"); rc=$?
check "root duplicate key" 1 'duplicate key "a" in root table' "$rc" "$out"

cat > "$TMP/mlstr.toml" <<'EOF'
x = """
hello
"""
EOF
out=$($TOML "$TMP/mlstr.toml"); rc=$?
check "multiline string unsupported" 1 "multiline strings are not supported" "$rc" "$out"

cat > "$TMP/noval.toml" <<'EOF'
key =
EOF
out=$($TOML "$TMP/noval.toml"); rc=$?
check "missing value" 1 "expected a value" "$rc" "$out"

cat > "$TMP/multi.toml" <<'EOF'
a = 1
a = 2
b = "unterminated
EOF
out=$($TOML "$TMP/multi.toml"); rc=$?
check "multiple errors counted" 1 "2 error(s)" "$rc" "$out"

echo "----------------------------------------"
echo "janet-toml: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || exit 1