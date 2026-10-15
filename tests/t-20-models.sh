#!/usr/bin/env bash
# Model catalogue: Verify floor, host tool, newest-version pick, refresh.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
teststore

# Verify floor: never below deep, never below the previous Verify round
mkstore store-vf >/dev/null <<'EOF'
orchestration:
  gate_quick: "true"
  gate_full: "true"
EOF
$RC state init --store store-vf --name feat-vf
$RC session append --store store-vf --name feat-vf role worker phase applying tier standard model claude-sonnet-5 transcript_id v1
check_out "model verify: standard implementer -> deep (tier-above, no floor note)" "claude-opus-5" $RC model verify --store store-vf --name feat-vf
vf_full="$($RC model verify --store store-vf --name feat-vf)"; vf_line1="${vf_full%%$'\n'*}"
check "model verify: first line is the bare model id even with a floor" test "$vf_line1" = claude-opus-5-5
$RC session append --store store-vf --name feat-vf role worker phase checking tier mechanical model claude-haiku-4-5-20251001 transcript_id fix1
check_out "model verify: mechanical fixer still gets a deep Verify" "claude-opus-5" $RC model verify --store store-vf --name feat-vf
$RC state set --store store-vf --name feat-vf phase checking last_gate_result green
check_out "next: verify after a mechanical fix names the floor" "floor: deep" $RC next --store store-vf --name feat-vf
check_out "next: verify tier is deep, not standard" "tier: deep" $RC next --store store-vf --name feat-vf
$RC session append --store store-vf --name feat-vf role worker phase verify tier max model claude-fable-5-1 transcript_id ver2
$RC session append --store store-vf --name feat-vf role worker phase checking tier mechanical model claude-haiku-4-5-20251001 transcript_id fix2
check_out "model verify: never below the previous Verify round" "claude-fable-5-1" $RC model verify --store store-vf --name feat-vf
check_out "next: verify names the previous round as the floor" "floor: previous round ran at max" $RC next --store store-vf --name feat-vf
$RC state set --store store-vf --name feat-vf last_gate_result ""
check_out "next: check's concurrent verify carries the floor too" "also_model: claude-fable-5-1" $RC next --store store-vf --name feat-vf
$RC session append --store store-vf --name feat-vf role worker phase checking tier deep model claude-opus-5 transcript_id fix3
check_out "model verify: a deep fixer still goes to max by the tier-above rule" "claude-fable-5-1" $RC model verify --store store-vf --name feat-vf
vf_out="$($RC next --store store-vf --name feat-vf)"
case "$vf_out" in *"floor:"*) echo "FAIL next: no floor note when tier-above already wins"; fails=$((fails+1)) ;; *) echo "ok   next: no floor note when tier-above already wins" ;; esac

# host tool: selects the models.tsv column and the agent set
mkstore store-host >/dev/null <<'EOF'
orchestration:
  tool: codex
  model_max: "gpt-custom"
EOF
check_out "model get uses the host tool's catalogue" "gpt-6-astra" $RC model get --store store-host --tier deep
check_out "model get still honors an override on a non-Claude host" "gpt-custom" $RC model get --store store-host --tier max
$RC state init --store store-host --name feat-host
$RC session append --store store-host --name feat-host role worker phase applying tier standard model gpt-6.1-sol transcript_id h1
check_out "model verify picks from the host tool's catalogue" "gpt-6-astra" $RC model verify --store store-host --name feat-host
$RC session append --store store-host --name feat-host role proposer phase proposed tier deep model gpt-6-astra transcript_id h2
check_out "model critic still uses a mapped tier above on a non-Claude host" "gpt-custom" $RC model critic --store store-host --name feat-host
sed -i.bak 's/tool: codex/tool: emacs/' "$TMP/store-host/openspec/config.yaml"
check_err "unknown host tool errors" "unknown orchestration.tool 'emacs'" $RC model get --store store-host --tier deep
check_err "unknown host tool errors even for a tier with a model override" "unknown orchestration.tool 'emacs'" $RC model get --store store-host --tier max
sed -i.bak 's/tool: emacs/tool: "*"/' "$TMP/store-host/openspec/config.yaml"
check_err "host tool is matched exactly, not as a pattern" "unknown orchestration.tool '*'" $RC model get --store store-host --tier deep
sed -i.bak 's/tool: "\*"/tool: codex/' "$TMP/store-host/openspec/config.yaml"
# default Codex: deep and max share gpt-6-astra, so a deep proposer's max
# critic runs on max's fallback instead of erroring
mkstore store-cx >/dev/null <<'EOF'
orchestration:
  tool: codex
EOF
mkchange store-cx feat-cx
$RC session append --store store-cx --name feat-cx role proposer phase proposed tier deep model gpt-6-astra transcript_id x1
check_line "model critic on default Codex runs a deep proposer's critic on max's fallback" "gpt-6.1-sol" bash -c "$RC model critic --store store-cx --name feat-cx | sed -n 1p"
check_out "next on default Codex dispatches that critic" "model: gpt-6.1-sol" $RC next --store store-cx --name feat-cx
check_not "next prints no fallback_model when the checker already runs on it" "fallback_model:" $RC next --store store-cx --name feat-cx
mkstore store-oc >/dev/null <<'EOF'
orchestration:
  tool: opencode
EOF
mkchange store-oc feat-oc
check_line "next on OpenCode names the agent with its -opencode suffix" "agent: openspec-proposer-standard-opencode" $RC next --store store-oc --name feat-oc

# model catalogue: newest version per family, a different family as fallback
check_out "model get prints a fallback from the next family" "fallback: gpt-6.1-sol" $RC model get --store store-host --tier deep
check_out "model get: newest version in a family wins (6.1 over 6)" "gpt-6.1-sol" $RC model get --store store-host --tier standard
mkdir -p "$TMP/store-host/.orchestration"
printf 'gpt-6-astra\ngpt-6.9-sol\ngpt-6.10-sol\n' > "$TMP/store-host/.orchestration/models.codex.txt"
check_out "a listed newer version is promoted, compared per dotted part (6.10 over 6.9)" "gpt-6.10-sol" $RC model get --store store-host --tier standard
check_out "an unlisted catalogue id is dropped (no luna listed)" "gpt-6.10-sol" $RC model get --store store-host --tier mechanical
rm "$TMP/store-host/.orchestration/models.codex.txt"
cat >> "$TMP/store-host/openspec/config.yaml" <<'EOF'
  model_deep_fallback: "gpt-fb-custom"
EOF
check_out "model_<tier>_fallback overrides the catalogue fallback" "fallback: gpt-fb-custom" $RC model get --store store-host --tier deep
check_out "models refresh is a no-op for a tool without a model listing" "catalogue used as-is" $RC models refresh --store teststore
mkdir -p "$TMP/codex-home/.codex"
echo '{"models":[{"slug":"gpt-6-luna","visibility":"list"},{"slug":"gpt-5.6-terra","visibility":"list"},{"slug":"gpt-6-astra","visibility":"hide"}]}' > "$TMP/codex-home/.codex/models_cache.json"
HOME="$TMP/codex-home" $RC models refresh --store store-host >/dev/null
check_out "codex refresh: an account without sol or astra falls back to terra" "gpt-5.6-terra" $RC model get --store store-host --tier standard
rm "$TMP/store-host/.orchestration/models.codex.txt"
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nprintf "Available models\\n\\nauto - Auto\\nclaude-sonnet-5-5-medium - S\\nclaude-sonnet-5-5-thinking-high - S\\ngpt-5.6-sol-high-fast - G\\n"\n' > "$TMP/fakebin/agent"; chmod +x "$TMP/fakebin/agent"
mkstore store-cur >/dev/null <<'EOF'
orchestration:
  tool: cursor
EOF
PATH="$TMP/fakebin:$PATH" $RC models refresh --store store-cur >/dev/null
check "cursor refresh reduces effort and thinking variants to bare ids" bash -c "! grep -qE -- '-(medium|high|thinking|fast)\$' '$TMP/store-cur/.orchestration/models.cursor.txt' && grep -qx claude-sonnet-5-5 '$TMP/store-cur/.orchestration/models.cursor.txt' && grep -qx gpt-5.6-sol '$TMP/store-cur/.orchestration/models.cursor.txt'"
check_out "cursor standard resolves from the refreshed list" "claude-sonnet-5-5" $RC model get --store store-cur --tier standard
mkdir -p "$TMP/failbin"; printf '#!/bin/sh\nexit 1\n' > "$TMP/failbin/agent"; chmod +x "$TMP/failbin/agent"
cur_list="$(cat "$TMP/store-cur/.orchestration/models.cursor.txt")"
check_fails "models refresh fails when the tool's listing fails" env PATH="$TMP/failbin:$PATH" $RC models refresh --store store-cur
check_err "models refresh names the failed listing" "model listing for cursor failed" env PATH="$TMP/failbin:$PATH" $RC models refresh --store store-cur
check "a failed refresh leaves the previous list untouched" test "$cur_list" = "$(cat "$TMP/store-cur/.orchestration/models.cursor.txt")"
# Copilot ids contain spaces and must survive every pick
mkstore store-cp >/dev/null <<'EOF'
orchestration:
  tool: copilot
  gate_quick: "true"
  gate_full: "true"
EOF
mkchange store-cp feat-cp phase checking last_gate_result green
$RC session append --store store-cp --name feat-cp role worker phase applying tier standard model "Claude Sonnet 5.5" transcript_id c1
check_line "model verify keeps a Copilot id with spaces whole" "Claude Opus 5.5" bash -c "$RC model verify --store store-cp --name feat-cp | sed -n 1p"
check_line "next prints the whole Copilot id as model:" "model: Claude Opus 5.5" $RC next --store store-cp --name feat-cp
check_not "next leaks no part of the id into reason:" "; Opus" $RC next --store store-cp --name feat-cp
$RC session append --store store-cp --name feat-cp role proposer phase proposed tier deep model "Claude Opus 5.5" transcript_id c2
check_line "model critic keeps a Copilot id with spaces whole" "Claude Fable 5.1" bash -c "$RC model critic --store store-cp --name feat-cp | sed -n 1p"
check_out "next prints a fallback_model" "fallback_model: " $RC next --store store-host --name feat-host
check_out "next names the per-tier agent" "agent: openspec-" $RC next --store store-host --name feat-host

finish
