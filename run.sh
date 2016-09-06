#/bin/sh
export HOSTIP="$(resolveip -s $HOSTNAME)" 
ZOOKEEPER_URL=$(echo $ZOOKEEPER_URL | sed 's#\([]\#\%\@\*\$\/&[]\)#\\\1#g')
sed -i "s/ZOOKEEPER_URL/$ZOOKEEPER_URL/g" /usr/local/tranquility-distribution-0.8.0/conf/kafka.json 
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
