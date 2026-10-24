variable "project" {
  type = string
}
variable "region" {
  type = string
}
variable "ip_cidr_range" {
  type    = string
  default = "10.0.0.0/24"
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
