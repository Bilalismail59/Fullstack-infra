provider "google" {
  project     = var.gcp_project_id
  region      = var.gcp_region
  credentials = file(var.gcp_credentials_file)
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/compute"
  ]
}

# Activation des APIs requises
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# Réseau VPC
resource "google_compute_network" "vpc_network" {
  name                    = "${var.gcp_project_id}-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.required_apis]
}

# Sous-réseaux Production
resource "google_compute_subnetwork" "prod_subnets" {
  for_each = {
    frontend = "10.0.1.0/24"
    backend  = "10.0.2.0/24"
    database = "10.0.3.0/24"
  }

  name          = "${var.gcp_project_id}-${each.key}-subnet"
  ip_cidr_range = each.value
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
}

# Instances Compute
resource "google_compute_instance" "prod_instances" {
  for_each = {
    frontend = {
      subnet        = google_compute_subnetwork.prod_subnets["frontend"].id
      access_config = [{}] # Avec IP publique
    }
    backend = {
      subnet        = google_compute_subnetwork.prod_subnets["backend"].id
      access_config = [] # Sans IP publique
    }
    database = {
      subnet        = google_compute_subnetwork.prod_subnets["database"].id
      access_config = [] # Sans IP publique
    }
  }

  name         = "${var.gcp_project_id}-prod-instance-${each.key}"
  machine_type = "e2-small"
  zone         = "${var.gcp_region}-b"
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.id
    subnetwork = each.value.subnet
    
    dynamic "access_config" {
      for_each = each.value.access_config
      content {}
    }
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOF

  tags = ["${each.key}"]
}

# Règles de firewall
resource "google_compute_firewall" "firewall_rules" {
  for_each = {
    ssh = {
      ports    = ["22"]
      sources  = [var.admin_ip]
    }
    http = {
      ports    = ["80"]
      sources  = ["0.0.0.0/0"]
    }
    https = {
      ports    = ["443"]
      sources  = ["0.0.0.0/0"]
    }
    internal = {
      ports    = ["80", "443", "3306"]
      sources  = ["10.0.0.0/8"]
    }
  }

  name    = "${var.gcp_project_id}-allow-${each.key}"
  network = google_compute_network.vpc_network.id
  
  allow {
    protocol = "tcp"
    ports    = each.value.ports
  }

  source_ranges = each.value.sources
  target_tags   = each.key == "ssh" ? ["frontend"] : null
}

# Cluster GKE
resource "google_container_cluster" "primary" {
  name                = "${var.gcp_project_id}-gke-cluster"
  location            = var.gcp_region
  initial_node_count  = 1
  deletion_protection = false # Désactivé pour faciliter les tests

  node_config {
    machine_type = "e2-small"
    disk_size_gb = 20
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring"
    ]
  }

  depends_on = [
    google_project_service.required_apis
  ]
}

# NAT Gateway
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

# Load Balancer
resource "google_compute_global_address" "lb_ip" {
  name = "${var.gcp_project_id}-lb-ip"
}

resource "google_compute_health_check" "http_health_check" {
  name = "${var.gcp_project_id}-http-health-check"

  http_health_check {
    port = 80
  }
}

resource "google_compute_instance_group" "frontend_group" {
  name    = "${var.gcp_project_id}-frontend-group"
  zone    = "${var.gcp_region}-b"
  instances = [google_compute_instance.prod_instances["frontend"].id]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_backend_service" "frontend_backend" {
  name        = "${var.gcp_project_id}-frontend-backend"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group.frontend_group.id
  }

  health_checks = [google_compute_health_check.http_health_check.id]
}

resource "google_compute_url_map" "url_map" {
  name            = "${var.gcp_project_id}-url-map"
  default_service = google_compute_backend_service.frontend_backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${var.gcp_project_id}-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name       = "${var.gcp_project_id}-http-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.lb_ip.address
}

# Outputs
output "load_balancer_ip" {
  value       = google_compute_global_address.lb_ip.address
  description = "IP publique du Load Balancer"
}

output "frontend_external_ip" {
  value       = google_compute_instance.prod_instances["frontend"].network_interface[0].access_config[0].nat_ip
  description = "IP publique de l'instance frontend"
}

output "internal_ips" {
  value = {
    for k, instance in google_compute_instance.prod_instances :
    k => instance.network_interface[0].network_ip
  }
  description = "IPs internes de toutes les instances"
}