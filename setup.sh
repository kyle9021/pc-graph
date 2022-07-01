#!/bin/bash
# written by Kyle Butler


source ./func/func.sh
source ./secrets/secrets


printf '\n%s\n%s\n%s\n'  "This script will set up your secrets file in the ./secrets directory and modify the permissions so the user running it will be the only one who can modify the file." \
                          "It will also verify you have the proper dependencies and ensure an api token can be retrieved." \
                          "It will override any existing file you have in the .secrets/secrets directory"

printf '\n%s\n' "Would you like to continue?"
read -r ANSWER

if [ "$ANSWER" != "${ANSWER#[Yy]}" ]
  then
    printf '\n%s\n\n' "checking dependencies..."
  else
    exit
fi

if ! command -v jq > /dev/null 2>&1; then
    printf '\n%s\n%s\n' "ERROR: Jq is not available." \
                        "These scripts require jq, please install and try again."
    exit 1
fi

if ! command -v curl -V > /dev/null 2>&1; then
      printf '\n%s\n%s\n' "ERROR: curl is not available." \
                          "These scripts require jq, please install and try again."
      exit 1
fi

if ! docker info > /dev/null 2>&1
  then
    printf '%s\n%s\n' "ERROR: docker is not available or not runnning." \
                      "This script requires docker, please install and try again."
    exit 1
fi
if ! docker-compose version > /dev/null 2>&1
  then
    printf '%s\n%s\n' "ERROR: docker-compose is not available or not runnning." \
                      "This script requires docker-compose, please install and try again."
    exit 1
fi



printf '\n%s\n\n' "dependency check passed...checking secret file"




PATH_TO_SECRETS_FILE="./secrets/secrets"

if [ ! -f "$PATH_TO_SECRETS_FILE" ]
  then
      printf '\n%s\n' "creating secrets file"
      touch $PATH_TO_SECRETS_FILE
fi


if [ -z "$PC_SECRETKEY" ] || [ -z "$PC_ACCESSKEY" ] || [ -z "$PC_APIURL" ];
  then
        printf '\n%s\n' "Is it okay to reconfigure the ./secrets/secrets file?"
        read -r VERIFY
        if [ "$VERIFY" != "${VERIFY#[Yy]}" ]
          then
            printf '\n%s\n\n' "checking variable assignement..."
          else
            exit
        fi
        printf '\n%s\n' "enter your prisma cloud access key id:"
        read -r PC_ACCESSKEY
        printf '\n%s\n' "enter your prisma cloud secret key id:"
        read -r -s PC_SECRETKEY
        printf '\n%s\n' "enter your prisma cloud api url (found here https://prisma.pan.dev/api/cloud/api-urls):"
        read -r PC_APIURL
        pce-var-check
fi

AUTH_PAYLOAD=$(cat <<EOF
{"username": "$PC_ACCESSKEY", "password": "$PC_SECRETKEY"}
EOF
)


PC_JWT_RESPONSE=$(curl -s --request POST \
                       --url "$PC_APIURL/login" \
                       --header 'Accept: application/json; charset=UTF-8' \
                       --header 'Content-Type: application/json; charset=UTF-8' \
                       --data "${AUTH_PAYLOAD}")


PC_JWT=$(printf %s "$PC_JWT_RESPONSE" | jq -r '.token' )


if [ -z "$PC_JWT" ]
  then
      printf '\n%s\n' "Prisma Cloud Enterprise CSPM api token not retrieved, have you verified the expiration date of the access key and secret key? Have you verified connectivity to the url provided? Troubleshoot and then you'll need to run this script again"
      exit 1
  else
     printf '\n%s\n' "Token retrieved, access key, secret key, and prisma cloud enterprise edition api url are valid"
fi






printf '%s\n%s\n%s\n%s\n' "#!/usr/bin/env bash" \
                          "PC_APIURL=\"$PC_APIURL\"" \
                          "PC_ACCESSKEY=\"$PC_ACCESSKEY\"" \
                          "PC_SECRETKEY=\"$PC_SECRETKEY\"" > "$PATH_TO_SECRETS_FILE"



chmod 700 ./secrets/secrets


printf '%s\n\n\n' "beginning dgraph deployment"


docker-compose up -d


printf '%s\n\n\n%s\n\n\n%s\n\n' 'dgraph, ratel, and alpha are up!' 'Starting etl...' 'This could take a while to retrieve the data from Prisma Cloud'

sleep 5

{
bash ./etl.sh
}


GRAPHQL_QUERY=$(cat <<EOF
{
  vm(func: has(name), first: 100){
    rrn
    name
    imageId
    vpc_id:  networkInterfaces {
      vpcId
    security_group:  groups {
        groupId
      }
    network_association:  privateIpAddresses {
      publicIp:  association {
          publicIp
        }
      }
    }
    blockDeviceMappings {
    ebs_volume:  ebs {
        volumeId
      }
    }
    iam_permissions: iam {
     sourceCloudResourceRrn
     sourceResourceName
     destCloudServiceName
    }
    vulnerability {
      normalizedName
    }
  }
}
EOF
)

printf '\n\n\n%s\n\n%s\n\n\n%s\n\n\n%s\n\n' 'Ready! Open a browser and navigate to: http://localhost:8001/?local' \
                                            'Copy and paste the query below in the query section and then hit run:' \
                                            "$GRAPHQL_QUERY" \
                                            'Make sure to hit the expand all nodes and to look at the legend in the bottom. You can now start applying filters'



exit
