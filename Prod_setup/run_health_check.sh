#!/bin/bash

# -------------
# CONFIGURATION
# -------------
PAGES_DIR="./pages"
REPORTS_DIR="./reports"
mkdir -p "$REPORTS_DIR"

# Login credentials
MOBILE="$MOBILEE"
OTP="$OTPP"

# Slack webhook
SLACK_WEBHOOK_URL=""

DATE=$(date "+%Y-%m-%d %H:%M:%S")

# -------------
# AUTHENTICATE
# -------------
echo "Logging in to retrieve token..."
LOGIN_RESPONSE=$(curl -s --location '$DEV_LOGIN_API' \
  --header 'Content-Type: application/json' \
  --data "{
    \"mobile\": \"$MOBILE\",
    \"otp\": \"$OTP\"
  }")

# Correct token extraction path
AUTH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.message.data[0].token')

# Validate token
if [[ "$AUTH_TOKEN" == "null" || -z "$AUTH_TOKEN" ]]; then
  echo "Failed to retrieve auth token. Exiting."
  echo "Response was:"
  echo "$LOGIN_RESPONSE"
  exit 1
fi

echo "Token retrieved: $AUTH_TOKEN"

# -------------
# SLACK ALERT FUNCTION
# -------------
send_slack_alert() {
  local page="$1"
  local url="$2"
  local status="$3"
  local message=""
  if [[ "$page" == "IMP-feature-specific" ]]; then
    message="API Alert ❗ *Feature-specific problem detected.* \n*Page:* $page\n*URL:* <$url>\n*Status Code:* *$status*\n *This is P1 - services might need to be RESTARTED.* "
  elif [[ "$page" == "App-crashing" ]]; then
    message="API Alert 🚨 *Critical issue: The app has crashed.* \n*URL:* <$url>\n*Status Code:* *$status*\n *This is P0 - the app is crashing. Check IMMEDIATELY!* "
  fi

  curl -s -X POST -H 'Content-type: application/json' \
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
    # Skip empty lines and comments
    if [[ "$URL" == "" || "$URL" == \#* ]]; then
      continue
    fi

    echo "API: $URL" >> "$REPORT_FILE"

    # Define retry delays in seconds
    RETRY_DELAYS=(1 2 4 7)
    ATTEMPT=0
    STATUS="500"

    # Loop with initial attempt + retries
    while : ; do
      # Make authenticated request
      curl -s -o response.tmp \
        -H "x-access-token: $AUTH_TOKEN" \
        -H "Content-Type: application/json" \
        -w "Status: %{http_code}\n" \
        "$URL" > metrics.tmp

      STATUS=$(grep "Status" metrics.tmp | awk '{print $2}')

      echo "Attempt $((ATTEMPT + 1)): Status $STATUS" >> "$REPORT_FILE"

      # If status is not 500, break retry loop
      if [[ "$STATUS" != "500" ]]; then
        break
      fi

      # Check if there are more retries
      if [[ $ATTEMPT -ge ${#RETRY_DELAYS[@]} ]]; then
        break
      fi

      # Wait before next retry
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

    # Alert if status != 200
    if [[ "$STATUS" != "200" ]]; then
      send_slack_alert "$PAGE_NAME" "$URL" "$STATUS"
    fi

  done < "$PAGE_FILE"

done

# -------------
# CLEAN UP
# -------------
# Uncomment these lines if you want to delete reports after run
rm -f response.tmp metrics.tmp
rm -rf "$REPORTS_DIR"

echo "All reports processed and cleaned up."
