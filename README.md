# .github

Default files for repositories in the @Andrews-McMeel-Universal organization.

## Environment Variables

The environment variables for this project are sourced from Azure Key Vault Secrets.

By default, the `.env` file is what is read for local development. You can specify different .env files in the `docker-compose.yaml` file (example: `.env.development` or `.env.test`).

### Retrieving Secrets

You have options when generating a local `.env` file:

- For a specific environment, run `Get-Secrets.ps1 -Environment [ENVIRONMENT]` with the environment of your choosing. By default, the environment is set to "development".
- To specify an Azure Key Vault, run `Get-Secrets.ps1 -KeyVaultName [KEY VAULT NAME]`

More information on how to use environment variables and how to edit them in an application, here: [Application Environment Variables](https://amuniversal.atlassian.net/wiki/spaces/DEVOps/pages/2796191745/Application+Environment+Variables)

### Azure Key Vault Names

Here are the available Azure Key Vault names for this project:

```
appname-development
appname-staging
appname-production
```

---
