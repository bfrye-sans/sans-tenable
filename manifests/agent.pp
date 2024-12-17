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
  Optional[String] $proxy_host,
  Optional[Integer] $proxy_port,
  Optional[String] $host = undef,
  Optional[Boolean] $cloud = false,
  String $version,
  $major_release = $facts['os']['release']['major'],
  $arch = $facts['os']['architecture'],
) {
# Run nessuscli -v and capture the version into a temporary file
exec { 'get_nessus_version':
  command => '/opt/nessus_agent/sbin/nessuscli -v | sed -n "s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p" > /tmp/nessus_version 2>/dev/null',
  creates => '/tmp/nessus_version',
  path    => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
}

# Use a fallback if the file doesn't exist or is empty
exec { 'set_default_version_if_missing':
  command => 'echo "Not Installed" > /tmp/nessus_version',
  onlyif  => 'test ! -s /tmp/nessus_version', # Only if file is empty or missing
  require => Exec['get_nessus_version'],
}

# Capture the version content into a fact file for Puppet to process
exec { 'capture_nessus_version':
  command => '/bin/cat /tmp/nessus_version > /tmp/nessus_version_fact',
  creates => '/tmp/nessus_version_fact',
  require => Exec['set_default_version_if_missing'],
}

# Use a variable to read the captured fact
$current_version = file('/tmp/nessus_version_fact')

# Clean up the temporary files
exec { 'cleanup_nessus_files':
  command => 'rm -f /tmp/nessus_version /tmp/nessus_version_fact',
  onlyif  => 'test -f /tmp/nessus_version || test -f /tmp/nessus_version_fact',
  require => Exec['capture_nessus_version'],
}

# Output the version
notify { 'NessusAgent Version':
  message => "The current version of NessusAgent is: ${current_version}",
  require => Exec['cleanup_nessus_files'],
}

  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if versioncmp($current_version, $version) < 0 or $current_version == 'Not Installed' {
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

      notify { "Nessus Agent version: ${version} installed successfully": 
        message => "Nessus Agent version: ${version} installed successfully and cleaned up.",
        require => Exec['cleanup_nessus_agent'],
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
