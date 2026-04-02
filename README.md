# 🚀 DevOps Staging / Production Infrastructure

A complete DevOps infrastructure to deploy, expose, and monitor applications across **staging** and **production** environments, built with a modular, automated, and production-oriented approach.

---

## 🎯 Project Goal

This project serves as a **real-world DevOps showcase**, not a theoretical lab.

It is designed to:

- 🔧 Deploy applications quickly (web, APIs, static sites)
- 🌐 Expose services through a centralized reverse proxy
- 📊 Provide observability (metrics, logs, monitoring)

It is actively used to:
- host real services
- validate architecture decisions
- demonstrate hands-on DevOps capabilities

---

## 🧠 High-Level Architecture


Internet
│
▼
[ Proxy VM (Caddy) ]
│
├── lavallee.staging.local → Web VM (Nginx)
├── facturier.staging.local → Containerized app
└── other services

[ Application VMs ]
├── vm-lavallee-staging
├── vm-facturier-staging
└── additional project VMs

[ Monitoring VM ]
├── Prometheus
├── Grafana
├── Loki / Promtail

## ⚙️ Tech Stack

### 🐧 Infrastructure
- Linux (Debian / Ubuntu)
- Proxmox (virtualization)
- Private networking with controlled exposure

### 🔁 Automation
- Ansible (deployment & configuration)
- modular roles
- structured inventory (staging / production)

### 🌐 Web Layer
- Caddy (reverse proxy, TLS, routing)
- Nginx (application web server)

### 📦 Containerization
- Docker
- services packaged as containers

### 📊 Observability
- Prometheus (metrics)
- Grafana (dashboards)
- Loki + Promtail (log aggregation)

---

## 📁 Project Structure

```text
ansible/
├── inventory/
│   ├── staging.ini
│   ├── production.ini
│   └── group_vars/
│
├── playbooks/
│   ├── site-staging.yml
│   └── site-production.yml
│
├── roles/
│   ├── proxy_caddy/
│   ├── monitoring/
│   ├── common/
│   └── ...
│
├── vars/
│   └── projects/
│       ├── facturier-staging.yml
│       ├── lavallee-site-staging.yml
│       └── ...
