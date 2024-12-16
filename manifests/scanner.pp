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

) {
  # Grab the current version of the Nessus scanner.
  $current_version = inline_template('<%= `/opt/nessus/sbin/nessusd -v | sed -n \'s/.*Nessus) \\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/p\'`.strip %>')
  # Since Tenable doesn't offer a mirrorable repo, we're going to check for updates and download from the API directly.
  if versioncmp($current_version, $version) < 0 {
    # RHEL Releases
    if $facts['os']['family'] == 'RedHat' {
      # Grab the major release and architecture.
      $major_release = $facts['os']['release']['major']
      $arch = $facts['os']['architecture']
      # Find out the newest version of the Nessus scanner.      
      $newest_version = inline_template('<%= `curl -s https://www.tenable.com/downloads/api/v2/pages/nessus | sed -n \'s/.*"version": *"\\([0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\.[0-9]\\{1,2\\}\\)".*/\\1/p\'`.strip %>')
      # If the newest version is greater than the current version, download and install it.
      if versioncmp($extracted_version, $version) > 0 {
        exec { 'download_nessus_agent':
          command => "rpm -i https://www.tenable.com/downloads/api/v2/pages/nessus/Nessus-latest-el${major_release}.${arch}.rpm",
        }

        notify { "Nessus Service version: ${extracted_version} installed.": }
      }
    } else {
      fail('Unsupported OS family.')
    }
  }
  # Ensure the Nessus service is running and enabled.
  service { 'nessusd':
    ensure     => running,
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
    require    => Package['Nessus'],
  }
}
