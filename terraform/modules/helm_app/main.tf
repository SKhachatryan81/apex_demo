resource "kubernetes_namespace" "apex-app" {
  metadata {
    name = var.namespace
  }
}
resource "kubernetes_secret" "db_creds" {
  metadata {
    name      = "db-creds"
    namespace = "apex-app"
  }
  data = {
    host     = var.db_host
    name     = var.db_name
    user     = var.db_user
    password = var.db_password
    port     = var.db_port
  }
  depends_on = [kubernetes_namespace.apex-app]
}
resource "kubernetes_secret" "dockerhub_creds" {
  type = "kubernetes.io/dockerconfigjson"
  metadata {
    name      = "dockerhub-creds"
    namespace = "apex-app"
  }
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = var.dockerhub_user
          password = var.dockerhub_pass
          auth     = base64encode("${var.dockerhub_user}:${var.dockerhub_pass}")
        }
      }
    })
  }
  depends_on = [kubernetes_namespace.apex-app]
}

resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "app-secrets"
    namespace = "apex-app"
  }
  data = {
    jwt_access_secret  = var.jwt_access_secret
    jwt_refresh_secret = var.jwt_refresh_secret
    salt               = var.salt

  }
  depends_on = [kubernetes_namespace.apex-app]
}

resource "kubernetes_config_map" "app_configmap" {
  metadata {
    name      = "app-configmap"
    namespace = "apex-app"
  }
  data = {
    CORS_ORIGIN            = var.cors_origin
    JWT_ACCESS_EXPIRES_IN  = var.jwt_access_expires_in
    JWT_REFRESH_EXPIRES_IN = var.jwt_refresh_expires_in
  }
  depends_on = [kubernetes_namespace.apex-app]
}
