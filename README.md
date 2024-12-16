# Nessus

This module sets up, installs and allows updating of the following Tenable products: 

## Description

This module will setup the following products from Tenable:
 * Nessus Agent
 * Nessus Scanner
 * Security Center

## Setup

### What nessus affects

* Can alter php settings on Security Center installations
* Installs OpenJDK on Security Center installations


### Beginning with nessus

Module can be completely configured via hiera separating classes for:
`tenable::agent` - handles installation and upgrading of client agents
`tenable::scanner` - handles installation and upgrading of zoned scanning agents
`tenable::security_center` - handles installation and upgrading of security center

## Usage

Since there's not a lot of options when installing Tenable products, configuration
is kept to a minimum.  For any processes, it will detect if it is running and if not,
install necessary dependencies and options, then install the package itself and
provide paths for updating.

Since Tenable does not maintain a public repo to mirror, all installed are done
via RPM with dependencies processed beforehand.  State in your hiera configuration
what version of each service you wish to run and it will download, configure and
install said version.

To upgrade, simply change the version number to the version you wish to upgrade to
and on the next puppet run it will upgrade.
 * for security center, when upgrading it will shut down security center, then backup
   databases before processing the upgrade.


## Security Center

```puppet
classes
  - tenable::security_center

tenable::security_center::security_center_version: latest
```

## Nessus Scanner

```puppet
classes
  - tenable::scanner

tenable::scanner::scanner_version: latest
```

## Nessus Agent
```puppet
classes
  - tenable::agent

tenable::agent::agent_version: latest
tenable::agent::port: 8834
tenable::agent::agent_key: 'your-activation-key'
tenable::agent::proxy_host: 'https://yourproxy.server.com'
tenable::agent::proxy_port: '10010'
```




[1]: https://puppet.com/docs/pdk/latest/pdk_generating_modules.html
[2]: https://puppet.com/docs/puppet/latest/puppet_strings.html
[3]: https://puppet.com/docs/puppet/latest/puppet_strings_style.html
