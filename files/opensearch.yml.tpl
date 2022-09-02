cluster.name: ${opensearch.cluster_name}
node.name: ${node_name}
%{ if opensearch.manager ~}
node.roles:
  - cluster_manager
%{ else ~}
node.roles:
  - data
  - ingest
%{ endif ~}
network.host: ${node_ip}
discovery.seed_hosts:
%{ for seed_host in opensearch.seed_hosts ~}
  - ${seed_host}
%{ endfor ~}
plugins.security.ssl.http.enabled: true
%{ if opensearch.verify_domains ~}
plugins.security.ssl.transport.enforce_hostname_verification: true
plugins.security.ssl.transport.resolve_hostname: true
%{ else ~}
plugins.security.ssl.transport.enforce_hostname_verification: false
plugins.security.ssl.transport.resolve_hostname: false
%{ endif ~}
plugins.security.ssl.http.clientauth_mode: REQUIRE
plugins.security.ssl.transport.pemkey_filepath: /etc/opensearch/server-certs/server-key-pk8.pem
plugins.security.ssl.transport.pemcert_filepath: /etc/opensearch/server-certs/server.crt
plugins.security.ssl.transport.pemtrustedcas_filepath: /etc/opensearch/ca-certs/ca.crt
plugins.security.ssl.http.pemkey_filepath: /etc/opensearch/server-certs/server-key-pk8.pem
plugins.security.ssl.http.pemcert_filepath: /etc/opensearch/server-certs/server.crt
plugins.security.ssl.http.pemtrustedcas_filepath: /etc/opensearch/ca-certs/ca.crt
plugins.security.nodes_dn:
  - "CN=${opensearch.auth_dn_fields.node_common_name},O=${opensearch.auth_dn_fields.organization}"
plugins.security.authcz.admin_dn:
  - "CN=${opensearch.auth_dn_fields.admin_common_name},O=${opensearch.auth_dn_fields.organization}"
