output "load_balancer_ip" {
  value = vkcs_lb_loadbalancer.main.vip_address
}

output "web_servers_ips" {
  value = vkcs_compute_instance.web[*].access_ip_v4
}
