# This class installs and configures Tenable SecurityCenter.
#
class tenable::security_center: (
  String $service_ensure = 'running',
  Boolean $service_enable = true,
  $major_release = $facts['os']['release']['major'],
  $arch = $facts['os']['architecture'],
) {
  $file_path = '/opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt'

  # Ensure the facts.d directory exists
  file { '/opt/puppetlabs/facter/facts.d':
    ensure => 'directory',
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # Populate the Nessus security center version fact file conditionally
  exec { 'get_nessus_security_center_version':
    command => '/bin/bash -c "if rpm -q SecurityCenter > /dev/null 2>&1; then rpm -q SecurityCenter | sed -n \'s/SecurityCenter-\\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_security_center_version=\\1/p\' > ${file_path}; else echo \'nessus_security_center_version=0.0.0\' > ${file_path}; fi"',
    unless    => '/usr/bin/test -f /opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt',
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
    require => Exec['get_nessus_security_center_version'],
  }

  if $facts['nessus_security_center_version'] {
    # Assign the current version of the Nessus security center to a variable so we can determine if it's eligible for upgrade
    $current_version = $facts['nessus_security_center_version']
  } else {
    # No version fact found, so we'll assume it's not installed
    $current_version = '0.0.0'
  }


  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if ($current_version == 'Not Installed') or (versioncmp($current_version, $version) < 0) {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Grab the major release and architecture. 
      # Download the package from Tenable API
      $package_source = "https://www.tenable.com/downloads/api/v2/pages/nessus/files/Nessus-latest-el${major_release}.${arch}.rpm"
      $download_path = "/tmp/Nessus-${version}-el${major_release}.${arch}.rpm"
      exec { 'download_nessus_security_center':
        command => "/usr/bin/curl -L -o ${download_path} ${package_source}",
        creates => $download_path,
      }

      # Install the package
      Package { 'nessusd':
        ensure   => 'installed',
        source   => $download_path,
        provider => 'rpm',
        require  => Exec['download_nessus_security_center'],
      }

      # Clean up the downloaded package
      exec { 'cleanup_nessus_security_center':
        command => "/bin/rm -f ${download_path}",
        onlyif => "/usr/bin/test -f ${download_path}",
        require => Package['nessusd'],
      }

      # Generate the version file dynamically after installation/upgrade
      exec { 'reset_nessus_security_center_version':
        command     => 'rpm -q SecurityCenter > /dev/null 2>&1; then rpm -q SecurityCenter | sed -n \'s/SecurityCenter-\\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_security_center_version=\\1/p\' > ${file_path} || echo \"nessus_security_center_version=0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt',
        path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require     => File['/opt/puppetlabs/facter/facts.d'],
      }

      # Notify the exec resource after package installation/upgrade
      Package['nessusd'] -> Exec['reset_nessus_security_center_version']

      # Configure agent
      service { 'nessusd':
        ensure  => $service_ensure,
        enable  => $service_enable,
        require => Package['nessusd'],
      }
    }
  }
}
