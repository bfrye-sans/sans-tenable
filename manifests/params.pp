
class tenable::agent::params {
  version => 'latest',
  key => undef
  group => undef
  service_ensure => 'running',
  service_enable => true,
  port => 8834,
  proxy_host => undef
  proxy_port => undef
  host => undef
  cloud => true
}

class tenable::security_center::params {
  version => 'latest'
  service_enable => true,
  service_ensure => 'running',
}

class tenable::scanner::params {
  version => 'latest'
  service_enable => true,
  service_ensure => 'running',
}
