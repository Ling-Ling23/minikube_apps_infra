# minikube_apps_infra
export PROJECT_DIR=/app/src
export PROJECT_GIT_BRANCH=main
export PROJECT_GIT_URL=git@github.com:Ling-Ling23/minikube_apps_infra_app_one.git


🔍 OpenEBS Overview
OpenEBS is a Cloud Native Storage solution that provides persistent volumes for Kubernetes:

What OpenEBS Brings:
Dynamic Persistent Volumes - No need to pre-provision storage
Storage Classes - Different performance tiers (SSD, HDD, NVMe)
Data Protection - Snapshots, backups, replication
Storage Engines - Multiple options (Mayastor, cStor, Jiva, LocalPV)
Perfect for Your Current Setup:
Loki Storage - Replace ephemeral storage with persistent volumes
Database Workloads - If you add PostgreSQL, MongoDB, etc.
Development Consistency - Same storage behavior across environments
🔍 FluentOperator Overview
FluentOperator is a modern logging solution using Fluent Bit:

What FluentOperator Brings:
High Performance - Much lighter than Promtail (written in C)
Built-in Operators - Kubernetes-native configuration
Multiple Outputs - Send to Loki, Elasticsearch, S3, etc.
Advanced Processing - Filtering, parsing, enrichment
vs. Your Current Loki + Promtail:
Better Performance - Lower CPU/memory usage
More Flexible - Advanced log processing capabilities
Cloud Ready - Easy to send logs to multiple destinations