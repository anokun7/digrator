#!/bin/bash

source ./migrate.conf

>/var/tmp/accounts
>/var/tmp/repos
>/var/tmp/dest_accounts
>/var/tmp/dest_repos

getAllAccounts() {
  curl -s --user \
    "$SOURCE_DTR_ADMIN":"$SOURCE_DTR_PASSWORD" --insecure \
    https://"$SOURCE_DTR_DOMAIN"/api/v0/repositories?limit=$SOURCE_NO_OF_REPOS | \
      jq '.repositories[] | { (.namespaceType):(.namespace)  }' | grep -v '[{}]' | grep -v admin
}

getAllRepos() {
  curl -s --user \
    "$SOURCE_DTR_ADMIN":"$SOURCE_DTR_PASSWORD" --insecure \
    https://"$SOURCE_DTR_DOMAIN"/api/v0/repositories?limit=$SOURCE_NO_OF_REPOS | \
      jq '.repositories[] | {  (.namespace):(.name) }' | grep -v '[{}]' | \
          sed -e 's/:\s*/\//' -e 's/\s*"\s*//g'
}

getTagsPerRepo() {
  curl -s --user \
    "$SOURCE_DTR_ADMIN":"$SOURCE_DTR_PASSWORD" --insecure \
    https://"$SOURCE_DTR_DOMAIN"/api/v0/repositories/${1}/tags | \
          jq '. | { (.name): .tags[].name }' | grep -v '[{}]' | sed 's/[" ]//g'
}

getAllTags() {
  cat /var/tmp/repos | sort -u | while IFS= read -r i;
    do
      getTagsPerRepo $i
    done
}

pullImages() {
  echo "###  Downloading images from https://$SOURCE_DTR_DOMAIN/"
  for i in `getAllTags`
    do
     docker pull $SOURCE_DTR_DOMAIN/$i
     docker tag $SOURCE_DTR_DOMAIN/$i $DEST_DTR_DOMAIN/$i
   done
}

createNameSpaces() {
  echo "###  Creating namespaces (Orgs & Users) to host repositories on https://$DEST_DTR_DOMAIN/"
  for i in `getAllAccounts`
    do
      sed -e '/"user":/s/^\s*"\(.*\)":\s*"\(.*\)"/{"type": "\1", "name": "\2", "password": "\2123456"}/' \
          -e '/"organization":/s/^\s*"\(.*\)":\s*"\(.*\)"/{"type": "\1", "name": "\2"}/' \
          /var/tmp/accounts > /var/tmp/dest_accounts
    done

  cat /var/tmp/dest_accounts | sort -u | while IFS= read -r i;
    do
      curl --insecure --user "$DEST_DTR_ADMIN":"$DEST_DTR_PASSWORD" -X POST --header "Content-Type: application/json" \
         --header "Accept: application/json" -d "$i" https://"$DEST_DTR_DOMAIN"/enzi/v0/accounts
    done
}

createRepos() {
  echo "###  Creating repositories under their corresponding namespaces on https://$DEST_DTR_DOMAIN/"
  cat /var/tmp/repos | sort -u | while IFS= read -r i;
    do
      sed 's^/\(.*\)$^/{"name": "\1", "visibility": "public" }^' /var/tmp/repos > /var/tmp/dest_repos
    done

  cat /var/tmp/dest_repos | sort -u | while IFS= read -r i;
    do
      curl --insecure --user "$DEST_DTR_ADMIN":"$DEST_DTR_PASSWORD" -X POST --header "Content-Type: application/json" \
        --header "Accept: application/json" -d "`echo $i | awk -F/ '{ print $2 }'`" \
        "https://"$DEST_DTR_DOMAIN"/api/v0/repositories/`echo $i | awk -F/ '{ print $1 }'`"
    done
}

pushImages() {
  echo "###  Pushing (Uploading) images to https://$DEST_DTR_DOMAIN/"
  for i in `getAllTags`
    do
      docker push $DEST_DTR_DOMAIN/$i
    done
}

echo "###  Fetching all repositories from https://$SOURCE_DTR_DOMAIN/"
getAllRepos > /var/tmp/repos
echo "###  Fetching all tags for each repository from https://$SOURCE_DTR_DOMAIN/"
pullImages
echo "###  Getting all Orgs & Users that have at least one repository in their namespace, from https://$SOURCE_DTR_DOMAIN/"
getAllAccounts > /var/tmp/accounts
createNameSpaces
createRepos
pushImages
