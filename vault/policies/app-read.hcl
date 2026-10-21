# Политика приложения devops-app: только чтение собственных секретов (KV v2)
path "secret/data/devops-app/*" {
  capabilities = ["read"]
}

path "secret/metadata/devops-app/*" {
  capabilities = ["list", "read"]
}
