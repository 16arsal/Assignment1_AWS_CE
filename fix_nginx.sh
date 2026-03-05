#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="/etc/nginx/conf.d"
PREFERRED_CONF="$CONF_DIR/frontend_flask.conf"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

err() {
  printf 'ERROR: %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

run_root_cmd() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

backup_file() {
  local file="$1"
  local backup="${file}.bak.${TIMESTAMP}"
  cp -a "$file" "$backup"
  printf '%s\n' "$backup"
}

is_candidate_conf() {
  local file="$1"
  grep -Eq '(^|[[:space:]])server_name[[:space:]]+_[[:space:];]' "$file" || \
  grep -Eq '(^|[[:space:]])listen[[:space:]]+80([[:space:];]|$)' "$file"
}

is_competing_conf() {
  local file="$1"

  if ! grep -Eq '(^|[[:space:]])listen[[:space:]]+80([[:space:];]|$)' "$file"; then
    return 1
  fi

  if grep -Eq '(^|[[:space:]])server_name[[:space:]]+_[[:space:];]' "$file"; then
    return 0
  fi

  if ! grep -Eq '(^|[[:space:]])server_name[[:space:]]+' "$file"; then
    return 0
  fi

  return 1
}

pick_newest_file() {
  local newest=""
  local newest_mtime="-1"
  local file mtime

  for file in "$@"; do
    mtime="$(stat -c '%Y' "$file")"
    if (( mtime > newest_mtime )); then
      newest="$file"
      newest_mtime="$mtime"
    fi
  done

  printf '%s\n' "$newest"
}

has_listen80_server_block() {
  local file="$1"

  awk '
    function strip_comments(s, t) {
      t = s
      sub(/#.*/, "", t)
      return t
    }
    function brace_delta(s, t, o, c) {
      t = s
      o = gsub(/\{/, "{", t)
      t = s
      c = gsub(/\}/, "}", t)
      return o - c
    }
    {
      line = strip_comments($0)

      if (!in_server && line ~ /^[[:space:]]*server[[:space:]]*\{/) {
        in_server = 1
        depth = brace_delta(line)
        has_listen = (line ~ /(^|[[:space:]])listen[[:space:]]+80([[:space:];]|$)/)
        next
      }

      if (in_server) {
        if (line ~ /(^|[[:space:]])listen[[:space:]]+80([[:space:];]|$)/) {
          has_listen = 1
        }
        depth += brace_delta(line)
        if (depth <= 0) {
          if (has_listen) {
            found = 1
            exit
          }
          in_server = 0
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

patch_active_conf() {
  local file="$1"
  local proxy_target="$2"
  local prefer_listen80="$3"
  local tmp

  tmp="$(mktemp)"

  awk -v proxy_target="$proxy_target" -v prefer_listen80="$prefer_listen80" '
    function strip_comments(s, t) {
      t = s
      sub(/#.*/, "", t)
      return t
    }
    function brace_delta(s, t, o, c) {
      t = s
      o = gsub(/\{/, "{", t)
      t = s
      c = gsub(/\}/, "}", t)
      return o - c
    }
    function leading_ws(s) {
      match(s, /^[ \t]*/)
      return substr(s, 1, RLENGTH)
    }
    function emit_api_block(indent) {
      print indent "location /api/ {"
      print indent "    proxy_pass " proxy_target ";"
      print indent "    proxy_set_header Host $host;"
      print indent "    proxy_set_header X-Real-IP $remote_addr;"
      print indent "    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
      print indent "    proxy_set_header X-Forwarded-Proto $scheme;"
      print indent "}"
    }
    function emit_modified_server(    i, line, stripped, stripped2, loc_indent, in_api, api_depth, api_done,
                                      in_root, root_depth, root_has_try, root_done, root_n, j) {
      loc_indent = leading_ws(server_lines[1]) "    "

      in_api = 0
      api_depth = 0
      api_done = 0

      in_root = 0
      root_depth = 0
      root_has_try = 0
      root_done = 0
      root_n = 0

      for (i = 1; i <= server_n; i++) {
        line = server_lines[i]
        stripped = strip_comments(line)

        if (!in_api && stripped ~ /^[[:space:]]*location[[:space:]]+\/api\/[[:space:]]*\{/) {
          in_api = 1
          api_depth = brace_delta(stripped)
          if (!api_done) {
            emit_api_block(loc_indent)
            api_done = 1
          }
          continue
        }

        if (in_api) {
          api_depth += brace_delta(stripped)
          if (api_depth <= 0) {
            in_api = 0
          }
          continue
        }

        if (!in_root && stripped ~ /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/) {
          in_root = 1
          root_depth = brace_delta(stripped)
          root_has_try = (stripped ~ /try_files[[:space:]]+\$uri[[:space:]]+\/index\.html[[:space:]]*;/)
          root_n = 0
          root_buf[++root_n] = line
          root_done = 1
          continue
        }

        if (in_root) {
          stripped2 = strip_comments(line)
          if (stripped2 ~ /try_files[[:space:]]+\$uri[[:space:]]+\/index\.html[[:space:]]*;/) {
            root_has_try = 1
          }

          root_buf[++root_n] = line
          root_depth += brace_delta(stripped2)

          if (root_depth <= 0) {
            if (!root_has_try) {
              for (j = 1; j < root_n; j++) {
                print root_buf[j]
              }
              print loc_indent "    try_files $uri /index.html;"
              print root_buf[root_n]
            } else {
              for (j = 1; j <= root_n; j++) {
                print root_buf[j]
              }
            }
            delete root_buf
            root_n = 0
            in_root = 0
          }
          continue
        }

        if (i == server_n) {
          if (!api_done) {
            print ""
            emit_api_block(loc_indent)
            api_done = 1
          }
          if (!root_done) {
            print ""
            print loc_indent "location / {"
            print loc_indent "    try_files $uri /index.html;"
            print loc_indent "}"
            root_done = 1
          }
        }

        print line
      }
    }

    {
      raw = $0
      line = strip_comments(raw)

      if (!in_server) {
        if (line ~ /^[[:space:]]*server[[:space:]]*\{/) {
          in_server = 1
          depth = brace_delta(line)
          server_n = 0
          server_has_listen80 = (line ~ /(^|[[:space:]])listen[[:space:]]+80([[:space:];]|$)/)
          server_lines[++server_n] = raw
        } else {
          print raw
        }
        next
      }

      server_lines[++server_n] = raw
      if (line ~ /(^|[[:space:]])listen[[:space:]]+80([[:space:];]|$)/) {
        server_has_listen80 = 1
      }
      depth += brace_delta(line)

      if (depth <= 0) {
        server_count++
        should_edit = 0

        if (!edited) {
          if (prefer_listen80 == 1 && server_has_listen80) {
            should_edit = 1
          } else if (prefer_listen80 == 0 && server_count == 1) {
            should_edit = 1
          }
        }

        if (should_edit) {
          emit_modified_server()
          edited = 1
        } else {
          for (k = 1; k <= server_n; k++) {
            print server_lines[k]
          }
        }

        in_server = 0
        delete server_lines
      }
    }

    END {
      # If there were no server blocks, leave file unchanged by printing nothing extra.
    }
  ' "$file" > "$tmp"

  if ! cmp -s "$file" "$tmp"; then
    local backup
    backup="$(backup_file "$file")"
    cp "$tmp" "$file"
    log "Updated $file (backup: $backup)"
  else
    log "No content changes needed in $file"
  fi

  rm -f "$tmp"
}

main() {
  local -a all_conf_files=()
  local -a candidate_files=()
  local -a competing_files=()
  local -a enabled_files=()
  local -a disabled_files=()
  local active_conf=""
  local file
  local proxy_target=""
  local api_code
  local hello_code
  local prefer_listen80="0"

  [[ "$(uname -s)" == "Linux" ]] || {
    err "This script must run on Linux."
    exit 1
  }

  require_cmd nginx
  require_cmd curl
  require_cmd awk
  require_cmd sed
  require_cmd stat
  require_cmd find
  require_cmd head

  mapfile -t all_conf_files < <(find "$CONF_DIR" -maxdepth 1 -type f -name '*.conf' | sort)
  if (( ${#all_conf_files[@]} == 0 )); then
    err "No .conf files found in $CONF_DIR"
    exit 1
  fi

  for file in "${all_conf_files[@]}"; do
    if is_candidate_conf "$file"; then
      candidate_files+=("$file")
    fi
    if is_competing_conf "$file"; then
      competing_files+=("$file")
    fi
  done

  if (( ${#competing_files[@]} > 0 )) && [[ -f "$PREFERRED_CONF" ]]; then
    for file in "${competing_files[@]}"; do
      if [[ "$file" == "$PREFERRED_CONF" ]]; then
        active_conf="$PREFERRED_CONF"
        break
      fi
    done
  fi

  if [[ -z "$active_conf" ]] && (( ${#competing_files[@]} > 0 )); then
    active_conf="$(pick_newest_file "${competing_files[@]}")"
  fi

  if [[ -z "$active_conf" ]] && [[ -f "$PREFERRED_CONF" ]]; then
    active_conf="$PREFERRED_CONF"
  fi

  if [[ -z "$active_conf" ]] && (( ${#candidate_files[@]} > 0 )); then
    active_conf="$(pick_newest_file "${candidate_files[@]}")"
  fi

  if [[ -z "$active_conf" ]]; then
    active_conf="$(pick_newest_file "${all_conf_files[@]}")"
  fi

  if [[ ! -f "$active_conf" ]]; then
    err "Could not determine an active nginx conf file to patch."
    exit 1
  fi

  log "Chosen primary active conf: $active_conf"

  if (( ${#competing_files[@]} > 1 )); then
    for file in "${competing_files[@]}"; do
      if [[ "$file" == "$active_conf" ]]; then
        continue
      fi

      if [[ -f "$file" ]]; then
        backup_file "$file" >/dev/null
        if [[ -e "${file}.disabled" ]]; then
          mv "$file" "${file}.${TIMESTAMP}.disabled"
          log "Disabled conflicting conf: $file -> ${file}.${TIMESTAMP}.disabled"
        else
          mv "$file" "${file}.disabled"
          log "Disabled conflicting conf: $file -> ${file}.disabled"
        fi
      fi
    done
  fi

  api_code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/api/hello || true)"
  hello_code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/hello || true)"

  if [[ "$api_code" == "200" ]]; then
    proxy_target="http://127.0.0.1:5000"
  elif [[ "$hello_code" == "200" ]]; then
    proxy_target="http://127.0.0.1:5000/"
  else
    proxy_target="http://127.0.0.1:5000"
    log "Warning: backend probes did not return HTTP 200 (/api/hello=$api_code, /hello=$hello_code). Using $proxy_target"
  fi

  if has_listen80_server_block "$active_conf"; then
    prefer_listen80="1"
  fi

  patch_active_conf "$active_conf" "$proxy_target" "$prefer_listen80"

  if run_root_cmd nginx -t; then
    run_root_cmd systemctl restart nginx
    log "nginx syntax OK and service restarted"
  else
    err "nginx syntax check failed; service was not restarted"
    exit 1
  fi

  mapfile -t enabled_files < <(find "$CONF_DIR" -maxdepth 1 -type f -name '*.conf' | sort)
  mapfile -t disabled_files < <(find "$CONF_DIR" -maxdepth 1 -type f -name '*.disabled' | sort)

  printf '\n===== FINAL STATUS =====\n'
  printf 'Primary conf: %s\n' "$active_conf"
  printf 'Backend probe results: /api/hello=%s, /hello=%s\n' "$api_code" "$hello_code"
  printf 'Proxy target chosen: %s\n' "$proxy_target"

  printf '\nEnabled conf files:\n'
  if (( ${#enabled_files[@]} == 0 )); then
    printf '  (none)\n'
  else
    printf '  %s\n' "${enabled_files[@]}"
  fi

  printf '\nDisabled conf files:\n'
  if (( ${#disabled_files[@]} == 0 )); then
    printf '  (none)\n'
  else
    printf '  %s\n' "${disabled_files[@]}"
  fi

  printf '\n--- curl -i http://localhost/api/hello (first 20 lines) ---\n'
  curl -i http://localhost/api/hello 2>&1 | head -n 20 || true

  printf '\n--- curl -i http://localhost/health (first 20 lines) ---\n'
  curl -i http://localhost/health 2>&1 | head -n 20 || true
}

main "$@"

