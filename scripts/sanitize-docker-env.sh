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

keep_re='^(JWT_SECRET|RESEND_API_KEY|RESEND_FROM_EMAIL|SMTP_HOST|SMTP_PORT|SMTP_USERNAME|SMTP_PASSWORD|SMTP_TLS|SMTP_TLS_INSECURE|SMTP_EHLO_NAME|GOOGLE_CLIENT_ID|GOOGLE_CLIENT_SECRET|S3_BUCKET|S3_REGION|AWS_ENDPOINT_URL|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|ATTACHMENT_DOWNLOAD_MODE|ATTACHMENT_DOWNLOAD_URL_TTL|CLOUDFRONT_DOMAIN|CLOUDFRONT_KEY_PAIR_ID|CLOUDFRONT_PRIVATE_KEY|COOKIE_DOMAIN|ALLOW_SIGNUP|ALLOWED_EMAILS|ALLOWED_EMAIL_DOMAINS|DISABLE_WORKSPACE_CREATION|GITHUB_APP_SLUG|GITHUB_WEBHOOK_SECRET|GITHUB_APP_ID|GITHUB_APP_PRIVATE_KEY|MULTICA_LARK_SECRET_KEY|MULTICA_LARK_HTTP_BASE_URL|MULTICA_LARK_CALLBACK_BASE_URL|REDIS_URL|ANALYTICS_DISABLED|POSTHOG_API_KEY|POSTHOG_HOST)='
drop_re='^(DATABASE_URL|POSTGRES_DB|POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_PORT|PORT|BACKEND_PORT|FRONTEND_PORT|FRONTEND_ORIGIN|CORS_ALLOWED_ORIGINS|MULTICA_APP_URL|MULTICA_PUBLIC_URL|LOCAL_UPLOAD_DIR|LOCAL_UPLOAD_BASE_URL|MULTICA_BACKEND_IMAGE|MULTICA_WEB_IMAGE|MULTICA_IMAGE_TAG)='

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && { printf '%s\n' "$line" >> "$tmp"; continue; }
  if [[ "$line" =~ ^DATABASE_URL= && "$force" != true ]]; then
    echo "Refusing to write DATABASE_URL. Use --force-database-url only if you intentionally target an external DB." >&2
    exit 1
  fi
  if [[ "$line" =~ $keep_re ]]; then
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
