First run this:

```bash
cat ./json/temp_config.json | jq -r '.data.items[] | {name: .name, id: .id}'
```

We can see the relationship between the `"name"`  ec2 instance: `"ec2instancename_example"` and the instance `"id"` represented in json format. Something like this: 

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
_:i-awsinstanceid <name> "i-awsinstanceid" .
...
````

Which can then be easily loaded into dgraph using a request like this:

```bash
curl -H "Content-Type: application/rdf" \
     -X POST \
     --url localhost:8080/mutate?commitNow=true \
     -d $'{
           set {
                 _:i-awsinstanceid <name> "i-awsinstanceid" .
               }
           }'
```

