# 🚀 Kubernetes API Health Checker

A Kubernetes CronJob to **authenticate**, **monitor API endpoints**, **retry transient failures**, and **send Slack alerts** when something goes wrong.

Designed for **production workloads on AWS EKS**.

---

## ✨ Features

* ✅ Automatic authentication to your API using Mobile/OTP
* ✅ Retries on 500 errors with backoff
* ✅ Slack notifications for any non-200 status
* ✅ Timestamped reports for each API group
* ✅ Runs hourly (or configurable schedule)
* ✅ Clean up after each run

---

## 📦 Folder Structure

```
.
├── cronjob.yaml               # Kubernetes CronJob manifest
├── health-check-secrets.yaml  # Kubernetes Secret manifest for credentials
├── run_health_check.sh        # Health check script
├── pages/                     # API URL lists
│   ├── critical.txt
│   └── important.txt
```

---

## ⚙️ Prerequisites

* ✅ An EKS cluster running (e.g., created with `eksctl` or Terraform)
* ✅ `kubectl` configured to point to your EKS cluster
* ✅ Slack webhook URL
* ✅ Mobile and OTP credentials for authentication

---

## 🚀 Installation Guide (EKS)

Follow these steps carefully:

---

### 1️⃣ Configure kubectl for EKS

If you used `eksctl`, configure your context:

```bash
aws eks --region <your-region> update-kubeconfig --name <your-cluster-name>
```

Verify:

```bash
kubectl get nodes
```

✅ You should see EKS nodes.

---

### 2️⃣ Prepare Secrets

Create a `health-check-secrets.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: health-check-secrets
type: Opaque
stringData:
  MOBILE: "your_mobile_number"
  OTP: "your_otp_code"
  SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/..."
```

Apply:

```bash
kubectl apply -f health-check-secrets.yaml
```

---

### 3️⃣ Create the Script ConfigMap

Verify this line in `run_health_check.sh` is correct:

```bash
PAGES_DIR="/pages"
```

Then create the ConfigMap:

```bash
kubectl create configmap health-check-script --from-file=run_health_check.sh
```

---

### 4️⃣ Create the Pages ConfigMap

Inside your `pages/` folder, create `.txt` files listing API URLs.

Example `pages/critical.txt`:

```
https://api.example.com/health
https://api.example.com/status
```

Example `pages/important.txt`:

```
https://api.example.com/info
```

Create the ConfigMap:

```bash
kubectl create configmap health-check-pages --from-file=pages/
```

---

### 5️⃣ Deploy the CronJob

Apply the manifest:

```bash
kubectl apply -f cronjob.yaml
```

This schedules the job **every hour** (`0 * * * *`).

---

### 6️⃣ Run a Manual Test

Create a one-time job:

```bash
kubectl create job --from=cronjob/health-check-cron health-check-manual-run
```

Find the pod:

```bash
kubectl get pods
```

View logs:

```bash
kubectl logs <pod-name>
```

✅ You should see logs for:

* Authentication success
* API call attempts
* Slack alerts (if failures)

---

## 🔄 Adjusting the Schedule

In `cronjob.yaml`, edit:

```yaml
spec:
  schedule: "0 * * * *"
```

**Examples:**

* Every 30 minutes:

  ```
  */30 * * * *
  ```
* Daily at midnight:

  ```
  0 0 * * *
  ```

Use [crontab.guru](https://crontab.guru/) to verify cron syntax.

---

## 🧭 Architecture Overview

There are two primary ways to run this kind of health-check CronJob in Kubernetes:

---

### 🅰️ **Method A: Custom Docker Image (Pre-baked Script)**

* Build your own Docker image with all dependencies (`bash`, `curl`, `jq`) and the script baked inside.
* Push it to a container registry (like ECR or DockerHub).
* Use it in the CronJob directly.
* ✅ **Faster startup**
* ⚠️ **Requires CI pipeline and image versioning**

---

### 🅱️ **Method B: Script from ConfigMap (This Repo’s Approach)**

* Mount the script and API pages via **ConfigMaps**
* Install tools (`bash`, `curl`, `jq`) on-the-fly inside an Alpine container
* No need to build or push custom Docker images
* ✅ **Easier to update scripts**
* ✅ **Fully GitOps-friendly**
* ⚠️ **Slightly slower startup due to tool installation**

---

✅ **Why this approach?**

This repository uses **Method B** to keep the system:

* Fully version-controlled in Git
* Easy to update without rebuilding Docker images
* Simple to audit and evolve

---

## 🧹 Cleanup

When you need to remove resources:

```bash
kubectl delete cronjob health-check-cron
kubectl delete job health-check-manual-run
kubectl delete configmap health-check-script
kubectl delete configmap health-check-pages
kubectl delete secret health-check-secrets
```

---

## ✨ Advanced Usage

✅ **Keep Reports:**

By default, reports are deleted after each run.
To keep them, comment out this line in `run_health_check.sh`:

```bash
rm -rf "$REPORTS_DIR"
```

✅ **Adjust Retry Delays:**

Edit this array in the script:

```bash
RETRY_DELAYS=(1 2 4 7)
```

✅ **Add More API Groups:**

Just create new `.txt` files in `pages/`, then recreate the ConfigMap:

```bash
kubectl delete configmap health-check-pages
kubectl create configmap health-check-pages --from-file=pages/
```

✅ **Rotate Secrets:**

Update `health-check-secrets.yaml` and re-apply:

```bash
kubectl apply -f health-check-secrets.yaml
```

---

## 🛠️ Troubleshooting

✅ **Script can’t find `./pages/*.txt`**

* Make sure `PAGES_DIR="/pages"` in your script.

✅ **Permission denied**

* Ensure you execute:

  ```yaml
  bash /scripts/run_health_check.sh
  ```

  in `cronjob.yaml`.

✅ **No Slack notifications**

* Double-check the Slack webhook URL.

✅ **Pods can’t access the Internet**

* Verify your EKS nodes have outbound Internet (NAT Gateway or public IP).

---

## 💬 Questions?

Open an issue or create a pull request—happy to help!

---

**Happy monitoring!** 🎯

