#!/usr/bin/env bash
# UI units: screenshot ownership and the critic over green units.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# UI green needs the screenshot: a gate_quick that exits 0 but never writes it
mkstore storeu2 >/dev/null <<'EOF'
orchestration:
  concurrency: 1
  gate_quick: "exit 0"
  gate_full: "exit 0"
EOF
UPROJECT2="$TMP/uproject2"
mkproject "$UPROJECT2" a.js
$RC state init --store storeu2 --name feat-nopng
$RC state set --store storeu2 --name feat-nopng seams "s=a.js" units "a=a.js" unit_deps "" ui_units "a"
$RC workspace create --store storeu2 --project "$UPROJECT2" --name feat-nopng >/dev/null 2>&1
nwt="$($RC unit create --store storeu2 --project "$UPROJECT2" --name feat-nopng --unit a)"
echo check > "$nwt/a.test.js"; git -C "$nwt" add -A && git -C "$nwt" commit -qm checks
$RC unit checks-done --store storeu2 --project "$UPROJECT2" --name feat-nopng --unit a
check_fails "UI unit with a gate_quick that writes no PNG returns red" $RC unit iterate --store storeu2 --project "$UPROJECT2" --name feat-nopng --unit a
check_out "that iterate is logged red" "checks=red" $RC session list --store storeu2 --name feat-nopng
check "its status is not green" bash -c "! grep -q '^status: green' <($RC unit get --store storeu2 --name feat-nopng --unit a)"

# only the owning unit's test writes the screenshot
mkstore storeu3 >/dev/null <<'EOF'
orchestration:
  concurrency: 2
  unit_concurrency: 2
  gate_quick: '[ "$UNIT_NAME" != a ] || touch "$UNIT_SCREENSHOT"'
  gate_full: "exit 0"
EOF
UPROJECT3="$TMP/uproject3"
mkproject "$UPROJECT3" a.js b.js
$RC state init --store storeu3 --name feat-owner
$RC state set --store storeu3 --name feat-owner seams "s=a.js,b.js" units "a=a.js;b=b.js" unit_deps "" ui_units "a,b"
$RC workspace create --store storeu3 --project "$UPROJECT3" --name feat-owner >/dev/null 2>&1
owt_a="$($RC unit create --store storeu3 --project "$UPROJECT3" --name feat-owner --unit a)"
owt_b="$($RC unit create --store storeu3 --project "$UPROJECT3" --name feat-owner --unit b)"
echo c > "$owt_a/a.test.js"; git -C "$owt_a" add -A && git -C "$owt_a" commit -qm checks
echo c > "$owt_b/b.test.js"; git -C "$owt_b" add -A && git -C "$owt_b" commit -qm checks
$RC unit checks-done --store storeu3 --project "$UPROJECT3" --name feat-owner --unit a
$RC unit checks-done --store storeu3 --project "$UPROJECT3" --name feat-owner --unit b
check_fails "owner store: non-owning unit b returns red" $RC unit iterate --store storeu3 --project "$UPROJECT3" --name feat-owner --unit b
check "owner store: unit b records no screenshot" bash -c "! grep -q '^screenshot: /' <($RC unit get --store storeu3 --name feat-owner --unit b)"
check "owner store: owning unit a returns green" $RC unit iterate --store storeu3 --project "$UPROJECT3" --name feat-owner --unit a
check_out "owner store: unit a status green" "status: green" $RC unit get --store storeu3 --name feat-owner --unit a

# =====================================================================
# critic over green units with screenshots
# =====================================================================
check_out "units ready-for-review lists the green unit" "unit: a" $RC units ready-for-review --store storeu3 --name feat-owner
out_rfr="$($RC units ready-for-review --store storeu3 --name feat-owner)"
case "$out_rfr" in
  *"unit: b"*) echo "FAIL units ready-for-review includes the non-green unit b"; fails=$((fails+1)) ;;
  *) echo "ok   units ready-for-review excludes the non-green unit b" ;;
esac
check_out "units ready-for-review prints the absolute screenshot path" "$TMP/storeu3/.orchestration/state/feat-owner.units/a/screenshot-1.png" $RC units ready-for-review --store storeu3 --name feat-owner

critique_dir="$TMP/storeu3/.orchestration/state/feat-owner.units"
shotpath="$critique_dir/a/screenshot-1.png"
echo "basename only: screenshot-1.png" > "$critique_dir/a.critique.md"
check_err "unit set critique: report with only the basename is refused" "does not contain" $RC unit set --store storeu3 --name feat-owner --unit a critique clean
printf 'looks correct: %s\n' "$shotpath" > "$critique_dir/a.critique.md"
check "unit set critique: report with the absolute path is accepted" $RC unit set --store storeu3 --name feat-owner --unit a critique clean
check_out "unit critique recorded" "critique: clean" $RC unit get --store storeu3 --name feat-owner --unit a

$RC session append --store storeu3 --name feat-owner role worker phase proposed tier deep model claude-opus-5-custom transcript_id u1
# avoid piping a live process into `head`: with pipefail the writer's SIGPIPE
# (once head closes the pipe after one line) would kill this whole script
out1_full="$($RC model critic --store storeu3 --name feat-owner)"; out1="${out1_full%%$'\n'*}"
out2_full="$($RC model critic --store storeu3 --name feat-owner --unit a)"; out2="${out2_full%%$'\n'*}"
check "model critic line 1 is max over the deep proposer" test "$out1" = claude-fable-5-1
check "model critic --unit line 1 is deep over the standard leaf worker" test "$out2" = claude-opus-5-5
check_out "model critic --unit contract mentions checks_commit" "checks_commit" $RC model critic --store storeu3 --name feat-owner --unit a
check_out "model critic --unit contract mentions screenshot" "screenshot" $RC model critic --store storeu3 --name feat-owner --unit a
check_out "model critic --unit contract mentions input:" "input:" $RC model critic --store storeu3 --name feat-owner --unit a
check "model critic --unit contract names no Project glossary or ADRs" bash -c "out=\"\$($RC model critic --store storeu3 --name feat-owner --unit a)\" && case \"\$out\" in *openspec/CONTEXT.md*|*openspec/adr/*) exit 1 ;; esac"

finish
