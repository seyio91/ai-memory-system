#!/usr/bin/env bash
# deny-match.sh: the executor deny-list matcher, and pretooluse.sh's fail-closed paths.
#
# This is a SECURITY control. Every row below is a command an executor could actually
# type. A false negative here is an executor applying to running infrastructure.
. "$(dirname "$0")/_assert.sh"

. "$SCRIPTS_DIR/deny-match.sh"

SPEC="$SCRIPTS_DIR/deny-list.txt"

deny_is() { # deny_is <expected DENY|ALLOW> <cmdline> [specfiles...]
    local want="$1" cmd="$2"; shift 2
    local specs="${*:-$SPEC}" got
    if deny_match "$cmd" $specs >/dev/null 2>&1; then got=DENY; else got=ALLOW; fi
    assert_eq "$want" "$got" "$want: $cmd"
}

# --- the bypass this plan exists to close: flag interposition -----------------
deny_is DENY 'terraform -chdir=envs/prod apply'
deny_is DENY 'kubectl -n foo delete pod x'
deny_is DENY 'kubectl --context=prod apply -f x.yaml'
deny_is DENY 'gh --repo o/r pr merge 12'
deny_is DENY 'az --debug repos pr update --status completed'

# --- interposition in the WRAPPER, not the command (sudo -u takes a value) ----
deny_is DENY 'sudo -u root kubectl delete pod x'
deny_is DENY 'sudo kubectl delete pod x'
deny_is DENY 'sudo -n kubectl delete pod x'

# --- shell re-entry: -c, bundled short flags, glued payload, eval, $( ), `` ---
deny_is DENY 'sh -c "terraform apply"'
deny_is DENY 'sh -c "terraform -chdir=x apply"'
deny_is DENY 'bash -lc "terraform apply"'
deny_is DENY 'bash -xc "kubectl delete pod x"'
deny_is DENY 'sh -c"terraform apply"'
deny_is DENY 'eval "terraform apply"'
deny_is DENY 'eval terraform apply'
deny_is DENY '$(terraform apply)'
deny_is DENY 'echo `kubectl delete pod x`'

# --- separators the splitter must not miss ------------------------------------
# `A & B` backgrounds A and RUNS B. A lone `&` is an operator, not a character.
deny_is DENY 'echo starting & terraform apply'
deny_is DENY 'sleep 1 & terraform apply'
deny_is DENY 'true & kubectl delete pod x'
deny_is DENY 'echo & helm uninstall prod'
deny_is DENY 'foo & bar & terraform apply'
deny_is DENY 'echo hi |& terraform apply'
deny_is ALLOW 'echo a & echo b'

# --- a wrapper (whose flag takes a value) then a bundled sh -c: the composition --
# of two independently-covered forms. `timeout 5 terraform apply` and `sh -c "…"`
# each deny; before the round-6 fix their composition slipped through because the
# wrapper skip landed on the flag value, so the sh -c payload was never extracted.
deny_is DENY 'timeout 5 sh -c "terraform apply"'
deny_is DENY 'flock /tmp/l sh -c "terraform apply"'
deny_is DENY 'nice -n 10 sh -c "terraform apply"'
deny_is DENY 'sudo -u root sh -c "terraform apply"'
deny_is DENY 'sudo -u root sh -c "kubectl delete pod x"'
deny_is DENY 'stdbuf -oL sh -c "terraform apply"'
deny_is DENY 'xargs -n1 sh -c "terraform apply"'
deny_is DENY 'watch -n5 sh -c "terraform apply"'
deny_is DENY 'nice -n 10 ionice -c2 sh -c "terraform apply"'
deny_is DENY 'time nice -n 10 sh -c "terraform apply"'
deny_is DENY 'nice -n 10 bash -lc "terraform apply"'
deny_is DENY 'nice -n 10 su - deploy -c "terraform apply"'
deny_is DENY 'timeout 5 find . -exec terraform apply \;'

# `eval`/`trap` are shell builtins with NO on-disk executable, so a wrapper cannot
# exec them: `nice -n 10 eval "…"` errors, runs nothing. Denying these would be a
# false positive. (Direct `eval terraform apply` still denies — the shell runs that.)
deny_is ALLOW 'timeout 5 eval "terraform apply"'
deny_is ALLOW 'nice -n 10 eval "terraform apply"'
deny_is ALLOW 'timeout 5 trap "terraform apply" EXIT'
deny_is ALLOW 'timeout 5 sh -c "echo hi"'
deny_is ALLOW 'sudo -u root sh -c "kubectl get pods"'

# flock/script are wrappers that ALSO carry their own -c/--command shell-command flag.
# `flock <lock> -c "terraform apply"` ≡ `flock <lock> sh -c "…"` — both must deny.
deny_is DENY  'flock /tmp/l -c "terraform apply"'
deny_is DENY  'flock /tmp/l --command "terraform apply"'
deny_is DENY  'flock -c "terraform apply" /tmp/l'
deny_is DENY  'script -c "terraform apply" /dev/null'
deny_is DENY  'script -qc "terraform apply" /dev/null'
deny_is DENY  'sudo flock /tmp/l -c "kubectl delete pod x"'
deny_is ALLOW 'flock /tmp/l -c "kubectl get pods"'
deny_is ALLOW 'script -c "ls -la" /dev/null'
deny_is ALLOW 'flock /tmp/l terraform plan'

# --- transparent exec-wrappers an honest agent actually types ------------------
deny_is DENY 'timeout 5 terraform apply'
deny_is DENY 'timeout --signal=9 5 kubectl delete pod x'
deny_is DENY 'nice terraform apply'
deny_is DENY 'nice -n 10 terraform apply'
deny_is DENY 'flock /tmp/l terraform apply'
deny_is DENY 'setsid kubectl delete pod x'
deny_is DENY 'stdbuf -oL terraform apply'
deny_is DENY 'xargs terraform apply'

# --- herestrings and process substitution -------------------------------------
deny_is DENY 'bash <<< "terraform apply"'
deny_is DENY 'bash <<<"kubectl delete pod x"'
deny_is DENY 'cat <(terraform apply)'

# --- su/runuser run their command ONLY via -c: wrapper status is not coverage ---
deny_is DENY 'su - deploy -c "terraform apply"'
deny_is DENY 'su deploy -c "kubectl delete pod x"'
deny_is DENY 'runuser -l deploy -c "helm uninstall prod"'
deny_is ALLOW 'su - user -c "kubectl get pods"'

# --- shell syntax that hides the binary in the head slot -----------------------
deny_is DENY '( terraform apply )'
deny_is DENY '(terraform apply)'
deny_is DENY '{ terraform apply; }'
deny_is DENY 'if true; then terraform apply; fi'
deny_is DENY 'for x in 1; do terraform apply; done'
deny_is DENY 'while true; do kubectl delete pod x; done'
deny_is DENY 'trap "terraform apply" EXIT'

# --- wrappers that exec their argument ----------------------------------------
deny_is DENY 'busybox sh -c "terraform apply"'
deny_is ALLOW 'busybox ls'
deny_is DENY 'xargs kubectl delete pod'
deny_is DENY 'exec terraform apply'
deny_is DENY 'watch kubectl delete pod x'
deny_is ALLOW 'exec bash'
deny_is ALLOW 'watch kubectl get pods'
deny_is ALLOW 'xargs -n1 echo terraform'

# --- find -exec execve's an argv: quoting survives, so the payload must too -----
# Joining payload tokens with bare spaces flattened `sh -c "terraform -chdir=. apply"`
# into `sh -c terraform -chdir=. apply`, losing the -c boundary and the deny with it.
deny_is DENY 'find . -execdir sh -c "terraform -chdir=. apply" \;'
deny_is DENY 'find . -exec sh -c "kubectl -n p delete pod x" \;'
deny_is DENY 'find . -exec sh -xc "terraform -chdir=x apply" \;'
deny_is DENY 'find . -exec sh -c "terraform apply" \;'
deny_is DENY 'find . -exec echo hi \; -exec terraform apply \;'
deny_is DENY 'find . -name "*.tf" -exec terraform apply {} +'
deny_is DENY 'sudo find . -exec terraform apply \;'

# `eval` CONCATENATES its args and re-parses, so quoting is flattened by the shell.
# `eval sh -c "terraform -chdir=x apply"` becomes `sh -c terraform -chdir=x apply`,
# which runs bare `terraform` — no `apply`. Verified against real bash. Re-quoting the
# payload here would model a shell that does not exist (and would break `trap`).
deny_is ALLOW 'eval sh -c "terraform -chdir=x apply"'
deny_is DENY  'eval terraform apply'
deny_is DENY  'trap "terraform apply" EXIT'

# --- ANSI-C quoting: in $'…' a backslash escapes, so `\'` is a literal ---------
deny_is DENY "echo \$'a\\'b' \$(terraform apply)"
deny_is DENY "echo \$'x' \$(kubectl delete pod x)"

# --- quote machine, both directions -------------------------------------------
deny_is DENY  'echo "a\" $(terraform apply)"'
deny_is DENY  'echo "$(echo "$(terraform apply)")"'
deny_is ALLOW "echo 'it'\\''s \$(terraform apply)'"
deny_is ALLOW "git commit -m 'don'\\''t run \$(terraform apply)'"

# --- `find` executes only after -exec/-execdir/-ok, never its -name values -----
deny_is DENY  'find . -exec terraform apply \;'
deny_is DENY  'find /etc -type f -name "*.conf" -exec kubectl apply -f {} \;'
deny_is DENY  'find . -execdir helm uninstall r \;'
deny_is DENY  'find . -ok terraform destroy \;'
deny_is ALLOW 'find . -name terraform'
deny_is ALLOW 'find . -name terraform -o -name apply'
deny_is ALLOW 'find . -path ./terraform -prune -o -name apply -print'
deny_is ALLOW 'find . -name kubectl -name delete'

# --- an apostrophe inside DOUBLE quotes is a literal, not a quote --------------
# `echo "it's $(terraform apply)"` executes the substitution. A quote-scanner that
# tracks only `'` opens a phantom single-quoted region and skips the live payload.
# A contraction must not read like an exploit — nor mask one.
deny_is DENY "echo \"it's \$(terraform apply)\""
deny_is DENY "echo \"don't \$(kubectl delete pod x)\""
deny_is DENY "echo \"a'b \$(terraform apply)\""
deny_is DENY "echo \"it's \`terraform apply\`\""
deny_is DENY "echo \"\$(terraform apply) it's\""
deny_is DENY "git commit -m \"it's a fix\" && terraform apply"
deny_is ALLOW "git commit -m \"it's a fix\""

# --- braces/parens as separators must not corrupt quoted content ---------------
deny_is ALLOW "kubectl get pods -o jsonpath='{.items[0].metadata.name}'"
deny_is ALLOW 'kubectl get pods -o jsonpath="{.items}"'
deny_is ALLOW "awk '{print \$1}' file"
deny_is ALLOW "git log --pretty=format:'%h {%an}'"

# --- single quotes suppress substitution; double quotes do not -----------------
deny_is ALLOW "echo '\$(terraform apply)'"
deny_is ALLOW "git commit -m 'run \$(terraform apply) later'"
deny_is ALLOW "echo 'use \`kubectl delete pod x\` here'"
deny_is DENY  'echo "$(terraform apply)"'
deny_is ALLOW 'grep -r "terraform apply" docs/'
deny_is ALLOW 'echo "a && terraform apply"'
deny_is ALLOW 'git commit -m "a & terraform apply"'

# --- redirection must survive the `&` split -----------------------------------
deny_is DENY  'kubectl delete pod x 2>&1'
deny_is DENY  'terraform apply &> /tmp/o'
deny_is ALLOW 'kubectl get pods 2>&1'

# --- recursion depth cap fails CLOSED (a cap that allows is a bypass) ---------
# Innermost payload is benign, so a DENY here can only come from the cap itself.
deep='echo safe'
for _i in 1 2 3 4 5 6 7 8 9 10; do deep="\$($deep)"; done
deny_is DENY "$deep"
# ...and a shallow nest of the same shape stays ALLOW, proving the cap is what fired.
deny_is ALLOW '$($(echo safe))'

# --- basename must match exactly ----------------------------------------------
deny_is ALLOW 'terraform2 apply'
deny_is ALLOW 'myterraform apply'

# --- everything the old regex already caught: no regressions -----------------
deny_is DENY 'terraform apply'
deny_is DENY 'terraform apply -auto-approve'
deny_is DENY 'echo hi && terraform apply'
deny_is DENY 'FOO=1 terraform apply'
deny_is DENY '/usr/local/bin/terraform apply'
deny_is DENY 'terraform destroy'
deny_is DENY 'kubectl apply -f x.yaml'

# --- the destructive helm verbs that were missing entirely -------------------
deny_is DENY 'helm uninstall my-release'
deny_is DENY 'helm delete my-release'
deny_is DENY 'helm install r chart'
deny_is DENY 'helm upgrade r chart'

# --- no false positives: a deny-list that blocks real work gets disabled ------
deny_is ALLOW 'terraform plan'
deny_is ALLOW 'kubectl get pods'
deny_is ALLOW 'kubectl get pod delete-me'
deny_is ALLOW 'kubectl get pods -l app=delete'
deny_is ALLOW 'git commit -m "kubectl delete"'
deny_is ALLOW 'helm template r chart'
deny_is ALLOW 'sudo apt-get install terraform'
deny_is ALLOW 'git log --oneline'
# `echo terraform apply` is ALLOWED: the binary is echo. This is a deliberate change
# from the pre-2026-07-09 substring regex, which denied it. Recorded, not accidental.
deny_is ALLOW 'echo terraform apply'

# --- the local overlay: additive, gitignored, enforced -----------------------
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t denylist)"
trap 'rm -rf "$TMP"' EXIT
printf 'aws s3 rb\n' >"$TMP/local.txt"
deny_is ALLOW 'aws s3 rb s3://bucket'
deny_is DENY  'aws s3 rb s3://bucket' "$SPEC" "$TMP/local.txt"
deny_is DENY  'aws --profile prod s3 rb s3://bucket' "$SPEC" "$TMP/local.txt"
# defaults still enforced when an overlay is present
deny_is DENY  'terraform apply' "$SPEC" "$TMP/local.txt"

# --- no un-deny syntax: a leading '-' is an ordinary entry, not a removal -----
printf -- '-terraform apply\n' >"$TMP/undeny.txt"
deny_is DENY 'terraform apply' "$SPEC" "$TMP/undeny.txt"

# --- comments and blanks ignored ---------------------------------------------
printf '# a comment\n\n   \n' >"$TMP/empty.txt"
deny_is DENY 'terraform apply' "$SPEC" "$TMP/empty.txt"
deny_is ALLOW 'terraform plan' "$SPEC" "$TMP/empty.txt"

# --- the tracked defaults are never hand-edited: overlay keeps the tree clean --
# (the sync-brick this design exists to avoid: a modified TRACKED file aborts sync)
out="$(cd "$SCRIPTS_DIR/.." && git check-ignore scripts/deny-list.local.txt 2>&1)"
assert_eq "scripts/deny-list.local.txt" "$out" "deny-list.local.txt is gitignored"
out="$(cd "$SCRIPTS_DIR/.." && git ls-files scripts/deny-list.txt)"
assert_eq "scripts/deny-list.txt" "$out" "deny-list.txt is tracked (defaults reach every instance on sync)"

# --- pretooluse.sh fail-closed paths -----------------------------------------
GUARD="$SCRIPTS_DIR/../harnesses/antigravity/hooks/pretooluse.sh"
payload='{"toolCall":{"name":"run_command","args":{"CommandLine":"terraform plan"}}}'

# A PATH with the coreutils the hook needs, but deliberately WITHOUT jq/python3.
# (PATH=/nonexistent would kill the hook at `dirname`, testing nothing.)
NOPARSER_BIN="$TMP/bin"
mkdir -p "$NOPARSER_BIN"
for prog in dirname cat grep sed awk rm; do
    src="$(command -v "$prog" 2>/dev/null)"
    [ -n "$src" ] && ln -sf "$src" "$NOPARSER_BIN/$prog"
done
if [ -n "$(PATH="$NOPARSER_BIN" command -v jq 2>/dev/null)" ] || \
   [ -n "$(PATH="$NOPARSER_BIN" command -v python3 2>/dev/null)" ]; then
    _bad "test setup: stub PATH still exposes a JSON parser"
fi

BASH_BIN="$(command -v bash)"

# no jq AND no python3, under an executor role -> DENY (not skip)
out="$(printf '%s' "$payload" | env -i PATH="$NOPARSER_BIN" AI_MEMORY_ROLE=task "$BASH_BIN" "$GUARD" 2>/dev/null)"
case "$out" in
    *'"decision":"deny"'*) _ok "no JSON parser + guarded role -> deny (fails closed)" ;;
    *) _bad "no JSON parser + guarded role -> deny (got: '$out')" ;;
esac

# no parser, but NO role: interactive agy must stay unguarded
out="$(printf '%s' "$payload" | env -i PATH="$NOPARSER_BIN" "$BASH_BIN" "$GUARD" 2>/dev/null)"
case "$out" in
    *'"decision":"allow"'*) _ok "no JSON parser + interactive (no role) -> allow (human unaffected)" ;;
    *) _bad "no JSON parser + no role -> allow (got: '$out')" ;;
esac

# a MISSING deny-list must deny, not silently skip layer 1
FAKE_REPO="$TMP/repo"
mkdir -p "$FAKE_REPO/scripts" "$FAKE_REPO/harnesses/antigravity/hooks"
cp "$SCRIPTS_DIR/jsonutil.sh" "$SCRIPTS_DIR/deny-match.sh" "$FAKE_REPO/scripts/"
cp "$GUARD" "$FAKE_REPO/harnesses/antigravity/hooks/pretooluse.sh"
out="$(printf '%s' "$payload" | env AI_MEMORY_ROLE=task bash "$FAKE_REPO/harnesses/antigravity/hooks/pretooluse.sh" 2>/dev/null)"
case "$out" in
    *'"decision":"deny"'*) _ok "missing deny-list.txt + guarded role -> deny (cannot disarm the guard)" ;;
    *) _bad "missing deny-list.txt -> deny (got: '$out')" ;;
esac

# an EMPTY (or all-comment) deny-list must deny too: existence is not armed-ness.
# `: > deny-list.txt` disarms exactly as well as `rm` does.
printf '# only a comment\n\n' >"$FAKE_REPO/scripts/deny-list.txt"
out="$(printf '%s' "$payload" | env AI_MEMORY_ROLE=task bash "$FAKE_REPO/harnesses/antigravity/hooks/pretooluse.sh" 2>/dev/null)"
case "$out" in
    *'"decision":"deny"'*) _ok "rule-less deny-list.txt + guarded role -> deny (truncation cannot disarm)" ;;
    *) _bad "rule-less deny-list.txt -> deny (got: '$out')" ;;
esac

# ...and a populated one in the fake repo allows a benign command, proving the two
# denies above come from the guard's arming checks, not from the fake repo being broken.
printf 'terraform apply\n' >"$FAKE_REPO/scripts/deny-list.txt"
out="$(printf '%s' "$payload" | env AI_MEMORY_ROLE=task bash "$FAKE_REPO/harnesses/antigravity/hooks/pretooluse.sh" 2>/dev/null)"
case "$out" in
    *'"decision":"allow"'*) _ok "armed deny-list + benign command -> allow (arming checks are load-bearing)" ;;
    *) _bad "armed deny-list + benign command -> allow (got: '$out')" ;;
esac

finish
