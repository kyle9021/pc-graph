```bash
cat temp_config.json | jq -r '.data.items[] |[( "_:"  + .id ), "<name>", ("\"" + .name + "\" ." )]|@sh' | tr -d \'
```
