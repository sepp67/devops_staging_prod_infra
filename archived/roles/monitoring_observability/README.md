# monitoring_observability

Installe la stack centrale de monitoring sur `vm-monitoring` :

- Prometheus
- Grafana
- Loki
- Blackbox Exporter

## Périmètre

Ce rôle ne gère pas :

- node_exporter
- promtail
- prometheus_target
- blackbox_target

Ces éléments restent gérés par l'infra staging/production.

## Déploiement

Playbook dédié :

```yaml
- name: Deploy central monitoring stack
  hosts: monitoring
  become: true
  gather_facts: true
  roles:
    - role: base_linux
    - role: docker_host
    - role: monitoring_observability