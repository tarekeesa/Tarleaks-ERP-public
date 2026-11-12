# shellcheck shell=bash
# =============================================================================
# lib-move.sh — move a company from Tarleaks Cloud to this installation.
#
# From 1.2.0. The ERP does the work: its sign-in service makes a key pair, the
# cloud sends the company encrypted to that key, the server restores it, checks
# every table and file, and switches over when a person says so. This file is
# the kit's side of `./tarleaks migrate-from-cloud` (and so of
# `./install.sh --from-cloud`): it asks the installation's own API, shows the
# progress on one line, prints the verification report and asks before the
# switch over. Windows: scripts/lib-move.ps1. Guide: docs/move-from-cloud.md.
#
#   POST /api/auth/installation/cloud-move          start {code}, go on {resume}
#   GET  /api/auth/installation/cloud-move          where it stands
#   POST /api/auth/installation/cloud-move/switch   Switch over (when ready)
#   POST /api/auth/installation/cloud-move/cancel   stop, remove the copy here
#
# Every call is guarded by the setup code (TARLEAKS_SETUP_CODE in .env) and is
# made inside the sign-in container, so the address, port and HTTPS settings
# of the gateway do not matter. The setup code and the move code reach curl on
# its standard input, never on a command line; neither is printed or written
# to a file. The answers are read with awk (no python or jq needed).
#
# Needs, from ./tarleaks: env_get, set_env, env_del, url, wait_ready,
# is_running, ok, warn, bad, die, B, N, and _reg_json (scripts/lib-registry.sh).
# =============================================================================

MOVE_API=http://localhost:8001/api/auth/installation/cloud-move
MOVE_CMD="./tarleaks migrate-from-cloud"
MOVE_USAGE="usage: $MOVE_CMD [<code>] [--switch-over] | --status | --resume | --cancel   (docs/move-from-cloud.md)"
MOVE_HTTP=""          # HTTP status of the last call (000: no answer)
MOVE_JSON=""          # its body, one "<path><TAB><value>" line per value
MOVE_SETUP_CODE=""
MOVE_MISSES=0         # polls in a row without an answer
MOVE_LINE_OPEN=0      # a progress line is on the screen without its newline
MOVE_REPORT_SHOWN=0

# A move code: TLM-XXXXX-XXXXX-XXXXX-XXXXX, made in the cloud workspace. Case,
# spaces and dashes as typed; the TLM in front may be left out.
move_code_valid() {
  local c
  c=$(printf '%s' "$1" | LC_ALL=C tr -cd 'A-Za-z0-9' | LC_ALL=C tr '[:lower:]' '[:upper:]')
  if [ "${#c}" = 23 ] && [ "${c#TLM}" != "$c" ]; then c=${c#TLM}; fi
  [ "${#c}" = 20 ] || return 1
  case "$c" in *[!ABCDEFGHJKLMNPQRSTUVWXYZ23456789]*) return 1 ;; esac
  return 0
}

# --vendor: another Tarleaks platform, only for tests (`default` goes back).
move_vendor_valid() {
  [ "$1" = default ] && return 0
  printf '%s' "$1" | grep -qE '^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$'
}

# JSON on stdin -> one line per value: "<path><TAB><value>". The path joins the
# keys and array positions with dots (report.files.copied,
# report.reconnect.0.table); strings are unescaped, null is empty, empty
# objects and arrays give no line.
move_json_flat() {
  awk '
    function here() { return (d == 0) ? "" : pre[d] ((kind[d] == "[") ? idx[d] : key[d]) }
    BEGIN { RS = "\001" }
    { s = s $0 "\n" }
    END {
      n = split(s, ch, "")
      d = 0; i = 1
      while (i <= n) {
        c = ch[i]
        if (c == "{" || c == "[") {
          p = here()
          d++; kind[d] = c; idx[d] = 0; key[d] = ""; wantkey[d] = (c == "{")
          pre[d] = (p == "") ? "" : p "."
          i++
        } else if (c == "}" || c == "]") {
          d--; i++
        } else if (c == ",") {
          if (kind[d] == "[") idx[d]++; else wantkey[d] = 1
          i++
        } else if (c == ":") {
          wantkey[d] = 0; i++
        } else if (c == "\"") {
          v = ""; i++
          while (i <= n && ch[i] != "\"") {
            if (ch[i] == "\\") {
              i++; e = ch[i]
              if (e == "u") { v = v " "; i += 4 }
              else if (e == "n" || e == "r" || e == "t" || e == "b" || e == "f") v = v " "
              else v = v e
            } else v = v ch[i]
            i++
          }
          i++
          if (kind[d] == "{" && wantkey[d]) key[d] = v
          else print here() "\t" v
        } else if (c == " " || c == "\t" || c == "\n" || c == "\r") {
          i++
        } else {
          v = ""
          while (i <= n && index(",}] \t\n\r", ch[i]) == 0) { v = v ch[i]; i++ }
          if (v == "null") v = ""
          print here() "\t" v
        }
      }
    }'
}

# One value of the last answer (empty when absent or null).
mj() { awk -F '\t' -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }' <<<"$MOVE_JSON"; }
# The same as a whole number (0 when absent).
mjn() {
  local v; v=$(mj "$1")
  case "$v" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac
}
# "a, b, c": the strings of an array (move_list report.secret_settings.), or
# one field of each object in it (move_list report.tables_failed. table).
move_list() {
  awk -F '\t' -v p="$1" -v f="${2:-}" '
    index($1, p) == 1 {
      rest = substr($1, length(p) + 1); take = 0
      if (f == "") { if (rest !~ /\./) take = 1 }
      else if (rest ~ ("^[0-9]+\\." f "$")) take = 1
      if (take) out = out (out == "" ? "" : ", ") substr($0, length($1) + 2)
    }
    END { print out }' <<<"$MOVE_JSON"
}

move_size() { awk -v b="${1:-0}" 'BEGIN { if (b >= 1073741824) printf "%.1f GB", b / 1073741824; else printf "%.1f MB", b / 1048576 }'; }

# "connecting 2 s, data 3 min 10 s, ..." from the step times under a prefix
# (progress.timings_ms. or report.timings_ms.), in the order the move runs.
move_timings() {
  awk -F '\t' -v p="$1" '
    function dur(ms,   s) {
      s = int(ms / 1000 + 0.5)
      if (s < 60) return s " s"
      if (s < 3600) return int(s / 60) " min " (s % 60) " s"
      return int(s / 3600) " h " int((s % 3600) / 60) " min"
    }
    index($1, p) == 1 { t[substr($1, length(p) + 1)] = substr($0, length($1) + 2) }
    END {
      n = split("handshake=connecting|schema=database layout|data=data|people=people and settings|files=files|indexes=indexes and keys|verify=checks|final_changes=last changes|switch=switch over", w, "|")
      out = ""
      for (i = 1; i <= n; i++) {
        split(w[i], kv, "=")
        if (kv[1] in t) { out = out (out == "" ? "" : ", ") kv[2] " " dur(t[kv[1]]); delete t[kv[1]] }
      }
      for (k in t) out = out (out == "" ? "" : ", ") k " " dur(t[k])
      print out
    }' <<<"$MOVE_JSON"
}

# What to reconnect: one line per secret that did not move.
move_reconnect() {
  awk -F '\t' -v p=report.reconnect. '
    index($1, p) == 1 {
      rest = substr($1, length(p) + 1); j = index(rest, ".")
      i = substr(rest, 1, j - 1); f = substr(rest, j + 1)
      if (!(i in seen)) { seen[i] = 1; order[++n] = i }
      v[i, f] = substr($0, length($1) + 2)
    }
    END {
      for (k = 1; k <= n; k++) {
        i = order[k]
        what = (v[i, "action"] == "removed") ? "removed, set it up again" : "cleared, enter it again"
        printf "    - %s (%s): %s record(s), %s\n", v[i, "table"], v[i, "column"], v[i, "rows"], what
      }
    }' <<<"$MOVE_JSON"
}

# What stays in the cloud, one line per reason with its tables.
move_stays() {
  awk -F '\t' -v p=report.stays. '
    index($1, p) == 1 {
      t = substr($1, length(p) + 1); r = substr($0, length($1) + 2)
      if (!(r in tables)) { order[++n] = r; tables[r] = t } else tables[r] = tables[r] ", " t
    }
    END { for (k = 1; k <= n; k++) printf "    - %s (%s)\n", order[k], tables[order[k]] }' <<<"$MOVE_JSON"
}

move_step_words() { # state step
  case "$1:$2" in
    connecting:*) echo "Connecting to Tarleaks Cloud" ;;
    copying:schema) echo "Copying the database layout" ;;
    copying:data) echo "Copying the data" ;;
    copying:people) echo "Copying people, roles and settings" ;;
    copying:files) echo "Copying the files" ;;
    copying:indexes) echo "Rebuilding indexes and keys" ;;
    copying:*) echo "Copying" ;;
    verifying:*) echo "Checking every table and file against the cloud" ;;
    ready:*) echo "Copied and checked, ready to switch over" ;;
    switching:read_only) echo "Switching over: making the cloud workspace read-only" ;;
    switching:final_changes) echo "Switching over: copying the last changes" ;;
    switching:finishing) echo "Switching over: putting the company in place" ;;
    switching:confirming) echo "Switching over: telling Tarleaks Cloud" ;;
    switching:*) echo "Switching over" ;;
    live:*) echo "Live on this server" ;;
    *) echo "$1" ;;
  esac
}

# The progress line (without the clock): the step in words, and its numbers.
move_line() { # state step
  local s bt fc fh
  s=$(move_step_words "$1" "$2")
  case "$1:$2" in
    copying:files)
      fc=$(mjn progress.files_copied); fh=$(mjn progress.files_already_here)
      s="$s: $fc copied ($(move_size "$(mjn progress.files_bytes)"))"
      [ "$fh" = 0 ] || s="$s, $fh already here" ;;
    copying:*)
      bt=$(mjn progress.batches_total)
      [ "$bt" = 0 ] || s="$s: batch $(mjn progress.batches_done) of $bt, $(move_size "$(mjn progress.bytes_done)") of $(move_size "$(mjn progress.bytes_total)")" ;;
  esac
  printf '%s' "$s"
}

move_clock() { # start (epoch seconds) -> [mm:ss]
  local e; e=$(( $(date +%s) - $1 ))
  printf '[%02d:%02d]' $((e / 60)) $((e % 60))
}

move_line_end() { if [ "$MOVE_LINE_OPEN" = 1 ]; then printf '\n'; MOVE_LINE_OPEN=0; fi; }

# One call to the installation's API, inside the sign-in container. Sets
# MOVE_HTTP and MOVE_JSON; returns 0 on a 2xx answer.
move_call() { # GET | POST  <"" | /switch | /cancel>  [JSON members to add]
  local method=$1 path="$MOVE_API${2:-}" extra=${3:-} resp="" rc=0
  if [ "$method" = GET ]; then
    resp=$(printf 'header = "X-Setup-Code: %s"\n' "$MOVE_SETUP_CODE" \
      | docker compose exec -T auth curl -sS -K - --max-time 30 -w '\n%{http_code}' "$path" 2>/dev/null) || rc=$?
  else
    resp=$(printf '{"setup_code":%s%s}' "$(_reg_json "$MOVE_SETUP_CODE")" "${extra:+,$extra}" \
      | docker compose exec -T auth curl -sS --max-time 60 -H 'Content-Type: application/json' \
          --data-binary @- -w '\n%{http_code}' "$path" 2>/dev/null) || rc=$?
  fi
  MOVE_HTTP=$(printf '%s' "${resp##*$'\n'}" | tr -dc '0-9')
  if [ "$rc" != 0 ] || [ -z "$MOVE_HTTP" ]; then MOVE_HTTP=000; fi
  case "$resp" in
    *$'\n'*) MOVE_JSON=$(printf '%s' "${resp%$'\n'*}" | move_json_flat) ;;
    *) MOVE_JSON="" ;;
  esac
  case "$MOVE_HTTP" in 2??) return 0 ;; esac
  return 1
}

# The same, waiting up to 2 minutes while the ERP does not answer (it may
# still be starting).
move_call_patient() {
  local i=0
  while :; do
    if move_call "$@"; then return 0; fi
    case "$MOVE_HTTP" in 000|502|503|504) ;; *) return 1 ;; esac
    i=$((i + 1))
    [ "$i" -lt 24 ] || return 1
    sleep 5
  done
}

# Why the last call was refused, in words, with what to do.
move_explain() {
  local code msg
  code=$(mj error.code); msg=$(mj error.message)
  case "$MOVE_HTTP" in
    000|502|503|504)
      bad "The ERP's sign-in service does not answer${msg:+ ($msg)}. See: ./tarleaks status   and   ./tarleaks logs auth" ;;
    404)
      bad "This release ($(env_get TARLEAKS_VERSION)) cannot take a company from Tarleaks Cloud: that comes with release 1.2.0-rc.6. Update first (./tarleaks update), then run this again." ;;
    *)
      bad "${msg:-The ERP answered HTTP $MOVE_HTTP.}${code:+ ($code)}"
      case "$code" in
        SETUP_CODE_INVALID) echo "  The kit sends TARLEAKS_SETUP_CODE from .env. If it was changed there, apply it first: ./tarleaks restart" ;;
        SERVER_HAS_WORKSPACE)
          echo "  Install a fresh copy for the move: on another server, or in a second copy of this folder with its own name and port:"
          echo "    COMPOSE_PROJECT_NAME=erp2 ./install.sh --port 8080 --from-cloud <code>" ;;
        MOVE_NOT_READY) echo "  Watch it until it is ready: $MOVE_CMD --status" ;;
        MOVE_ALMOST_DONE) echo "  Finish the switch over: $MOVE_CMD --resume" ;;
        CLOUD_MOVE_IN_PROGRESS) echo "  Watch it: $MOVE_CMD --status" ;;
      esac ;;
  esac
}

# The next answer, every 5 seconds. A passing silence (the ERP restarting)
# keeps the last answer; 5 minutes of it stop the watching, not the move.
move_poll() {
  local prev=$MOVE_JSON
  if move_call GET; then MOVE_MISSES=0; return 0; fi
  case "$MOVE_HTTP" in
    000|502|503|504)
      MOVE_JSON=$prev; MOVE_MISSES=$((MOVE_MISSES + 1))
      if [ "$MOVE_MISSES" -ge 60 ]; then
        move_line_end
        bad "The ERP has not answered for 5 minutes. See why: ./tarleaks doctor   and   ./tarleaks logs auth"
        echo "  The move goes on by itself once the ERP is back. Watch it again: $MOVE_CMD --status"
        return 1
      fi
      return 0 ;;
  esac
  move_line_end
  move_explain
  return 1
}

move_show_fingerprint() {
  local company slug
  company=$(mj company); slug=$(mj slug)
  ok "Connected to Tarleaks Cloud${company:+: $company}${slug:+ ($slug)}"
  echo "  This server's key fingerprint: ${B}$(mj fingerprint)${N}"
  echo "  The cloud workspace shows the fingerprint of the server that used the code (Settings >"
  echo "  Move to your own server). It must be the same. If it is not, cancel the move there at once."
}

move_show_report() {
  local list
  [ -n "$(mj report.tables)" ] || return 0
  MOVE_REPORT_SHOWN=1
  echo
  echo "${B}Verification report${N}"
  if [ "$(mj report.all_green)" = true ]; then
    ok "Everything matches the cloud: every table and every file was checked."
  else
    bad "Not everything matches the cloud (below)."
  fi
  echo "  Tables:  $(mjn report.tables), each checked by its row count and checksum"
  list=$(move_list report.tables_failed. table)
  [ -z "$list" ] || echo "           different: $list"
  echo "  Rows:    $(mjn report.rows), and $(mjn report.platform_rows) of people, roles and settings ($(mjn report.platform_tables) tables)"
  echo "  People:  $(mjn report.people.people) ($(mjn report.people.active) active, $(mjn report.people.two_step) with two-step sign-in), $(mjn report.people.settings) settings"
  if [ "$(mj report.files.mode)" = keep_own_bucket ]; then
    echo "  Files:   stay in the company's own storage bucket (not copied)"
  else
    echo "  Files:   $(mjn report.files.copied) copied, $(mjn report.files.already_here) already here, $(move_size "$(mjn report.files.bytes)"), $(mjn report.files.failed) failed; each checked by size and SHA-256"
  fi
  list=$(move_timings report.timings_ms.)
  [ -z "$list" ] || echo "  Time:    $list"
  list=$(move_reconnect)
  if [ -n "$list" ]; then
    echo "  ${B}To reconnect after the switch over${N} (secrets sealed in the cloud do not move):"
    printf '%s\n' "$list"
  fi
  list=$(move_list report.secret_settings.)
  [ -z "$list" ] || echo "  Settings to type again: $list"
  list=$(move_stays)
  if [ -n "$list" ]; then
    echo "  Stays in Tarleaks Cloud:"
    printf '%s\n' "$list"
  fi
}

# A licence key in .env wins over the one the move brings.
move_licence_note() {
  [ -n "$(env_get TARLEAKS_LICENSE_KEY)" ] || return 0
  warn "TARLEAKS_LICENSE_KEY in .env holds a licence key, and a key set there wins over the company's own licence that came with the move. Unless it is the key you want, remove that line from .env and run ./tarleaks restart."
}

move_show_live() {
  local list company
  [ "$MOVE_REPORT_SHOWN" = 1 ] || move_show_report
  echo
  company=$(mj company)
  ok "Moved: ${company:-the company} now runs on this server."
  echo "  Open $(url) and sign in as in the cloud: the same e-mail addresses, passwords and two-step sign-in."
  list=$(move_timings progress.timings_ms.)
  [ -z "$list" ] || echo "  Time: $list"
  if [ -n "$(move_reconnect)$(move_list report.secret_settings.)" ]; then
    echo "  Reconnect what the report lists (mail server, storage, integrations): those secrets do not move."
  fi
  echo "  Tell your people the new address, and take a first backup: ./tarleaks backup"
  if [ -n "$(mj certificate)" ]; then
    ok "The cloud copy is destroyed: the deletion certificate, signed by Tarleaks, is in Settings > Move to your own server."
  else
    echo "  The copy in Tarleaks Cloud stays read-only for the retention period set there (30 days unless"
    echo "  changed), then it is destroyed. The deletion certificate, signed by Tarleaks, then appears on this"
    echo "  server in Settings > Move to your own server."
  fi
  move_licence_note
}

move_show_failed() {
  local msg st
  msg=$(mj error.message); st=$(mj error.state)
  if [ -n "$(mj report.tables)" ] && [ "$MOVE_REPORT_SHOWN" = 0 ]; then move_show_report; fi
  echo
  bad "The move stopped: ${msg:-no reason was given (see ./tarleaks logs auth)}"
  [ -z "$st" ] || echo "  While: $(move_step_words "$st" "$(mj error.step)")"
  if [ "$st" = connecting ]; then
    echo "  Nothing was copied. Run it again with the code: $MOVE_CMD <code>"
    echo "  A code works once and for 24 hours: if the message says it is used or expired, make a new one in"
    echo "  the cloud workspace (Settings > Move to your own server)."
  else
    if [ "$st" = switching ]; then
      echo "  The cloud workspace stays read-only until the switch over finishes. If this server stays silent"
      echo "  for 6 hours, the cloud workspace becomes writable again by itself."
    fi
    echo "  Go on from where it stopped: $MOVE_CMD --resume"
    echo "  Or stop and remove the copy here (the cloud workspace keeps working): $MOVE_CMD --cancel"
  fi
  echo "  The details: ./tarleaks logs auth"
}

move_not_switched() {
  ok "Copied and checked. Not switched over: the cloud workspace keeps working as before; what changes there until the switch over is copied then."
  echo "  Switch over when you are ready (a few minutes of read-only in the cloud): $MOVE_CMD --switch-over"
  echo "  Or stop and remove the copy here: $MOVE_CMD --cancel"
}

move_stop_watching() {
  move_line_end
  echo
  warn "Stopped watching. The move goes on by itself on this server."
  echo "  Watch it again: $MOVE_CMD --status"
  echo "  When it is ready, switch over: $MOVE_CMD --switch-over"
  exit 130
}

# Follow the move until it is live, stopped, or ready and not switched over.
# MOVE_JSON holds the first answer. $1 = 1: switch over at ready without asking.
move_watch() {
  local auto=$1 state step line shown="" fp=0 started switched=0 tty=0 cols=80 a
  started=$(date +%s)
  if [ -t 1 ]; then tty=1; cols=$(tput cols 2>/dev/null || echo 80); fi
  case "$cols" in ''|*[!0-9]*) cols=80 ;; esac
  trap move_stop_watching INT
  while :; do
    state=$(mj state); step=$(mj step)
    if [ "$fp" = 0 ] && [ -n "$(mj fingerprint)" ] && { [ -n "$(mj company)" ] || [ "$state" != connecting ]; }; then
      move_line_end; move_show_fingerprint; fp=1
    fi
    case "$state" in
      ready)
        if [ "$switched" = 0 ]; then
          move_line_end
          move_show_report
          echo
          if [ "$auto" = 1 ]; then
            echo "Switching over now (--switch-over)."
          elif [ -t 0 ]; then
            printf 'Switch over now? The cloud workspace becomes read-only from now on; the last changes come over in a few minutes, then this server opens. [y/N] '
            read -r a || a=""
            case "$a" in
              y|Y|yes|Yes|YES) ;;
              *) move_not_switched; return 0 ;;
            esac
          else
            move_not_switched
            return 0
          fi
          move_call POST /switch || { move_explain; return 1; }
          switched=1
          continue
        fi ;;
      live) move_line_end; move_show_live; return 0 ;;
      failed) move_line_end; move_show_failed; return 1 ;;
      cancelled)
        move_line_end
        bad "The move was cancelled (on this server or in the cloud workspace). The cloud workspace keeps working as before."
        echo "  To move later, make a new code in the cloud workspace (Settings > Move to your own server), then: $MOVE_CMD <code>"
        return 1 ;;
      '')
        move_line_end
        bad "There is no move from Tarleaks Cloud on this server."
        return 1 ;;
      *)
        line="$(move_clock "$started") $(move_line "$state" "$step")"
        [ "$MOVE_MISSES" = 0 ] || line="$line (the ERP does not answer, trying again)"
        if [ "$tty" = 1 ]; then
          printf '\r\033[K%s' "${line:0:$((cols - 1))}"
          MOVE_LINE_OPEN=1
        elif [ "${line#* }" != "$shown" ]; then
          printf '%s\n' "$line"
          shown=${line#* }
        fi ;;
    esac
    sleep 5
    move_poll || return 1
  done
}

move_cancel() {
  local a
  move_call_patient GET || { move_explain; return 1; }
  case "$(mj state)" in
    '') ok "There is no move from Tarleaks Cloud on this server."; return 0 ;;
    cancelled) ok "The move is already cancelled."; return 0 ;;
    live) ok "Nothing to cancel: the move is finished and the company runs on this server."; return 0 ;;
  esac
  if [ -t 0 ]; then
    printf 'Cancel the move? The copy on this server is removed, and the cloud workspace keeps working as before. [y/N] '
    read -r a || a=""
    case "$a" in y|Y|yes|Yes|YES) ;; *) echo "Not cancelled."; return 0 ;; esac
  fi
  move_call POST /cancel || { move_explain; return 1; }
  ok "Cancelled. The copy on this server is removed; the cloud workspace is writable and works as before."
  echo "  The code is used up. To move later, make a new one in the cloud workspace (Settings > Move to"
  echo "  your own server), then: $MOVE_CMD <code>"
}

# --vendor: the Tarleaks platform the move (and a trial) talks to, only for
# tests. The sign-in service reads it at start, so it is started again.
move_set_vendor() { # <address> | default
  local want=$1 cur
  [ "$want" != default ] || want=""
  want=${want%/}
  cur=$(env_get TARLEAKS_VENDOR_URL)
  [ "$want" != "$cur" ] || return 0
  if [ -z "$want" ]; then
    env_del TARLEAKS_VENDOR_URL
    ok "Tarleaks Cloud is https://tarleaks.com again (TARLEAKS_VENDOR_URL removed from .env)."
  else
    set_env TARLEAKS_VENDOR_URL "$want"
    warn "Tarleaks Cloud is $want for this installation (TARLEAKS_VENDOR_URL in .env), for tests only. Back to normal: --vendor default"
  fi
  echo "Starting the sign-in service again to use it…"
  sig_require_verified "$MOVE_CMD --vendor $1" || die "Nothing was started; TARLEAKS_VENDOR_URL is changed in .env and takes effect at the next start."
  docker compose up -d --no-deps auth auth-jobs || die "The sign-in service did not start again (above). See: ./tarleaks logs auth"
  printf 'Waiting for the ERP to answer'
  wait_ready || die "The ERP does not answer. See: ./tarleaks doctor"
}

# The code typed or pasted, not shown and not kept in the shell's history.
move_ask_code() {
  local c=""
  printf 'Move code from the cloud workspace (Settings > Move to your own server; not shown): ' >&2
  read -r -s c || c=""
  printf '\n' >&2
  printf '%s' "$c"
}

# A code piped in (./tarleaks migrate-from-cloud < code.txt): keeps it off the
# command line and out of the shell history, for scripts and for --switch-over.
# The first line that is not blank; an open pipe that sends nothing for 5
# seconds does not hang the command.
move_piped_code() {
  local c=""
  while IFS= read -r -t 5 c || [ -n "$c" ]; do   # also a last line without a newline
    c=$(printf '%s' "$c" | tr -d '[:space:]')
    [ -z "$c" ] || break
  done
  printf '%s' "$c"
}

# ./tarleaks migrate-from-cloud [<code>] [--switch-over] [--status | --resume | --cancel] [--vendor <url>]
move_main() {
  local code="" switch=0 resume=0 cancel=0 status=0 vendor="" rc=0 st piped=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --switch-over) switch=1 ;;
      --resume) resume=1 ;;
      --cancel) cancel=1 ;;
      --status) status=1 ;;
      --vendor)
        [ $# -ge 2 ] && [ -n "$2" ] || die "--vendor needs an address (only to test against another Tarleaks platform; leave it out otherwise)"
        vendor=$2; shift ;;
      --vendor=*) vendor=${1#--vendor=} ;;
      -h|--help) echo "$MOVE_USAGE"; return 0 ;;
      -*) die "Unknown option: $1. $MOVE_USAGE" ;;
      *) [ -z "$code" ] || die "$MOVE_USAGE"; code=$1 ;;
    esac
    shift
  done
  [ $((resume + cancel + status)) -le 1 ] || die "Give only one of --status, --resume and --cancel."
  # Read a piped code first: every 'docker compose exec -T' below forwards stdin
  # into the container and would swallow it.
  if [ -z "$code" ] && [ $((resume + cancel + status)) = 0 ] && [ ! -t 0 ]; then
    code=$(move_piped_code); piped=1
  fi
  if [ -n "$code" ] && [ $((resume + cancel + status)) -gt 0 ]; then
    die "A move code starts a new move: leave out --status, --resume and --cancel."
  fi
  [ "$cancel" = 0 ] || [ "$switch" = 0 ] || die "--cancel and --switch-over do not go together."
  if [ -n "$code" ] && ! move_code_valid "$code"; then
    die "That is not a move code. It looks like TLM-XXXXX-XXXXX-XXXXX-XXXXX: make one in the cloud workspace, Settings > Move to your own server."
  fi
  if [ -n "$vendor" ] && ! move_vendor_valid "$vendor"; then
    die "--vendor must be an address such as https://tarleaks.com (or default)."
  fi
  is_running auth || die "The ERP is not running. Start it first: ./tarleaks start"
  MOVE_SETUP_CODE=$(env_get TARLEAKS_SETUP_CODE)
  [ -n "$MOVE_SETUP_CODE" ] || MOVE_SETUP_CODE=$(env_get NEXUS_SETUP_CODE)   # an .env from before the rename
  case "$MOVE_SETUP_CODE" in
    ''|GENERATED) die "There is no setup code in .env (TARLEAKS_SETUP_CODE). Run ./install.sh again: it makes one." ;;
  esac
  [ -z "$vendor" ] || move_set_vendor "$vendor"
  # The ERP answers before it is asked anything (the kit's own wait otherwise).
  if ! docker compose exec -T auth curl -fsS -o /dev/null --max-time 10 http://localhost:8001/api/auth/healthz >/dev/null 2>&1; then
    printf 'Waiting for the ERP to answer'
    wait_ready || die "The ERP does not answer, so the move cannot start. See: ./tarleaks doctor"
  fi

  if [ "$cancel" = 1 ]; then
    move_cancel
    return
  fi
  if [ -n "$code" ]; then
    echo "Asking Tarleaks Cloud for the company (the code works once)…"
    move_call_patient POST "" "\"code\":$(_reg_json "$code")" || { move_explain; return 1; }
  elif [ "$resume" = 1 ]; then
    echo "Going on with the move…"
    move_call_patient POST "" '"resume":true' || { move_explain; return 1; }
  else
    move_call_patient GET || { move_explain; return 1; }
    st=$(mj state)
    if [ -z "$st" ] || { [ "$st" = cancelled ] && [ "$status" = 0 ] && [ "$switch" = 0 ]; }; then
      if [ "$status" = 0 ] && [ "$switch" = 0 ] && [ -t 0 ]; then
        [ "$st" != cancelled ] || echo "The last move was cancelled. Starting a new one."
        code=$(move_ask_code)
        move_code_valid "$code" || die "That is not a move code. It looks like TLM-XXXXX-XXXXX-XXXXX-XXXXX: make one in the cloud workspace, Settings > Move to your own server."
        echo "Asking Tarleaks Cloud for the company (the code works once)…"
        move_call_patient POST "" "\"code\":$(_reg_json "$code")" || { move_explain; return 1; }
      else
        if [ "$st" = cancelled ]; then ok "The last move from Tarleaks Cloud was cancelled."
        else ok "There is no move from Tarleaks Cloud on this server."; fi
        [ "$piped" = 0 ] || echo "  No move code came in on standard input."
        echo "  Start one with the code from the cloud workspace (Settings > Move to your own server):"
        echo "    $MOVE_CMD TLM-XXXXX-XXXXX-XXXXX-XXXXX"
        if [ "$status" = 1 ]; then return 0; fi
        return 1
      fi
    fi
  fi
  move_watch "$switch" || rc=$?
  trap - INT
  return "$rc"
}
