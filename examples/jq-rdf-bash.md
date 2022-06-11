

Take the `.id` from the ec2 instance as the subject, `<name>` as the predicate, and the `.name` as the object.

RDF subject, predicate, object

```bash
cat ./json/temp_config.json | jq -r '.data.items[] |[( "_:"  + .id ), "<name>", ("\"" + .name + "\" ." )]|@sh' | tr -d \'
```
will output

```rdf
_:i-0caEXAMPLE <name> "test-ebs" .
````

