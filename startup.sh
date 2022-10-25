#!/bin/sh

set -e
#set -x

if [ -d "/opt/ejabberd/external-auth" ]; then
  cd /opt/ejabberd/external-auth

  # Let's find the user to use for commands.
  # If $DOCKER_USER, let's use this. Otherwise, let's find it.
  if [[ "$DOCKER_USER" == "" ]]; then
      # On MacOSX, the owner of the current directory can be completely random (it can be root or docker depending on what happened previously)
      # But MacOSX does not enforce any rights (the docker user can edit any file owned by root).
      # On Windows, the owner of the current directory is root if mounted
      # But Windows does not enforce any rights either

      # Let's make a test to see if we have those funky rights.
      set +e
      mkdir testing_file_system_rights.foo
      chmod 700 testing_file_system_rights.foo
      su ejabberd -c "touch testing_file_system_rights.foo/somefile > /dev/null 2>&1"
      HAS_CONSISTENT_RIGHTS=$?

      if [[ "$HAS_CONSISTENT_RIGHTS" != "0" ]]; then
          # If not specified, the DOCKER_USER is the owner of the current working directory (heuristic!)
          DOCKER_USER=`ls -dl $(pwd) | cut -d " " -f 3`
      else
          # we are on a Mac or Windows,
          # Most of the cases, we don't care about the rights (they are not respected)
          FILE_OWNER=`ls -dl testing_file_system_rights.foo/somefile | cut -d " " -f 3`
          if [[ "$FILE_OWNER" == "root" ]]; then
              # if the created user belongs to root, we are likely on a Windows host.
              # all files will belong to root, but it does not matter as everybody can write/delete those (0777 access rights)
              DOCKER_USER=ejabberd
          else
              # In case of a NFS mount (common on MacOS), the created files will belong to the NFS user.
              # Apache should therefore have the ID of this user.
              DOCKER_USER=$FILE_OWNER
          fi
      fi

      rm -rf testing_file_system_rights.foo
      set -e

      unset HAS_CONSISTENT_RIGHTS
  fi

  # DOCKER_USER is a user name if the user exists in the container, otherwise, it is a user ID (from a user on the host).

  # If DOCKER_USER is an ID, let's
  if echo "$DOCKER_USER" | grep -Eq '^[0-9]+$'; then
      # MAIN_DIR_USER is a user ID.
      # Let's change the ID of the docker user to match this free id!
      #echo Switching docker id to $DOCKER_USER
      usermod -u $DOCKER_USER -G ejabberd ejabberd;
      #echo Switching done
      DOCKER_USER=ejabberd
  fi


  #echo "Docker user: $DOCKER_USER"
  DOCKER_USER_ID=`id -ur $DOCKER_USER`
  #echo "Docker user id: $DOCKER_USER_ID"

  sudo "-E" "-H" "-u" "#$DOCKER_USER_ID" "composer" "install";
fi

cd /opt/ejabberd

if [[ ${JWT_SECRET:-"unset"} != "unset" ]]; then
  JWT_SECRET_BASE64=$(echo -ne "$JWT_SECRET" | base64);
  jo -p kty=oct use=sig k="$JWT_SECRET_BASE64" alg=HS256 > /opt/ejabberd/conf/jwt_key
else
  echo "Environment variable JWT_SECRET key is not defined"
  exit 1
fi

# Check if all variables used in the template is defined or not
grep -o '\${[0-9A-Za-z_]*}' /opt/ejabberd/conf/ejabberd.template.yml | while read line
do
    line=$(echo "$line" | sed 's/^..//' | sed 's/.$//')
    if [[ -z `printenv $line` ]]; then
      echo "Environment variable $line key is not defined"
      exit 1
    fi
done

exit 1

envsubst < /opt/ejabberd/conf/ejabberd.template.yml > /opt/ejabberd/conf/ejabberd.yml
if [[ ${DB_HOST:-"unset"} != "unset" ]]; then
  dbmate -u "mysql://ejabberd:$DB_PASSWORD@$DB_HOST:3306/ejabberd" up
fi

# Warning, this is needed in dev but might take a long time if we have a lot of files in prod (?)
chown ejabberd:ejabberd -R /opt/ejabberd

exec "sudo" "-E" "-H" "-u" "ejabberd" "ejabberdctl" "$@";