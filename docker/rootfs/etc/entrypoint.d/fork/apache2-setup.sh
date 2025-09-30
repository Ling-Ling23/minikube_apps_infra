#!/bin/bash
echo "Setup Apache2 ...start"
export APP_USER="${APP_USER:-www-data}"
export APP_GROUP="${APP_GROUP:-www-data}"
export HTTPD_PORT="${HTTPD_PORT:-80}"
export HTDOCS_DIR="${HTDOCS_DIR:-/app/src}"
export HTTPD_USER="${APP_USER}"
export HTTPD_GROUP="${APP_GROUP}"

echo "Setup Apache2 ..."
sed -i \
    -e "s/#LoadModule rewrite_module/LoadModule rewrite_module/" \
    -e "s/^User .*/User ${HTTPD_USER}/" \
    -e "s/^Group .*/Group ${HTTPD_GROUP}/" \
    -e "s/^Listen .*/Listen ${HTTPD_PORT}/" \
    -e "s/AllowOverride None/AllowOverride All/" \
/etc/apache2/apache2.conf 

if [ -f /etc/apache/envvars ]; then
    sed -i \
        -e "s/USER=www-data/USER=${HTTPD_USER}/" \
        -e "s/GROUP=www-data/GROUP=${HTTPD_GROUP}/" \
    /etc/apache2/envvars 
fi

# set/fix permissions for htdocs
echo "${HTTPD_USER}:${HTTPD_GROUP} ${HTDOCS_DIR}"
chown -R ${HTTPD_USER}:${HTTPD_GROUP} ${HTDOCS_DIR}
apache2ctl restart
