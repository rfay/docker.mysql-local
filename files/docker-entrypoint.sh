#!/bin/bash
set -x
set -eu
set -o pipefail

# If mariadb itself has not been initialized, initialize it.
# This will be the case if we're running on an uninitialized /var/lib/mysql
if [ ! -d "/var/lib/mysql/mysql" ]; then
	mkdir -p /var/lib/mysql
	chown -R mysql:mysql /var/lib/mysql

	echo 'Initializing mysql'
	mysql_install_db --datadir="/var/lib/mysql"
	CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
	GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;

	echo 'Mariadb initialized'
fi

mysqld --skip-networking &
pid="$!"

for i in {60..0}; do
	if mysqladmin ping -uroot --socket=/var/tmp/mysql.sock 2>/dev/null; then
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

# If no $MYSQL_DATABASE database exists, run initialization
# Create the database and users we need.
# Note that password is empty while we're running in socket mode.
# The value in ~/.my.cnf has to be overridden here.
if ! mysql -uroot -e "use $MYSQL_DATABASE;" 2>/dev/null; then
	mysql mysql -uroot --password='' -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;"

	mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -uroot --password='' mysql

	mysql -uroot  --password='' -e "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;"
	mysql -uroot  --password='' -e "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;"
	mysql -uroot  --password='' -e 'FLUSH PRIVILEGES ;'
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
