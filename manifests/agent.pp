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
) {
  $file_path       = '/opt/puppetlabs/facter/facts.d/nessus_version.txt'

  # Ensure the facts.d directory exists
  file { '/opt/nessus_agent/facter/facts.d':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Populate the Nessus version fact file conditionally
  exec { 'get_nessus_agent_version':
    command => '/bin/bash -c "if command -v /opt/nessus_agent/sbin/nessuscli > /dev/null 2>&1; then /opt/nessus_agent/sbin/nessuscli -v | sed -n \"s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p\" > /opt/puppetlabs/facter/facts.d/nessus_version.txt; else echo \"0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_version.txt; fi" 2>> /tmp/nessus_debug.log',
    unless  => '/usr/bin/test -f /opt/puppetlabs/facter/facts.d/nessus_version.txt',
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    logoutput => true,
    require => File['/opt/puppetlabs/facter/facts.d'],
  }

  # Ensure the fact file has proper permissions
  file { '/opt/puppetlabs/facter/facts.d/nessus_version.txt':
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Exec['get_nessus_agent_version'],
  }

  $current_version = file(/opt/puppetlabs/facter/facts.d/nessus_version.txt)

  if ($current_version == 0) or (versioncmp($current_version, $version) < 0) {
    notify { 'Update Required':
      message => "NessusAgent version '${current_version}' is outdated or not installed. Expected version: ${version}.",
    }
  } else {
    notify { 'NessusAgent Up-to-Date':
      message => "NessusAgent version '${current_version}' is up-to-date.",
    }
  }

  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if ($current_version == 'Not Installed') or (versioncmp($current_version, $version) > 0) {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Download the package from Tenable API
      $package_source = "https://www.tenable.com/downloads/api/v2/pages/nessus-agents/files/NessusAgent-latest-el${major_release}.${arch}.rpm"
      $download_path = "/tmp/NessusAgent-${version}-el${major_release}.${arch}.rpm"
      exec { 'download_nessus_agent':
        command => "/usr/bin/curl -L -o ${download_path} ${package_source}",
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
      exec { 'get_nessus_agent_version':
        command => '/opt/nessus_agent/sbin/nessuscli -v | sed -n "s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p" > /opt/puppetlabs/facter/facts.d/nessus_version.txt || echo "Not Installed" > /opt/puppetlabs/facter/facts.d/nessus_version.txt',
        creates => $file_path,
        path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require => File['/opt/puppetlabs/facter/facts.d'],
      }

      # Configure agent
      service { 'nessusagent':
        ensure  => $service_ensure,
        enable  => $service_enable,
        require => Package['NessusAgent'],
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
  } else {
    notify { "Nessus Agent is already at the latest version: ${version}": }
  }
}
