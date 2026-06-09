# HCHI Complete Deployment Guide

## Hybrid Cloud HomeLab Infrastructure (HCHI)

This document defines the complete standard for deploying applications into the HCHI Platform Infrastructure — covering application structure, required files, Dockerfile standards, CI/CD workflows, and operational commands.

**Platform Stack:** Docker · GitHub Actions · Self-Hosted Runner · HCHI Deployment Engine · NGINX Proxy Manager

---

## Platform Goals

- Reusable, automated deployments
- Self-hosted CI/CD via GitHub Actions
- Intelligent internal routing via NGINX Proxy Manager
- Dockerized application hosting on Raspberry Pi 5
- Centralized infrastructure management
- Scalable multi-application hosting

---

## Platform Philosophy

The HCHI platform simulates real-world enterprise DevOps workflows using zero-cost, open-source tooling:

- Enterprise DevOps & platform engineering
- Self-hosted cloud infrastructure
- Automated CI/CD pipelines
- Intelligent routing systems
- Centralized application orchestration

**Built with:** Raspberry Pi 5 · Docker · GitHub Actions · NGINX Proxy Manager · Open-source tooling

---

# Part 1 — Infrastructure Reference

## 1.1 Platform Directory Structure

| Purpose              | Path                                           |
| -------------------- | ---------------------------------------------- |
| Platform Root        | `/mnt/homelab-storage/platform`                |
| Deployment Scripts   | `/mnt/homelab-storage/platform/scripts`        |
| Applications         | `/mnt/homelab-storage/platform/apps`           |
| Deployment Metadata  | `/mnt/homelab-storage/platform/deployments`    |
| Platform Logs        | `/mnt/homelab-storage/platform/logs`           |
| GitHub Runner        | `/mnt/homelab-storage/docker/github-runner`    |

---

## 1.2 HCHI Automated Deployment Flow

```
Developer Laptop
        ↓
Git Push to main branch
        ↓
GitHub Repository
        ↓
GitHub Actions
        ↓
HCHI Shared Self-Hosted Runner (Pi 5)
        ↓
sync-app.sh / HCHI Deployment Engine
        ↓
Docker Build & Container Redeploy
        ↓
NGINX Proxy Manager Routing
        ↓
Application Live
```

---

# Part 2 — Application Standard

## 2.1 Required Application Structure

Every deployable application MUST follow this structure:

```
app-name/
├── Dockerfile
├── deployment.json
├── .dockerignore
├── README.md
├── .github/
│   └── workflows/
│       └── deploy.yml
├── backend/
├── frontend/
└── (application source code)
```

---

## 2.2 Required Files

| File              | Required | Purpose                              |
| ----------------- | -------- | ------------------------------------ |
| `Dockerfile`      | YES      | Container build instructions         |
| `deployment.json` | YES      | HCHI deployment metadata             |
| `.dockerignore`   | YES      | Optimized Docker builds              |
| `deploy.yml`      | YES      | Automated GitHub Actions deployment  |
| `README.md`       | YES      | Project documentation                |

---

## 2.3 deployment.json

This file is **required**. The HCHI deployment engine reads it automatically.

### Example

```json
{
  "app_name": "task-management-app",
  "container_name": "task-manager-app",
  "internal_domain": "task-manager.homelab",
  "container_port": 3031,
  "host_port": 3031,
  "health_endpoint": "/api/health",
  "restart_policy": "unless-stopped",
  "network": "homelab-network"
}
```

### Field Definitions

| Field             | Purpose                          |
| ----------------- | -------------------------------- |
| `app_name`        | Docker image name                |
| `container_name`  | Docker container name            |
| `internal_domain` | Internal reverse proxy domain    |
| `container_port`  | Internal application port        |
| `host_port`       | Raspberry Pi exposed port        |
| `health_endpoint` | Health monitoring endpoint       |
| `restart_policy`  | Docker restart strategy          |
| `network`         | Docker network used for routing  |

> **Note:** Docker image and container names MUST be lowercase. The HCHI platform automatically converts names to lowercase internally.

---

## 2.4 Dockerfile Standards

All applications MUST be Dockerized.

### Static Frontend (nginx)

```dockerfile
FROM nginx:alpine

COPY . /usr/share/nginx/html

EXPOSE 80
```

### Node.js Backend

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

EXPOSE 3031

CMD ["npm", "start"]
```

---

## 2.5 Frontend Deployment Rules (React / Vite)

`vite.config.js` MUST include the following configuration:

```js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: './'
})
```

This ensures reverse proxy compatibility, proper asset loading, and Dockerized deployment support.

---

## 2.6 Static Asset Rules

Applications MUST use relative asset paths and proxy-safe routing.

**Avoid:**
```
/assets/...
```

**Use instead:**
```
./assets/...
```

---

## 2.7 GitHub Actions Workflow

Every application must include a workflow file at:

```
.github/workflows/deploy.yml
```

### Standard Workflow

```yaml
name: HCHI Automated Deployment

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: self-hosted

    steps:
      - name: Trigger HCHI Sync Engine
        run: |
          sync-app APP_FOLDER_NAME
```

> **Important:** Replace `APP_FOLDER_NAME` with the actual folder name inside `/mnt/homelab-storage/platform/apps`.

**Example:**

```yaml
sync-app Task-management-app
```

---

# Part 3 — Deployment Procedures

## 3.1 First-Time Application Deployment

Follow these steps in order when deploying a **new** application.

---

### Step 1 — Push Code to GitHub

From your laptop:

```bash
git add .
git commit -m "Initial deployment"
git push
```

---

### Step 2 — Verify Required Files Exist

Ensure the following are present in the repository:

- `Dockerfile`
- `deployment.json`
- `.github/workflows/deploy.yml`

---

### Step 3 — Configure Shared HCHI Runner

Go to your GitHub repository:

```
Repository → Settings → Actions → Runners → New self-hosted runner
```

Choose: **Linux / ARM64**

GitHub will generate a command like:

```bash
./config.sh --url https://github.com/USERNAME/REPO --token XXXXX
```

Copy this command.

---

### Step 4 — Register Runner on Raspberry Pi

```bash
cd /mnt/homelab-storage/docker/github-runner
```

Run the GitHub-generated command:

```bash
./config.sh --url https://github.com/Dharunr257/Task-management-app --token XXXXX
```

---

### Step 5 — Install Runner as Persistent Service

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

Verify the runner is active:

```bash
sudo ./svc.sh status
```

Expected output:

```
active (running)
```

Also verify on GitHub under:

```
Repository → Settings → Actions → Runners
```

The runner should show as **Idle**.

---

### Step 6 — Deploy Application into HCHI

```bash
deploy-app GITHUB_REPO_URL
```

**Example:**

```bash
deploy-app https://github.com/Dharunr257/Task-management-app.git
```

The HCHI platform automatically:

- Clones repository
- Validates `deployment.json`
- Builds Docker image
- Creates container
- Configures restart policy
- Configures Docker networking
- Configures NGINX proxy host
- Saves deployment metadata
- Enables CI/CD updates

---

### Step 7 — Verify Deployment

Check running containers:

```bash
docker ps
```

Check NGINX proxy hosts:

```
http://PI-IP:81
```

Check platform logs:

```bash
ls /mnt/homelab-storage/platform/logs
```

---

## 3.2 Accessing Applications

### Direct Port Access

```
http://192.168.1.10:3031
```

### Internal Domain Routing

```
http://task-manager.homelab
```

### Local DNS Setup (Laptop)

Add the internal domain to your hosts file:

**Windows:** `C:\Windows\System32\drivers\etc\hosts`

```
192.168.1.10 task-manager.homelab
```

---

## 3.3 CI/CD — Pushing Updates

After initial deployment, all future updates are fully automated.

Push from your laptop:

```bash
git add .
git commit -m "Update"
git push
```

GitHub Actions automatically:

- Triggers the self-hosted runner
- Executes `sync-app`
- Rebuilds the Docker image
- Redeploys the container

---

# Part 4 — Platform Commands Reference

## 4.1 Application Commands

| Action            | Command                        |
| ----------------- | ------------------------------ |
| Deploy New App    | `deploy-app <git-repo-url>`    |
| Sync Existing App | `sync-app <app-folder-name>`   |
| Delete App        | `delete-app <app-folder-name>` |

---

## 4.2 Runner Commands

| Action           | Command                                  |
| ---------------- | ---------------------------------------- |
| Register Runner  | `./config.sh --url ... --token ...`      |
| Install Service  | `sudo ./svc.sh install`                  |
| Start Service    | `sudo ./svc.sh start`                    |
| Stop Service     | `sudo ./svc.sh stop`                     |
| Restart Service  | `sudo ./svc.sh restart`                  |
| Check Status     | `sudo ./svc.sh status`                   |
| Remove Runner    | `./config.sh remove --token ...`         |
| View Runner Logs | `journalctl -u actions.runner.* -f`      |

**Runner path:**

```bash
cd /mnt/homelab-storage/docker/github-runner
```

---

# Part 5 — Platform Features

## 5.1 Current Features

Applications deployed into HCHI automatically receive:

- Dockerized containerized deployment
- Self-hosted CI/CD via GitHub Actions
- Reverse proxy routing via NGINX Proxy Manager
- Internal intelligent domain routing
- Multi-application hosting on a single Pi
- Automatic restart on reboot/power loss (`unless-stopped` policy)
- Centralized deployment engine
- Reusable infrastructure patterns

---

## 5.2 Container Persistence

All containers use the `unless-stopped` restart policy. Applications automatically restart after reboot, shutdown, or power loss.

---

## 5.3 NGINX Automation

The HCHI deployment engine automatically creates proxy hosts, configures routing, and enables internal domain access — no manual NGINX configuration required.

---

## 5.4 Planned Future Features

- Automatic rollback system
- Deployment dashboard
- Internal DNS via Pi-hole
- Monitoring & observability
- Deployment logs visualization
- Health monitoring
- Automatic SSL
- Deployment registry
