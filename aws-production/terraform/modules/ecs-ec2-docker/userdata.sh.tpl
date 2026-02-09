#!/bin/bash
# ECS EC2 Docker Instance — Userdata
# Configures the ECS agent to join the cluster.
# The ECS-optimized AMI already has Docker and the ECS agent installed.

cat >> /etc/ecs/ecs.config <<'EOSEOF'
ECS_CLUSTER=${cluster_name}
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_ENI=true
ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=1h
ECS_IMAGE_CLEANUP_INTERVAL=30m
ECS_IMAGE_MINIMUM_CLEANUP_AGE=1h
ECS_CONTAINER_STOP_TIMEOUT=30s
EOSEOF
