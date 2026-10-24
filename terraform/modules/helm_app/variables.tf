variable "namespace" {
  type    = string
  default = "apex-app"
}
variable "db_host" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_port" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "dockerhub_user" { type = string }
variable "dockerhub_pass" {
  type      = string
  sensitive = true
}

variable "jwt_access_secret" {
  type      = string
  sensitive = true
}
variable "jwt_refresh_secret" {
  type      = string
  sensitive = true
}
variable "salt" {
  type      = string
  sensitive = true
}

variable "jwt_access_expires_in" { type = string }
variable "jwt_refresh_expires_in" { type = string }
variable "cors_origin" { type = string }

variable "ingress_ip" { type = string }
