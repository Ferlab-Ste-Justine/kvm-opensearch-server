locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_interfaces = length(var.macvtap_interfaces) == 0 ? [{
    network_id = var.libvirt_network.network_id
    macvtap = null
    addresses = [var.libvirt_network.ip]
    mac = var.libvirt_network.mac != "" ? var.libvirt_network.mac : null
    hostname = var.name
  }] : [for macvtap_interface in var.macvtap_interfaces: {
    network_id = null
    macvtap = macvtap_interface.interface
    addresses = null
    mac = macvtap_interface.mac
    hostname = null
  }]
  ips = length(var.macvtap_interfaces) == 0 ? [
    var.libvirt_network.ip
  ] : [
    for macvtap_interface in var.macvtap_interfaces: macvtap_interface.ip
  ]
}

module "network_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//network?ref=main"
  network_interfaces = var.macvtap_interfaces
}

module "opensearch_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//opensearch?ref=main"
  install_dependencies = var.install_dependencies
  opensearch_host = {
    bind_ip            = local.ips.0
    bootstrap_security = var.opensearch.bootstrap_security
    host_name          = var.name
    initial_cluster    = var.opensearch.initial_cluster
    manager            = var.opensearch.manager
  }
  opensearch_cluster = {
    auth_dn_fields      = var.opensearch.auth_dn_fields
    basic_auth_enabled  = var.opensearch.basic_auth_enabled
    cluster_name        = var.opensearch.cluster_name
    seed_hosts          = var.opensearch.seed_hosts
    verify_domains      = var.opensearch.verify_domains
  }
  tls = {
    server_cert = tls_locally_signed_cert.server.cert_pem
    server_key  = tls_private_key.server.private_key_pem
    ca_cert     = var.opensearch.ca.certificate
    admin_cert  = var.opensearch.bootstrap_security ? tls_locally_signed_cert.admin.0.cert_pem : ""
    admin_key   = var.opensearch.bootstrap_security ? tls_private_key.admin.0.private_key_pem : ""
  }
}

module "prometheus_node_exporter_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//prometheus-node-exporter?ref=main"
  install_dependencies = var.install_dependencies
}

module "chrony_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//chrony?ref=main"
  install_dependencies = var.install_dependencies
  chrony = {
    servers  = var.chrony.servers
    pools    = var.chrony.pools
    makestep = var.chrony.makestep
  }
}

module "fluentd_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//fluentd?ref=main"
  install_dependencies = var.install_dependencies
  fluentd = {
    docker_services = []
    systemd_services = [
      {
        tag     = var.fluentd.opensearch_tag
        service = "opensearch"
      },
      {
        tag     = var.fluentd.node_exporter_tag
        service = "node-exporter"
      }
    ]
    forward = var.fluentd.forward,
    buffer = var.fluentd.buffer
  }
}

locals {
  cloudinit_templates = concat([
      {
        filename     = "base.cfg"
        content_type = "text/cloud-config"
        content = templatefile(
          "${path.module}/files/user_data.yaml.tpl", 
          {
            hostname = var.name
            ssh_admin_public_key = var.ssh_admin_public_key
            ssh_admin_user = var.ssh_admin_user
            admin_user_password = var.admin_user_password
          }
        )
      },
      {
        filename     = "opensearch.cfg"
        content_type = "text/cloud-config"
        content      = module.opensearch_configs.configuration
      },
      {
        filename     = "node_exporter.cfg"
        content_type = "text/cloud-config"
        content      = module.prometheus_node_exporter_configs.configuration
      }
    ],
    var.chrony.enabled ? [{
      filename     = "chrony.cfg"
      content_type = "text/cloud-config"
      content      = module.chrony_configs.configuration
    }] : [],
    var.fluentd.enabled ? [{
      filename     = "fluentd.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentd_configs.configuration
    }] : [],
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  dynamic "part" {
    for_each = local.cloudinit_templates
    content {
      filename     = part.value["filename"]
      content_type = part.value["content_type"]
      content      = part.value["content"]
    }
  }
}

resource "libvirt_cloudinit_disk" "opensearch" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = length(var.macvtap_interfaces) > 0 ? module.network_configs.configuration : null
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "opensearch" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  disk {
    volume_id = var.volume_id
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.opensearch.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}