#!/usr/bin/env bash
# written by Kyle Butler
# SELF-HOSTED when deployed with a self-signed cert this script requires:  -k or --insecure with the curl commands

source ./secrets/secrets
source ./func/func.sh


# TODO Incorporate this block into the setup script

printf '\n%s\n' "Are you wanting to request data from the self-hosted version of prisma cloud compute? (y/n)"
read -r VERSION_QUESTION
  if [ "$VERSION_QUESTION" != "${VERSION_QUESTION#[Yy]}" ]
    then
       COMPUTE_SELF_HOSTED="TRUE"
     else
       COMPUTE_SELF_HOSTED="FALSE"
  fi

if [[ $COMPUTE_SELF_HOSTED == "TRUE" ]]
  then
    printf '\n%s\n' "enter your prisma compute username:"
    read -r  TL_USER
    printf '\n%s\n' "enter your prisma compute username password:"
    read -r -s  TL_PASSWORD
    printf '\n%s\n' "Enter your prisma cloud compute console FQDN with https:// and port if different than 443. Example: https://example.prisma-compute-lab.com:8083"
    read -r TL_CONSOLE
    printf '\n%s\n' "NOTE: You'll need to modify the script prior to running and add -k or --insecure to each curl command if using a self-hosted version of platform with a self-signed certificate"
  else
    printf '\n%s\n' "enter your prisma cloud compute api url (found under compute > settings > system > utilities):"
    read -r TL_CONSOLE
    TL_USER=$PC_ACCESSKEY
    TL_PASSWORD=$PC_SECRETKEY
fi




JSON_LOCATION=./json


AUTH_PAYLOAD=$(cat <<EOF
{"username": "$TL_USER", "password": "$TL_PASSWORD"}
EOF
)



# add -k to curl if using self-hosted version with a self-signed cert
TL_JWT_RESPONSE=$(curl -s --request POST \
                       --url "$TL_CONSOLE/api/v1/authenticate" \
                       --header 'Content-Type: application/json' \
                       --data "$AUTH_PAYLOAD")

quick_check "/api/v1/authenticate"

TL_JWT=$(printf %s "$TL_JWT_RESPONSE" | jq -r '.token' )





WAAS_POLICY_RESPONSE=$(curl --request GET \
                            --url "$TL_CONSOLE/api/v1/policies/firewall/app/container?project=Central+Console" \
                            --header 'Accept: application/json, text/plain, */*' \
                            --header "Authorization: Bearer $TL_JWT")

quick_check "/api/v1/policies/firewall/app/container?project=Central+Console"

printf '%s' "$WAAS_POLICY_RESPONSE" | jq '{set: .rules} | {set: [.set[]| {modified: .modified, owner: .owner,ruleName: .name, uid: ("_:" + .name), previousName: .previousName, collections: .collections[] |{hosts: .hosts[] |[ {hostName: ., uid3: ("_:" + .)}], images: .images[] |[ {imageName: ., uid4: ("_:" + .)}], labels: .labels[] |[ {labelName: ., uid5: ("_:" + .)}], containers: .containers[] |[ {containerName: ., uid6: ("_:" + .)}], functions: .functions[] |[ {functionName: ., uid7: ("_:" + .)}], namespaces: .namespaces[] |[ {namespaceName: ., uid8: ("_:" + .)}], appIDs: .appIDs[] |[ {appIDName: ., uid9: ("_:" + .)}], accountIDs: .accountIDs[] |[ {accountIDName: ., uid10: ("_:" + .)}], codeRepos: .codeRepos[] |[ {codeRepoName: ., uid11: ("_:" + .)}], clusters: .clusters[] |[ {clusterName: ., uid12: ("_:" + .)}] }, applicationsSpec: [.applicationsSpec[] |{appID: .appID, uid2: ("_:" + .appID), banDurationMinutes: .banDurationMinutes, certificate: .certificate, tlsConfig: .tlsConfig, dosConfig: .dosConfig | {enabled: .enabled, alert: .alert, ban: .ban}, apiSpec: .apiSpec | {endpoints: .endpoints, paths: [.paths[]? | {requestPath: .path, methods: .methods[]? |{requestMethod: .method, parameters: [.parameters[]?]}}], effect: .effect, fallbackEffect: .fallbackEffect, queryParamFallbackEffect: .queryParamFallbackEffect, skipLearning: .skipLearning}, botProtectionSpec: .botProtectionSpec, networkControls: .networkControls, body: .body, intelGathering: .intelGathering, maliciousUpload: .maliciousUpload, csrfEnabled: .csrfEnabled, clickjackingEnabled: .clickjackingEnabled, sqli: .sqli, lfi: .lfi, codeInjection: .codeInjection, remoteHostForwarding: .remoteHostForwarding} ]}]}' > $JSON_LOCATION/waas.json


sed -i 's/uid[0-9]\{0,9\}/uid/g' "$JSON_LOCATION/waas.json"

curl -H "content-type: application/json" \
     -X POST \
     --url "localhost:8080/mutate?commitNow=true" \
     --data-binary @"$JSON_LOCATION/waas.json"

quick_check "/mutate?commitNow=true"

GRAPHQL_QUERY=$(cat <<EOF
{
  waasrule(func: has(ruleName)){
  ruleName
  owner
  collections {
    hosts {}
    images {imageName}
    containers {}
    functions {}
    namespaces {}
    appIds {}
    accountIDs {}
    codeRepos {}
    clusters {}
  }
    applicationsSpec {
      appID
      apiSpec {
        endpoints {}
       paths {
        requestPath {}
        methods {
          requestMethod
          parameters {}
        }
      }
      }
    }
  }
}
EOF
)

printf '\n\n\n%s\n\n%s\n\n\n%s\n\n\n%s\n\n\n%s' "WAAS policy extracted transformed and loaded" \
                                                'Open a browser and navigate to: http://localhost:8001/?local' \
                                                'Copy and paste the query below in the query section and then hit run:' \
                                                "$GRAPHQL_QUERY" \
                                                'Make sure to hit the expand all nodes and to look at the legend in the bottom. You can now start applying filters'

