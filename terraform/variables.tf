
variable "gcp_project_id" {
  description = "my-project-devops-449109."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to deploy resources in."
  type        = string
  default     = "europe-west9"
}

variable "gcp_credentials_file" {
  description = "~/.config/gcloud/chrome-entropy-464618-v3-6bc81d673c95.json"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"
}

variable "admin_ip" {
  description = "Adresse IP autorisée (ex: pour SSH ou HTTP)"
  type        = string
}
