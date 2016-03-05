#!/bin/bash

source ./migrate.conf

getAllAccounts() {
  curl -s --user \
  	"$SOURCE_DTR_ADMIN":"$SOURCE_DTR_PASSWORD" --insecure \
  	https://"$SOURCE_DTR_DOMAIN"/api/v0/repositories | \
  		jq '.repositories[] | { (.namespaceType):(.namespace)  }' | grep -v '[{}]' | grep -v admin
}

getAllRepos() {
  curl -s --user \
  	"$SOURCE_DTR_ADMIN":"$SOURCE_DTR_PASSWORD" --insecure \
  	https://"$SOURCE_DTR_DOMAIN"/api/v0/repositories | \
  		jq '.repositories[] | {  (.namespace):(.name) }' | grep -v '[{}]' | sed -e 's/:\s*/\//' -e 's/\s*"\s*//g' 
}

getTagsPerRepo() {
  curl -s --user \
  	"$SOURCE_DTR_ADMIN":"$SOURCE_DTR_PASSWORD" --insecure \
  	https://"$SOURCE_DTR_DOMAIN"/api/v0/repositories/${1}/tags | \
          jq '. | { (.name): .tags[].name }' | grep -v '[{}]' | sed 's/[" ]//g'
}

pullImages() {
  for i in `getAllTags`
    do
     docker pull $SOURCE_DTR_DOMAIN/$i 
     docker tag $SOURCE_DTR_DOMAIN/$i $DEST_DTR_DOMAIN/$i
   done
}

createNameSpaces() {
  for i in `getAllAccounts`
    do
      sed -e '/"user":/s/^\s*"\(.*\)":\s*"\(.*\)"/{"type": "\1", "name": "\2", "password": "\2123"}/' \
          -e '/"organization":/s/^\s*"\(.*\)":\s*"\(.*\)"/{"type": "\1", "name": "\2"}/' \
          /var/tmp/accounts > /var/tmp/dest_accounts
    done

  cat /var/tmp/dest_accounts | sort -u | while IFS= read -r i;
    do
      curl --insecure --user "$DEST_DTR_ADMIN":"$DEST_DTR_PASSWORD" -X POST --header "Content-Type: application/json" \
         --header "Accept: application/json" --header "X-Csrf-Token: lCag00CgWAlVzYuTNCinQbbDYqvfo2b6-W1zpvyY52S0=" \
         -d "$i" https://"$DEST_DTR_DOMAIN"/api/v0/accounts
    done
}
      
getAllTags() {
  cat /var/tmp/repos | sort -u | while IFS= read -r i;
    do
      getTagsPerRepo $i
    done
}

createRepos() {
  cat /var/tmp/repos | sort -u | while IFS= read -r i;
    do
      sed 's^/\(.*\)$^/{"name": "\1", "visibility": "public" }^' /var/tmp/repos > /var/tmp/dest_repos
    done

  cat /var/tmp/dest_repos | sort -u | while IFS= read -r i;
    do
      curl --insecure --user "$DEST_DTR_ADMIN":"$DEST_DTR_PASSWORD" -X POST --header "Content-Type: application/json" \
        --header "Accept: application/json" --header "X-Csrf-Token: jaYLzzlpH1SB0uv217SExOfwK8t-7QdXA6PymflfOOs=" \
        -d "`echo $i | awk -F/ '{ print $2 }'`" "https://"$DEST_DTR_DOMAIN"/api/v0/repositories/`echo $i | awk -F/ '{ print $1 }'`"
    done
}

pushImages() {
  for i in `getAllTags`
    do
      docker push $DEST_DTR_DOMAIN/$i
    done
}

getAllRepos > /var/tmp/repos
pullImages
getAllAccounts > /var/tmp/accounts
createNameSpaces
createRepos
pushImages
