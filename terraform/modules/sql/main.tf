resource "google_sql_database_instance" "database_instance" {
  name             = "apex-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  # this is where all user data lives, so don't let terraform delete it by accident
  deletion_protection = true

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
  }

  timeouts {
    create = "60m"
    update = "40m"
    delete = "40m"
  }
  depends_on = [
    var.networking_connection
  ]
}

resource "random_password" "password" {
  length  = 24
  special = false
}
resource "google_sql_database" "database" {
  name     = "apex-db"
  instance = google_sql_database_instance.database_instance.name
}

resource "google_sql_user" "db_user" {
  name     = "apex-db-user"
  instance = google_sql_database_instance.database_instance.name
  password = random_password.password.result

  # Ensures destroy order drops the database (and everything it owns) before
  # dropping this user — otherwise Postgres refuses to drop a role that still
  # owns objects (tables/sequences created by migrations running as this user).
  depends_on = [google_sql_database.database]
}
