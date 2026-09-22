# Knwlge releases

Downloadable builds of the Knwlge Enterprise Server and the `knwlge` developer CLI.
Each release carries the platform tarballs, `checksums.txt` and an install script.

## Enterprise Server

```bash
# macOS
brew install replient/tap/knwlge-enterprise
# Linux / macOS
curl -fsSL https://github.com/Replient/knwlge-releases/releases/latest/download/install.sh | sh

knwlge-enterprise setup
```

Needs PostgreSQL 18 with `pgvector` and somewhere to keep artifacts (a directory, S3 or Azure).
Docs: https://knwlge.com/docs/getting-started/enterprise

## Developer CLI

```bash
brew install replient/tap/knwlge
# or
curl -fsSL https://github.com/Replient/knwlge-releases/releases/latest/download/install-cli.sh | sh

knwlge init --api-url https://your-enterprise-server
```

Releases are tagged `enterprise-v<version>` and `cli-v<version>`; `latest` points at the newest
Enterprise Server release. Source: [knwlge-enterprise](https://github.com/Replient/knwlge-enterprise)
(private) and [knwlge-cli](https://github.com/Replient/knwlge-cli) (private).
