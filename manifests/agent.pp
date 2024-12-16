# Class: tenable::agent
#
# Parameters:
#   String $key
#     The activation key for the Nessus agent.
#
#   String $group
#     The group to which the Nessus agent belongs.
#
#   Boolean $manage_agent_updates
#     Whether to manage agent updates. Defaults to true.
#
#   String $service_ensure
#     The desired state of the Nessus agent service. Defaults to 'running'.
#
#   Boolean $service_enable
#     Whether to enable the Nessus agent service at boot. Defaults to true.
#
#   Integer $port
#     The port on which the Nessus agent listens. Defaults to 8834.
#
# Example:
#
#   class { 'tenable::agent':
#     service_ensure       => 'running',
#     service_enable       => true,
#     port                 => 8834,
#     key                  => 'your-activation-key',
#     group                => 'your-group',
#     manage_agent_updates => true,
#   }

class tenable::agent (
  String $key = $tenable::params::agent_key,
  String $group = $tenable::params::agent_group,
  Boolean $manage_agent_updates = $tenable::params::manage_agent_updates,
  String $service_ensure = $tenable::params::service_ensure,
  Boolean $service_enable = $tenable::params::service_enable,
  Integer $port = $tenable::params::agent_port,
  String $proxy_host = $tenable::params::proxy_host,
  Optional[Integer] $proxy_port = $tenable::params::proxy_port,
  String $host = $tenable::params::host,
  Boolean $cloud = $tenable::params::cloud,
) {
  # Grab the current version of the Nessus agent.
  $current_version = inline_template('<%= `/opt/nessus/sbin/nessuscli -v | sed -n \'s/.*Nessus \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p\'`.strip %>')
  # fail if group is not set
  if $group == undef {
    fail('Tenable group parameter was not found.')
  }
  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if versioncmp($current_version, $version) < 0 {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Grab the major release and architecture.
      $major_release = $facts['os']['release']['major']
      $arch = $facts['os']['architecture']
      # Find out the newest version of the Nessus agent.
      $newest_version = inline_template('<%= `curl -s https://www.tenable.com/downloads/api/v2/pages/nessus-agents | sed -n \'s/.*"version": *"\\([0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\)".*/\\1/p\'`.strip %>')
      # If the newest version is greater than the current version, download and install it.
      if versioncmp($newest_version_version, $version) > 0 {
        exec { 'download_nessus_agent':
          command => "rpm -i https://www.tenable.com/downloads/api/v2/pages/nessus-agents/NessusAgent-latest-el${major_release}.${arch}.rpm",
        }

        notify { "Nessus Agent version: ${newest_version} installed.": }
      }
    } else {
      fail('Unsupported OS family.')
    }
  }

  # Configure agent
  service { 'nessusagent':
    ensure  => $service_ensure,
    enable  => $service_enable,
    require => Package['NessusAgent'],
  }

  # Register agent if it's not already linked
  exec { 'register_nessus_agent':
    command => "/opt/nessus_agent/sbin/nessuscli agent link --key=${key} --groups=${group} --port=${port}" + 
        ($proxy_host ? { undef => '', default => " --proxy-host=${proxy_host}" }) +
        ($proxy_port ? { undef => '', default => " --proxy-port=${proxy_port}" }) +
        ($host ? { undef => '', default => " --host=${host}" }) +
        ($cloud ? { undef => '', default => " --cloud" }),
      unless  => "/opt/nessus_agent/sbin/nessuscli agent status | grep -q 'None'",
    require => Service['nessusagent'],
  }
}
