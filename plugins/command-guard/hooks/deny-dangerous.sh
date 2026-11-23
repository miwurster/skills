#!/bin/bash
# command guard. Inspects every agent Bash command before it runs.
#
# Three models in one pass:
#   1. Denylist        dangerous-patterns.txt — allow by default, deny the
#                      irreversible (rm -rf /, dd, git push --force, gh/glab
#                      repo delete, keychain and password-manager access,
#                      cloud reads that hand over a credential).
#                      credential-patterns.txt names the ones that read a secret.
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
# So does the command ssh runs on a remote host, as if it ran here.
#
# Wired by hooks.json as PreToolUse, matcher Bash. A block ends on one of two exits:
#   rewrite    stage 3 and the poll check: exit 2 + reason on stderr, which names
#              the alternative; the agent goes on.
#   hand over  denylist and read allowlist: PreToolUse JSON on stdout, deny, with
#              the command for the user in systemMessage; the agent hands it over
#              and ends its turn. A credential read is explained only, never
#              handed over: running it would put the secret into the conversation.
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
CREDENTIALS_FILE="$HOOK_DIR/credential-patterns.txt"

# Used only when ALLOW_FILE cannot be read, so stage 2 still knows what to deny.
# A copy of the CLIs ALLOW_FILE names; test-guard.sh fails when the two drift.
FALLBACK_CLIS="kubectl gcloud aws terraform terragrunt helm stripe"

# Commands that run another command we cannot inspect. A segment led by one of
# these is denied as soon as it so much as mentions a guarded CLI.
WRAPPERS=" bash sh zsh dash ksh eval xargs nohup setsid "

# Commands whose heredoc body is commands the guard reads line by line.
HEREDOC_SHELLS="$WRAPPERS ssh "

# ssh options that take a value, so the word after them is not the host.
SSH_VALUE_OPTS="bceilmopBDEFIJLOPQRSWw"

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

# How deep a script that runs a script, or an ssh command, is followed before
# the guard stops looking.
MAX_SCRIPT_DEPTH=4
SCRIPT_DEPTH=${GUARD_SCRIPT_DEPTH:-0}
# 1 when the command text comes from a script file, whose quoted strings are data.
IN_SCRIPT=${GUARD_IN_SCRIPT:-0}
# 1 when the command runs on a remote host, where local script files do not exist.
REMOTE=${GUARD_REMOTE:-0}
# The largest script file the guard reads, in bytes; a larger one runs unread.
MAX_SCRIPT_BYTES=262144

# Flags taking a separate value, so the token after them is not a verb.
VALUE_FLAGS=" -n --namespace --context --kubeconfig --cluster --user -o --output
-l --selector --field-selector --since --tail -c --container --project --account
--format --filter --region --zone --configuration --chdir -chdir --var-file
-var-file --var -var --state -state --out -out --target -target --backend-config
--working-dir --terragrunt-working-dir --kube-context --values --set --repo --limit
--profile --endpoint-url --query --ca-bundle --cli-read-timeout --cli-connect-timeout
--api-key --project-name --config --log-level --device-name "
# One line, so the flag opening each continuation line still matches " $tok ".
VALUE_FLAGS=" $(printf '%s ' $VALUE_FLAGS)"

# Flags that take a value after a guarded CLI only. A prefix runner reads them
# differently (command -p, watch --color), so command_of must not skip past them.
CLI_VALUE_FLAGS=" -p --color "

# Denies the call as PreToolUse JSON: $1 = systemMessage for the user, $2 = reason for the agent.
deny_json() {
  jq -nc --arg m "$1" --arg r "$2" \
    '{systemMessage:$m,hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# A nested run (a script, an ssh command) reports to the run above it instead:
# exit 2 = hand over, exit 3 = explain only, reason on stderr. The top run names
# the command the agent ran.
hand_over() {
  [ "$SCRIPT_DEPTH" -gt 0 ] && { echo "$1" >&2; exit 2; }
  deny_json "Command guard blocked this command. To run it yourself: ! $CMD" \
    "$1 Hand it over: give the user the exact, complete command in a code block, to run themselves by typing ! followed by it in the Claude Code prompt, say in one sentence what it does, and end your turn there. As a subagent, put the command verbatim in your final report under 'Hand over', so the orchestrator passes it on."
}

explain_only() {
  [ "$SCRIPT_DEPTH" -gt 0 ] && { echo "$1" >&2; exit 3; }
  deny_json "Command guard blocked this command: it reads a credential." \
    "$1 Explain to the user that the guard blocks reading this credential, and end your turn. As a subagent, say so in your final report, so the orchestrator passes it on."
}

# A nested run's verdict, exit code $1 with reason $2, as this run's own.
nested_block() {
  case "$1" in
    2) hand_over "$2" ;;
    3) explain_only "$2" ;;
  esac
}

# One shell word: a quoted string stays inside its word, quotes kept, so
# FOO="kubectl get" is one assignment and "my file.sh" one path.
WORD_RE='^[[:space:]]*((\\.|[^[:space:]\\"'\'']|"([^"\\]|\\.)*"|'\''[^'\'']*'\'')+)(.*)$'

# The words of segment $1, in WORDS.
split_words() {
  local rest=$1
  WORDS=()
  while [[ $rest =~ $WORD_RE ]]; do
    WORDS[${#WORDS[@]}]=${BASH_REMATCH[1]}
    rest=${BASH_REMATCH[4]}
  done
}

# Arguments of one CLI invocation, the WORDS from index $1 on, minus the leading
# flags, so the verb comes first. Sets ARGS.
strip_flags() {
  local i=$1 tok skip=0 rest=""
  while [ "$i" -lt ${#WORDS[@]} ]; do
    tok=${WORDS[$i]}
    i=$((i+1))
    if [ -n "$rest" ]; then rest="$rest $tok"; continue; fi
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$tok" in
      -*)
        case "$tok" in
          *=*) ;;
          *) case "$VALUE_FLAGS$CLI_VALUE_FLAGS" in *" $tok "*) skip=1 ;; esac ;;
        esac
        ;;
      *) rest="$tok" ;;
    esac
  done
  ARGS=$rest
}

# The command the segment in WORDS actually runs: leading VAR=val, flags and
# prefix runners (sudo, timeout, watch) skipped, path stripped, so
# /usr/local/bin/kubectl is kubectl. Sets COMMAND, and COMMAND_AT to the index
# of the word after it.
command_of() {
  local i=0 tok skip=0 prev=""
  COMMAND="" COMMAND_AT=0
  while [ "$i" -lt ${#WORDS[@]} ]; do
    tok=${WORDS[$i]}
    i=$((i+1))
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
    COMMAND=${tok##*/}
    COMMAND_AT=$i
    return
  done
}

# The words in $1 joined by |, in ALTERNATION.
alternation() {
  local words IFS=$' \t\n'
  words=($1)
  IFS='|'
  ALTERNATION="${words[*]}"
}

# The command line with heredoc bodies dropped: a body is data (a commit message,
# a file written with cat), not a command. $2 lists the commands that run their
# heredoc; a line naming one of them keeps its body visible. A << inside quotes
# or a comment is text, but one inside a $(…) or `…` in double quotes is code.
strip_heredocs() {
  alternation "$2"
  printf '%s\n' "$1" | awk -v runner="$ALTERNATION" '
    BEGIN { ctx = "T" }
    function top() { return substr(ctx, length(ctx)) }
    function push(c) { ctx = ctx c }
    function pop() { if (length(ctx) > 1) ctx = substr(ctx, 1, length(ctx) - 1) }
    skip {
      line = $0
      if (dash) sub(/^\t+/, "", line)
      if (line == delim) skip = 0
      next
    }
    {
      start = 0
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1); t = top()
        if (t == "S") { if (c == "\047") pop(); continue }
        if (t == "A") { if (c == "\\") i++; else if (c == "\047") pop(); continue }
        if (c == "\\") { i++; continue }
        if (t == "D") {
          if (c == "\"") pop()
          else if (c == "`") push("B")
          else if (substr($0, i, 2) == "$(") { push("P"); i++ }
          continue
        }
        if (c == "\047") { push(substr($0, i - 1, 1) == "$" ? "A" : "S"); continue }
        if (c == "\"") { push("D"); continue }
        if (c == "`") { if (t == "B") pop(); else push("B"); continue }
        if (c == "(") { if (t == "P") push("P"); continue }
        if (c == ")") { if (t == "P") pop(); continue }
        if (c == "#" && (i == 1 || substr($0, i - 1, 1) ~ /[[:space:];&|(]/)) break
        if (substr($0, i, 3) == "<<<") { i += 2; continue }
        if (substr($0, i, 2) == "<<") {
          if (!start && match(substr($0, i), /^<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
            start = i; len = RLENGTH
            i += len - 1
            if (substr($0, start, len) ~ /["\047][A-Za-z_][A-Za-z0-9_]*$/) i++
          } else i++
          continue
        }
      }
      if (start && $0 !~ ("(^|[[:space:];&|(`\"\047])([^[:space:]]*/)?(" runner ")([[:space:]<;&|)]|$)")) {
        delim = substr($0, start, len)
        dash = (substr(delim, 3, 1) == "-")
        sub(/^<<-?[[:space:]]*["\047]?/, "", delim)
        skip = 1
      }
      print
    }'
}

# Script text $1 with the text of its quoted strings dropped, since a script
# passes data around in them (echo 'rm -rf ~'). A string stays when its pipeline
# runs it: a wrapper, an interpreter, trap or a -c flag outside quotes, or a $(…)
# or `…` inside double quotes. Heredoc bodies left in $1 run, so they stay too.
# A string that runs also gets a line of its own at the end, unquoted, so a
# pattern finds bash -c 'rm -rf ~' as the rm -rf ~ it runs.
drop_data_quotes() {
  alternation "$WRAPPERS $INTERPRETERS trap"
  printf '%s\n' "$1" | awk -v runner="$ALTERNATION" '
    function end_word(  w) {
      w = word
      sub(/.*\//, "", w)
      if (w != "" && !quoted && (w ~ ("^(" runner ")$") || w ~ /^-[A-Za-z]*c$/)) runs = 1
      word = ""; quoted = 0
    }
    function add(s) { kept = kept s; dropped = dropped s }
    function flush(sep) {
      end_word()
      printf "%s%s", (runs ? kept : dropped), sep
      if (runs) unquoted = unquoted strings
      kept = ""; dropped = ""; strings = ""; runs = 0
    }
    body {
      print
      line = $0
      if (dash) sub(/^\t+/, "", line)
      if (line == delim) body = 0
      next
    }
    {
      s = $0 "\n"
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (quote != "") {
          str = str c
          if ((quote == "\"" || ansi) && c == "\\") { i++; str = str substr(s, i, 1); continue }
          if (c != quote) continue
          kept = kept str
          strings = strings substr(str, 2, length(str) - 2) "\n"
          if (quote == "\"" && (index(str, "$(") || index(str, "`"))) dropped = dropped str
          else dropped = dropped quote quote
          quote = ""
          continue
        }
        if (c == " " || c == "\t" || (c == "\n" && piped)) { end_word(); add(c); continue }
        piped = 0
        if (c == "#" && word == "" && !quoted) { add(substr(s, i, length(s) - i)); i = length(s) - 1; continue }
        if (c == "\\") { i++; c = c substr(s, i, 1); word = word c; add(c); continue }
        if (c == "\"" || c == "\047") {
          ansi = (c == "\047" && substr(word, length(word)) == "$")
          quote = c; str = c; quoted = 1; continue
        }
        if (substr(s, i, 2) == "<<" && substr(s, i, 3) != "<<<" && substr(s, i - 1, 1) != "<" &&
            match(substr(s, i), /^<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
          delim = substr(s, i, RLENGTH)
          dash = (substr(delim, 3, 1) == "-")
          sub(/^<<-?[[:space:]]*["\047]?/, "", delim)
          opened = 1
        }
        if (c == "|" && substr(s, i + 1, 1) != "|") { end_word(); add(c); piped = 1; continue }
        if (c == "&" && (substr(s, i - 1, 1) == ">" || substr(s, i + 1, 1) == ">")) { word = word c; add(c); continue }
        if (index(";&|`()\n", c)) { flush(c); continue }
        word = word c; add(c)
      }
      if (opened && quote == "") { body = 1; opened = 0 }
    }
    END { if (quote != "") add(str); flush("\n"); printf "%s", unquoted }'
}

# The command line split into the segments stage 2 inspects: heredoc bodies
# dropped, and separators honored only outside quotes. Both carry data, not
# commands, so a guarded CLI named there is prose, not an invocation. A wrapper
# or ssh runs its heredoc, so that body stays visible.
segments() {
  strip_heredocs "$1" "$HEREDOC_SHELLS" | awk '
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

# The script file the segment in WORDS runs, as "<kind> <path>": "arg" for
# bash x.sh, sh x.sh, source x.sh and . x.sh, "exec" for ./x.sh or any other
# path run directly. Empty when the segment runs no file: bash -c "…" is inline
# code, which the wrapper check covers. Sets SCRIPT.
script_of() {
  local tok cmd=""
  SCRIPT=""
  for tok in "${WORDS[@]}"; do
    if [ -z "$cmd" ]; then
      case "$tok" in -*|*=*|[0-9]*) continue ;; esac
      case "$PREFIX_RUNNERS" in *" $tok "*) continue ;; esac
      cmd=$tok
      case "$SCRIPT_SHELLS" in *" ${tok##*/} "*) continue ;; esac
      case "$tok" in
        source|.) continue ;;
        */*) SCRIPT="exec $tok"; return ;;
        *) return ;;
      esac
    fi
    case "$tok" in
      -c|-[!-]*c*) return ;;
      -*) continue ;;
      \<*|\>*|[0-9]\>*) return ;;
    esac
    SCRIPT="arg $tok"
    return
  done
}

# The directory the segment in WORDS moves RUN_DIR to, when it is a cd the
# guard can follow.
cd_target() {
  local dir
  [ "${WORDS[0]}" = cd ] && [ ${#WORDS[@]} -eq 2 ] || return
  dir=${WORDS[1]#[\"\']}; dir=${dir%[\"\']}
  case "$dir" in
    '~') dir=$HOME ;;
    '~/'*) dir="$HOME/${dir#\~/}" ;;
    *'$'*|*'`'*|-) return ;;
    /*) ;;
    *) dir="$RUN_DIR/$dir" ;;
  esac
  RUN_DIR=$dir
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
    GUARD_SCRIPT_DEPTH=$((SCRIPT_DEPTH+1)) GUARD_IN_SCRIPT=1 GUARD_SCRIPT_DIR=$(dirname "$file") \
      /bin/bash "$HOOK_DIR/deny-dangerous.sh" 2>&1 >/dev/null)
  nested_block $? "Blocked by the command guard: the script $path runs a command the guard denies. $reason"
}

# Word $1 with one level of shell quoting removed, in UNQUOTED.
unquote() {
  local w=$1 out="" c q="" i=0
  while [ "$i" -lt ${#w} ]; do
    c=${w:i:1}
    i=$((i+1))
    if [ "$q" = "'" ]; then
      [ "$c" = "'" ] && q="" || out=$out$c
      continue
    fi
    if [ "$q" = '"' ]; then
      case "$c" in
        '"') q="" ;;
        \\)
          case "${w:i:1}" in
            '$'|'`'|'"'|\\) out=$out${w:i:1}; i=$((i+1)) ;;
            *) out=$out$c ;;
          esac ;;
        *) out=$out$c ;;
      esac
      continue
    fi
    case "$c" in
      "'"|'"') q=$c ;;
      \\) out=$out${w:i:1}; i=$((i+1)) ;;
      *) out=$out$c ;;
    esac
  done
  UNQUOTED=$out
}

# A redirection word, and one whose target is the next word.
REDIRECT_RE='^([0-9]*|&)[<>]'
REDIRECT_OP_RE='^([0-9]*|&)(<+|>+)&?$'

# The command the ssh segment in WORDS runs on the remote host: its words after
# the options and the host, unquoted and joined by spaces, as ssh sends them.
# Local redirections are left out. Sets SSH_HOST and REMOTE_CMD.
remote_command_of() {
  local i=$COMMAND_AT tok opts=1 j
  SSH_HOST="" REMOTE_CMD=""
  while [ "$i" -lt ${#WORDS[@]} ]; do
    tok=${WORDS[$i]}
    i=$((i+1))
    if [[ $tok =~ $REDIRECT_RE ]]; then
      [[ $tok =~ $REDIRECT_OP_RE ]] && i=$((i+1))
      continue
    fi
    if [ "$opts" = 1 ]; then
      case "$tok" in
        --) opts=0; continue ;;
        -?*)
          for ((j = 1; j < ${#tok}; j++)); do
            case "$SSH_VALUE_OPTS" in
              *"${tok:j:1}"*) [ $((j+1)) -eq ${#tok} ] && i=$((i+1)); break ;;
            esac
          done
          continue ;;
      esac
    fi
    if [ -z "$SSH_HOST" ]; then SSH_HOST=$tok; continue; fi
    opts=0
    unquote "$tok"
    REMOTE_CMD="${REMOTE_CMD:+$REMOTE_CMD }$UNQUOTED"
  done
}

# ssh runs its command on another host: put that command through the whole
# guard, so ssh cannot carry what the guard denies here.
inspect_remote() {
  local reason
  remote_command_of
  [ -n "$REMOTE_CMD" ] && [ "$SCRIPT_DEPTH" -lt "$MAX_SCRIPT_DEPTH" ] || return 0
  reason=$(jq -nc --arg c "$REMOTE_CMD" --arg d "$RUN_DIR" '{tool_input:{command:$c},cwd:$d}' |
    GUARD_SCRIPT_DEPTH=$((SCRIPT_DEPTH+1)) GUARD_IN_SCRIPT=$IN_SCRIPT GUARD_REMOTE=1 \
      /bin/bash "$HOOK_DIR/deny-dangerous.sh" 2>&1 >/dev/null)
  nested_block $? "Blocked by the command guard: the command ssh runs on $SSH_HOST is one the guard denies. $reason"
}

# The guarded CLIs in CLIS, and the allowlist lines in ALLOW_CLI and ALLOW_RE.
load_allowlist() {
  local allow_cli allow_pattern
  CLIS=" " ALLOW_CLI=() ALLOW_RE=()
  if [ ! -r "$ALLOW_FILE" ]; then
    CLIS=$FALLBACK_CLIS
    return
  fi
  while read -r allow_cli allow_pattern; do
    case "$allow_cli" in ''|\#*) continue ;; esac
    ALLOW_CLI[${#ALLOW_CLI[@]}]=$allow_cli
    ALLOW_RE[${#ALLOW_RE[@]}]=$allow_pattern
    case "$CLIS" in *" $allow_cli "*) ;; *) CLIS="$CLIS$allow_cli " ;; esac
  done < "$ALLOW_FILE"
}

# Without jq we cannot read the command: fail open rather than break agents.
command -v jq >/dev/null 2>&1 || exit 0

# .tool_input = Claude Code and Codex, .toolInput = Grok in Claude-compat mode.
# One jq call reads both fields; @sh quotes them for eval.
CMD="" RUN_DIR=""
eval "$(jq -r '@sh "CMD=\(.tool_input.command // .toolInput.command // .command // "") RUN_DIR=\(.cwd // "")"' 2>/dev/null)"
while [[ $CMD == *$'\n' ]]; do CMD=${CMD%$'\n'}; done
[ -z "$CMD" ] && exit 0
RUN_DIR=${RUN_DIR:-$PWD}

# --- exemption: deleting Dependabot's branches -------------------------------
# With an exempt segment present, the denylist sees the other segments only,
# one per line, so a delete of anything else in the same command still matches.
# Otherwise it sees the whole command line minus data-only heredoc bodies.
DENY_CMD=$(strip_heredocs "$CMD" "$HEREDOC_SHELLS $INTERPRETERS")
[ "$IN_SCRIPT" = 1 ] && DENY_CMD=$(drop_data_quotes "$DENY_CMD")
SEGMENTS=$(segments "$CMD")
exempt=0
rest=""
while IFS= read -r segment; do
  if dependabot_delete "$segment"; then exempt=1; else rest="$rest$segment
"; fi
done <<SEGMENTS
$SEGMENTS
SEGMENTS
[ "$exempt" = 1 ] && DENY_CMD=$rest

# --- stage 1: denylist, matched against the command line in DENY_CMD ---------
# The pattern of file $1 that DENY_CMD matches, in MATCHED. One grep for all
# patterns; only a hit, or a pattern grep cannot compile, goes through them one
# by one to name the match.
first_match() {
  local pattern patterns=()
  MATCHED=""
  [ -r "$1" ] || return 1
  while IFS= read -r pattern; do
    case "$pattern" in ''|\#*) continue ;; esac
    patterns[${#patterns[@]}]=$pattern
  done < "$1"
  [ ${#patterns[@]} -gt 0 ] || return 1
  printf '%s\n' "$DENY_CMD" | grep -qE "${patterns[@]/#/-e}" 2>/dev/null
  [ $? -ne 1 ] || return 1
  for pattern in "${patterns[@]}"; do
    if printf '%s\n' "$DENY_CMD" | grep -qE -- "$pattern" 2>/dev/null; then
      MATCHED=$pattern
      return 0
    fi
  done
  return 1
}

# Credential reads first, so a command that also matches another pattern is
# still explained only.
first_match "$CREDENTIALS_FILE" &&
  explain_only "Blocked by the command guard: this command reads a credential (pattern $MATCHED in plugins/command-guard/hooks/credential-patterns.txt of miwurster/skills)."
first_match "$PATTERNS_FILE" &&
  hand_over "Blocked by the command guard: this command is on the dangerous-command denylist (pattern $MATCHED in plugins/command-guard/hooks/dangerous-patterns.txt of miwurster/skills)."

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
load_allowlist
while IFS= read -r segment; do
  [ -z "$segment" ] && continue
  split_words "$segment"
  command_of
  command=$COMMAND
  [ -z "$command" ] && continue
  cd_target

  if [ "$command" = ssh ]; then
    inspect_remote
    continue
  fi

  if [ "$REMOTE" = 0 ]; then
    script_of
    [ -n "$SCRIPT" ] && inspect_script "$SCRIPT" "$RUN_DIR"
  fi

  # A wrapper hides its payload from us, so any mention of a guarded CLI is enough.
  case "$WRAPPERS" in
    *" $command "*)
      for cli in $CLIS; do
        printf '%s\n' "$segment" | grep -qE -- "(^|[^A-Za-z0-9_-])$cli([^A-Za-z0-9_-]|$)" &&
          hand_over "Blocked by the command guard: a $cli command inside '$command' cannot be inspected, so it is denied."
      done
      continue ;;
  esac

  for cli in $CLIS; do
    [ "$command" = "$cli" ] || continue

    [ -r "$ALLOW_FILE" ] ||
      hand_over "Blocked by the command guard: the read allowlist ($ALLOW_FILE) is unreadable, so every $cli command is denied."

    strip_flags "$COMMAND_AT"
    args=$ARGS
    allow=()
    for i in "${!ALLOW_CLI[@]}"; do
      [ "${ALLOW_CLI[$i]}" = "$cli" ] && allow[${#allow[@]}]="-e${ALLOW_RE[$i]}"
    done

    [ ${#allow[@]} -gt 0 ] && printf '%s\n' "$args" | grep -qE "${allow[@]}" ||
      hand_over "Blocked by the command guard: only reads are allowed for $cli, and '$cli $args' is not one of them."
  done
done <<SEGMENTS
$SEGMENTS
SEGMENTS

exit 0
