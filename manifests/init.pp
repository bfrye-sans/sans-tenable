class tenable (
  String $agent_version = 'latest',
  Integer $agent_port = 8834,
  Optional[String] $agent_key = undef,
  Boolean $agent_service_enable = true,
  String $agent_service_ensure = 'running',
  Optional[String] $agent_proxy_host = undef,
  Optional[Integer] $agent_proxy_port = undef,
  Optional[String] $agent_host = undef,
  Boolean $agent_cloud = true,
  Optional[String] $agent_group = undef,
  String $security_center_version = 'latest',
  Boolean $security_center_service_enable = true,
  String $security_center_service_ensure = 'running',
  String $scanner_version = 'latest',
  Boolean $scanner_service_enable = true,
  String $scanner_service_ensure = 'running',
) {
  class { 'tenable::agent':
    version => $agent_version,
    key => $agent_key,
    group => $agent_group,
    service_ensure => $agent_service_ensure,
    service_enable => $agent_service_enable,
    port => $agent_port,
    proxy_host => $agent_proxy_host,
    proxy_port => $agent_proxy_port,
    host => $agent_host,
    cloud => $agent_cloud,
  }

  class { 'tenable::security_center':
    version => $security_center_version,
    service_enable => $security_center_service_enable,
    service_ensure => $security_center_service_ensure,
  }

  class { 'tenable::scanner':
    version => $scanner_version,
    service_enable => $scanner_service_enable,
    service_ensure => $scanner_service_ensure,
  }
}
