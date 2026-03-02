# MCPhound MCP Security Scanner

A GitHub Action that scans your MCP (Model Context Protocol) server configurations for security vulnerabilities and compositional attack paths.

MCPhound detects dangerous permission combinations, cross-server attack vectors, and known CVEs across your MCP setup — then uploads the results as SARIF to GitHub Code Scanning.



## Quick Start

1. Request an API token — [open an issue](https://github.com/tayler-id/mcphound-action/issues/new?title=Token+request&labels=token-request) or email mcphound@tayler.id
2. Add it as a repository secret named `MCPHOUND_API_TOKEN`
3. Create `.github/workflows/mcphound.yml`:

```yaml
name: MCPhound Security Scan

on:
  push:
    branches: [main]
  pull_request:

permissions:
  security-events: write
  contents: read

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: tayler-id/mcphound-action@v0
        with:
          api_token: ${{ secrets.MCPHOUND_API_TOKEN }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api_token` | Yes | — | MCPhound API token (store as repository secret) |
| `config_path` | No | `.cursor/mcp.json` | Path to MCP config file |
| `fail_on` | No | `critical` | Minimum severity to fail the check (`critical` \| `high` \| `medium` \| `low` \| `none`) |
| `api_url` | No | `https://mcphound-api.fly.dev` | MCPhound API URL |
| `mode` | No | `ci` | Scan mode |
| `timeout_seconds` | No | `120` | API request timeout in seconds |
| `category` | No | `mcphound` | SARIF category for Code Scanning |

## Outputs

| Output | Description |
|--------|-------------|
| `sarif_file` | Path to the SARIF results file |
| `findings_count` | Number of security findings |
| `max_severity` | Highest severity level found (`critical`, `medium`, `low`, or `none`) |

## Examples

### Custom config path

```yaml
- uses: tayler-id/mcphound-action@v0
  with:
    api_token: ${{ secrets.MCPHOUND_API_TOKEN }}
    config_path: "config/mcp-servers.json"
```

### Fail on high severity or above

```yaml
- uses: tayler-id/mcphound-action@v0
  with:
    api_token: ${{ secrets.MCPHOUND_API_TOKEN }}
    fail_on: "high"
```

### Never fail the build (report only)

```yaml
- uses: tayler-id/mcphound-action@v0
  with:
    api_token: ${{ secrets.MCPHOUND_API_TOKEN }}
    fail_on: "none"
```

### Use scan outputs in subsequent steps

```yaml
- uses: tayler-id/mcphound-action@v0
  id: mcphound
  with:
    api_token: ${{ secrets.MCPHOUND_API_TOKEN }}

- run: echo "Found ${{ steps.mcphound.outputs.findings_count }} findings"
```

## Fork PR Behavior

For security, MCPhound automatically skips scans on pull requests from forked repositories. Fork PRs do not have access to repository secrets, so the API token would be unavailable. The action exits cleanly with a notice instead of failing.

## Config File Detection

The action looks for your MCP config in this order:

1. The path specified in `config_path`
2. `.vscode/mcp.json`
3. `.cursor/mcp.json`

## How It Works

1. The action reads your MCP server configuration file
2. Sends it to the MCPhound API for analysis
3. Receives a SARIF report with security findings
4. Uploads the SARIF to GitHub Code Scanning (appears in the Security tab)
5. Optionally fails the check if findings exceed your severity threshold

## License

MIT
