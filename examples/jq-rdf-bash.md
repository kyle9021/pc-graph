```bash
cat temp_config.json | jq -r '.data.items[] |[( "_:"  + .id ), "<name>", ("\"" + .name + "\" ." )]|@sh' | tr -d \'![image](https://user-images.githubusercontent.com/54778108/173166675-5e21c3f2-18f1-4613-9413-61efd997a3e5.png)
```
