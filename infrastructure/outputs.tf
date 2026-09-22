output "master_node_ip" {
  description = "Master Node IP Address"
  value       = module.hcloud_kubernetes_cluster.master_node_ip
}
