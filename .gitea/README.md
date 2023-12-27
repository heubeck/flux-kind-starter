# Local Gitea instance

```shell
# in .gitea
cd tls
gitea cert -ca=true -duration=876000h0m0s -host=<your host ip>
cd ..
docker compose up
```
