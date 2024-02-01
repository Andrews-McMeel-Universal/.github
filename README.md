# .github

Default files for repositories in the @Andrews-McMeel-Universal organization.

## Environment Variables

The environment variables for this project are sourced from Azure Key Vault Secrets.

> :white_check_mark: Read about [Application Environment Variables](https://amuniversal.atlassian.net/l/cp/z7HWk0Ah) for information on how to use and edit environment variables in an application **before proceeding**.

### Retrieving Environment Variables

You have options when generating a local `.env` file:

- To generate a `.env` file for a specific environment: In a PowerShell session, run `./Get-Secrets.ps1 -Environment [ENVIRONMENT]`. If no environment is provided, the script defaults to the "development" environment.
- To generate a `.env` file for a specific key vault: In a PowerShell session, run `./Get-Secrets.ps1 -KeyVaultName [KEY VAULT NAME]`. You can find the available key vaults for this project below.

Here are the available Azure Key Vault names for this project:

- `appname-development`
- `appname-staging`
- `appname-production`
