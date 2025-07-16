#!/usr/bin/env bash

# ============================================================
# Zenduty API Health Check Script
# ============================================================

# CONFIGURATION
PAGES_DIR="./pages"
REPORTS_DIR="./reports"
mkdir -p "$REPORTS_DIR"

# Credentials (Load securely in production)
MOBILE="9********9"
OTP="0****7"

# Slack Webhook
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"

# Zenduty Generic Integration Webhook
INCIDENT_URL="https://events.zenduty.com/integration/XXXX/generic/YYYY/"

# Timestamp
DATE=$(date "+%Y-%m-%d %H:%M:%S")

# ============================================================
# AUTHENTICATION
# ============================================================
echo "Logging in to retrieve token..."

LOGIN_RESPONSE=$(curl -s --location '<login Auth Api>' \
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

echo "✅ Token retrieved."

# ============================================================
# FUNCTIONS
# ============================================================

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
    message="API Alert ℹ️ *Handled error detected.* \n*URL:* <$url>\n*Status:* *$status*\n*P2 - Please review.*"
  else
    message="API Alert ⚠️ *General issue detected.* \n*Page:* $page\n*URL:* <$url>\n*Status:* *$status*"
  fi

  curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\": \"$message\"}" \
    "$SLACK_WEBHOOK_URL" > /dev/null
}

send_zenduty_alert() {
  local page="$1"
  local url="$2"
  local status="$3"

  local alert_type="error"
  local message="API issue detected"
  local summary="API returned status $status"

  if [[ "$page" == "App-crashing" ]]; then
    alert_type="critical"
    message="🚨 CRITICAL: App is crashing!"
    summary="App crash detected"
  elif [[ "$page" == "IMP-feature-spacific" ]]; then
    alert_type="critical"
    message="❗ Important feature failure detected."
    summary="Feature-specific failure"
  fi

  # Compose payload
  JSON_PAYLOAD=$(jq -n \
    --arg alert_type "$alert_type" \
    --arg message "$message" \
    --arg summary "$summary" \
    --arg entity_id "$page" \
    --arg link_url "$url" \
    --arg link_text "Failed API" \
    '{
      alert_type: $alert_type,
      message: $message,
      summary: $summary,
      entity_id: $entity_id,
      urls: [
        {
          link_url: $link_url,
          link_text: $link_text
        }
      ]
    }')

  echo "Sending Zenduty Alert:"
  echo "URL: $INCIDENT_URL"
  echo "Payload: $JSON_PAYLOAD"

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$INCIDENT_URL" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

  HTTP_BODY=$(echo "$RESPONSE" | head -n1)
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

  if [[ "$HTTP_CODE" -eq 200 || "$HTTP_CODE" -eq 202 ]]; then
    echo "✅ Zenduty alert triggered successfully."
  else
    echo "❌ Failed to trigger Zenduty alert (HTTP $HTTP_CODE)."
    echo "Response body: $HTTP_BODY"
  fi
}

# ============================================================
# PROCESS PAGES
# ============================================================

for PAGE_FILE in "$PAGES_DIR"/*.txt; do
  PAGE_NAME=$(basename "$PAGE_FILE" .txt)
  REPORT_FILE="$REPORTS_DIR/${PAGE_NAME}_report.txt"

  echo "🔍 Processing page: $PAGE_NAME"
  echo "API Health Report for: $PAGE_NAME" > "$REPORT_FILE"
  echo "Generated on: $DATE" >> "$REPORT_FILE"
  echo "----------------------------------------" >> "$REPORT_FILE"

  while read -r URL || [ -n "$URL" ]; do
    if [[ -z "$URL" || "$URL" == \#* ]]; then
      continue
    fi

    echo "API: $URL" >> "$REPORT_FILE"

    # Retry mechanism
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

    # Trigger alerts
    if [[ "$STATUS" != "200" ]]; then
      if [[ "$PAGE_NAME" == "IMP-feature-spacific" || "$PAGE_NAME" == "App-crashing" ]]; then
        send_zenduty_alert "$PAGE_NAME" "$URL" "$STATUS"
      elif [[ "$PAGE_NAME" == "handled" ]]; then
        send_slack_alert "$PAGE_NAME" "$URL" "$STATUS"
      fi
    fi

  done < "$PAGE_FILE"
done

# Clean up
rm -f response.tmp metrics.tmp

echo "✅ All checks completed."
