#!/bin/bash
usage="usage: $0 -x proxy_host -p proxy_port -U username -P password (-R realm) -s host -g port"

while getopts "x:p:s:g:U:P:R:h" options; do
  case $options in
    U ) USER=$OPTARG;;
    P ) PASS=$OPTARG;;
    R ) REALM=$OPTARG;;
    s ) HOST=$OPTARG;;
    g ) PORT=$OPTARG;;
    x ) PROXY_HOST=$OPTARG;;
    p ) PROXY_PORT=$OPTARG;;
    h ) echo $usage 1>&2
         exit 1;;
    \? ) echo $usage 1>&2
         exit 1;;
    * ) echo $usage 1>&2
          exit 1;;
  esac
done

if type md5;
then
  MD5='md5'
else
  MD5='md5sum'
fi


for tool in $MD5 nc; do
  if ! type $tool >/dev/null 2>&1; then
    echo "ERROR: \"$tool\" not found." 1>&2
    echo "       This is needed by $scriptname to work. Check your" 1>&2
    echo "       \$PATH variable or install the tool \"$tool\"." 1>&2
    if [[ $tool == "$MD5" ]]
    then
      echo "        $MD5 is available in the openssl package" 1>&2
      echo "" 1>&2
    elif [[ $tool == 'nc' ]]
    then
      echo "        netcat is available in many package repositories, or from http://netcat.sourceforge.net/" 1>&2
      echo "" 1>&2
    fi
    exit 2
  fi
done

if [[ -z $PROXY_HOST ]] || [[ -z $PROXY_PORT ]]
then
  echo $usage
  exit 1
fi

CONNECT=`echo -n ''| ( echo "CONNECT ${HOST}:${PORT} HTTP/1.0"; echo; cat ) | nc ${PROXY_HOST} ${PROXY_PORT}`

echo "test"
echo "${CONNECT}"
echo "after test"

if echo "${CONNECT}" | grep -q 'HTTP.* 407 '
then
  echo "got a 407!"
  PROXY_INFO=`echo "${CONNECT}" | grep '^Proxy-Authenticate'`
  # STALE=`echo $PROXY_INFO|grep '^Proxy-Authenticate'|grep -oi 'stale=[^,]*'|awk -F'=' '{print $2}'`
  NONCE=`echo $PROXY_INFO|grep '^Proxy-Authenticate'|grep -oi 'nonce="[^"]*'|awk -F'"' '{print $2}'`
  QOP=`echo $PROXY_INFO|grep '^Proxy-Authenticate'|grep -oi 'qop="[^"]*'|awk -F'"' '{print $2}'`
  CNONCE=`( echo $$; w ; date ) | cksum| cut -f1 -d" " | $MD5 | awk '{print $1}' | cut -b 1-8`
  NC="00000001"

  if [[ -z $REALM ]]
  then
    REALM=`echo $PROXY_INFO|grep '^Proxy-Authenticate'|grep -oi 'realm="[^"]*'|awk -F'"' '{print $2}'`
  fi

  # check for credentials
  if [[ -z $USER ]]
  then
    echo "You must specify a username with -U for this proxy!" 1>&2
    exit 1
  fi
  if [[ -z $PASS ]]
  then
    echo "You must specify a password with -P for this proxy!" 1>&2
    exit 1
  fi

  # now calculate digest auth info
  HA1=`echo -n "${USER}:${REALM}:${PASS}" | $MD5 | awk '{print $1}'`
  HA2=`echo -n "CONNECT:${HOST}:${PORT}" | $MD5 | awk '{print $1}'`
  RESPONSE=`echo -n "${HA1}:${NONCE}:${NC}:${CNONCE}:${QOP}:${HA2}" | $MD5 | awk '{print $1}'`
  PROXY_AUTHORIZATION="CONNECT ${HOST}:${PORT} HTTP/1.0
Host: ${HOST}:${PORT}
Proxy-Authorization: Digest username=\"${USER}\", realm=\"${REALM}\", nonce=\"${NONCE}\", uri=\"${HOST}:${PORT}\", cnonce=\"${CNONCE}\", nc=${NC}, qop=\"${QOP}\", response=\"${RESPONSE}\", algorithm=\"MD5\"
Proxy-Connection: Keep-Alive
"

  echo "${PROXY_AUTHORIZATION}" 1>&2
  (echo "${PROXY_AUTHORIZATION}"; cat) | nc -vv ${PROXY_HOST} ${PROXY_PORT} &
  # Get PID of nc process
# NCPID=$!
# echo $NCPID
# sleep 2
# if ! ps -p $NCPID
# then
# echo -n ''
# (echo "${PROXY_AUTHORIZATION}"; cat) | nc -vv ${PROXY_HOST} ${PROXY_PORT} &
# fi


else
  # alright, no auth required!
  echo "No auth required"
  (cat) | nc ${PROXY_HOST} ${PROXY_PORT}
fi
