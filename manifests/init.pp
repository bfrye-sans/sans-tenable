class tenable (
) inherits tenable::params {
  class { 'tenable::agent':
    agent_version        => 'latest',
    agent_port           => '8834',
    agent_key            => undef,
    agent_service_enable => true,
    agent_service_ensure => 'running',
    agent_proxy_host     => undef,
    agent_proxy_port     => undef,
    agent_host           => undef,
    agent_cloud          => true,
    agent_group          => undef,
  }

  class { 'tenable::security_center':
    security_center_version => 'latest',
    security_center_service_enable => true,
    security_center_service_ensure => 'running',
  }

  class { 'tenable::scanner':
    scanner_version => 'latest',
    scanner_service_enable => true,
    scanner_service_ensure => 'running',
  }
}
