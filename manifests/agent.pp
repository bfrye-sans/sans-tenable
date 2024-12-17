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
  # create an external fact for current_version
  $file_path = '/opt/puppetlabs/facter/facts.d/nessus_agent_version.txt'

  # ensure the directory exists
  file { '/etc/puppetlabs/facter/facts.d':
    ensure => 'directory',
    owner => 'root',
    group => 'root',
    mode => '0755',
  }

  # Generate the external fact with the current version of the Nessus agent
  exec { 'get_nessus_agent_version':
    command => '/opt/nessus_agent/sbin/nessuscli -v | sed -n "s/.*Nessus Agent) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_version=\\1/p" > /etc/puppetlabs/facter/facts.d/nessus_version.txt || echo "nessus_version=Not Installed" > /etc/puppetlabs/facter/facts.d/nessus_version.txt',
    creates => $file_path,
    path => '/usr/bin:/bin,/sbin:/usr/sbin',
    require => File['/opt/puppetlabs/facter/facts.d'],
  }

  # Assign the current version to a variable
  $current_version = $facts['nessus_agent_version']

  # Set permissions on the external fact
  file { $file_path:
    ensure => 'file',
    owner => 'root',
    group => 'root',
    mode => '0644',
    require => Exec['get_nessus_agent_version'],
  }

  # Notify the user of the current version
  notify { "Current Nessus Agent version: ${current_version}": }

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
