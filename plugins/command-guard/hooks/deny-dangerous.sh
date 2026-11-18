#!/bin/bash
# command guard. Inspects every agent Bash command before it runs.
#
# Three models in one pass:
#   1. Denylist        dangerous-patterns.txt — allow by default, deny the
#                      irreversible (rm -rf /, dd, git push --force, gh/glab
#                      repo delete, keychain and password-manager access,
#                      cloud reads that hand over a credential).
#   2. Read allowlist  readonly-clis.txt — for a guarded CLI (each one that file
#                      names) deny by default and allow only the named reads.
#   3. Uncheckable     UNCHECKABLE below — deny what Claude Code's own command
#                      parser cannot check (an interpreter fed by a heredoc, a
#                      zsh-only expansion), which would otherwise wait on a
#                      permission prompt, in bypass mode too, for hours in an
#                      unattended run. The deny tells the agent how to rewrite it.
# Plus one habit check: a sleep loop polling a background task's output file is
# denied, since Claude Code notifies the agent when that task finishes.
# A shell script the command runs (bash x.sh, ./x.sh, source x.sh) goes through
# models 1 and 2 as well, read from disk, scripts it runs in turn included.
#
# Wired by hooks.json as PreToolUse, matcher Bash. Deny = exit 2 + reason on
# stderr, which Claude Code shows the agent and blocks the call.
#
# It is a seatbelt against accidents, NOT a sandbox against a malicious agent:
# variable indirection (K=kubectl; $K apply) and python -c slip past regex.
#
# Fail-open when jq is missing, and on the denylist, so a broken guard never
# bricks an agent. Fail-CLOSED on the read allowlist: denying the guarded CLIs
# is the team's status quo, while failing open there restores terraform apply.

set -f  # no globbing: command text is data, never patterns to expand

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/dangerous-patterns.txt"
ALLOW_FILE="$HOOK_DIR/readonly-clis.txt"

# Used only when ALLOW_FILE cannot be read, so stage 2 still knows what to deny.
# A copy of the CLIs ALLOW_FILE names; test-guard.sh fails when the two drift.
FALLBACK_CLIS="kubectl gcloud aws terraform terragrunt helm"

# Commands that run another command we cannot inspect. A segment led by one of
# these is denied as soon as it so much as mentions a guarded CLI.
WRAPPERS=" bash sh zsh dash ksh eval xargs nohup setsid "

# Interpreters that run a heredoc as code. Stage 2 leaves them alone, but the
# denylist keeps their heredoc bodies in view: os.system() runs what it names.
INTERPRETERS=" python python3 node ruby perl php osascript deno bun "

# Stage 3: an interpreter reading code from a heredoc or here-string, either
# order around a pipe, and zsh's ${(flags)…} and $=VAR expansions.
INTERP_RE='(python3?|node|ruby|perl|php|deno|bun|osascript)'
UNCHECKABLE="(^|[^A-Za-z0-9_.-])$INTERP_RE([[:space:]][^;&|]*)?<<|<<[^;&]*\|[[:space:]]*([^[:space:]]*/)?$INTERP_RE([[:space:]]|$)|\\\$\\{\\([^)]*\\)|\\\$=[A-Za-z_{]"

# Commands and shell keywords that merely prefix the real one, so the guarded
# CLI is still visible: "do kubectl delete pod" in a for loop runs kubectl.
PREFIX_RUNNERS=" sudo env command exec time nice ionice stdbuf timeout watch
if then else elif while until do ! { "
PREFIX_RUNNERS=" $(printf '%s ' $PREFIX_RUNNERS)"

# Shells that run a script file named as their first argument.
SCRIPT_SHELLS=" bash sh zsh dash ksh "

# How deep a script that runs a script is followed before the guard stops looking.
MAX_SCRIPT_DEPTH=4
SCRIPT_DEPTH=${GUARD_SCRIPT_DEPTH:-0}
# The largest script file the guard reads, in bytes; a larger one runs unread.
MAX_SCRIPT_BYTES=262144

# Flags taking a separate value, so the token after them is not a verb.
VALUE_FLAGS=" -n --namespace --context --kubeconfig --cluster --user -o --output
-l --selector --field-selector --since --tail -c --container --project --account
--format --filter --region --zone --configuration --chdir -chdir --var-file
-var-file --var -var --state -state --out -out --target -target --backend-config
--working-dir --terragrunt-working-dir --kube-context --values --set --repo --limit
--profile --endpoint-url --query --ca-bundle --cli-read-timeout --cli-connect-timeout "
# One line, so the flag opening each continuation line still matches " $tok ".
VALUE_FLAGS=" $(printf '%s ' $VALUE_FLAGS)"

deny() {
  echo "$1 Do not retry it or try to work around the guard; explain the block to the user instead." >&2
  exit 2
}

# Arguments of one CLI invocation, minus the leading flags, so the verb comes first.
strip_flags() {
  local tok skip=0 rest=""
  for tok in $1; do
    if [ -n "$rest" ]; then rest="$rest $tok"; continue; fi
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$tok" in
      -*)
        case "$tok" in
          *=*) ;;
          *) case "$VALUE_FLAGS" in *" $tok "*) skip=1 ;; esac ;;
        esac
        ;;
      *) rest="$tok" ;;
    esac
  done
  printf '%s' "$rest"
}

# The command a segment actually runs: leading VAR=val, flags and prefix runners
# (sudo, timeout, watch) skipped, path stripped, so /usr/local/bin/kubectl is kubectl.
command_of() {
  local tok skip=0 prev=""
  for tok in $1; do
    # command -v/-V looks names up in PATH and runs none of them.
    if [ "$prev" = command ]; then
      case "$tok" in -[!-]*[vV]*|-[vV]*) return ;; esac
    fi
    prev=$tok
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$tok" in
      -*)
        case "$tok" in
          *=*) ;;
          *) case "$VALUE_FLAGS" in *" $tok "*) skip=1 ;; esac ;;
        esac
        continue ;;
      *=*) continue ;;
      [0-9]*) continue ;;
    esac
    case "$PREFIX_RUNNERS" in *" $tok "*) continue ;; esac
    printf '%s' "${tok##*/}"
    return
  done
}

# The command line with heredoc bodies dropped: a body is data (a commit message,
# a file written with cat), not a command. $2 lists the commands that run their
# heredoc; a line naming one of them keeps its body visible.
strip_heredocs() {
  printf '%s\n' "$1" | awk -v runner="$(echo $2 | tr -s ' ' '|')" '
    skip {
      line = $0
      if (dash) sub(/^\t+/, "", line)
      if (line == delim) skip = 0
      next
    }
    {
      if (match($0, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) &&
          substr($0, RSTART, 3) != "<<<" &&
          $0 !~ ("(^|[[:space:];&|(`\"\047])([^[:space:]]*/)?(" runner ")([[:space:]<;&|)]|$)")) {
        delim = substr($0, RSTART, RLENGTH)
        dash = (substr(delim, 3, 1) == "-")
        sub(/^<<-?[[:space:]]*["\047]?/, "", delim)
        skip = 1
      }
      print
    }'
}

# The command line split into the segments stage 2 inspects: heredoc bodies
# dropped, and separators honoured only outside quotes. Both carry data, not
# commands, so a guarded CLI named there is prose, not an invocation. A wrapper
# runs its heredoc, so that body stays visible.
segments() {
  strip_heredocs "$1" "$WRAPPERS" | awk '
    { buf = buf $0 "\n" }
    END {
      for (i = 1; i <= length(buf); i++) {
        c = substr(buf, i, 1)
        if (quote != "") { if (c == quote) quote = ""; seg = seg c; continue }
        if (c == "\"" || c == "\047") { quote = c; seg = seg c; continue }
        # The & of a redirection (2>&1, &>file) joins, it does not separate.
        if (c == "&" && (substr(buf, i - 1, 1) == ">" || substr(buf, i + 1, 1) == ">")) { seg = seg c; continue }
        if (index(";&|`()\n", c)) { print seg; seg = ""; continue }
        seg = seg c
      }
      print seg
    }'
}

# True when a segment does nothing but delete Dependabot's branches on origin:
# git [-C <path>] push [origin] (--delete|-d) dependabot-<x> …, or the
# :dependabot-<x> refspec. triage-dependency-bumps closes the bot MRs and deletes
# their branches; every other remote delete stays on the denylist (rule 6b).
# Only -C passes: -c could repoint origin (-c remote.origin.url=…).
dependabot_delete() {
  local tok refs=0 deletes=0
  set -- $1
  [ "$1" = git ] || return 1
  shift
  if [ "$1" = -C ]; then
    case "$2" in ''|*[!A-Za-z0-9._/~-]*) return 1 ;; esac
    shift 2
  fi
  [ "$1" = push ] || return 1
  shift
  for tok in "$@"; do
    case "$tok" in
      origin) continue ;;
      # Output redirections to /dev/null or another fd only: the segment leaves
      # the denylist, so a write anywhere else (> /dev/disk0) must not ride along.
      [0-9]\>\&[0-9]|\>\&[0-9]|\>/dev/null|[0-9]\>/dev/null|\&\>/dev/null) continue ;;
      --delete|-d) deletes=1; continue ;;
      :*) deletes=1; tok=${tok#:} ;;
    esac
    case "$tok" in
      dependabot-*) ;;
      *) return 1 ;;
    esac
    case "$tok" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
    refs=$((refs+1))
  done
  [ "$deletes" = 1 ] && [ "$refs" -gt 0 ]
}

# The script file a segment runs, as "<kind> <path>": "arg" for bash x.sh,
# sh x.sh, source x.sh and . x.sh, "exec" for ./x.sh or any other path run
# directly. Empty when the segment runs no file: bash -c "…" is inline code,
# which the wrapper check covers.
script_of() {
  local tok cmd=""
  for tok in $1; do
    if [ -z "$cmd" ]; then
      case "$tok" in -*|*=*|[0-9]*) continue ;; esac
      case "$PREFIX_RUNNERS" in *" $tok "*) continue ;; esac
      cmd=$tok
      case "$SCRIPT_SHELLS" in *" ${tok##*/} "*) continue ;; esac
      case "$tok" in
        source|.) continue ;;
        */*) printf 'exec %s' "$tok"; return ;;
        *) return ;;
      esac
    fi
    case "$tok" in
      -c|-[!-]*c*) return ;;
      -*) continue ;;
      \<*|\>*|[0-9]\>*) return ;;
    esac
    printf 'arg %s' "$tok"
    return
  done
}

# The directory a "cd <dir>" segment moves to from $2, or $2 when it is no cd
# the guard can follow.
cd_target() {
  local from=$2 dir
  set -- $1
  [ "$1" = cd ] && [ $# -eq 2 ] || { printf '%s' "$from"; return; }
  dir=${2#[\"\']}; dir=${dir%[\"\']}
  case "$dir" in
    '~') dir=$HOME ;;
    '~/'*) dir="$HOME/${dir#\~/}" ;;
    *'$'*|*'`'*|-) dir=$from ;;
    /*) ;;
    *) dir="$from/$dir" ;;
  esac
  printf '%s' "$dir"
}

# A shell script run from the command line is a command line too: read it and
# put it through the whole guard, so bash deploy.sh cannot carry what the guard
# denies inline. $1 = kind and path from script_of, $2 = directory it runs in.
inspect_script() {
  local kind=${1%% *} path=${1#* } dir=$2 file reason first
  [ "$SCRIPT_DEPTH" -lt "$MAX_SCRIPT_DEPTH" ] || return 0
  path=${path#[\"\']}; path=${path%[\"\']}
  case "$path" in
    '~/'*) path="$HOME/${path#\~/}" ;;
    ''|*'$'*|*'`'*) return 0 ;;
  esac
  case "$path" in
    /*) file=$path ;;
    *)
      file="$dir/$path"
      [ -f "$file" ] || [ -z "$GUARD_SCRIPT_DIR" ] || file="$GUARD_SCRIPT_DIR/$path" ;;
  esac
  # A file that is missing, binary or too large runs unread: the guard checks
  # shell text, and a missing file fails on its own.
  [ -f "$file" ] && [ -r "$file" ] || return 0
  [ "$(wc -c < "$file")" -le "$MAX_SCRIPT_BYTES" ] || return 0
  grep -Iq . "$file" 2>/dev/null || return 0
  if [ "$kind" = exec ]; then
    first=$(head -n 1 "$file")
    case "$first" in
      '#!'*) printf '%s\n' "$first" | grep -qE '^#!.*[/[:space:]](ba|z|da|k)?sh([[:space:]]|$)' || return 0 ;;
    esac
  fi
  # Comment lines dropped and continuation lines joined, so a script reads like
  # the one-line commands the guard was written for.
  reason=$(awk '
      /^[[:space:]]*#/ { next }
      { if (sub(/\\$/, "")) { buf = buf $0 " "; next } print buf $0; buf = "" }
      END { if (buf != "") print buf }' "$file" |
    jq -Rsc --arg d "$dir" '{tool_input:{command:.},cwd:$d}' |
    GUARD_SCRIPT_DEPTH=$((SCRIPT_DEPTH+1)) GUARD_SCRIPT_DIR=$(dirname "$file") \
      /bin/bash "$HOOK_DIR/deny-dangerous.sh" 2>&1 >/dev/null)
  if [ $? -eq 2 ]; then
    echo "Blocked by the command guard: the script $path runs a command the guard denies. $reason" >&2
    exit 2
  fi
}

guarded_clis() {
  if [ -r "$ALLOW_FILE" ]; then
    awk '$1 !~ /^#/ && NF { print $1 }' "$ALLOW_FILE" | sort -u
  else
    printf '%s\n' $FALLBACK_CLIS
  fi
}

# Without jq we cannot read the command: fail open rather than break agents.
command -v jq >/dev/null 2>&1 || exit 0

# .tool_input = Claude Code and Codex, .toolInput = Grok in Claude-compat mode.
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .toolInput.command // .command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0
RUN_DIR=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
RUN_DIR=${RUN_DIR:-$PWD}

# --- exemption: deleting Dependabot's branches -------------------------------
# With an exempt segment present, the denylist sees the other segments only,
# one per line, so a delete of anything else in the same command still matches.
# Otherwise it sees the whole command line minus data-only heredoc bodies.
DENY_CMD=$(strip_heredocs "$CMD" "$WRAPPERS $INTERPRETERS")
exempt=0
rest=""
while IFS= read -r segment; do
  if dependabot_delete "$segment"; then exempt=1; else rest="$rest$segment
"; fi
done <<SEGMENTS
$(segments "$CMD")
SEGMENTS
[ "$exempt" = 1 ] && DENY_CMD=$rest

# --- stage 1: denylist, matched against the command line in DENY_CMD ---------
if [ -r "$PATTERNS_FILE" ]; then
  while IFS= read -r pattern; do
    case "$pattern" in ''|\#*) continue ;; esac
    if printf '%s\n' "$DENY_CMD" | grep -qE -- "$pattern" 2>/dev/null; then
      deny "Blocked by the command guard (plugins/command-guard/hooks/dangerous-patterns.txt in miwurster/skills). Matched pattern: $pattern."
    fi
  done < "$PATTERNS_FILE"
fi

# --- polling a background task: the harness already notifies on completion ---
# An until/while loop that sleeps, in a command naming a Claude Code background
# task's output file (<claude temp dir>/…/tasks/<id>.output), directly or via a
# variable set in the same command. A one-shot cat or tail of the file passes.
TASK_OUTPUT_RE='/claude-[^/[:space:]]*/([^[:space:]]*/)?tasks/[A-Za-z0-9_-]+\.output'
POLL_LOOP_RE='(^|[^A-Za-z0-9_.-])(until|while)[[:space:]]'
SLEEP_RE='(^|[^A-Za-z0-9_.-])sleep[[:space:]]'
# A script body is not what Claude Code parses or polls with, so the poll and
# stage 3 checks are for the command line alone.
[ "$SCRIPT_DEPTH" -gt 0 ] && CHECK_CMD="" || CHECK_CMD=$CMD
case "$CHECK_CMD" in
  *tasks/*.output*)
    POLL_CMD=$(strip_heredocs "$CMD" "$WRAPPERS")
    if printf '%s\n' "$POLL_CMD" | grep -qE -- "$TASK_OUTPUT_RE" &&
       printf '%s\n' "$POLL_CMD" | grep -qE -- "$POLL_LOOP_RE" &&
       printf '%s\n' "$POLL_CMD" | grep -qE -- "$SLEEP_RE"; then
      echo "Blocked by the command guard: this loop polls a background task's output file. The task notifies you when it finishes; wait for that notification, then read the output file once." >&2
      exit 2
    fi ;;
esac

# --- stage 3: uncheckable, matched against the command minus data heredocs ---
# Checked before stage 2 runs, but after the denylist, so an irreversible
# command keeps its own deny. The case filter keeps plain commands free of it.
case "$CHECK_CMD" in
  *'<<'*|*'${('*|*'$='*)
    if strip_heredocs "$CMD" "$WRAPPERS" | grep -qE -- "$UNCHECKABLE"; then
      echo "Blocked by the command guard: Claude Code cannot parse this command, so it would wait on a permission prompt. Edit files with the Edit or Write tool, and give each Bash call one plain POSIX command line; then go on." >&2
      exit 2
    fi ;;
esac

# --- stage 2: read allowlist, matched per command segment -------------------
# Segment so an allowed read cannot smuggle a mutation: "cd /tmp && kubectl apply".
CLIS=$(guarded_clis)
while IFS= read -r segment; do
  [ -z "$segment" ] && continue
  command=$(command_of "$segment")
  [ -z "$command" ] && continue
  RUN_DIR=$(cd_target "$segment" "$RUN_DIR")

  script=$(script_of "$segment")
  [ -n "$script" ] && inspect_script "$script" "$RUN_DIR"

  # A wrapper hides its payload from us, so any mention of a guarded CLI is enough.
  case "$WRAPPERS" in
    *" $command "*)
      for cli in $CLIS; do
        printf '%s\n' "$segment" | grep -qE -- "(^|[^A-Za-z0-9_-])$cli([^A-Za-z0-9_-]|$)" &&
          deny "Blocked by the command guard: a $cli command inside '$command' cannot be inspected, so it is denied. Run the read directly instead."
      done
      continue ;;
  esac

  for cli in $CLIS; do
    [ "$command" = "$cli" ] || continue

    [ -r "$ALLOW_FILE" ] ||
      deny "Blocked by the command guard: the read allowlist ($ALLOW_FILE) is unreadable, so every $cli command is denied."

    args=$(strip_flags "${segment#*$cli}")
    allowed=0
    while read -r allow_cli allow_pattern; do
      [ -z "$allow_cli" ] && continue
      case "$allow_cli" in \#*) continue ;; esac
      [ "$allow_cli" = "$cli" ] || continue
      printf '%s\n' "$args" | grep -qE -- "$allow_pattern" && { allowed=1; break; }
    done < "$ALLOW_FILE"

    [ "$allowed" = 1 ] ||
      deny "Blocked by the command guard: only reads are allowed for $cli, and '$cli $args' is not one of them (plugins/command-guard/hooks/readonly-clis.txt in miwurster/skills). If this really is a read, the fix is one line in that file plus a case in test-guard.sh, made there and synced here."
  done
done <<SEGMENTS
$(segments "$CMD")
SEGMENTS

exit 0
