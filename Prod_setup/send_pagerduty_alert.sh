#!/bin/bash

# === CONFIGURATION ===
INTEGRATION_KEY="INTEGRATION KEY FROM PAGAERDUTU API KEY"   # Replace with your real key
EVENTS_API_URL="https://events.pagerduty.com/v2/enqueue"

# === ALERT DETAILS ===
SUMMARY="🚨 Test alert from shell script"
SEVERITY="critical"  # Options: info, warning, error, critical
SOURCE="Local Shell Script"

# === PAYLOAD ===
read -r -d '' PAYLOAD <<EOF
{
  "routing_key": "$INTEGRATION_KEY",
  "event_action": "trigger",
  "payload": {
    "summary": "$SUMMARY",
    "severity": "$SEVERITY",
    "source": "$SOURCE"
  }
}
EOF

# === SEND ALERT ===
echo "🚀 Sending alert to PagerDuty..."

RESPONSE=$(curl --silent --write-out "\n%{http_code}" --request POST \
  --url "$EVENTS_API_URL" \
  --header 'Content-Type: application/json' \
  --data "$PAYLOAD")

# Separate JSON and HTTP code
HTTP_BODY=$(echo "$RESPONSE" | head -n1)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" -eq 202 ]; then
  echo "✅ Alert sent successfully."
else
  echo "❌ Failed to send alert. HTTP $HTTP_CODE"
  echo "Response:"
  echo "$HTTP_BODY"
fi