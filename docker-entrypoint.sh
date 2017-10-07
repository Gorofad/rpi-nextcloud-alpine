#!/bin/bash

# Set TimeZone
if [ ! -z "$TZ" ]; then
	echo ">> set timezone"
	echo ${TZ} >/etc/timezone && dpkg-reconfigure -f noninteractive tzdata
	sed -i -e 's/;date.timezone =/date.timezone=${TZ}/g' /etc/php/7.0/fpm/php.ini
fi

# Display PHP error's or not
if [[ "$PHP_ERRORS" == "1" ]] ; then
	sed -i -e 's/display_errors = Off/display_errors = On/g' /etc/php/7.0/fpm/php.ini
	#sed -i -e 's/;php_flag[display_errors] = off/php_flag[display_errors] = on/g' /etc/php/7.0/fpm/pool.d/www.conf
fi

# Increase the memory_limit
if [ ! -z "$PHP_MEM_LIMIT" ]; then
	sed -i "s/memory_limit = 128M/memory_limit = ${PHP_MEM_LIMIT}M/g" /etc/php/7.0/fpm/php.ini
fi

# Increase the post_max_size
if [ ! -z "$PHP_POST_MAX_SIZE" ]; then
	sed -i "s/post_max_size = 8M/post_max_size = ${PHP_POST_MAX_SIZE}M/g" /etc/php/7.0/fpm/php.ini
fi

# Increase the upload_max_filesize
if [ ! -z "$PHP_UPLOAD_MAX_FILESIZE" ]; then
	sed -i "s/upload_max_filesize = 2M/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}M/g" /etc/php/7.0/fpm/php.ini
fi

# Increase the max_file_uploads
if [ ! -z "$PHP_MAX_FILE_UPLOADS" ]; then
	sed -i "s/max_file_uploads = 20/max_file_uploads = ${PHP_MAX_FILE_UPLOADS}/g" /etc/php/7.0/fpm/php.ini
fi

set -e

# version_greater A B returns whether A > B
function version_greater() {
	[[ "$(printf '%s\n' "$@" | sort | head -n 1)" != "$1" ]];
}

# return true if specified directory is empty
function directory_empty() {
    [ -n "$(find "$1"/ -prune -empty)" ]
}

function run_as() {
  if [[ $EUID -eq 0 ]]; then
    su - www-data -s /bin/bash -c "$1"
  else
    bash -c "$1"
  fi
}

installed_version="0.0.0~unknown"
if [ -f /var/www/html/version.php ]; then
    installed_version=$(php -r 'require "/var/www/html/version.php"; echo "$OC_VersionString";')
fi
image_version=$(php -r 'require "/usr/src/nextcloud/version.php"; echo "$OC_VersionString";')

if version_greater "$installed_version" "$image_version"; then
    echo "Can't start Nextcloud because the version of the data ($installed_version) is higher than the docker image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
    exit 1
fi

if version_greater "$image_version" "$installed_version"; then
    if [ "$installed_version" != "0.0.0~unknown" ]; then
        run_as 'php /var/www/html/occ app:list' > /tmp/list_before
    fi
    if [[ $EUID -eq 0 ]]; then
      rsync_options="-rlDog --chown www-data:root"
    else
      rsync_options="-rlD"
    fi
    rsync $rsync_options --delete --exclude /config/ --exclude /data/ --exclude /custom_apps/ --exclude /themes/ /usr/src/nextcloud/ /var/www/html/

    for dir in config data custom_apps themes; do
        if [ ! -d /var/www/html/"$dir" ] || directory_empty /var/www/html/"$dir"; then
            rsync $rsync_options --include /"$dir"/ --exclude '/*' /usr/src/nextcloud/ /var/www/html/
        fi
    done

    if [ "$installed_version" != "0.0.0~unknown" ]; then
        run_as 'php /var/www/html/occ upgrade --no-app-disable'

        run_as 'php /var/www/html/occ app:list' > /tmp/list_after
        echo "The following apps have beed disabled:"
        diff <(sed -n "/Enabled:/,/Disabled:/p" /tmp/list_before) <(sed -n "/Enabled:/,/Disabled:/p" /tmp/list_after) | grep '<' | cut -d- -f2 | cut -d: -f1
        rm -f /tmp/list_before /tmp/list_after
    fi
fi

# exec CMD
echo ">> exec docker CMD"
echo "$@"
exec "$@"
