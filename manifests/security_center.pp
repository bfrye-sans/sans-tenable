# This class installs and configures Tenable SecurityCenter.
#


class tenable::security_center (
  String $version = $tenable::params::security_center_version,
  Boolean $service_enable = $tenable::params::service_enable,
  String $service_ensure = $tenable::params::service_ensure,
  String $tenable_api_key = $tenable::params::tenable_api_key,
) {
  # Setup prequisites for installing Security Center and checking for updates.
  package { 'wget':
    ensure => present,
  }
  package { 'sed':
    ensure => present,
  }
  package { 'curl':
    ensure => present,
  }
  # OpenJDK 1.8 is required for SecurityCenter.
  package { 'java-1.8.0-openjdk':
    ensure => present,
  }

  # Grab the current version of SecurityCenter.
  $current_version = inline_template('<%= `rpm -qa | sed -n \'s/.*SecurityCenter-\\([0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\).*/\\1/p\'`.strip %>')
  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if versioncmp($current_version, $version) < 0 {
    # First we need to shut down security center to backup the database.
    service { 'SecurityCenter':
      ensure => stopped,
    }
    # Backup the SecurityCenter database.
    exec { 'backup_security_center':
      command => '/opt/sc/support/backup/backup_db.sh',
    }
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Grab the major release and architecture.
      $major_release = $facts['os']['release']['major']
      $arch = $facts['os']['architecture']
      # Find out the newest version of SecurityCenter.
      $newest_version = inline_template('<%= `curl -s https://www.tenable.com/downloads/api/v2/pages/security-center | sed -n \'s/.*"version": *"\\([0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\)".*/\\1/p\'`.strip %>')
      # If the newest version is greater than the current version, download and install it.
      if versioncmp($newest_version, $version) > 0 {
        exec { 'download_security_center':
          command => "rpm -i <(wget --header='X-Api-Key: ${tenable_api_key} -O https://www.tenable.com/downloads/api/v2/pages/security-center/SecurityCenter-latest-el${major_release}.${arch}.rpm)",
        }

        notify { "Nessus Security Center version: ${newest_version} installed.": }
      }
    } else {
      fail('Unsupported OS family.')
    }
  }
  # Ensure the SecurityCenter service is running and enabled.
  service { 'SecurityCenter':
    ensure     => running,
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
  }
}
  
