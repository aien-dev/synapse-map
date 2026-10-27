#!/bin/sh
# tests/run.sh: build synapse-map with the pinned omc and run every case against throwaway homes.
# Env: OMEGA_SRC (omega-mv checkout at the omega.pin sha, default /tmp/Coord/omega-mv),
# TEST_ROOT (scratch dir, default /tmp/Coord/test-homes/map), XERJ (default 127.0.0.1:9200).
# jq and python3 are used only as checkers. Cases needing xerj or the crumb CLI print NOT_RUN when
# those are absent; NOT_RUN is counted separately and never as a pass. Exit 1 on any FAIL.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
OMEGA_SRC=${OMEGA_SRC:-/tmp/Coord/omega-mv}
TEST_ROOT=${TEST_ROOT:-/tmp/Coord/test-homes/map}
XERJ=${XERJ:-127.0.0.1:9200}
fx=$here/tests/fixtures
pass=0 fail=0 notrun=0

ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }
nr() { notrun=$((notrun + 1)); echo "NOT_RUN $1 ($2)"; }

rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"
bin=$TEST_ROOT/bin/synapse-map
if ! sh "$here/build.sh" "$OMEGA_SRC" "$bin" 2> "$TEST_ROOT/build.err"; then
  cat "$TEST_ROOT/build.err"
  echo "FAIL build"
  exit 1
fi
ok build
H=$TEST_ROOT/home
out=$TEST_ROOT/out
err=$TEST_ROOT/err

# run CASE EXPECTED_RC ARGS...: stdout to $out, stderr to $err
run() {
  name=$1 want=$2
  shift 2
  "$bin" "$@" > "$out" 2> "$err"
  rc=$?
  if [ "$rc" -ne "$want" ]; then
    bad "$name: exit $rc, want $want"
    sed 's/^/  stderr: /' "$err" | head -5
    return 1
  fi
  return 0
}

# every stdout line must be a JSON object
jsonl() {
  if [ -s "$out" ] && ! jq -e -s 'all(type == "object")' "$out" > /dev/null 2>&1; then
    bad "$1: stdout is not JSONL"
    return 1
  fi
  return 0
}

# check JQFILTER over the slurped stdout lines
expect() {
  name=$1 filter=$2
  if jq -e -s "$filter" "$out" > /dev/null 2>&1; then ok "$name"; else bad "$name"; head -c 600 "$out"; echo; fi
}

# ---- usage ----
run usage-none 64 && ok usage-none
run usage-unknown 64 frobnicate && ok usage-unknown
run usage-badflag 64 --home "$H" import --catalog "$fx/catalog.json" --bogus && ok usage-badflag
run usage-help 0 --help && ok usage-help
run usage-limit 64 --home "$H" where x --limit 0 --no-xerj && ok usage-limit
env -u HOME -u AIEN_COORD_HOME "$bin" tree > "$out" 2> "$err"; rc=$?
[ "$rc" -eq 64 ] && ok usage-nohome || bad "usage-nohome: exit $rc, want 64"

# ---- import ----
run tree-nomap 4 --home "$H" tree && ok tree-nomap
run import-bad 65 --home "$H" import --catalog "$fx/bad.json" && ok import-malformed
run import-missing 4 --home "$H" import --catalog "$fx/nonexistent.json" && ok import-missing-file
[ ! -e "$H/map.jsonl" ] && ok import-bad-writes-nothing || bad import-bad-writes-nothing
if run import 0 --home "$H" import --catalog "$fx/catalog.json" --extra "$fx/extra.jsonl" \
  --crumbs "$fx/crumbs" --infer "$fx/infer.tsv" && jsonl import; then
  expect import-summary '.[0].ok == true and .[0].records == 12'
  cp "$out" "$TEST_ROOT/import.out"
  out_save=$out
  out=$H/map.jsonl
  expect map-keyorder 'all(keys_unsorted == ["repo","parent","parent_status","purpose","layer","archived","fork","default_branch","pushed_at","brief","source","infer_rule"])'
  expect map-count 'length == 12'
  expect map-root '.[] | select(.repo == "t-org/lang") | .parent_status == "ROOT" and .parent == null and .layer == "language"'
  expect map-inferred '.[] | select(.repo == "t-org/lang-fmt") | .parent_status == "INFERRED" and .parent == "t-org/lang@main" and (.infer_rule | startswith("L"))'
  expect map-confirmed '.[] | select(.repo == "t-org/memkid") | .parent_status == "CONFIRMED" and .parent == "t-org/oldbase@main" and .layer == "memory"'
  expect map-ref-default '.[] | select(.repo == "t-org/bootcfg") | .parent == "t-org/upfork@main"'
  expect map-extra '.[] | select(.repo == "t-org/vc-tool") | .source == "extra" and .parent == "t-org/vc@trunk"'
  expect map-none '.[] | select(.repo == "t-org/lonely") | .parent_status == "NONE" and .parent == null'
  expect map-flags '.[] | select(.repo == "t-org/oldbase") | .archived == true and .fork == false'
  out=$out_save
fi

# ---- tree ----
if run tree 0 --home "$H" tree && jsonl tree; then
  expect tree-once 'length == 12 and ([.[].repo] | unique | length) == 12'
  expect tree-depth '.[] | select(.repo == "t-org/lang-fmt") | .depth == 1'
fi
run tree-text 0 --home "$H" tree --text && grep -q '^  t-org/lang-fmt \[INFERRED\]' "$out" && ok tree-text || bad tree-text

# ---- check ----
if run check-findings 1 --home "$H" check --no-xerj && jsonl check; then
  expect check-orphan 'any(.kind == "orphan" and .repo == "t-org/lonely")'
  expect check-missing 'any(.kind == "missing_parent" and .repo == "t-org/ghostkid" and .parent == "t-org/ghost@main")'
  expect check-archived 'any(.kind == "archived_parent" and .repo == "t-org/memkid")'
  expect check-fork 'any(.kind == "fork_parent" and .repo == "t-org/bootcfg")'
  expect check-inferred 'any(.kind == "inferred_parent" and .repo == "t-org/lang-fmt" and .infer_rule != null)'
  expect check-duplicate 'any(.kind == "duplicate_purpose" and .repo == "t-org/dup-a" and .other == "t-org/dup-b" and .semantic == null)'
  expect check-no-false-dup '[.[] | select(.kind == "duplicate_purpose")] | length == 1'
fi
H2=$TEST_ROOT/clean
run import-clean 0 --home "$H2" import --catalog "$fx/clean.json" --infer "$fx/infer.tsv" && ok import-clean
run check-clean 0 --home "$H2" check --no-xerj && [ ! -s "$out" ] && ok check-clean || bad "check-clean: stdout not empty"

# ---- where (lexical) ----
if run where-lex 0 --home "$H" where "TLS 1.3 handshake" --no-xerj --skills "$fx/skills.jsonl" && jsonl where-lex; then
  expect where-top '.[0].repo == "t-org/lang"'
  expect where-shape '.[0] | keys_unsorted == ["repo","score","purpose","parent","why","skills","similar"]'
  expect where-nowarn 'all(has("warn") | not)'
  expect where-skill '.[0].skills[0] == "lang-tls"'
fi
run where-vc 0 --home "$H" where "source control for AI agents" --no-xerj --limit 3 && expect where-vc '[.[].repo] | index("t-org/vc") != null and length <= 3'
run where-nomatch 4 --home "$H" where "zzzqqq" --no-xerj && ok where-nomatch
# xerj down: closed port, warn line first, exit 0
if run where-xdown 0 --home "$H" where "TLS handshake" --xerj 127.0.0.1:9 && jsonl where-xdown; then
  expect where-xdown '.[0] == {"warn":"xerj unreachable"} and .[1].repo == "t-org/lang"'
fi
run index-xdown 75 --home "$H" index --xerj 127.0.0.1:9 && ok index-xdown

# ---- where/check with xerj (index aien-map-test, deleted afterwards) ----
if curl -fsS -m 3 "http://$XERJ/" > /dev/null 2>&1; then
  if run index-xerj 0 --home "$H" index --xerj "$XERJ" --index aien-map-test --skills "$fx/skills.jsonl"; then
    expect index-xerj '.[0].ok == true and .[0].repos == 12'
    run where-xerj 0 --home "$H" where "TLS handshake for the language" --xerj "$XERJ" --index aien-map-test \
      && expect where-xerj '.[0].repo == "t-org/lang" and (.[0].why | test("semantic"))'
    run check-xerj 1 --home "$H" check --xerj "$XERJ" --index aien-map-test \
      && expect check-xerj-sem 'any(.kind == "duplicate_purpose" and (.semantic | type) == "boolean")'
  fi
  curl -fsS -m 5 -X DELETE "http://$XERJ/aien-map-test" > /dev/null 2>&1
else
  nr index-xerj "xerj unreachable at $XERJ"
  nr where-xerj "xerj unreachable at $XERJ"
  nr check-xerj "xerj unreachable at $XERJ"
fi

# ---- new ----
D=$TEST_ROOT/new/child-x
if run new 0 --home "$H" new child-x --parent t-org/vc --purpose "A child tool" --dir "$D" && jsonl new; then
  expect new-files '.[0].files == [".crumb",".goals.json","README.md","AGENTS.md","PARENT-PR.md"]'
  jq -e '.extensions.map.parent == "t-org/vc@trunk" and .extensions.map.parent_status == "CONFIRMED" and .name == "child-x"' "$D/.crumb" > /dev/null \
    && ok new-crumb || bad new-crumb
  jq -e '.schema == "goals/v1" and .project == "child-x"' "$D/.goals.json" > /dev/null && ok new-goals || bad new-goals
  head -1 "$D/README.md" | grep -q 'https://github.com/t-org/vc' && ok new-readme-parent || bad new-readme-parent
  grep -q '^- \[child-x\](https://github.com/t-org/child-x): A child tool$' "$D/PARENT-PR.md" && ok new-parent-pr || bad new-parent-pr
  if command -v crumb > /dev/null 2>&1; then
    expect new-validate '.[0].crumb_validate == "PASS" and .[0].ok == true'
  else
    expect new-validate-notrun '.[0].crumb_validate == "NOT_RUN"'
    nr new-validate "crumb CLI absent"
  fi
fi
run new-exists 64 --home "$H" new child-x --parent t-org/vc --purpose "again" --dir "$D" && ok new-refuses-existing
run new-badname 64 --home "$H" new "../evil" --parent t-org/vc --purpose p --dir "$TEST_ROOT/new/evil" && ok new-badname
run new-noparent 64 --home "$H" new child-y --purpose p --dir "$TEST_ROOT/new/y" && ok new-needs-parent
run new-dryonly 64 --home "$H" new child-y --parent t-org/vc --purpose p --dir "$TEST_ROOT/new/y" --dry-run && ok new-dryrun-needs-publish
D3=$TEST_ROOT/new/synapse-zz
if run new-synapse 0 --home "$H" new synapse-zz --parent aien-dev/synapse@099a980fedab8a6797bbf0358b8c5502c8045142 \
  --purpose "Test child" --dir "$D3" --publish --dry-run && jsonl new-synapse; then
  [ "$(cat "$D3/synapse.pin")" = "aien-dev/synapse@099a980fedab8a6797bbf0358b8c5502c8045142" ] && ok new-synapse-pin || bad new-synapse-pin
  expect publish-steps '[.[] | select(has("argv"))] | length == 10'
  expect publish-create '[.[] | select(has("argv")) | .argv][3] == ["gh","repo","create","aien-dev/synapse-zz","--public","--description","Test child","--source","'"$D3"'","--push"]'
  expect publish-clone '[.[] | select(has("argv")) | .argv][4] == ["git","clone","https://github.com/aien-dev/synapse","'"$D3"'.parent"]'
  expect publish-edit 'any(.edit == "'"$D3"'.parent/README.md" and .line == "- [synapse-zz](https://github.com/aien-dev/synapse-zz): Test child")'
  expect publish-pr '[.[] | select(has("argv")) | .argv][9] == ["gh","pr","create","--draft","-R","aien-dev/synapse","--head","connected/synapse-zz","--title","Connect synapse-zz","--body-file","'"$D3"'/PARENT-PR.md"]'
  [ ! -e "$D3/.git" ] && [ ! -e "$D3.parent" ] && ok publish-dryrun-ran-nothing || bad publish-dryrun-ran-nothing
fi

echo "summary: pass=$pass fail=$fail not_run=$notrun"
[ "$fail" -eq 0 ]
