
variable "gcp_project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to deploy resources in."
  type        = string
  default     = "europe-west9"
}

variable "gcp_credentials_file" {
  description = "Path to the GCP service account key file."
  type        = string
}


