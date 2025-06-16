
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
    access_config {}
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
    access_config {}
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

output "backend_external_ip" {
  value = google_compute_instance.backend_instance.network_interface[0].access_config[0].nat_ip
}

output "database_external_ip" {
  value = google_compute_instance.database_instance.network_interface[0].access_config[0].nat_ip
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


