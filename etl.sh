#!/bin/bash
#------------------------------------------------------------------------------------------------------------------#
# Written By Kyle Butler
#
# REQUIREMENTS: 
# Requires jq to be installed: 'sudo apt-get install jq'
#

source ./secrets/secrets
source ./func/func.sh




AUTH_PAYLOAD=$(cat <<EOF
{"username": "$PC_ACCESSKEY", "password": "$PC_SECRETKEY"}
EOF
)


PC_JWT_RESPONSE=$(curl --request POST \
                       --url "$PC_APIURL/login" \
                       --header 'Accept: application/json; charset=UTF-8' \
                       --header 'Content-Type: application/json; charset=UTF-8' \
                       --data "${AUTH_PAYLOAD}")

quick_check "/login"


PC_JWT=$(printf %s "$PC_JWT_RESPONSE" | jq -r '.token' )

CONFIG_SEARCH=$(cat <<EOF
{
  "query":"config from cloud.resource where api.name = 'aws-ec2-describe-instances'",
  "timeRange":{
     "type":"relative",
     "value":{
        "unit":"hour",
        "amount":24
     }
  }
}
EOF
)

CONFIG_RESPONSE=$(curl --request POST \
                       --url "$PC_APIURL/search/config" \
                       --header 'content-type: application/json; charset=UTF-8' \
                       --header "x-redlock-auth: $PC_JWT" \
                       --data "$CONFIG_SEARCH")


quick_check "/search/config"

printf '%s' "$CONFIG_RESPONSE" > './json/temp_config.json'
VULN_SEARCH=$(cat <<EOF
{
  "query":"config from cloud.resource where api.name = 'aws-ec2-describe-instances' AND finding.type IN ( 'Host Vulnerability' )",
  "timeRange":{
     "type":"relative",
     "value":{
        "unit":"hour",
        "amount":24
     }
  }
}
EOF
)

VULN_RESPONSE=$(curl --request POST \
                       --url "$PC_APIURL/search/config" \
                       --header 'content-type: application/json; charset=UTF-8' \
                       --header "x-redlock-auth: $PC_JWT" \
                       --data "$VULN_SEARCH")

quick_check "/search/config"


JSON_LOCATION=./json
VULN_RRN_ARRAY=( $(printf '%s' "$VULN_RESPONSE" | jq -r '.data.items[].rrn') )


for rrn in "${VULN_RRN_ARRAY[@]}"; do \
VULN_PAYLOAD=$(cat <<EOF
{
 "rrn": "$rrn",
 "findingType":[],
 "riskFactors":[]
}
EOF
)


VULN_FINDINGS=$(curl --request POST \
                     --url "$PC_APIURL/resource/external_finding" \
                     --header 'content-type: application/json; charset=UTF-8' \
                     --header 'accept: application/json, text/plain, */*' \
                     --header "x-redlock-auth: $PC_JWT" \
                     --data-raw "$VULN_PAYLOAD")

quick_check "/resource/external_finding"

printf '%s' "$VULN_FINDINGS" | jq '.[] | {normalizedName: .normalizedName, riskFactors: .riskFactors, findingId: .findingId, source: .source, severity: .severity, status: .status, resourceCloudId: .resourceCloudId}' >> "$JSON_LOCATION/temp_vuln.json"

done

#printf '%s' "$CONFIG_RESPONSE" > $JSON_LOCATION/temp_vm.json

# creates an array of vm names
VM_ARRAY=( $(printf '%s' "$CONFIG_RESPONSE" | jq -r '.data.items[].name') )




# makes a request of the permissions api endpoint to see if any of the vms in the array have permissions which are attached to them. 
for vm in "${VM_ARRAY[@]}"; do \
IAM_QUERY=$(cat <<EOF
{
  "searchId": null,
  "limit": 300,
  "query": "config from iam where source.cloud.resource.name = '$vm'"
}
EOF
)

IAM_QUERY_RESPONSE=$(curl --request POST \
                          --url "$PC_APIURL/api/v1/permission" \
                          --header 'content-type: application/json; charset=UTF-8' \
                          --header 'accept: application/json' \
                          --header "x-redlock-auth: $PC_JWT" \
                          --data "$IAM_QUERY")
quick_check "/api/v1/permission"


# dumps the IAM query response to a temp json file
printf '%s' "$IAM_QUERY_RESPONSE" |jq '.data.items[]?' >> "$JSON_LOCATION/temp_iam.json"


done

# combines the responses from the iam query and the config query on the name of the ec2 instance and the .sourceResourceName from the iam query. starts the transform
printf '%s' "$CONFIG_RESPONSE" | jq '[.data.items[] | {id: .id, name: .name, uid: ("_:" + .name), rrn: .rrn, imageId: .data.imageId, state: .data.state, licenses: .data.licenses, tags: .data.tags, networkInterfaces: .data.networkInterfaces, blockDeviceMappings: .data.blockDeviceMappings} ]| map({id, name, uid, rrn, imageId, state, licenses, tags, networkInterfaces, blockDeviceMappings, iam: [(.name as $name | $iamdata |..| select(.sourceResourceName? and .sourceResourceName==$name))]})' --slurpfile iamdata "$JSON_LOCATION/temp_iam.json" |\

jq '[.[] | {id: .id, name: .name, uid: .uid, rrn: .rrn, uid2: ("_:" + .rrn), imageId: .imageId, uid3: ("_:" + .imageId), networkInterfaces: [.networkInterfaces[] | {vpcId: .vpcId, groups: [.groups[] | {groupId: .groupId, groupName: .groupName} ], status: .status, ownerId: .ownerId, attachment: {status: .attachment.status, attachTime: .attachment.attachTime, attachmentId: .attachment.attachmentId, uid8: ("_:" + .attachment.attachmentId), networkCardIndex: .attachment.networkCardIndex, deleteOnTermination: .attachment.deleteOnTermination}, macAddress: .macAddress, uid9: ("_:" + .macAddress), interfaceType: .interfaceType, ipv6Addresses: .ipv6Addresses , privateDnsName: .privateDnsName, uid10: ("_:" + .privateDnsName), sourceDestCheck: .sourceDestCheck, privateIpAddress: .privateIpAddress, networkInterfaceId: .networkInterfaceId, privateIpAddresses: [.privateIpAddresses[] | {primary: .primary, privateDnsName: .privateDnsName, privateIpAddress: .privateIpAddress, association: {publicIp: .association.publicIp?, ipOwnerId: .association.ipOwnerId?, publicDnsName: .association.publicDnsName?}} ] }], blockDeviceMappings: [.blockDeviceMappings[] | {ebs: {status: .ebs.status, volumeId: .ebs.volumeId, uid12: ("_:" + .ebs.volumeId), attachTime: .ebs.attachTime, deleteOnTermination: .ebs.deleteOnTermination}} ], iam: .iam} ]' > "$JSON_LOCATION/temp_config_iam.json"


# combines the three responses together and merges the json on the id from the config response and the resourceCloudId on the vulnerability response
cat "$JSON_LOCATION/temp_config_iam.json" | jq '. | map({id, name,uid, rrn, uid2,imageId, uid3, networkInterfaces, blockDeviceMappings, iam, vulnerability: [(.id as $id | $vulndata |..| select( .resourceCloudId? and .resourceCloudId==$id ))]})' --slurpfile vulndata "$JSON_LOCATION/temp_vuln.json" | jq '{set: .}' > "$JSON_LOCATION/done.json"

# fixes the key value pairs getting it ready for import to dgraph
sed -i 's/uid[0-9]\{0,9\}/uid/g' "$JSON_LOCATION/done.json"


# load the data into the alpha mutate endpoint
curl -H "content-type: application/json" \
     -X POST \
     --url "localhost:8080/mutate?commitNow=true" \
     --data-binary @"$JSON_LOCATION/done.json"


quick_check "/mutate?/commitNow=true"


exit
