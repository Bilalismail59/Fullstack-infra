provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  credentials = file(var.gcp_credentials_file)
}

resource "google_compute_network" "vpc_network" {
  name                    = "${var.gcp_project_id}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "frontend_subnet" {
  name          = "${var.gcp_project_id}-frontend-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "backend_subnet" {
  name          = "${var.gcp_project_id}-backend-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "database_subnet" {
  name          = "${var.gcp_project_id}-database-subnet"
  ip_cidr_range = "10.0.3.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_instance" "frontend_instance" {
  name         = "${var.gcp_project_id}-frontend-instance"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.frontend_subnet.id
    access_config {}
  }
  metadata_startup_script = ""
}

resource "google_compute_instance" "backend_instance" {
  name         = "${var.gcp_project_id}-backend-instance"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.backend_subnet.id
  }
  metadata_startup_script = ""
}

resource "google_compute_instance" "database_instance" {
  name         = "${var.gcp_project_id}-database-instance"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.database_subnet.id
  }
  metadata_startup_script = ""
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.gcp_project_id}-allow-ssh"
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_http" {
  name    = "${var.gcp_project_id}-allow-http"
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_https" {
  name    = "${var.gcp_project_id}-allow-https"
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${var.gcp_project_id}-allow-internal"
  network = google_compute_network.vpc_network.id
  allow {
    protocol = "tcp"
    ports    = ["80", "443", "3306"]
  }
  source_ranges = ["10.0.0.0/8"]
}

output "frontend_external_ip" {
  value = google_compute_instance.frontend_instance.network_interface[0].access_config[0].nat_ip
}

resource "google_container_cluster" "primary" {
  name     = "${var.gcp_project_id}-gke-cluster"
  location = var.gcp_region
  initial_node_count = 1

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring"
    ]
  }
}

resource "google_compute_subnetwork" "frontend_subnet_preprod" {
  name          = "${var.gcp_project_id}-frontend-subnet-preprod"
  ip_cidr_range = "10.0.4.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "backend_subnet_preprod" {
  name          = "${var.gcp_project_id}-backend-subnet-preprod"
  ip_cidr_range = "10.0.5.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "database_subnet_preprod" {
  name          = "${var.gcp_project_id}-database-subnet-preprod"
  ip_cidr_range = "10.0.6.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_instance" "frontend_instance_preprod" {
  name         = "${var.gcp_project_id}-frontend-instance-preprod"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.frontend_subnet_preprod.id
  }
  metadata_startup_script = ""
}

resource "google_compute_instance" "backend_instance_preprod" {
  name         = "${var.gcp_project_id}-backend-instance-preprod"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.backend_subnet_preprod.id
  }
  metadata_startup_script = ""
}

resource "google_compute_instance" "database_instance_preprod" {
  name         = "${var.gcp_project_id}-database-instance-preprod"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-b"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = google_compute_subnetwork.database_subnet_preprod.id
  }
  metadata_startup_script = ""
}

output "frontend_internal_ip" {
  value = google_compute_instance.frontend_instance.network_interface[0].network_ip
}

output "backend_internal_ip" {
  value = google_compute_instance.backend_instance.network_interface[0].network_ip
}

output "database_internal_ip" {
  value = google_compute_instance.database_instance.network_interface[0].network_ip
}

output "frontend_internal_ip_preprod" {
  value = google_compute_instance.frontend_instance_preprod.network_interface[0].network_ip
}

output "backend_internal_ip_preprod" {
  value = google_compute_instance.backend_instance_preprod.network_interface[0].network_ip
}

output "database_internal_ip_preprod" {
  value = google_compute_instance.database_instance_preprod.network_interface[0].network_ip
}



# NAT Gateway pour permettre l'accès Internet aux instances sans IP publique
resource "google_compute_router" "nat_router" {
  name    = "${var.gcp_project_id}-nat-router"
  region  = var.gcp_region
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${var.gcp_project_id}-nat-gateway"
  router                             = google_compute_router.nat_router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Load Balancer pour l'accès externe aux environnements
resource "google_compute_global_address" "lb_ip" {
  name = "${var.gcp_project_id}-lb-ip"
}

resource "google_compute_health_check" "http_health_check" {
  name = "${var.gcp_project_id}-http-health-check"

  http_health_check {
    port = 80
  }
}

resource "google_compute_instance_group" "frontend_group_prod" {
  name = "${var.gcp_project_id}-frontend-group-prod"
  zone = "${var.gcp_region}-b"

  instances = [
    google_compute_instance.frontend_instance.id
  ]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_instance_group" "frontend_group_preprod" {
  name = "${var.gcp_project_id}-frontend-group-preprod"
  zone = "${var.gcp_region}-b"

  instances = [
    google_compute_instance.frontend_instance_preprod.id
  ]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_backend_service" "frontend_backend_prod" {
  name        = "${var.gcp_project_id}-frontend-backend-prod"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group.frontend_group_prod.id
  }

  health_checks = [google_compute_health_check.http_health_check.id]
}

resource "google_compute_backend_service" "frontend_backend_preprod" {
  name        = "${var.gcp_project_id}-frontend-backend-preprod"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group.frontend_group_preprod.id
  }

  health_checks = [google_compute_health_check.http_health_check.id]
}

resource "google_compute_url_map" "url_map" {
  name            = "${var.gcp_project_id}-url-map"
  default_service = google_compute_backend_service.frontend_backend_prod.id

  host_rule {
    hosts        = ["preprod.${var.domain_name}"]
    path_matcher = "preprod"
  }

  path_matcher {
    name            = "preprod"
    default_service = google_compute_backend_service.frontend_backend_preprod.id
  }
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name   = "${var.gcp_project_id}-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name       = "${var.gcp_project_id}-http-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.lb_ip.address
}

output "load_balancer_ip" {
  value = google_compute_global_address.lb_ip.address
}

output "frontend_external_ip_preprod" {
  value = "Accessible via Load Balancer IP: ${google_compute_global_address.lb_ip.address}"
}

