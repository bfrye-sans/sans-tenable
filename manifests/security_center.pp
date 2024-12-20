# This class installs and configures Tenable SecurityCenter.
#
class tenable::security_center (
  String $service_ensure = 'running',
  Boolean $service_enable = true,
  String $api_key,
  String $license_key,
  String $version,
  $major_release = $facts['os']['release']['major'],
  $arch = $facts['os']['architecture'],
  Boolean $backup,
  Optional[Variant[String, Undef]] $proxy_host = undef,
  Optional[Variant[Integer, Undef]] $proxy_port = undef,
) {
  $file_path = '/opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt'

  # Populate the Nessus security center version fact file conditionally
  exec { 'get_nessus_security_center_version':
    command => '/bin/bash -c "if rpm -q SecurityCenter > /dev/null 2>&1; then rpm -q SecurityCenter | sed -n \'s/SecurityCenter-\\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_security_center_version=\\1/p\' > /opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt; else echo \'nessus_security_center_version=0.0.0\' > /opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt; fi"',
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
    $backup = true
  } else {
    # No version fact found, so we'll assume it's not installed
    $current_version = '0.0.0'
    $backup = false
  }
  # create /opt/sc/daemon directory
  file { '/opt/sc/daemons':
    ensure => 'directory',
    owner  => 'tns',
    group  => 'tns',
    mode   => '0755',
  }

  # Lets handle the license key in /opt/sc/daemons
  file { '/opt/sc/daemons/license.key':
    ensure  => 'file',
    content => $license_key,
    owner   => 'tns',
    group   => 'tns',
    mode    => '0600',
  }

  # restart the service if the license key changes
  File['/opt/sc/daemons/license.key'] -> Service['SecurityCenter']

  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if (versioncmp($current_version, $version) < 0) {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Grab the major release and architecture. 
      # Download the package from Tenable API
      $package_source = "https://www.tenable.com/downloads/api/v2/pages/nessus/files/Nessus-latest-el${major_release}.${arch}.rpm"
      $download_path = "/tmp/Nessus-${version}-el${major_release}.${arch}.rpm"
      $proxy_option   = $proxy_host ? { undef => '', default => "--proxy ${proxy_host}:${proxy_port}" }
      exec { 'download_nessus_security_center':
        command => "/usr/bin/curl -L -o ${download_path} -H 'Authorization: Bearer=${api_key}' ${proxy_option} ${package_source}",
        creates => $download_path,
      }

      # openjdk 1.8 is a dependency, so lets get that installed
      package { 'java-1.8.0-openjdk':
        ensure => 'installed',
      }

      # true backup means we're upgrading, so stop the service and backup the current configuration
      if $backup == true {
        service { 'SecurityCenter':
          ensure => 'stopped',
        }
        # Backup the current configuration
        exec { 'backup_nessus_security_center':
          command => '/usr/bin/tar -pzcf /opt/sc/backup/sc_backup_$(date +%Y%m%d).tar /opt/sc',
          onlyif => '/usr/bin/test -d /opt/sc',
        }
      }

      # Install the package
      Package { 'SecurityCenter':
        ensure   => 'installed',
        source   => $download_path,
        provider => 'rpm',
        require  => Exec['download_nessus_security_center'],
      }

      # Clean up the downloaded package
      exec { 'cleanup_nessus_security_center':
        command => "/bin/rm -f ${download_path}",
        onlyif => "/usr/bin/test -f ${download_path}",
        require => Package['SecurityCenter'],
      }

      # Fix up a few php settings before we start the service
      file_line { 'php_memory_limit':
        ensure  => present,
        path    => '/opt/sc/support/etc/php.ini',
        line    => 'memory_limit = 2000M',
        match   => '^memory_limit =',
        require => Package['SecurityCenter'],
      }

      file_line { 'php_post_max_size':
        ensure  => present,
        path    => '/opt/sc/support/etc/php.ini',
        line    => 'post_max_size = 2000M',
        match   => '^post_max_size =',
        require => Package['SecurityCenter'],
      }

      # Generate the version file dynamically after installation/upgrade
      exec { 'reset_nessus_security_center_version':
        command     => "rpm -q SecurityCenter > /dev/null 2>&1; then rpm -q SecurityCenter | sed -n 's/SecurityCenter-\\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/nessus_security_center_version=\\1/p' > ${file_path} || echo \"nessus_security_center_version=0.0.0\" > /opt/puppetlabs/facter/facts.d/nessus_security_center_version.txt",
        path        => ['/usr/bin', '/usr/sbin', '/bin', '/sbin'],
        require     => File['/opt/puppetlabs/facter/facts.d'],
      }

      # Notify the exec resource after package installation/upgrade
      Package['SecurityCenter'] -> Exec['reset_nessus_security_center_version']

      # Configure agent
      service { 'SecurityCenter':
        ensure  => $service_ensure,
        enable  => $service_enable,
        require => Package['SecurityCenter'],
      }
    }
  }
}
