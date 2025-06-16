#!/bin/bash

PROJECT="primordial-port-462408-q7"
REGION="europe-west9"
ZONE="europe-west9-b"

# Subnetworks
terraform import google_compute_subnetwork.frontend_subnet projects/$PROJECT/regions/$REGION/subnetworks/${PROJECT}-frontend-subnet
terraform import google_compute_subnetwork.backend_subnet projects/$PROJECT/regions/$REGION/subnetworks/${PROJECT}-backend-subnet
terraform import google_compute_subnetwork.database_subnet projects/$PROJECT/regions/$REGION/subnetworks/${PROJECT}-database-subnet

terraform import google_compute_subnetwork.frontend_subnet_preprod projects/$PROJECT/regions/$REGION/subnetworks/${PROJECT}-frontend-subnet-preprod
terraform import google_compute_subnetwork.backend_subnet_preprod projects/$PROJECT/regions/$REGION/subnetworks/${PROJECT}-backend-subnet-preprod
terraform import google_compute_subnetwork.database_subnet_preprod projects/$PROJECT/regions/$REGION/subnetworks/${PROJECT}-database-subnet-preprod

# Instances
terraform import google_compute_instance.frontend_instance projects/$PROJECT/zones/$ZONE/instances/${PROJECT}-frontend-instance
terraform import google_compute_instance.backend_instance projects/$PROJECT/zones/$ZONE/instances/${PROJECT}-backend-instance
terraform import google_compute_instance.database_instance projects/$PROJECT/zones/$ZONE/instances/${PROJECT}-database-instance

terraform import google_compute_instance.frontend_instance_preprod projects/$PROJECT/zones/$ZONE/instances/${PROJECT}-frontend-instance-preprod
terraform import google_compute_instance.backend_instance_preprod projects/$PROJECT/zones/$ZONE/instances/${PROJECT}-backend-instance-preprod
terraform import google_compute_instance.database_instance_preprod projects/$PROJECT/zones/$ZONE/instances/${PROJECT}-database-instance-preprod

# Firewall rules
terraform import google_compute_firewall.allow_ssh $PROJECT/${PROJECT}-allow-ssh
terraform import google_compute_firewall.allow_http $PROJECT/${PROJECT}-allow-http
terraform import google_compute_firewall.allow_https $PROJECT/${PROJECT}-allow-https
terraform import google_compute_firewall.allow_internal $PROJECT/${PROJECT}-allow-internal

# NAT router
terraform import google_compute_router.nat_router projects/$PROJECT/regions/$REGION/routers/${PROJECT}-nat-router
terraform import google_compute_router_nat.nat_gateway $PROJECT/$REGION/${PROJECT}-nat-gateway

# Load balancer resources
terraform import google_compute_global_address.lb_ip ${PROJECT}-lb-ip
terraform import google_compute_health_check.http_health_check ${PROJECT}-http-health-check
terraform import google_compute_instance_group.frontend_group_prod projects/$PROJECT/zones/$ZONE/instanceGroups/${PROJECT}-frontend-group-prod
terraform import google_compute_instance_group.frontend_group_preprod projects/$PROJECT/zones/$ZONE/instanceGroups/${PROJECT}-frontend-group-preprod
terraform import google_compute_backend_service.frontend_backend_prod ${PROJECT}-frontend-backend-prod
terraform import google_compute_backend_service.frontend_backend_preprod ${PROJECT}-frontend-backend-preprod
terraform import google_compute_url_map.url_map ${PROJECT}-url-map
terraform import google_compute_target_http_proxy.http_proxy ${PROJECT}-http-proxy
terraform import google_compute_global_forwarding_rule.http_forwarding_rule ${PROJECT}-http-forwarding-rule
