# PC-Dgraph 

deployed on Ubuntu 20.04 desktop 
requires jq, docker-compose, curl, bash, and docker. 

```bash
git clone https://github.com/kyle9021/dgraph_project
cd dgraph_project/
bash setup.sh
```

open browser and go to http://localhost:8001

query to enter in the offline mode of ratel:

```graphql
{
  vm(func: has(name)){
    rrn
    name
    imageId
    vpc_id:  networkInterfaces {
      vpcId
    security_group:  groups {
        groupName
        groupId
      }
    network_association:  privateIpAddresses {
      publicIp:  association {
          publicIp
        }
      }
    }
    vm_storage: blockDeviceMappings {
    ebs_volume:  ebs {
        volumeId
      }
    }
    iam_permissions: iam {
     sourceCloudResourceRrn
     sourceResourceName
     destCloudServiceName
    }
  }
}
```
