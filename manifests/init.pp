class tenable (
) inherits tenable::params {
  class { 'tenable::agent':
    agent_version        => $tenable::params::agent_version,
    agent_port           => $tenable::params::agent_port,
    agent_key            => $tenable::params::agent_key,
    agent_source         => $tenable::params::agent_source,
    agent_package        => $tenable::params::agent_package,
    agent_service_enable => $tenable::params::agent_service_enable,
    agent_service_ensure => $tenable::params::agent_service_ensure,
    agent_proxy_host     => $tenable::params::agent_proxy_host,
    agent_proxy_port     => $tenable::params::agent_proxy_port,
    agent_host           => $tenable::params::agent_host,
    agent_cloud          => $tenable::params::agent_cloud,
    agent_group          => $tenable::params::agent_group,
  }

  class { 'tenable::security_center':
    security_center_version => $tenable::params::security_center_version,
    service_enable => $tenable::params::security_center_service_enable,
    service_ensure => $tenable::params::security_center_service_ensure,
  }

  class { 'tenable::scanner':
    scanner_version => $tenable::params::scanner_version,
    service_enable => $tenable::params::scanner_service_enable,
    service_ensure => $tenable::params::scanner_service_ensure,
  }
}
