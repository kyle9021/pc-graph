Assuming you'd do the below activity from the root directory of this project after running the setup.sh script
## JSON
First run this:

```bash
cat ./json/temp_config.json | jq '.data.items[] | {name: .name, id: .id}'
```

Our goal is to figure out which keys relate are univerally unique. In this example we know it's the `.id` values. While an ec2 instance might share the same name across different aws accounts. They would not share the same `.id`. So before we load it into dgraph. Let's indicate that. 

```bash
cat ./json/temp_config.json | jq '.data.items[] | {name: .name, id: .id, uid: ("_:" + .id)}'
```

This is how the etl.sh script works. Jq runs into some issues if you try reusing the same key name. To get around this I simply added a number to the end of uid. Like uid, uid1, uid2, uid3, and so on. Before loading into dgraph I dump the json to a file with the set command around the array of objects like this: 

```bash
cat ./json/temp_config.json | jq '{set: [ .data.items[] | {name: .name, id: .id, uid: ("_:" + .id)}]}' > ./load.json
```

After it's been written to a file we can clean up the keys with a simple sed script/command

```bash
sed -i 's/uid[0-9]\{0,9\}/uid/g' ./load.json
```

Now we can load this file into dgraph by sending a request with curl like this: 

```bash
curl -H "Content-Type: application/json" \
     -X POST \
     --url localhost:8080/mutate?commitNow=true \
     --data-binary @'load.json'  
```

## RDF
First run this:

```bash
cat ./json/temp_config.json | jq -r '.data.items[] | {name: .name, id: .id}'
```

We can see the relationship between the `"name"` of the ec2 instance `"ec2instancename_example"` and the instance `"id"` represented in json format. Running the above command returns something like this: 

```json
{
  "name": "ec2instancename_example",
  "id": "i-awsinstanceid"
}
```


Our goal is reformat json into rdf so it can be easily loaded into dgraph. 

RDF format should be:

```rdf
_:subject <predicate> "object"
```

see https://dgraph.io/docs/mutations/triples/ for more examples

Below is a one line code example where we take the id from the ec2 vm `i-awsinstanceid` as the subject,  the key `"name"` as the predicate, and the ec2 instance name `ec2instancename_example` as the object.

RDF: subject, predicate, object
This shows the relationship between the subject and the object by the predicate. 

Running:

```bash
cat ./json/temp_config.json | jq -r '.data.items[] |[( "_:"  + .id ), "<name>", ("\"" + .name + "\" ." )]|@sh' | tr -d \'
```
will output:

```rdf
...
_:i-awsinstanceid <name> "ec2instancename_example" .
...
````

Which can then be easily loaded into dgraph using a request like this:

```bash
curl -H "Content-Type: application/rdf" \
     -X POST \
     --url localhost:8080/mutate?commitNow=true \
     -d $'{
           set {
                 _:i-awsinstanceid <name> "ec2instancename_example" .
               }
           }'
```

So my simple script as an example might look something like this:

```bash
#!/bin/bash

payload=$(cat <<EOF
{
  set {
      $(cat ./json/temp_config.json | \
      jq -r '.data.items[] |[( "_:"  + .id ), "<name>", ("\"" + .name + "\" ." )]|@sh' |\
      tr -d \')
       }
}
EOF
)

curl -H "Content-Type: application/rdf" \
     -X POST \
     --url localhost:8080/mutate?commitNow=true \
     --data-binary "$payload"
```






