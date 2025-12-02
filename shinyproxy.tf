################################################################################
# ShinyProxy Namespace
################################################################################

resource "kubernetes_namespace" "shinyproxy" {
  metadata {
    name = var.shinyproxy_namespace

    labels = {
      name        = var.shinyproxy_namespace
      environment = var.environment
    }
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# ShinyProxy Service Account with IRSA
################################################################################

resource "kubernetes_service_account" "shinyproxy" {
  metadata {
    name      = "shinyproxy-sa"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.shinyproxy.arn
    }
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# ShinyProxy Operator RBAC
################################################################################

resource "kubernetes_cluster_role" "shinyproxy_operator" {
  metadata {
    name = "shinyproxy-operator-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "events"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["openanalytics.eu"]
    resources  = ["shinyproxies", "shinyproxies/status", "shinyproxies/finalizers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

resource "kubernetes_cluster_role_binding" "shinyproxy_operator" {
  metadata {
    name = "shinyproxy-operator-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.shinyproxy_operator.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.shinyproxy.metadata[0].name
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# ShinyProxy App Launcher RBAC (for launching app pods)
################################################################################

resource "kubernetes_role" "shinyproxy_app_launcher" {
  metadata {
    name      = "shinyproxy-app-launcher"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "events"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

resource "kubernetes_role_binding" "shinyproxy_app_launcher" {
  metadata {
    name      = "shinyproxy-app-launcher-binding"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.shinyproxy_app_launcher.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# ShinyProxy Operator CRD
################################################################################

resource "kubectl_manifest" "shinyproxy_crd" {
  yaml_body = <<-YAML
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: shinyproxies.openanalytics.eu
    spec:
      group: openanalytics.eu
      names:
        kind: ShinyProxy
        listKind: ShinyProxyList
        plural: shinyproxies
        singular: shinyproxy
        shortNames:
          - sp
      scope: Namespaced
      versions:
        - name: v1
          served: true
          storage: true
          schema:
            openAPIV3Schema:
              description: ShinyProxy
              type: object
              properties:
                apiVersion:
                  type: string
                kind:
                  type: string
                spec:
                  description: Specification of the ShinyProxy
                  type: object
                  x-kubernetes-preserve-unknown-fields: true
                  properties:
                    proxy:
                      type: object
                      x-kubernetes-preserve-unknown-fields: true
                    image:
                      type: string
                    imagePullPolicy:
                      type: string
                    fqdn:
                      type: string
                    replicas:
                      type: integer
                  required:
                    - proxy
                    - fqdn
                status:
                  description: ShinyProxyStatus defines the observed state of ShinyProxy
                  type: object
                  x-kubernetes-preserve-unknown-fields: true
          subresources:
            status: {}
        - name: v1alpha1
          served: true
          storage: false
          schema:
            openAPIV3Schema:
              type: object
              x-kubernetes-preserve-unknown-fields: true
          subresources:
            status: {}
  YAML

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# ShinyProxy Operator Deployment
################################################################################

resource "kubernetes_deployment" "shinyproxy_operator" {
  metadata {
    name      = "shinyproxy-operator"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "shinyproxy-operator"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "shinyproxy-operator"
      }
    }

    template {
      metadata {
        labels = {
          app = "shinyproxy-operator"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.shinyproxy.metadata[0].name

        container {
          name  = "operator"
          image = "openanalytics/shinyproxy-operator:2.3.1"

          image_pull_policy = "Always"

          env {
            name  = "SPO_MODE"
            value = "namespaced"
          }

          env {
            name  = "SPO_PROBE_TIMEOUT"
            value = "3"
          }

          env {
            name = "WATCH_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name  = "OPERATOR_NAME"
            value = "shinyproxy-operator"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.wait_for_cluster,
    kubectl_manifest.shinyproxy_crd,
    kubernetes_cluster_role_binding.shinyproxy_operator
  ]
}

################################################################################
# ShinyProxy ConfigMap
################################################################################

locals {
  shinyproxy_config = {
    proxy = {
      title             = "ShinyProxy"
      logo-url          = "https://www.openanalytics.eu/shinyproxy/logo.png"
      landing-page      = "/"
      heartbeat-rate    = 10000
      heartbeat-timeout = 60000
      port              = var.shinyproxy_port
      authentication    = var.shinyproxy_authentication.type
      container-backend = "kubernetes"

      kubernetes = {
        internal-networking = true
        namespace           = var.shinyproxy_namespace
        image-pull-policy   = var.shinyproxy_image_pull_policy
      }

      specs = [
        for app in var.shinyproxy_apps : {
          id              = app.id
          display-name    = app.display_name
          description     = app.description
          container-image = app.container_image
          container-cmd   = app.container_cmd
          container-env   = app.container_env
          port            = app.port
        }
      ]
    }

    logging = {
      file = {
        shinyproxy = "/dev/stdout"
      }
    }

    management = {
      metrics = {
        export = {
          prometheus = {
            enabled = true
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map" "shinyproxy" {
  metadata {
    name      = "shinyproxy-config"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name
  }

  data = {
    "application.yml" = yamlencode(local.shinyproxy_config)
  }

  depends_on = [
    null_resource.wait_for_cluster
  ]
}

################################################################################
# ShinyProxy Custom Resource
################################################################################

resource "kubectl_manifest" "shinyproxy" {
  yaml_body = <<-YAML
    apiVersion: openanalytics.eu/v1
    kind: ShinyProxy
    metadata:
      name: shinyproxy
      namespace: ${var.shinyproxy_namespace}
    spec:
      image: openanalytics/shinyproxy:${var.shinyproxy_version}
      imagePullPolicy: ${var.shinyproxy_image_pull_policy}
      replicas: ${var.shinyproxy_replicas}
      fqdn: shinyproxy.local

      serviceAccount: ${kubernetes_service_account.shinyproxy.metadata[0].name}

      spring:
        application:
          name: shinyproxy
        data:
          redis:
            host: redis-client.${var.shinyproxy_namespace}.svc.cluster.local
            port: 6379
            password: ${random_password.redis.result}

      proxy:
        title: ShinyProxy
        logo-url: https://www.openanalytics.eu/shinyproxy/logo.png
        landing-page: /
        port: ${var.shinyproxy_port}
        container-backend: kubernetes
        store-mode: Redis
        stop-proxies-on-shutdown: false
        authentication: ${var.shinyproxy_authentication.type}
        kubernetes:
          internal-networking: true
          namespace: ${var.shinyproxy_namespace}
          image-pull-policy: ${var.shinyproxy_image_pull_policy}
        specs:${length(var.shinyproxy_apps) > 0 ? "\n${join("\n", [for app in var.shinyproxy_apps : "          - id: ${app.id}\n            display-name: ${app.display_name}\n            description: ${app.description}\n            container-image: ${app.container_image}${length(app.container_cmd) > 0 ? "\n            container-cmd:\n${join("\n", [for cmd in app.container_cmd : "              - ${cmd}"])}" : ""}\n            port: ${app.port}"])}" : " []"}

      kubernetesPodTemplateSpecPatches: |
        - op: add
          path: /spec/securityContext
          value:
            runAsNonRoot: true
            runAsUser: 1000
            fsGroup: 1000
            seccompProfile:
              type: RuntimeDefault
        - op: add
          path: /spec/containers/0/securityContext
          value:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 1000
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
        - op: add
          path: /spec/containers/0/resources
          value:
            requests:
              memory: ${var.shinyproxy_resources.requests.memory}
              cpu: ${var.shinyproxy_resources.requests.cpu}
            limits:
              memory: ${var.shinyproxy_resources.limits.memory}
              cpu: ${var.shinyproxy_resources.limits.cpu}
  YAML

  depends_on = [
    kubernetes_deployment.shinyproxy_operator,
    kubernetes_config_map.shinyproxy,
    kubernetes_stateful_set.redis
  ]
}

################################################################################
# ShinyProxy Service
################################################################################

resource "kubernetes_service" "shinyproxy" {
  metadata {
    name      = "shinyproxy"
    namespace = kubernetes_namespace.shinyproxy.metadata[0].name

    labels = {
      app = "shinyproxy"
    }

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "shinyproxy"
    }

    port {
      name        = "http"
      port        = 80
      target_port = var.shinyproxy_port
      protocol    = "TCP"
    }
  }

  depends_on = [
    null_resource.wait_for_cluster,
    kubectl_manifest.shinyproxy
  ]
}
