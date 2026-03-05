#!/usr/bin/env bash
set -euo pipefail

CONF_DIR="/etc/nginx/conf.d"
TARGET_CONF="$CONF_DIR/frontend_flask.conf"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if LC_ALL=C grep -q $'\r' "$0"; then
  echo "WARNING: Windows CRLF line endings detected in $0" >&2
  echo "Convert and re-run:" >&2
  echo "  dos2unix $0" >&2
  exit 1
fi

[[ "$(uname -s)" == "Linux" ]] || die "This script must run on Linux (Amazon Linux 2023)."
[[ "${EUID}" -eq 0 ]] || die "Run this script as root (for example: sudo ./fix_nginx.sh)."

for cmd in nginx systemctl curl grep find mv cp awk sort; do
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done

[[ -d "$CONF_DIR" ]] || die "Directory not found: $CONF_DIR"

declare -a disabled_files=()
declare -a disabled_backups=()

auto_disable_conflicts() {
  local file
  local dest
  local backup

  while IFS= read -r -d '' file; do
    [[ "$file" == "$TARGET_CONF" ]] && continue

    if awk '
      {
        line = $0
        sub(/#.*/, "", line)
        if (line ~ /listen[[:space:]]+80[[:space:]]+default_server/ || line ~ /server_name[[:space:]]+_/) {
          found = 1
          exit
        }
      }
      END { exit(found ? 0 : 1) }
    ' "$file"; then
      dest="${file}.disabled"

      if [[ -e "$dest" ]]; then
        backup="${dest}.${TIMESTAMP}.bak"
        cp -a "$dest" "$backup"
        disabled_backups+=("$backup")
      fi

      mv "$file" "$dest"
      disabled_files+=("$dest")
    fi
  done < <(find "$CONF_DIR" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)
}

write_target_conf() {
  local target_backup=""

  if [[ -f "$TARGET_CONF" ]]; then
    target_backup="${TARGET_CONF}.bak.${TIMESTAMP}"
    cp -a "$TARGET_CONF" "$target_backup"
    echo "Backed up existing target config: $target_backup"
  fi

  cat > "$TARGET_CONF" <<'NGINX_CONF'
server {
    listen 80 default_server;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /health {
        proxy_pass http://127.0.0.1:5000/health;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /ready {
        proxy_pass http://127.0.0.1:5000/ready;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri /index.html;
    }
}
NGINX_CONF
}

verify_http_codes() {
  local api_code
  local health_code
  local ready_code

  if ! api_code="$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/hello)"; then
    api_code="000"
  fi

  if ! health_code="$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health)"; then
    health_code="000"
  fi

  if ! ready_code="$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ready)"; then
    ready_code="000"
  fi

  echo "curl -s -o /dev/null -w \"%{http_code}\" http://localhost/api/hello => $api_code"
  echo "curl -s -o /dev/null -w \"%{http_code}\" http://localhost/health    => $health_code"
  echo "curl -s -o /dev/null -w \"%{http_code}\" http://localhost/ready     => $ready_code"
}

print_summary() {
  echo
  echo "===== nginx config summary ====="
  echo "Active config: $TARGET_CONF"

  echo "Disabled conflicting configs:"
  if [[ ${#disabled_files[@]} -eq 0 ]]; then
    echo "  (none)"
  else
    printf '  %s\n' "${disabled_files[@]}"
  fi

  if [[ ${#disabled_backups[@]} -gt 0 ]]; then
    echo "Backups of existing .disabled files:"
    printf '  %s\n' "${disabled_backups[@]}"
  fi
}

auto_disable_conflicts
write_target_conf
nginx -t
systemctl restart nginx
print_summary
verify_http_codes