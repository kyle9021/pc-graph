First run this:

```bash
cat ./json/temp_config.json | jq -r '.data.items[] | {name: .name, id: .id}'
```

We can see the relationship between the name of an ec2 instance and the instance Id represented in json format. Something like this: 

```json
...
{
  "name": "ec2instancename_example",
  "id"": "i-awsinstanceid"
}
...
```

Our goal is reformat json into rdf so it can be easily loaded into dgraph. 

RDF format should be:

```rdf
_:subject <predicate> "object"
```

see https://dgraph.io/docs/mutations/triples/ for more examples

Below is a oneline code example where we take the `.id` from the ec2 instance as the subject, `<name>` as the predicate, and the `.name` as the object.

RDF: subject, predicate, object

```bash
cat ./json/temp_config.json | jq -r '.data.items[] |[( "_:"  + .id ), "<name>", ("\"" + .name + "\" ." )]|@sh' | tr -d \'
```
will output

```rdf
...
_:i-0caEXAMPLE <name> "test-ebs" .
...
````

