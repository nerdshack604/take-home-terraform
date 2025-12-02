################################################################################
# Redis for ShinyProxy Operator v2.x
# Redis Sentinel is MANDATORY starting from ShinyProxy Operator v2.0.0
################################################################################

################################################################################
# Redis Service Account and RBAC
################################################################################

resource "kubernetes_service_account" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

resource "kubernetes_role" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis-ha"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    verbs      = ["get"]
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

resource "kubernetes_role_binding" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis-ha"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.redis.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.redis.metadata[0].name
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# Redis Secret
################################################################################

resource "random_password" "redis" {
  length  = 32
  special = true
}

resource "kubernetes_secret" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  data = {
    auth = random_password.redis.result
  }

  type = "Opaque"

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# Redis Services
################################################################################

# Headless service for StatefulSet
resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  spec {
    type       = "ClusterIP"
    cluster_ip = "None"

    selector = {
      app = "redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = "redis"
      protocol    = "TCP"
    }

    port {
      name        = "sentinel"
      port        = 26379
      target_port = "sentinel"
      protocol    = "TCP"
    }
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

# Client service
resource "kubernetes_service" "redis_client" {
  metadata {
    name      = "redis-client"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = "redis"
      protocol    = "TCP"
    }

    port {
      name        = "sentinel"
      port        = 26379
      target_port = "sentinel"
      protocol    = "TCP"
    }
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# Redis ConfigMap
################################################################################

resource "kubernetes_config_map" "redis_config" {
  metadata {
    name      = "redis-config"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  data = {
    "redis.conf" = <<-EOT
      dir /data
      port 6379
      bind 0.0.0.0
      protected-mode no
      requirepass ${random_password.redis.result}
      masterauth ${random_password.redis.result}
      replica-announce-ip $POD_IP
      replica-announce-port 6379
      maxmemory 256mb
      maxmemory-policy allkeys-lru
      save ""
      appendonly yes
      appendfilename "appendonly.aof"
      auto-aof-rewrite-percentage 100
      auto-aof-rewrite-min-size 64mb
    EOT

    "sentinel.conf" = <<-EOT
      dir /data
      port 26379
      bind 0.0.0.0
      sentinel monitor shinyproxy 127.0.0.1 6379 2
      sentinel auth-pass shinyproxy ${random_password.redis.result}
      sentinel down-after-milliseconds shinyproxy 5000
      sentinel parallel-syncs shinyproxy 1
      sentinel failover-timeout shinyproxy 10000
      sentinel announce-ip $ANNOUNCE_IP
      sentinel announce-port 26379
    EOT
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# Redis StatefulSet
################################################################################

resource "kubernetes_stateful_set" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  spec {
    replicas     = 3
    service_name = kubernetes_service.redis.metadata[0].name

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.redis.metadata[0].name

        init_container {
          name  = "config"
          image = "public.ecr.aws/docker/library/redis:8.2.2-alpine"

          command = ["sh", "-c"]
          args = [
            <<-EOT
              set -ex
              mkdir -p /data/conf
              cp /tmp/redis/redis.conf /data/conf/redis.conf
              cp /tmp/redis/sentinel.conf /data/conf/sentinel.conf
              sed -i "s/\$POD_IP/$POD_IP/g" /data/conf/redis.conf
              sed -i "s/\$ANNOUNCE_IP/$POD_IP/g" /data/conf/sentinel.conf
            EOT
          ]

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/tmp/redis"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        container {
          name  = "redis"
          image = "public.ecr.aws/docker/library/redis:8.2.2-alpine"

          command = ["redis-server"]
          args    = ["/data/conf/redis.conf"]

          port {
            name           = "redis"
            container_port = 6379
            protocol       = "TCP"
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.redis.metadata[0].name
                key  = "auth"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "-a", "$(REDIS_PASSWORD)", "ping"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "-a", "$(REDIS_PASSWORD)", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 1
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            read_only_root_filesystem  = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        container {
          name  = "sentinel"
          image = "public.ecr.aws/docker/library/redis:8.2.2-alpine"

          command = ["redis-sentinel"]
          args    = ["/data/conf/sentinel.conf"]

          port {
            name           = "sentinel"
            container_port = 26379
            protocol       = "TCP"
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.redis.metadata[0].name
                key  = "auth"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "-p", "26379", "ping"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "-p", "26379", "ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 1
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            read_only_root_filesystem  = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.redis_config.metadata[0].name
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
        labels = {
          app = "redis"
        }
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp2"

        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }

    pod_management_policy  = "Parallel"
    revision_history_limit = 3
  }

  depends_on = [
    null_resource.wait_for_cluster,
    kubernetes_config_map.redis_config,
    kubernetes_secret.redis
  ]
}
