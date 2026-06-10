# devops_staging_prod_infra

Infrastructure-as-Code repository used to deploy and operate a small production and staging environment based on Proxmox, Ansible, Docker and Caddy.

The goal of this project is to provide a simple and reproducible way to deploy web applications on dedicated virtual machines while keeping the architecture easy to understand and maintain.

## Architecture Overview

```text
Internet
    |
    | HTTPS
    v
+------------------+
|  VM Proxy        |
|  Caddy           |
|  Let's Encrypt   |
+------------------+
          |
          +------------------------------+
          |                              |
          v                              v

+------------------+          +------------------+
| VM Application   |          | VM Application   |
| Docker           |          | Docker           |
| Project A        |          | Project B        |
+------------------+          +------------------+
```

Only the reverse proxy is exposed to the Internet.

Application VMs are reachable only through the internal network.

---

## Features

* Automated VM deployment with Ansible
* Project-based configuration
* Docker application deployment
* Automatic Let's Encrypt certificates
* Reverse proxy management with Caddy
* Production and staging environments
* Health checks
* Reusable VM templates
* Infrastructure fully stored in Git

---

## Repository Structure

```text
devops_staging_prod_infra/

├── inventory/
│   ├── production/
│   └── staging/
│
├── playbooks/
│   ├── site-production.yml
│   ├── site-staging.yml
│   ├── add-vm.yml
│   ├── remove-vm.yml
│   └── bootstrap-vm.yml
│
├── vars/
│   └── projects/
│       ├── lavallee-production.yml
│       ├── facturier-production.yml
│       ├── webcam-production.yml
│       ├── lavallee-staging.yml
│       ├── facturier-staging.yml
│       └── webcam-staging.yml
│
├── roles/
│   ├── project_registry/
│   ├── project_context/
│   ├── base_linux/
│   ├── docker_host/
│   ├── app_image_deploy/
│   ├── caddy_proxy/
│   └── healthcheck/
│
└── README.md
```

---

## Project Definition

Every application is described through a dedicated file in:

```text
vars/projects/
```

Example:

```yaml
project_name: lavallee
project_env: production
project_vm: vm-lavallee-prod

project_domain: lavallee.tech

project_image: ghcr.io/example/application:latest

project_host_bind_port: 18080
project_container_port: 80

project_expose_via_proxy: true
```

The project definition becomes the single source of truth.

---

## Deployment Workflow

### 1. Build project registry

The project registry is generated from all files stored in:

```text
vars/projects/
```

### 2. Configure VMs

Each VM receives:

* Base Linux configuration
* Docker installation
* Application deployment

### 3. Configure reverse proxy

Caddy automatically generates:

* Virtual hosts
* Reverse proxy rules
* Let's Encrypt certificates

### 4. Verify deployment

Health checks verify that applications are reachable.

---

## Production Deployment

Deploy the complete production environment:

```bash
ansible-playbook \
  -i inventory/production/hosts.ini \
  playbooks/site-production.yml \
  --ask-vault-password
```

---

## Staging Deployment

Deploy the staging environment:

```bash
ansible-playbook \
  -i inventory/staging/hosts.ini \
  playbooks/site-staging.yml \
  --ask-vault-password
```

---

## Connectivity Test

Verify SSH connectivity:

```bash
ansible \
  -i inventory/production/hosts.ini \
  production \
  -m ping \
  --ask-vault-password
```

---

## Reverse Proxy

Caddy provides:

* HTTPS termination
* Automatic certificate management
* Domain routing
* Access logging

Typical domains:

```text
lavallee.tech
facturier.lavallee.tech
webcam.lavallee.tech
```

---

## Design Principles

This repository intentionally focuses on:

* simplicity
* reproducibility
* project isolation
* infrastructure documentation
* easy maintenance

Application monitoring is intentionally managed outside of this repository in dedicated monitoring projects.

---

## License

GNU GPL v3
