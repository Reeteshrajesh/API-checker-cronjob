# 🚨 Zenduty Integration for API Health Alerts

This integration sends real-time API health alerts to [Zenduty](https://www.zenduty.com/) using the **Generic Integration Webhook**.

## 📦 Overview

This script monitors a list of APIs and triggers **Zenduty incidents** automatically when APIs return failure status codes (e.g. 500, 404). You can configure alert severity and summaries per API category, such as:

* `App-crashing` – Critical alert
* `IMP-feature-spacific` – Urgent alert
* `handled` – Info alert (Slack only)

---

## ⚙️ Prerequisites

1. **Zenduty account and team**
2. **Service & Generic Integration** created under your Zenduty team
3. `curl`, `jq`, and `bash` installed on the monitoring machine
4. API token or OTP authentication for the monitored service

---

## 🛠️ Setup in Zenduty

### 1. Create Integration

* Go to `Teams` → Select your team
* Navigate to `Services` → Choose or create a service
* Go to `Integrations` → Click `Add New Integration`
* Select **Generic Integration**
* Copy the generated **Webhook URL**

### 2. Configure Custom Mapping (optional)

If you use a custom payload, you must configure **Custom Mapping** in Zenduty:

* Use `message`, `summary`, and `alert_type` fields in your payload
* Map the fields under `Configure` → `Generic Configuration` in the integration settings

---

## 🧪 Sample Payload

Minimum payload Zenduty expects:

```json
{
  "alert_type": "critical",
  "message": "🚨 App is crashing!",
  "summary": "Critical crash on /api/health",
  "entity_id": "App-crashing_incident",
  "urls": [
    {
      "link_url": "https://api.example.com/health",
      "link_text": "Failed API"
    }
  ]
}
```

If `alert_type` is missing, **no incident will be created**, even if Zenduty responds with 200/202.

---

## 📜 Script Behavior

* Reads `.txt` files from the `pages/` directory
* Authenticates with the API
* Loops through each API and checks its health
* On non-200 response:

  * Sends Zenduty alert for critical/urgent issues
  * Sends Slack alert for info-only pages (like `handled`)
* Cleans up temporary files and generates local reports

---

## 📁 Directory Structure

```
.
├── zen-duty_check.sh         # Main script
├── pages/                    # Folder with .txt files containing URLs
│   ├── App-crashing.txt
│   └── IMP-feature-spacific.txt
├── reports/                  # Temporary folder for API health reports
```

---

## 📌 Important Notes

* `message`, `summary`, and `alert_type` are **required fields** in the payload.
* Use `entity_id` to prevent creating duplicate incidents on repeat alerts.
* You may track alert delivery using the returned `trace_id`.

---

## 🔄 Alert Status (Optional)

Use the following endpoint to get the status of a Zenduty alert:

```bash
curl -L 'https://events.zenduty.com/api/alert/status/<trace_id>/'
```

Possible responses:

* `queued`
* `completed`
* `failed`

---

## ✅ Recommended Alert Types

| Page Name              | alert\_type | Triggered By               |
| ---------------------- | ----------- | -------------------------- |
| `App-crashing`         | `critical`  | High-priority crash errors |
| `IMP-feature-spacific` | `critical`  | Feature failure APIs       |
| `handled`              | –           | Slack only (no Zenduty)    |

---

## ✨ Example Slack Message (handled)

```
API Alert ℹ️ Error Handled issue detected.
URL: https://api.example.com/fallback
Status: 500
P2 Please FIX this ASAP.
```

---

## 🔐 Secrets to Manage

| Key                 | Source               |
| ------------------- | -------------------- |
| `SLACK_WEBHOOK_URL` | Slack App Webhook    |
| `INCIDENT_URL`      | Zenduty Integration  |
| `MOBILE`, `OTP`     | API Auth credentials |

Store these as environment variables or in a secure vault/secrets manager.

---

## 📞 Support

If incidents aren't showing up:

* Ensure `alert_type` is included in payload
* Confirm integration key is valid
* Check if Custom Mapping is enabled but misconfigured
* Use `trace_id` to debug with Zenduty’s status API
