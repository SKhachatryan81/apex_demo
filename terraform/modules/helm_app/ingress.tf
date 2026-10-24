resource "helm_release" "apex_app_ingress" {
  name       = "apex-app-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.15.1"
  namespace  = "apex-app"
  depends_on = [kubernetes_namespace.apex-app]
  set {
    name  = "controller.nodeSelector.workload"
    value = "app"
  }
  set {
    name  = "controller.service.loadBalancerIP"
    value = var.ingress_ip
  }
}

