# This class installs and manages the Tenable Nessus scanner.
#
# Parameters:
#   String $package_name
#     The name of the package to install. Default is 'Nessus'.
#
#   String $package_source
#     The source URL for the package. Default is 'https://www.tenable.com/downloads/api/v1/public/pages/nessus/downloads/12345/download?i_agree_to_tenable_license_agreement=true'.
#
#   String $package_provider
#     The provider for the package management system. Default is 'rpm'.
#
#   String $service_name
#     The name of the service to manage. Default is 'nessusd'.
#
#   String $start_command
#     The command to start the Nessus service. Default is '/bin/systemctl start nessusd'.
#
#   String $path
#     The execution path for the start command. Default is '/bin:/usr/bin:/sbin:/usr/sbin'.
#
# Resources:
#   package { $package_name }
#     Ensures the Nessus package is installed from the specified source using the specified provider.
#
#   service { $service_name }
#     Ensures the Nessus service is running and enabled to start at boot.
#
#   exec { 'start_nessus' }
#     Executes the start command for the Nessus service, but only if the package is updated.

class tenable::scanner (
  String $service_ensure = 'running',
  Boolean $service_enable = true,
  String $version,
  $major_release = $facts['os']['release']['major'],
  $arch = $facts['os']['architecture'],
  Optional[Variant[String, Undef]] $proxy_host = undef,
  Optional[Variant[Integer, Undef]] $proxy_port = undef,
) {
  $file_path = '/opt/puppetlabs/facter/facts.d/nessus_scanner_version.txt'

  # Populate the Nessus scanner version fact file conditionally
  exec { 'get_nessus_scanner_version':
    command   => '/bin/bash -c "if command -v /opt/nessus/sbin/nessuscli > /dev/null 2>&1; then /opt/nessus/sbin/nessuscli -v | sed -n \"s/.*Nessus) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_scanner_version=\\1/p\" > /opt/puppetlabs/facter/facts.d/nessus_scanner_version.txt; else echo \"nessus_scanner_version=0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_scanner_version.txt; fi"',
    unless    => '/usr/bin/test -f /opt/puppetlabs/facter/facts.d/nessus_scanner_version.txt',
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
    require => Exec['get_nessus_scanner_version'],
  }

  if $facts['nessus_scanner_version'] {
    # Assign the current version of the Nessus scanner to a variable so we can determine if it's eligible for upgrade
    $current_version = $facts['nessus_scanner_version']
  } else {
    # No version fact found, so we'll assume it's not installed
    $current_version = '0.0.0'
  }


  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if (versioncmp($current_version, $version) < 0) {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Grab the major release and architecture. 
      # Download the package from Tenable API
      $package_source = "https://www.tenable.com/downloads/api/v2/pages/nessus/files/Nessus-latest-el${major_release}.${arch}.rpm"
      $download_path = "/tmp/Nessus-${version}-el${major_release}.${arch}.rpm"
      $proxy_option = $proxy_host ? { undef => '', default => "--proxy ${proxy_host}:${proxy_port}" }
      exec { 'download_nessus_scanner':
        command => "/usr/bin/curl -L -o ${download_path} ${proxy_option} ${package_source}"
        creates => $download_path,
      }

      # Install the package
      Package { 'nessusd':
        ensure   => 'installed',
        source   => $download_path,
        provider => 'rpm',
        require  => Exec['download_nessus_scanner'],
      }

      # Clean up the downloaded package
      exec { 'cleanup_nessus_scanner':
        command => "/bin/rm -f ${download_path}",
        onlyif => "/usr/bin/test -f ${download_path}",
        require => Package['nessusd'],
      }

      # Generate the version file dynamically after installation/upgrade
      exec { 'reset_nessus_scanner_version':
        command     => '/opt/nessus/sbin/nessuscli -v | sed -n "s/.*Nessus) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_scanner_version=\\1/p" > /opt/puppetlabs/facter/facts.d/nessus_scanner_version.txt || echo \"nessus_scanner_version=0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_scanner_version.txt',
        path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require     => File['/opt/puppetlabs/facter/facts.d'],
      }

      # Notify the exec resource after package installation/upgrade
      Package['nessusd'] -> Exec['reset_nessus_scanner_version']

      # Configure scanner
      service { 'nessusd':
        ensure  => $service_ensure,
        enable  => $service_enable,
        require => Package['nessusd'],
      }
    }
  }
}
