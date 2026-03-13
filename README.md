

# DevOps WordPress Infrastructure Showcase

This repository demonstrates a progressive DevOps infrastructure project built with **Ansible, Docker, and Caddy**.

The goal of this project is to show how a simple infrastructure can evolve into a **modular, production-like DevOps architecture** with automation, observability, and maintainable deployment workflows.

The infrastructure is built and tested on a **Proxmox-based homelab**.

---

# Architecture Overview

Current architecture (Level 2 – modular refactor)


Internet
↓
Caddy Reverse Proxy (vm-proxy)
↓
WordPress Backend VMs
(vm-wp1, vm-wp2, …)

Observability Stack

Grafana
Loki
Promtail agents


Key components:

- **Caddy** – reverse proxy and TLS termination
- **WordPress** – containerized application backends
- **Docker Compose** – service orchestration
- **Ansible** – infrastructure automation
- **Grafana + Loki + Promtail** – log aggregation and observability

---

# Infrastructure Topology

Example inventory:

vm-proxy → Reverse proxy + Promtail
vm-wp1 → WordPress backend
vm-wp2 → WordPress backend
vm-monitoring → Grafana + Loki + Prometheus


Traffic flow:


Client → Caddy Proxy → WordPress Backend

Logs:
Caddy → Promtail → Loki → Grafana


---

# Deployment Model

The infrastructure is managed through **modular playbooks**.

This refactoring allows targeted operations instead of a monolithic deployment.

Main operational playbooks:


proxy-bootstrap.yml
proxy-sites-refresh.yml
wordpress-backends.yml
wordpress-site.yml
monitoring.yml
level2.yml


## Proxy lifecycle

Bootstrap proxy infrastructure:


ansible-playbook playbooks/proxy-bootstrap.yml


Refresh only the published sites:


ansible-playbook playbooks/proxy-sites-refresh.yml


## WordPress lifecycle

Deploy all backends:


ansible-playbook playbooks/wordpress-backends.yml


Deploy a single site:


ansible-playbook playbooks/wordpress-site.yml -e "target_host=vm-wp1"


## Full deployment


ansible-playbook playbooks/level2.yml


---

# Repository Structure


ansible/
inventory/
group_vars/
playbooks/
roles/

deploy/
docker compose templates

docs/
architecture and examples


Important roles:


caddy_proxy
wordpress_backend
promtail
monitoring_stack


---

# Observability

Logs are centralized using the **Grafana stack**.

Components:


Promtail → log shipping
Loki → log storage
Grafana → visualization


Caddy access logs are automatically collected and visible in Grafana dashboards.

---

# Project Evolution

The repository shows the evolution of the infrastructure.

## Level 1

Single VM WordPress deployment.


VM
└── WordPress
└── Caddy
└── Docker


## Level 2

Reverse proxy architecture with multiple backends.


Proxy VM
↓
Multiple WordPress nodes


## Level 2.1 – Modular Refactor (current)

Infrastructure refactored to separate lifecycle operations.

Improvements:

- proxy bootstrap separated from configuration refresh
- targeted backend deployments
- Promtail attached to node lifecycle
- centralized site definitions
- cleaner orchestration

---

# Technologies Used

Core stack:


Ansible
Docker
Caddy
WordPress
Grafana
Loki
Promtail


Infrastructure:


Proxmox
Linux
GitHub


---

# Why This Project Exists

This repository is part of my **DevOps portfolio**.

The objective is to demonstrate:

- Infrastructure as Code
- Modular automation design
- Reverse proxy architectures
- Container-based deployments
- Observability integration
- Real-world operational workflows

---

# Future Improvements (Level 3)

Planned features:

- CI pipeline (GitHub Actions)
- automated deployment workflows
- staging environment
- infrastructure testing
- backup and restore automation

---

# Author

Sébastien Schmitt

DevOps / Linux Engineer  
Open-source enthusiast  
Focused on infrastructure automation and identity systems.
