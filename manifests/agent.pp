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
  $current_version     = '/tmp/nessus_version_output.txt'

  # Use the output file's content directly in the comparison
  exec { 'compare_nessus_version':
    command => "bash -c 'if [ \"$(cat ${current_version})\" = \"Not Installed\" ] || [ \"$(cat ${current_version})\" \< \"${version}\" ]; then echo \"Update Required\"; else echo \"Up-to-date\"; fi'",
    path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
    logoutput => true,  # Log the comparison result for visibility
    require  => Exec['read_nessus_version'],
  }

  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if ($current_version == 'Not Installed') or (versioncmp($current_version, $version) < 0) {
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

      # Ensure the facts.d directory exists on the agent
      file { '/opt/puppetlabs/facter/facts.d':
        ensure => 'directory',
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }

      # create external fact for Nessus Agent version
      file { '/opt/puppetlabs/facter/facts.d/nessus_agent_version.txt':
        ensure  => file,
        content => $version,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
      }

      # Generate the version file dynamically after installation/upgrade
      exec { 'get_nessus_agent_version':
        command => '/opt/nessus_agent/sbin/nessuscli -v | sed -n "s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p" > /opt/puppetlabs/facter/facts.d/nessus_version.txt || echo "Not Installed" > /opt/puppetlabs/facter/facts.d/nessus_version.txt',
        creates => $file_path,
        path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require => File['/opt/puppetlabs/facter/facts.d'],
      }

      # Copy the version file to a temporary file for reading
      exec { 'read_nessus_version':
        command => "cat ${file_path} > ${current_version}",
        creates => $current_version,
        path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require => Exec['get_nessus_agent_version'],
      }
    }
  } elsif $current_version == $version {
    notify { "Nessus Agent is already at the latest version: ${version}": }
  } else {
    fail('Unsupported OS family.')
  }

  # Configure agent
  service { 'nessusagent':
    ensure  => $service_ensure,
    enable  => $service_enable,
    require => Package['NessusAgent'],
  }

  # Register agent if it's not already linked
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
    require => Service['nessusagent'],
  }
}
