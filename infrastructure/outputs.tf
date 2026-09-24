output "master_nodes_public_ips" {
  description = "Master Nodes Public IP Addresses"
  value       = module.hcloud_kubernetes_cluster.master_nodes_ips
}

output "worker_nodes_public_ips" {
  description = "Worker Nodes Public IP Addresses"
  value       = module.hcloud_kubernetes_cluster.worker_nodes_ips
}
