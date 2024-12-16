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
#
#     manage_agent_updates => true,
#   }
include tenable::params

class tenable::agent (
  String $tenable_agent_version = $tenable::agent_version,
  Integer $tenable_agent_port = $tenable::agent_port,
  Optional[String] $tenable_agent_key = $tenable::agent_key,
  Boolean $tenable_agent_service_enable = $tenable::agent_service_enable,
  String $tenable_agent_service_ensure = $tenable::agent_service_ensure,
  Optional[String] $tenable_agent_proxy_host = $tenable::agent_proxy_host,
  Optional[Integer] $tenable_agent_proxy_port = $tenable::agent_proxy_port,
  Optional[String] $tenable_agent_host = $tenable::agent_host,
  Boolean $tenable_agent_cloud = $tenable::agent_cloud,
  Optional[String] $tenable_agent_group = $tenable::agent_group,
) {
  # Grab the current version of the Nessus agent.
  $current_version = inline_template('<%= `/opt/nessus/sbin/nessuscli -v | sed -n \'s/.*Nessus \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p\'`.strip %>')
  # fail if group is not set
  if $group == undef {
    fail('Tenable group parameter was not found.')
  }
  # fail if no key is set
  if $key == undef {
    fail('Tenable key is required to register agents.')
  }
  if $cloud == false and $host == undef {
    fail('If Tenable cloud is not used then host parameter must be set.')
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
      if versioncmp($newest_version, $version) > 0 {
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
