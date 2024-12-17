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

  # Use inline_template to fetch the version or fallback to default
  $current_version = inline_template('<%=
    begin
      output = %x[/usr/bin/rpm -q NessusAgent 2>/dev/null | sed -n \'s/.*NessusAgent-\\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p\'].strip
      output.empty? ? "Not Installed" : output
    rescue
      "Not Installed"
    end
  %>')

  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if versioncmp($current_version, $version) < 0 or $current_version == 'Not Installed' {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Download the package from Tenable API
      notify { "debug nessus: Desired: ${version} ${major_release} ${arch} Hiera set: ${current_version}": }
      $package_source = "https://www.tenable.com/downloads/api/v2/pages/nessus-agents/files/NessusAgent-${version}-el${major_release}.${arch}.rpm"
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
