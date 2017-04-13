#!/bin/bash 

datestamp=$(date +%Y%m%d)
tmpfile=/tmp/cloudmake-$datestamp-$$.tmp

function showUsage {
  cat <<+
CloudMake.sh -itemid    ITEMID
             -username  USERNAME
             -password  PASSWORD
             -platform  PLATFORM (e.g. win32)
             -appstudio AppStudio Cloud Make REST API (e.g. https://appstudio.arcgis.com)
             -h help
+
}

while [ "$1" != "" ]
do
  case "$1" in
  -itemid)
    shift
    ITEMID=$1
    ;;
  -platform | -p)
    shift
    PLATFORM=$1
    ;;
  -username)
    shift
    USERNAME=$1
    ;;
  -password)
    shift
    PASSWORD=$1
    ;;
  -appstudio)
    shift
    APPSTUDIO=$1
    ;;
  -h )
    showUsage
    exit 0
    ;;
  *)
    echo "Skipping $1"
    ;;
  esac
  shift
done

if [ "$PORTAL" == "" ]; then
  PORTAL=http://www.arcgis.com
fi

if [ "$APPSTUDIO" == "" ]; then
  APPSTUDIO=https://appstudio.arcgis.com
fi

if [ "$ITEMID" == "" ]; then
  echo "Missing ITEMID"
  echo
  showUsage
  exit 1
fi

if [ "$USERNAME" == "" ]; then
  echo "Missing USERNAME"
  echo
  showUsage
  exit 1
fi

if [ "$PASSWORD" == "" ]; then
  echo "Missing PASSWORD"
  echo
  showUsage
  exit 1
fi

if [ "$PLATFORM" == "" ]; then
  echo "Missing PLATFORM"
  echo
  showUsage
  exit 1
fi

function jsonPrint {
  python -m json.tool
}

function jsonGet {
  python -c 'import json,sys
o=json.load(sys.stdin)
for a in "'$1'".split("."):
  if isinstance(o, dict):
    o=o[a] if a in o else ""
  elif isinstance(o, list):
    if a == "length":
      o=str(len(o))
    elif a == "join":
      o=",".join(o)
    else:
      o=o[int(a)]
  else:
    o=""
if isinstance(o, str) or isinstance(o, unicode):
  print o
else:
  print json.dumps(o)
'
}

function jsonGetValues {
  for i in $*
  do
    n="${i//./_}"
    v="$(jsonGet $i < $tmpfile)"
    # echo "$n=$v"
    eval "$n=\"$v\""
  done
  # echo
}

function restApi {
  args=()
  vars=()
  while [ "$1" != "" ]
  do
    if [ "$1" == "--output" ]; then
      shift
      vars+=("$1")
    else
      args+=("$1")
    fi
    shift
  done

  # echo curl "${args[@]}"

  curl "${args[@]}" > $tmpfile
  # echo

  # cat $tmpfile
  # echo
  # echo

  if [ "$(jsonGet error.code < $tmpfile)" != "" ]; then
    cat $tmpfile
    echo
    rm $tmpfile
    exit 1
  fi

  if [ "$(jsonGet errorCode < $tmpfile)" != "" ]; then
    cat $tmpfile
    echo
    rm $tmpfile
    exit 1
  fi

  jsonGetValues "${vars[@]}"
}

function generateToken {
  restApi -s $PORTAL/sharing/rest/info?f=pjson \
          --output authInfo.tokenServicesUrl

  restApi -s $authInfo_tokenServicesUrl \
          -X POST \
          -d username=$USERNAME \
          -d password=$PASSWORD \
          -d referer=$PORTAL \
          -d expiration=120 \
          -d f=pjson \
	  --output token \
	  --output ssl \
	  --output expires
}

function getUserInfo {
  restApi -s $PORTAL/sharing/rest/community/self\
\?f=pjson\
\&token=$token \
          --output fullName \
          --output email
}

function getItemInfo {
  restApi -s $PORTAL/sharing/rest/content/items/$ITEMID\
\?f=pjson\
\&token=$token \
          --output title

}

function submitBuild {
  restApi -s $APPSTUDIO/api/buildrequest \
          -X POST \
          -F itemId=$ITEMID \
          -F clientType=desktop \
          -F username=$USERNAME \
          -F email=$email \
          -F token=$token \
          -F verbose=false \
          -F emailNotifications=none \
          -F platforms=$PLATFORM \
          -F f=pjson \
	  --output appBuildId
}

function pollBuild {
  echo

  until [ "$progress" == "1" ]
  do
    sleep 5

    restApi -s $APPSTUDIO/api/status\
\?appBuildId=$appBuildId\
\&token=$token\
\&f=pjson

    var_status=statusInfo.$PLATFORM.status
    var_progress=statusInfo.$PLATFORM.progress
    jsonGetValues $var_status $var_progress
    status=$(eval "echo \$${var_status//./_}")
    progress=$(eval "echo \$${var_progress//./_}")
    percent=$(awk '{printf "%0.1f\n", $1 * 100.0}' <<< $progress)
    rm $tmpfile

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
  if [ -f "$tmpfile" ]; then
    rm "$tmpfile"
  fi
  exit 1
fi
pollBuild

if [ -f "$tmpfile" ]; then
  rm "$tmpfile"
fi

