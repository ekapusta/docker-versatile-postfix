#!/bin/bash

function print_help {
cat <<EOF
        Generic Postfix Setup Script
===============================================

to create a new postfix server for your domain
you should use the following commands:

  docker run -p 25:25 -v /maildirs:/var/mail \
         dockerimage/postfix \
         yourdomain.com \
         user1:password \
         user2:password \
         userN:password

this creates a new smtp server which listens
on port 25, stores mail under /mailsdirs
and has serveral user accounts like
user1 with password "password" and a mail
address user1@yourdomain.com
________________________________________________
by MarvAmBass
EOF
}

if [ "-h" == "$1" ] || [ "--help" == "$1" ] || [ -z $1 ] || [ "" == "$1" ]
then
  print_help
  exit 0
fi

if [ ! -f /etc/default/saslauthd ]
then
  >&2 echo ">> you're not inside a valid docker container"
  exit 1;
fi

echo ">> setting up postfix for: $1"

# add domain
postconf -e myhostname="$1"
echo "$1" > /etc/mailname
echo "Domain $1" >> /etc/opendkim.conf

if [ ${#@} -gt 1 ]
then
  echo ">> adding users..."

  # all arguments but skip first argumenti
  i=0
  for ARG in "$@"
  do
    if [ $i -gt 0 ] && [ "$ARG" != "${ARG/://}" ]
    then
      USER=`echo "$ARG" | cut -d":" -f1`
      echo "    >> adding user: $USER"
      useradd -s /bin/bash $USER
      echo "$ARG" | chpasswd
      if [ ! -d /var/spool/mail/$USER ]
      then
        mkdir /var/spool/mail/$USER
      fi
      chown -R $USER:mail /var/spool/mail/$USER
      chmod -R a=rwx /var/spool/mail/$USER
      chmod -R o=- /var/spool/mail/$USER
    fi

    i=`expr $i + 1`
  done
fi

# DKIM
if [ -z ${DISABLE_DKIM+x} ]
then
  echo ">> enable DKIM support"
  
  if [ -z ${DKIM_CANONICALIZATION+x} ]
  then
    DKIM_CANONICALIZATION="simple"
  fi
  
  echo "Canonicalization $DKIM_CANONICALIZATION" >> /etc/opendkim.conf
  
  postconf -e milter_default_action="accept"
  postconf -e milter_protocol="2"
  postconf -e smtpd_milters="inet:localhost:8891"
  postconf -e non_smtpd_milters="inet:localhost:8891"
  
  # add dkim if necessary
  if [ ! -f /etc/postfix/dkim/dkim.key ]
  then
    echo ">> no dkim.key found - generate one..."
    opendkim-genkey -s mail -d $1
    mv mail.private /etc/postfix/dkim/dkim.key
    echo ">> printing out public dkim key:"
    cat mail.txt
    mv mail.txt /etc/postfix/dkim/dkim.public
    echo ">> please at this key to your DNS System"
  fi
  echo ">> change user and group of /etc/postfix/dkim/dkim.key to opendkim"
  chown opendkim:opendkim /etc/postfix/dkim/dkim.key
  chmod o=- /etc/postfix/dkim/dkim.key
fi

# add aliases
> /etc/aliases
if [ ! -z ${ALIASES+x} ]
then
  IFS=';' read -ra ADDR <<< "$ALIASES"
  for i in "${ADDR[@]}"; do
    echo "$i" >> /etc/aliases
    echo ">> adding $i to /etc/aliases"
  done
fi
echo ">> the new /etc/aliases file:"
cat /etc/aliases
newaliases

# starting services
echo ">> starting the services"
service rsyslog start

if [ -z ${DISABLE_DKIM+x} ]
then
  service opendkim start
fi

service saslauthd start
service postfix start

# print logs
echo ">> printing the logs"
touch /var/log/mail.log /var/log/mail.err /var/log/mail.warn
chmod a+rw /var/log/mail.*
tail -F /var/log/mail.*
