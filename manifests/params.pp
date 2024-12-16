class tenable::params {
  # Shared Params
  $service_ensure = 'running'
  $service_enable = true

  # Agent Params
  $agent_version = 'latest'
  $agent_port = 8834
  $agent_key = 'your-activation-key'
  $proxy_host = undef
  $proxy_port = undef
  $host = undef
  $cloud = true
  }

  # Scanner Params
  $scanner_version = 'latest'

  # Security Center Params
  $security_center_version = 'latest'
}
