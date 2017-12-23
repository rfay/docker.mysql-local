#!/bin/bash
set -x
set -eu
set -o pipefail


mysqld --skip-networking &
pid="$!"

for i in {60..0}; do
	if mysqladmin ping -uroot -p$MYSQL_ROOT_PASSWORD --socket=/var/tmp/mysql.sock 2>/dev/null; then
		break
	fi
	# Test to make sure we got it started in the first place. kill -s 0 just tests to see if process exists.
	if ! kill -s 0 $pid 2>/dev/null; then
		echo "mysqld local startup failed"
		exit 3
	fi
	echo "MySQL local startup process in progress... Try# $i"
	sleep 1
done
if [ "$i" -eq 0 ]; then
	echo 'MySQL local startup process failed.'
	exit 1
fi

# If no mysql database exists, run initialization
# Create the database and users we need.
if ! mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "use $MYSQL_DATABASE;" 2>/dev/null; then
	mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;"

	mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -uroot -p$MYSQL_ROOT_PASSWORD mysql

	mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;"
	mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;"
	mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e 'FLUSH PRIVILEGES ;'


fi

if ! kill -s TERM "$pid" || ! wait "$pid"; then
	echo >&2 'MySQL local startup process failed.'
	exit 1
fi

echo
echo 'MySQL local startup process done. Ready for start up.'
echo


# Change  to UID/GID of the docker user
# We use the default assignment to zero to prevent triggering
# unbound variable exit
if [ "${DDEV_UID:=0}" -gt "0" ] ; then
        echo "changing mysql user to uid: $DDEV_UID"
        usermod -u $DDEV_UID mysql
fi
if [ "${DDEV_GID:=0}" -gt 0 ] ; then
        echo "changing mysql group to gid: $DDEV_GID"
        groupmod -g $DDEV_GID mysql
fi

chown -R mysql:mysql /var/lib/mysql
chown mysql:mysql /var/log/mysqld.log

echo "Starting mysqld."
exec mysqld --max-allowed-packet=${MYSQL_MAX_ALLOWED_PACKET:-16m}
