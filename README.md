# PC-Graph
non-prod ready

* Deployed on Ubuntu 20.04 desktop 
* Requires jq, docker-compose, curl, bash, and docker



```bash
git clone https://github.com/kyle9021/pc-graph
cd pc-graph/
bash setup.sh
```

* open browser and go to http://localhost:8001/?local

_query to enter in the offline mode of ratel:_

```graphql
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
```
