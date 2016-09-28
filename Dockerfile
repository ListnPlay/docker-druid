FROM ubuntu:14.04

RUN apt-get update

# Java 8
RUN apt-get install -y software-properties-common \
      && apt-add-repository -y ppa:webupd8team/java \
      && apt-get purge --auto-remove -y software-properties-common \
      && apt-get update \
      && echo oracle-java-8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections \
      && apt-get install -y oracle-java8-installer \
      && apt-get install -y oracle-java8-set-default \
      && rm -rf /var/cache/oracle-jdk8-installer

# MySQL (Metadata store)
RUN apt-get install -y mysql-server

# Supervisor
RUN apt-get install -y supervisor

# git
RUN apt-get install -y git

# Maven
RUN wget -q -O - http://archive.apache.org/dist/maven/maven-3/3.2.5/binaries/apache-maven-3.2.5-bin.tar.gz | tar -xzf - -C /usr/local \
      && ln -s /usr/local/apache-maven-3.2.5 /usr/local/apache-maven \
      && ln -s /usr/local/apache-maven/bin/mvn /usr/local/bin/mvn

# Zookeeper
RUN wget -q -O - http://www.us.apache.org/dist/zookeeper/zookeeper-3.4.6/zookeeper-3.4.6.tar.gz | tar -xzf - -C /usr/local \
      && cp /usr/local/zookeeper-3.4.6/conf/zoo_sample.cfg /usr/local/zookeeper-3.4.6/conf/zoo.cfg \
      && ln -s /usr/local/zookeeper-3.4.6 /usr/local/zookeeper

# Druid system user
RUN adduser --system --group --no-create-home druid \
      && mkdir -p /var/lib/druid \
      && chown druid:druid /var/lib/druid

# Druid (from source)
RUN mkdir -p /usr/local/druid/lib
# whichever github owner (user or org name) you would like to build from
ENV GITHUB_OWNER druid-io

# trigger rebuild only if branch changed
ADD https://api.github.com/repos/$GITHUB_OWNER/druid/git/refs/heads/0.9.1.1 druid-version.json
RUN git clone -q --branch 0.9.1.1 --depth 1 https://github.com/$GITHUB_OWNER/druid.git /tmp/druid
WORKDIR /tmp/druid
# package and install Druid locally
# use versions-maven-plugin 2.1 to work around https://jira.codehaus.org/browse/MVERSIONS-285
RUN mvn -U -B org.codehaus.mojo:versions-maven-plugin:2.1:set -DgenerateBackupPoms=false -DnewVersion=0.9.1.1 \
  && mvn -U -B install -DskipTests=true -Dmaven.javadoc.skip=true \
  && cp services/target/druid-services-0.9.1.1-selfcontained.jar /usr/local/druid/lib

RUN cp -r distribution/target/extensions /usr/local/druid/
RUN cp -r distribution/target/hadoop-dependencies /usr/local/druid/

RUN wget -q -O - http://static.druid.io/tranquility/releases/tranquility-distribution-0.8.2.tgz | tar -xzf - -C /usr/local
ADD kafka.json /usr/local/tranquility-distribution-0.8.2/conf/

ADD tranquility /usr/local/tranquility-distribution-0.8.2/bin/
RUN chmod +x /usr/local/tranquility-distribution-0.8.2/bin/tranquility

RUN wget -q http://central.maven.org/maven2/net/minidev/json-smart/2.2/json-smart-2.2.jar -P /usr/local/tranquility-distribution-0.8.2/lib/
RUN wget -q http://central.maven.org/maven2/net/minidev/accessors-smart/1.1/accessors-smart-1.1.jar -P /usr/local/tranquility-distribution-0.8.2/lib/
RUN wget -q http://central.maven.org/maven2/org/ow2/asm/asm/5.0.3/asm-5.0.3.jar -P /usr/local/tranquility-distribution-0.8.2/lib/

RUN apt-get update
RUN apt-get install -y npm
RUN wget -O - https://deb.nodesource.com/setup_6.x | sudo -E bash - && apt-get install -y nodejs
RUN wget -q -O - https://static.imply.io/release/imply-1.3.0.tar.gz | tar -xzf - -C /usr/local
RUN npm install /usr/local/imply-1.3.0/dist/pivot --global

# clean up time
RUN apt-get purge --auto-remove -y git \
      && apt-get clean \
      && rm -rf /tmp/* \
                /var/tmp/* \
                /var/lib/apt/lists \
                /usr/local/apache-maven-3.2.5 \
                /usr/local/apache-maven \
                /root/.m2

WORKDIR /

# Setup metadata store and add sample data
ADD sample-data.sql sample-data.sql
ADD run.sh /tmp/run.sh
RUN chmod +x /tmp/run.sh
RUN /etc/init.d/mysql start \
      && mysql -u root -e "GRANT ALL ON druid.* TO 'druid'@'localhost' IDENTIFIED BY 'diurd'; CREATE database druid CHARACTER SET utf8;" \
      && java -cp /usr/local/druid/lib/druid-services-*-selfcontained.jar \
          -Ddruid.extensions.directory=/usr/local/druid/extensions \
          -Ddruid.extensions.loadList=[\"mysql-metadata-storage\"] \
          -Ddruid.metadata.storage.type=mysql \
          io.druid.cli.Main tools metadata-init \
              --connectURI="jdbc:mysql://localhost:3306/druid" \
              --user=druid --password=diurd \
      && mysql -u root druid < sample-data.sql \
      && /etc/init.d/mysql stop
# Setup supervisord
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# Expose ports:
# - 8081: HTTP (coordinator)
# - 8082: HTTP (broker)
# - 8083: HTTP (historical)
# - 8090: HTTP (overlord)
# - 3306: MySQL
# - 2181 2888 3888: ZooKeeper

# todo run tranquility
#/usr/local/tranquility-distribution-0.8.0/bin/tranquility kafka -configFile conf/kafka.json

EXPOSE 8081
EXPOSE 8082
EXPOSE 8083
EXPOSE 8090
EXPOSE 3306
EXPOSE 2181 2888 3888
EXPOSE 9090
WORKDIR /var/lib/druid
ENTRYPOINT /tmp/run.sh
#ENTRYPOINT export HOSTIP="$(resolveip -s $HOSTNAME)" && sed -i "s/ZOOKEEPER_URL/$ZOOKEEPER_URL/g" /usr/local/tranquility-distribution-0.8.0/conf/kafka.json && exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
