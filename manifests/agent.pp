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
#   }

class tenable::agent (
  Optional[String] $group = undef,
  Optional[String] $key = undef,
  String $service_ensure = 'running',
  Boolean $service_enable = true,
  Integer $port = 8834,
  Optional[Variant[String, Undef]] $proxy_host = undef,
  Optional[Variant[Integer, Undef]] $proxy_port = undef,
  Optional[String] $host = undef,
  Optional[Boolean] $cloud = false,
  String $version,
  $major_release = $facts['os']['release']['major'],
  $arch = $facts['os']['architecture'],
  Enum['low', 'normal', 'high'] $process_priority = 'normal',
) {
  $file_path       = '/opt/puppetlabs/facter/facts.d/nessus_version.txt'
  $priority_path   = '/opt/puppetlabs/facter/facts.d/nessus_process_priority.txt'

  # Ensure the facts.d directory exists
  file { '/opt/puppetlabs/facter/facts.d':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  exec { 'get_nessus_agent_version':
    command   => '/bin/bash -c "if command -v /opt/nessus_agent/sbin/nessuscli > /dev/null 2>&1; then /opt/nessus_agent/sbin/nessuscli -v | sed -n \"s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_version=\\1/p\" > /opt/puppetlabs/facter/facts.d/nessus_version.txt; else echo \"nessus_version=0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_version.txt; fi"',
    unless    => '/usr/bin/test -f /opt/puppetlabs/facter/facts.d/nessus_version.txt',
    path      => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    logoutput => true,
    require   => File['/opt/puppetlabs/facter/facts.d'],
  }

  # Ensure the fact file has proper permissions
  file { $file_path:
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Exec['get_nessus_agent_version'],
  }

  if $facts['nessus_version'] {
    # Assign the current version of the Nessus agent to a variable so we can determine if it's eligible for upgrade
    $current_version = $facts['nessus_version']
  } else {
    # No version fact found, so we'll assume it's not installed
    $current_version = '0.0.0'
  }

  if $facts['nessus_process_priority'] {
    if $facts['nessus_process_priority'] != $process_priority {
      exec { 'set_nessus_agent_process_priority':
        command => "/opt/nessus_agent/sbin/nessuscli agent set --process-priority=${process_priority}",
        path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
      }
    }
  }

  # This section can go away after a while, but we're going to remove any old NessusAgent packages
  # installed prior to using this module.
  if $current_version == '10.7.3' {
    # remove the package
    exec { 'autoremove_nessus_agent':
      command => '/usr/bin/dnf autoremove NessusAgent -y',
      onlyif  => '/usr/bin/rpm -q NessusAgent',
      path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    }
    # remove the old version file with exec since the file is already declared
    exec { 'remove_nessus_version':
      command => '/bin/rm -f /opt/puppetlabs/facter/facts.d/nessus_version.txt',
      onlyif  => '/usr/bin/test -f /opt/puppetlabs/facter/facts.d/nessus_version.txt',
    }
    # and finally clear the nessus directory
    exec { 'clear_nessus_directory':
      command => '/bin/rm -rf /opt/nessus_agent',
      onlyif  => '/usr/bin/test -d /opt/nessus_agent',
    }
  }

  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if (versioncmp($current_version, $version) < 0) {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Download the package from Tenable API
      $package_source = "https://www.tenable.com/downloads/api/v2/pages/nessus-agents/files/NessusAgent-latest-el${major_release}.${arch}.rpm"
      $download_path = "/tmp/NessusAgent-${version}-el${major_release}.${arch}.rpm"
      $proxy_option = $proxy_host ? { undef => '', default => "--proxy ${proxy_host}:${proxy_port}" }
      exec { 'download_nessus_agent':
        command => "/usr/bin/curl -L -o ${download_path} ${proxy_option} ${package_source}",
        creates => $download_path,
      }

      # Install the package
      Package { 'NessusAgent':
        ensure   => 'installed',
        source   => $download_path,
        provider => 'rpm',
        require  => Exec['download_nessus_agent'],
      }

      # Clean up the downloaded package
      exec { 'cleanup_nessus_agent':
        command => "/bin/rm -f ${download_path}",
        onlyif => "/usr/bin/test -f ${download_path}",
        require => Package['NessusAgent'],
      }

      # Generate the version file dynamically after installation/upgrade
      exec { 'reset_nessus_agent_version':
        command     => '/opt/nessus_agent/sbin/nessuscli -v | sed -n "s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_version=\\1/p" > /opt/puppetlabs/facter/facts.d/nessus_version.txt || echo \"nessus_version=0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_version.txt',
        path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require     => File['/opt/puppetlabs/facter/facts.d'],
      }

      # Notify the exec resource after package installation/upgrade
      Package['NessusAgent'] -> Exec['reset_nessus_agent_version']

      # Configure agent
      service { 'nessusagent':
        ensure  => $service_ensure,
        enable  => $service_enable,
        require => Package['NessusAgent'],
      }

      # update the process priority fact
      file { $priority_path:
        ensure  => 'file',
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "nessus_process_priority=${process_priority}",
        require => Exec['set_nessus_agent_process_priority'],
      }

      # Set the process priority
      exec { 'set_nessus_agent_process_priority':
        command => "/opt/nessus_agent/sbin/nessuscli agent set --process-priority=${process_priority}",
        require => Service['nessusagent'],
      }

      # Register agent if it's not already linked - only run this one time on registration
      exec { 'register_nessus_agent':
        command => sprintf(
          "/opt/nessus_agent/sbin/nessuscli agent link --key=%s --groups=%s --port=%s%s%s%s%s",
          $key,
          $group,
          $port,
          $proxy_host ? { undef => '', default => " --proxy-host=${proxy_host}" },
          $proxy_port ? { undef => '', default => " --proxy-port=${proxy_port}" },
          $host ? { undef => '', default => " --host=${host}" },
          $cloud ? { undef => '', default => " --cloud" }
        ),
        unless  => '/opt/nessus_agent/sbin/nessuscli agent status | grep -q "Link status: Connected"',
        creates => '/opt/nessus_agent/var/nessus/agent.db',  # Ensures this runs only if the agent is not already registered
        require => Service['nessusagent'],
      }
    }
  }
}
