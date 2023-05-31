# .github

Default files for repositories in the @Andrews-McMeel-Universal organization.

## Environment Variables

The environment variables for this project are sourced from Azure Key Vault Secrets. The `.env` file is what is read for local development.

### Retrieving Secrets

You have options when generating a local `.env` file:

- For a specific environment:
  - `Get-Secrets.ps1 -Environment [ENVIRONMENT]`: Replace `[ENVIRONMENT]` with the environment of your choosing. If no environment is provided, it defaults to the "development" environment.
- To specify an Azure Key Vault:
  - `Get-Secrets.ps1 -KeyVaultName [KEY VAULT NAME]`: Replace `[KEY VAULT NAME]` with one of the key vault names under [Azure Key Vault Names](#azure-key-vault-names)

More information on how to use environment variables and how to edit them in an application, here: [Application Environment Variables](https://amuniversal.atlassian.net/wiki/spaces/TD/pages/2796191745)

### Azure Key Vault Names

Here are the available Azure Key Vault names for this project:

```
appname-development
appname-staging
appname-production
```

---
