class tenable (
) inherits tenable::params {
  class { 'tenable::agent':
    agent_version        => $tenable::params::agent_version,
    agent_port           => $tenable::params::agent_port,
    agent_key            => $tenable::params::agent_key,
    service_enable       => $tenable::params::service_enable,
    service_ensure       => $tenable::params::service_ensure,
    proxy_host           => $tenable::params::proxy_host,
    proxy_port           => $tenable::params::proxy_port,
    host                 => $tenable::params::host,
    cloud                => $tenable::params::cloud,
    group                => $tenable::params::group,
  }

  class { 'tenable::security_center':
    security_center_version => $tenable::params::security_center_version,
    service_enable => $tenable::params::service_enable,
    service_ensure => $tenable::params::service_ensure,
  }

  class { 'tenable::scanner':
    scanner_version => $tenable::params::scanner_version,
    service_enable => $tenable::params::service_enable,
    service_ensure => $tenable::params::service_ensure,
  }
}
