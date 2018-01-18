#!/bin/bash
#
# Debian stretch setup on a virtual server.
#
# VERSION       :2.0.2
# URL           :https://github.com/szepeviktor/debian-server-tools
# AUTHOR        :Viktor Szépe <viktor@szepe.net>
# LICENSE       :The MIT License (MIT)
# BASH-VERSION  :4.2+
# CI            :shellcheck
# CONFIG        :/root/server.yml

# Choose providers
#
# - Domain registrar
# - DNS provider
# - Server provider (e.g. UpCloud)
# - SSL certificate provider (HTTPS)
# - CDN provider (static files)
# - Transactional email provider
# - Storage provider (server backup)
#
# Features
#
# - YAML configuration file with provider profiles
# - OS image normalization
# - Optionally switch to SysVinit
# - Boot and Halt alert
# - UTC timezone
# - Micro Name Service Caching
# - IRQ balance
# - Time synchronization
# - Hardware TRNG or HAVEGE generator
# - Fail2ban and blocking hostile networks
# - Monit monitoring
# - Courier MTA
# - System backup with S3QL
# - Nice motd welcome screen
# - Package managers: composer, pip, npm
# - CLI tools: WP-CLI, Drush, CacheTool
# - 155 MB memory usage, 2 GB disk usage
#
# Webserver
#
# - Apache 2.4 with HTTP/2 and event MPM
# - PHP-FPM 7.0 or 7.1
# - Redis in-memory cache [maxmemory 512mb, maxmemory-policy allkeys-lru]
# - MariaDB 10 or Percona Server 5.7
#
# Execution Steps
#
# 1. wget -O- https://github.com/szepeviktor/debian-server-tools/archive/master.tar.gz|tar xz
#    export LC_ALL=C.UTF-8; cd debian-server-tools-master/
# 2. Aquire settings: webmaster@, hostname, networking, DNS resolvers, NTP servers, custom kernel, user names, SSH keys
# 3. cat server.yml debian-setup/providers/upcloud-defra1.yml > /root/server.yml
#    editor /root/server.yml
# 4. Set up DNS resource records: PTR/IPv4 PTR/IPv6, A, AAAA, MX
# 5. Check fs type, set volume label:  lsblk -f; tune2fs -L "instanceID-root" /dev/vda1
# 6. Start!
#    script --timing=../debian-setup.time ../debian-setup.script
#    ./debian-setup.sh
# 7. PuTTY session: Connection/Data: viktor, xterm-256color; Connection/SSH/Auth: [ ] keyboard-interactive
# 8. Continue after reboot!
#    export LC_ALL=C.UTF-8; cd debian-server-tools-master/
#    @FIXME  export MONIT_EXCLUDED_PACKAGES=apache2:php5-fpm:php7.0-fpm:php7.1-fpm:php7.2-fpm
#    script --timing=../debian-setup2.time ../debian-setup2.script
#    ./debian-setup2.sh
# 9. Set up incoming ESP and bounce notification
#
# Tests
#
# - DNS test /monitoring/DNS.md
# - Webpage test https://www.webpagetest.org/
# - HTTP headers https://redbot.org/
# - Security headers https://securityheaders.io/
# - HTTPS https://www.ssllabs.com/ssltest/
# - HTTPS + Security headers https://observatory.mozilla.org/
# - CRL and OCSP test https://certificate.revocationcheck.com/
# - PHP configuration /webserver/php-env-check.php


export IMAGE_ARCH="amd64"
export IMAGE_MACHINE="x86_64"
export IMAGE_ID="Debian"
export IMAGE_CODENAME="stretch"
#export IMAGE_CODENAME="buster"

export WITHOUT_SYSTEMD="yes"

export SETUP_PACKAGES="debian-archive-keyring lsb-release ca-certificates wget apt apt-utils aptitude"
#:ubuntu test "$(dpkg-vendor --query vendor)" == Ubuntu
#export SETUP_PACKAGES="ubuntu-keyring lsb-release ca-certificates wget apt apt-utils"

# APT sources must be hardcoded as shyaml is unavailable before OS image normalization
export SETUP_APTSOURCES_URL_PREFIX="https://github.com/szepeviktor/debian-server-tools/raw/master/package/apt-sources"
# @TODO Update to https://deb.debian.org/
# Microsoft Azure Traffic Manager
export SETUP_APTSOURCESLIST_URL="${SETUP_APTSOURCES_URL_PREFIX}/${IMAGE_CODENAME}-azure.list"
# Fastly and Amazon CloudFront
#export SETUP_APTSOURCESLIST_URL="${SETUP_APTSOURCES_URL_PREFIX}/${IMAGE_CODENAME}-deb.list"
# Hungarian Debian mirror
#export SETUP_APTSOURCESLIST_URL="${SETUP_APTSOURCES_URL_PREFIX}/${IMAGE_CODENAME}-hu.list"

export SETUP_SHYAML_URL="https://github.com/szepeviktor/debian-server-tools/raw/master/tools/shyaml"
#export SETUP_SHYAML_URL="https://github.com/0k/shyaml/raw/master/shyaml"

set -e -x

# Am I root?
test "$(id -u)" == 0

# Common functions
# shellcheck disable=SC1091
source debian-setup-functions

# Necessary packages
IS_FUNCTIONAL="yes"
test -n "$(which dpkg-query)"
for PKG in ${SETUP_PACKAGES}; do
    if ! Is_installed "$PKG"; then
        IS_FUNCTIONAL="no"
        break
    fi
done
if [ "$IS_FUNCTIONAL" != "yes" ]; then
    apt-get update -qq || true
    # shellcheck disable=SC2086
    apt-get install -y ${SETUP_PACKAGES} || true
fi
# These packages should be auto-installed
apt-mark auto lsb-release ca-certificates

# Package sources
debian-setup/apt

# OS check
debian-setup/base-files

# OS image normalization (does dist-upgrade)
./debian-image-normalize.sh

# Remove wheezy packages
if Is_installed "libgnutls26"; then
    apt-get purge -qq \
        libboost-iostreams1.49.0 libdb5.1 libgcrypt11 libgnutls26 \
        libprocps0 libtasn1-3 libudev0 python2.6 python2.6-minimal
fi
# Remove jessie packages
if Is_installed "gcc-4.9-base"; then
    apt-get purge -qq \
        libapt-inst1.5 libapt-pkg4.12 libept1.4.12 libreadline6 libssl1.0.0 libxapian22 \
        gcc-4.9-base python-reportbug sysvinit
fi
# Remove ClamAV data
rm -rf /var/lib/clamav /var/log/clamav
# Remove left-over font
rm -rf /etc/console-setup

# Packages used on top of SETUP_PACKAGES
apt-get install -qq ssh sudo dirmngr apt-transport-https virt-what python-yaml
# Install SHYAML (config reader)
wget -nv -O /usr/local/bin/shyaml "$SETUP_SHYAML_URL"
chmod +x /usr/local/bin/shyaml

# Add APT repositories
for REPO in $(Data get-values package.apt.sources); do
    wget -nv -O "/etc/apt/sources.list.d/${REPO}.list" "${SETUP_APTSOURCES_URL_PREFIX}/${REPO}.list"
done
# Import signing keys
eval "$(grep -h -A 5 "^deb " /etc/apt/sources.list.d/*.list | grep "^#K: " | cut -d " " -f 2-)"
# Get package lists
apt-get update -qq

IP="$(ifconfig | sed -n -e '0,/^\s*inet \(addr:\)\?\([0-9\.]\+\)\b.*$/s//\2/p')"
export IP

# Virtualization environment
debian-setup/virt-what

debian-setup/hostname
debian-setup/login
debian-setup/readline-common
# Set Bash as default
debian-setup/dash

# Root user and first user
debian-setup/adduser
# After adduser
debian-setup/openssh-server

# Optionally (WITHOUT_SYSTEMD) switch to SysVinit
debian-setup/systemd

# Log in on a new terminal and log out here
exit 0
