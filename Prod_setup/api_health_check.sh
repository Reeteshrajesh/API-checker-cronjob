#!/bin/bash

# CONFIGURATION
PAGES_DIR="/pages"
REPORTS_DIR="./reports"
mkdir -p "$REPORTS_DIR"

# Login credentials
MOBILE="${MOBILE:?MOBILE not set}" # comes from secret
OTP="${OTP:?OTP not set}" # comes from secret

# Slack webhook
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL not set}" # comes from secret

# PagerDuty
PAGERDUTY_INTEGRATION_KEY="${PAGERDUTY_INTEGRATION_KEY}" # comes from secret
EVENTS_API_URL="https://events.pagerduty.com/v2/enqueue"

DATE=$(date "+%Y-%m-%d %H:%M:%S")

# AUTHENTICATE
echo "Logging in to retrieve token..."
LOGIN_RESPONSE=$(curl -s --location '$LOGIN_API'  \  # $LOGIN_API (mendatory to fill) before run cronjob hardcodes or add this is also in secret (use to get auth token)
  --header 'Content-Type: application/json' \
  --data "{
    \"mobile\": \"$MOBILE\",
    \"otp\": \"$OTP\"
  }")

AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.message.data[0].token')

if [[ "$AUTH_TOKEN" == "null" || -z "$AUTH_TOKEN" ]]; then
  echo "❌ Failed to retrieve auth token. Exiting."
  echo "Response was:"
  echo "$LOGIN_RESPONSE"
  exit 1
fi

echo " Token retrieved."

# FUNCTIONS

send_slack_alert() {
  local page="$1"
  local url="$2"
  local status="$3"
  local message=""

  if [[ "$page" == "IMP-feature-spacific" ]]; then
    message="API Alert ❗ *Feature-specific problem detected.* \n*Page:* $page\n*URL:* <$url>\n*Status:* *$status*\n*P1 - Please investigate.*"
  elif [[ "$page" == "App-crashing" ]]; then
    message="API Alert 🚨 *Critical issue: App is crashing.* \n*URL:* <$url>\n*Status:* *$status*\n*P0 - Immediate action required.*"
  elif [[ "$page" == "handled" ]]; then
    message="API Alert ℹ️ *Error Handled issue detected.* \n*URL:* <$url>\n*Status:* *$status*\n*P2 Please FIX this ASAP.*"
  else
    message="API Alert ⚠️ *General issue detected.* \n*Page:* $page\n*URL:* <$url>\n*Status:* *$status*"
  fi

  curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\": \"$message\"}" \
    "$SLACK_WEBHOOK_URL" > /dev/null
}

send_pagerduty_alert() {
  local page="$1"
  local url="$2"
  local status="$3"
  local severity="error"
  local summary="API issue detected"
  local component="$page"

  if [[ "$page" == "App-crashing" ]]; then
    severity="critical"
    summary="🚨 CRITICAL: App is crashing!"
  elif [[ "$page" == "IMP-feature-spacific" ]]; then
    severity="warning"
    summary="❗ Important feature failure detected."
  fi

  read -r -d '' PAYLOAD <<EOF
{
  "routing_key": "$PAGERDUTY_INTEGRATION_KEY",
  "event_action": "trigger",
  "payload": {
    "summary": "$summary URL: $url Status: $status",
    "severity": "$severity",
    "source": "API Health Check Script",
    "component": "$component"
  }
}
EOF

  RESPONSE=$(curl --silent --write-out "\n%{http_code}" --request POST \
    --url "$EVENTS_API_URL" \
    --header 'Content-Type: application/json' \
    --data "$PAYLOAD")

  HTTP_BODY=$(echo "$RESPONSE" | head -n1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

  if [ "$HTTP_CODE" -eq 202 ]; then
    echo " PagerDuty alert triggered."
  else
    echo "❌ Failed to trigger PagerDuty alert (HTTP $HTTP_CODE)."
    echo "Response: $HTTP_BODY"
  fi
}

# PROCESS PAGES

for PAGE_FILE in "$PAGES_DIR"/*.txt; do
  PAGE_NAME=$(basename "$PAGE_FILE" .txt)
  REPORT_FILE="$REPORTS_DIR/${PAGE_NAME}_report.txt"

  echo "🔍 Processing page: $PAGE_NAME"
  echo "API Health Report for: $PAGE_NAME" > "$REPORT_FILE"
  echo "Generated on: $DATE" >> "$REPORT_FILE"
  echo "----------------------------------------" >> "$REPORT_FILE"

  while read -r URL || [ -n "$URL" ]; do
    if [[ "$URL" == "" || "$URL" == \#* ]]; then
      continue
    fi

   # echo "Checking: $URL"
    echo "API: $URL" >> "$REPORT_FILE"

    # Retry delays
    RETRY_DELAYS=(1 2 4 7)
    ATTEMPT=0
    STATUS="500"

    while : ; do
      curl -s -o response.tmp \
        -H "x-access-token: $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -w "Status: %{http_code}\n" \
        "$URL" > metrics.tmp

      STATUS=$(grep "Status" metrics.tmp | awk '{print $2}')
      echo "Attempt $((ATTEMPT+1)): Status $STATUS" >> "$REPORT_FILE"

      if [[ "$STATUS" != "500" ]]; then
        break
      fi

      if [[ $ATTEMPT -ge ${#RETRY_DELAYS[@]} ]]; then
        break
      fi

      DELAY=${RETRY_DELAYS[$ATTEMPT]}
      echo "Retrying in $DELAY sec..." >> "$REPORT_FILE"
      sleep "$DELAY"
      ((ATTEMPT++))
    done

    echo "Result:" >> "$REPORT_FILE"
    cat metrics.tmp >> "$REPORT_FILE"

    BODY_PREVIEW=$(tr -d '\n' < response.tmp | cut -c1-200)
    echo "Body Preview: $BODY_PREVIEW" >> "$REPORT_FILE"
    echo "----------------------------------------" >> "$REPORT_FILE"

    # Decide action
    if [[ "$STATUS" != "200" ]]; then
      if [[ "$PAGE_NAME" == "IMP-feature-spacific" || "$PAGE_NAME" == "App-crashing" ]]; then
        send_pagerduty_alert "$PAGE_NAME" "$URL" "$STATUS"
      elif [[ "$PAGE_NAME" == "handled" ]]; then
        send_slack_alert "$PAGE_NAME" "$URL" "$STATUS"
      fi
    fi

  done < "$PAGE_FILE"
done

# Clean up
rm -f response.tmp metrics.tmp
rm -rf reports

echo " All checks completed."
