#!/bin/bash
set -euo pipefail

# -------------
# CONFIGURATION
# -------------
PAGES_DIR="/pages"
REPORTS_DIR="./reports"
mkdir -p "$REPORTS_DIR"

# Login credentials (from env)
MOBILE="${MOBILE:?MOBILE not set}"
OTP="${OTP:?OTP not set}"

# Slack webhook (from env)
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL not set}"

DATE=$(date "+%Y-%m-%d %H:%M:%S")

# Cleanup temp files on exit
cleanup() {
  rm -f response.tmp metrics.tmp
}
trap cleanup EXIT

# -------------
# AUTHENTICATE
# -------------
echo "Logging in to retrieve token..."
LOGIN_RESPONSE=$(curl -s --max-time 10 --connect-timeout 5 --location 'Auth url' \
  --header 'Content-Type: application/json' \
  --data "{
    \"mobile\": \"$MOBILE\",
    \"otp\": \"$OTP\"
  }")

AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.message.data[0].token')

if [[ "$AUTH_TOKEN" == "null" || -z "$AUTH_TOKEN" ]]; then
  echo "Failed to retrieve auth token. Exiting."
  echo "Response was:"
  echo "$LOGIN_RESPONSE"
  exit 1
fi

echo "Token retrieved."

# -------------
# SLACK ALERT FUNCTION
# -------------
send_slack_alert() {
  local page="$1"
  local url="$2"
  local status="$3"
  local message="*API Alert* on *$page*

URL: <$url>
Status Code: *$status*"

  curl -s --max-time 10 --connect-timeout 5 -X POST -H 'Content-type: application/json' \
    --data "{\"text\": \"$message\"}" \
    "$SLACK_WEBHOOK_URL" > /dev/null
}

# -------------
# LOOP OVER PAGES
# -------------
for PAGE_FILE in "$PAGES_DIR"/*.txt; do
  PAGE_NAME=$(basename "$PAGE_FILE" .txt)
  REPORT_FILE="$REPORTS_DIR/${PAGE_NAME}_report.txt"

  echo "API Health Report for: $PAGE_NAME" > "$REPORT_FILE"
  echo "Generated on: $DATE" >> "$REPORT_FILE"
  echo "----------------------------------------" >> "$REPORT_FILE"

  while read -r URL || [ -n "$URL" ]; do
    if [[ "$URL" == "" || "$URL" == \#* ]]; then
      continue
    fi

    echo "API: $URL" >> "$REPORT_FILE"

    RETRY_DELAYS=(1 2 4 7)
    ATTEMPT=0
    STATUS="500"

    while : ; do
      curl -s --max-time 10 --connect-timeout 5 -o response.tmp \
        -H "x-access-token: $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -w "Status: %{http_code}\n" \
        "$URL" > metrics.tmp

      STATUS=$(grep "Status" metrics.tmp | awk '{print $2}')

      echo "Attempt $((ATTEMPT + 1)): Status $STATUS" >> "$REPORT_FILE"

      if [[ "$STATUS" != "500" ]]; then
        break
      fi

      if [[ $ATTEMPT -ge ${#RETRY_DELAYS[@]} ]]; then
        break
      fi

      DELAY=${RETRY_DELAYS[$ATTEMPT]}
      echo "Retrying after $DELAY seconds..." >> "$REPORT_FILE"
      sleep "$DELAY"
      ((ATTEMPT++))
    done

    echo "Result:" >> "$REPORT_FILE"
    cat metrics.tmp >> "$REPORT_FILE"

    BODY_PREVIEW=$(cat response.tmp | tr -d '\n' | cut -c1-200)
    echo "Body Preview: $BODY_PREVIEW" >> "$REPORT_FILE"
    echo "----------------------------------------" >> "$REPORT_FILE"

    if [[ "$STATUS" != "200" ]]; then
      send_slack_alert "$PAGE_NAME" "$URL" "$STATUS"
    fi

  done < "$PAGE_FILE"

done

echo "All reports processed."
