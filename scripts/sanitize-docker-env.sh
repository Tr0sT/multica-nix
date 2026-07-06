#!/usr/bin/env bash
set -euo pipefail

force=false
output=""
input=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-database-url) force=true; shift ;;
    --output|-o) output="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--force-database-url] [--output FILE] docker.env"; exit 0 ;;
    *) input="$1"; shift ;;
  esac
done
[[ -n "$input" ]] || { echo "missing input .env" >&2; exit 2; }
[[ -f "$input" ]] || { echo "not found: $input" >&2; exit 1; }

join_re() {
  local IFS="|"
  printf '%s' "$*"
}

keep_vars=(
  JWT_SECRET
  DATABASE_MAX_CONNS
  DATABASE_MIN_CONNS
  RESEND_API_KEY
  RESEND_FROM_EMAIL
  SMTP_HOST
  SMTP_PORT
  SMTP_USERNAME
  SMTP_PASSWORD
  SMTP_TLS
  SMTP_TLS_INSECURE
  SMTP_EHLO_NAME
  MULTICA_DEV_VERIFICATION_CODE
  GOOGLE_CLIENT_ID
  GOOGLE_CLIENT_SECRET
  S3_BUCKET
  S3_REGION
  AWS_ENDPOINT_URL
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  ATTACHMENT_DOWNLOAD_MODE
  ATTACHMENT_DOWNLOAD_URL_TTL
  CLOUDFRONT_DOMAIN
  CLOUDFRONT_KEY_PAIR_ID
  CLOUDFRONT_PRIVATE_KEY_SECRET
  CLOUDFRONT_PRIVATE_KEY
  COOKIE_DOMAIN
  AUTH_TOKEN_TTL
  ALLOW_SIGNUP
  ALLOWED_EMAILS
  ALLOWED_EMAIL_DOMAINS
  DISABLE_WORKSPACE_CREATION
  GITHUB_APP_SLUG
  GITHUB_WEBHOOK_SECRET
  GITHUB_APP_ID
  GITHUB_APP_PRIVATE_KEY
  MULTICA_LARK_SECRET_KEY
  MULTICA_LARK_HTTP_BASE_URL
  MULTICA_LARK_CALLBACK_BASE_URL
  MULTICA_LARK_WS_PROXY_URL
  MULTICA_SLACK_SECRET_KEY
  REDIS_URL
  REDIS_DISABLE_CLIENT_NAME
  RATE_LIMIT_AUTH
  RATE_LIMIT_AUTH_VERIFY
  RATE_LIMIT_TRUSTED_PROXIES
  REALTIME_METRICS_TOKEN
  ANALYTICS_DISABLED
  ANALYTICS_ENVIRONMENT
  POSTHOG_API_KEY
  POSTHOG_HOST
  MULTICA_FEATURE_FLAGS_FILE
)

drop_vars=(
  DATABASE_URL
  POSTGRES_DB
  POSTGRES_USER
  POSTGRES_PASSWORD
  POSTGRES_PORT
  PORT
  BACKEND_PORT
  API_PORT
  SERVER_PORT
  FRONTEND_PORT
  FRONTEND_ORIGIN
  CORS_ALLOWED_ORIGINS
  GOOGLE_REDIRECT_URI
  MULTICA_APP_URL
  MULTICA_PUBLIC_URL
  MULTICA_TRUSTED_PROXIES
  METRICS_ADDR
  LOCAL_UPLOAD_DIR
  LOCAL_UPLOAD_BASE_URL
  NEXT_PUBLIC_API_URL
  NEXT_PUBLIC_WS_URL
  REMOTE_API_URL
  STANDALONE
  NODE_ENV
  HOSTNAME
  MULTICA_BACKEND_IMAGE
  MULTICA_WEB_IMAGE
  MULTICA_IMAGE_TAG
)

keep_re="^($(join_re "${keep_vars[@]}"))="
drop_re="^($(join_re "${drop_vars[@]}"))="

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && { printf '%s\n' "$line" >> "$tmp"; continue; }

  if [[ "$line" =~ ^DATABASE_URL= ]]; then
    if [[ "$force" != true ]]; then
      echo "Refusing to write DATABASE_URL. Use --force-database-url only if you intentionally target an external DB." >&2
      exit 1
    fi
    printf '%s\n' "$line" >> "$tmp"
  elif [[ "$line" =~ $keep_re || "$line" =~ ^FF_[A-Za-z0-9_]+= ]]; then
    printf '%s\n' "$line" >> "$tmp"
  elif [[ "$line" =~ $drop_re ]]; then
    echo "Dropping module-managed Docker/core variable: ${line%%=*}" >&2
  else
    echo "Skipping unknown variable: ${line%%=*}" >&2
  fi
done < "$input"

if [[ -n "$output" ]]; then
  install -m 0600 "$tmp" "$output"
else
  cat "$tmp"
fi
