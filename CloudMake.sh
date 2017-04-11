#!/bin/bash

portal=http://www.arcgis.com
appstudio=https://appstudio.arcgis.com
platform=win32
datestamp=$(date +%Y%m%d)
tmpfile=/tmp/cloudmake-$datestamp-$$.tmp

function showUsage {
  cat <<+
CloudMake.sh -i itemId
             -u username
             -p password
             -t platform (e.g. win32)
             -h help
+
}

while getopts "hi:u:p:t:" arg; do
  case $arg in
    h)
      showUsage
      exit 1
      ;;
    i)
      ITEMID=$OPTARG
      ;;
    u)
      USERNAME=$OPTARG
      ;;
    p)
      PASSWORD=$OPTARG
      ;;
    t)
      platform=$OPTARG
      ;;
  esac
done

if [ "$ITEMID" == "" ]; then
  echo "Missing itemId"
  echo
  showUsage
  exit 1
fi

if [ "$USERNAME" == "" ]; then
  echo "Missing username"
  echo
  showUsage
  exit 1
fi

if [ "$PASSWORD" == "" ]; then
  echo "Missing password"
  echo
  showUsage
  exit 1
fi

if [ "$platform" == "" ]; then
  echo "Missing platform"
  echo
  showUsage
  exit 1
fi

function json_get {
  python -c 'import json,sys
o=json.load(sys.stdin)
for a in "'$1'".split("."):
  o=o[a] if isinstance(o, dict) and a in o else ""
print o if isinstance(o, str) or isinstance(o, unicode) else json.dumps(o)
'
}

function getValues {
  for i in $*
  do
    n="${i//./_}"
    v="$(json_get $i < $tmpfile)"
    # echo "$n=$v"
    eval "$n=\"$v\""
  done
  # echo
}

function restApi {
  # echo curl $*
  # echo

  curl $* > $tmpfile

  # cat $tmpfile
  # echo
  # echo

  if [ "$(json_get error.code < $tmpfile)" != "" ]; then
    cat $tmpfile
    echo
    rm $tmpfile
    exit 1
  fi

  if [ "$(json_get errorCode < $tmpfile)" != "" ]; then
    cat $tmpfile
    echo
    rm $tmpfile
    exit 1
  fi

}

function generateToken {
  restApi -s $portal/sharing/rest/info?f=pjson

  getValues authInfo.tokenServicesUrl

  restApi -s $authInfo_tokenServicesUrl \
          -X POST \
          -d username=$USERNAME \
          -d password=$PASSWORD \
          -d referer=$portal \
          -d expiration=120 \
          -d f=pjson

  getValues token ssl expires
}

function getUserInfo {
  restApi -s $portal/sharing/rest/community/self\
\?f=pjson\
\&token=$token

  getValues fullName email
}

function getItemInfo {
  restApi -s $portal/sharing/rest/content/items/$ITEMID\
\?f=pjson\
\&token=$token

  getValues title

}

function submitBuild {
  restApi -s $appstudio/api/buildrequest \
          -X POST \
          -F itemId=$ITEMID \
          -F clientType=desktop \
          -F username=$USERNAME \
          -F email=$email \
          -F token=$token \
          -F verbose=false \
          -F emailNotifications=none \
          -F platforms=$platform \
          -F f=pjson

  getValues appBuildId
}

function pollBuild {
  echo

  until [ "$progress" == "1" ]
  do
    sleep 5

    restApi -s $appstudio/api/status\
\?appBuildId=$appBuildId\
\&token=$token\
\&f=pjson

    var_status=statusInfo.$platform.status
    var_progress=statusInfo.$platform.progress
    getValues $var_status $var_progress
    status=$(eval "echo \$${var_status//./_}")
    progress=$(eval "echo \$${var_progress//./_}")
    percent=$(awk '{printf "%0.1f\n", $1 * 100.0}' <<< $progress)

    echo -e -n "\033[A" 
    echo -e -n "\033[K" 
    echo "Building $title ($status $percent%)"

  done
}

generateToken
getUserInfo
getItemInfo
submitBuild
if [ "$appBuildId" == "" ]; then
  exit 1
fi
pollBuild

