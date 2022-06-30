#!/usr/bin/env bash
#------------------------------------------------------------------------------------------------------------------#
# Written By Kyle Butler
#
# REQUIREMENTS: 
# Requires jq to be installed: 'sudo apt-get install jq'
#

source ./secrets/secrets
source ./func/func.sh



JSON_LOCATION=./json
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

printf '%s' "$CONFIG_RESPONSE" > "$JSON_LOCATION/temp_config.json"
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


VULN_RRN_ARRAY=( $(printf '%s' "$VULN_RESPONSE" | jq -r '.data.items[].rrn') )

printf '%s\n' "Pulling vulnerability data..."

for rrn in "${!VULN_RRN_ARRAY[@]}"; do \
VULN_PAYLOAD=$(cat <<EOF
{
 "rrn": "${VULN_RRN_ARRAY[rrn]}",
 "findingType":[],
 "riskFactors":[]
}
EOF
)


curl -s --request POST \
     --url "$PC_APIURL/resource/external_finding" \
     --header 'content-type: application/json; charset=UTF-8' \
     --header 'accept: application/json, text/plain, */*' \
     --header "x-redlock-auth: $PC_JWT" \
     --data-raw "$VULN_PAYLOAD" > "$JSON_LOCATION/vuln_data/$(printf '%05d' "$rrn").json" &

done
wait

printf '%s\n' "Vulnerability data pulled...."
cat ./json/vuln_data/* | jq '.[] | {normalizedName: .normalizedName, riskFactors: .riskFactors, findingId: .findingId, source: .source, severity: .severity, status: .status, resourceCloudId: .resourceCloudId}' > "$JSON_LOCATION/temp_vuln.json"
wait
rm ./json/vuln_data/*


# creates an array of vm names
VM_ARRAY=( $(printf '%s' "$CONFIG_RESPONSE" | jq -r '.data.items[].name') )



printf '%s\n' "Pulling IAM permission data...."
# makes a request of the permissions api endpoint to see if any of the vms in the array have permissions which are attached to them. 
for vm in "${!VM_ARRAY[@]}"; do \



IAM_QUERY=$(cat <<EOF
{
  "searchId": null,
  "limit": 300,
  "query": "config from iam where source.cloud.resource.name = '${VM_ARRAY[vm]}'"
}
EOF
)

curl -s --request POST \
     --url "$PC_APIURL/api/v1/permission" \
     --header 'content-type: application/json; charset=UTF-8' \
     --header 'accept: application/json' \
     --header "x-redlock-auth: $PC_JWT" \
     --data "$IAM_QUERY" > "$JSON_LOCATION/iam/$(printf '%05d' "$vm").json" &

done

wait
printf '%s\n' "IAM permission data pulled"
cat ./json/iam/* | jq '.data.items[]?' > "$JSON_LOCATION/temp_iam.json"
wait
rm ./json/iam/*

printf '%s\n' "Getting the data ready for import..."





# combines the responses from the iam query and the config query on the name of the ec2 instance and the .sourceResourceName from the iam query. starts the transform
printf '%s' "$CONFIG_RESPONSE" | jq '[.data.items[] | {id: .id, name: .name, uid: ("_:" + .name), rrn: .rrn, imageId: .data.imageId, state: .data.state, licenses: .data.licenses, tags: .data.tags, networkInterfaces: .data.networkInterfaces, blockDeviceMappings: .data.blockDeviceMappings} ]| map({id, name, uid, rrn, imageId, state, licenses, tags, networkInterfaces, blockDeviceMappings, iam: [(.name as $name | $iamdata |..| select(.sourceResourceName? and .sourceResourceName==$name))]})' --slurpfile iamdata "$JSON_LOCATION/temp_iam.json" |\

jq '[.[] | {id: .id, name: .name, uid: .uid, rrn: .rrn, uid2: ("_:" + .rrn), imageId: .imageId, uid3: ("_:" + .imageId), networkInterfaces: [.networkInterfaces[] | {vpcId: .vpcId, groups: [.groups[] | {groupId: .groupId, uid5: ("_:" + .groupId), groupName: .groupName, uid6: ("_:" + .groupName)} ], status: .status, ownerId: .ownerId, uid7: ("_:" + .ownerId), attachment: {status: .attachment.status, attachTime: .attachment.attachTime, attachmentId: .attachment.attachmentId, uid8: ("_:" + .attachment.attachmentId), networkCardIndex: .attachment.networkCardIndex, deleteOnTermination: .attachment.deleteOnTermination}, macAddress: .macAddress, uid9: ("_:" + .macAddress), interfaceType: .interfaceType, ipv6Addresses: .ipv6Addresses , privateDnsName: .privateDnsName, uid10: ("_:" + .privateDnsName), sourceDestCheck: .sourceDestCheck, privateIpAddress: .privateIpAddress, networkInterfaceId: .networkInterfaceId, uid11: ("_:" + .networkInterfaceId ), privateIpAddresses: [.privateIpAddresses[] | {primary: .primary, privateDnsName: .privateDnsName, privateIpAddress: .privateIpAddress, association: {publicIp: .association.publicIp?, ipOwnerId: .association.ipOwnerId?, publicDnsName: .association.publicDnsName?}} ] }], blockDeviceMappings: [.blockDeviceMappings[] | {ebs: {status: .ebs.status, volumeId: .ebs.volumeId, uid12: ("_:" + .ebs.volumeId), attachTime: .ebs.attachTime, deleteOnTermination: .ebs.deleteOnTermination}} ], iam: .iam} ]' > "$JSON_LOCATION/temp_config_iam.json"


# combines the three responses together and merges the json on the id from the config response and the resourceCloudId on the vulnerability response
cat "$JSON_LOCATION/temp_config_iam.json" | jq '. | map({id, name,uid, rrn, uid2,imageId, uid3, networkInterfaces, blockDeviceMappings, iam, vulnerability: [(.id as $id | $vulndata |..| select( .resourceCloudId? and .resourceCloudId==$id ))]})' --slurpfile vulndata "$JSON_LOCATION/temp_vuln.json" | jq '{set: .}' > "$JSON_LOCATION/done.json"

# fixes the key value pairs getting it ready for import to dgraph
sed -i 's/uid[0-9]\{0,9\}/uid/g' "$JSON_LOCATION/done.json"

printf '%s\n' "Transform finished! Importing to dgraph"

# load the data into the alpha mutate endpoint
curl -H "content-type: application/json" \
     -X POST \
     --url "localhost:8080/mutate?commitNow=true" \
     --data-binary @"$JSON_LOCATION/done.json"


quick_check "/mutate?/commitNow=true"
printf '%s\n' "Data loaded"

exit
