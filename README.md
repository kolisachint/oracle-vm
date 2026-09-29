# Brainstorm — Oracle Cloud VM + AI CLI Setup

Provisions a free **Ampere A1.Flex** VM on Oracle Cloud Infrastructure (4 OCPU / 24 GB RAM, ARM64, Always Free; E2.1.Micro available as a fallback) with a reserved public IP and five AI CLI tools pre-installed.

## What's included

- **Terraform** — one-command VM provisioning on OCI Always Free tier
- **Cloud-init** — installs Node.js 20, all CLI tools, and configures git/SSH on first boot
- **Hoocowork server** — runs as a systemd service on port 8080 with `Restart=always` and OOM hardening
- **`hoocowork-health`** — one-command health check + restart helper installed on the VM

## CLI tools on the VM

| Tool | Package |
|---|---|
| Hoocowork | `@kolisachint/hoocowork` |
| Hoocode Agent | `@kolisachint/hoocode-agent` |
| Claude CLI | `@anthropic-ai/claude-code` |
| Codex CLI | `@openai/codex` |
| Opencode | `opencode` |

## Quick start

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# fill in your OCI credentials

terraform init
terraform apply
```

Terraform prints the public IP and hoocowork URL when done:

```
public_ip      = "xxx.xxx.xxx.xxx"
hoocowork_url  = "https://xxx-xxx-xxx-xxx.nip.io"   # Caddy + Let's Encrypt
ssh_command    = "ssh -i ~/.ssh/oci_vm ubuntu@xxx.xxx.xxx.xxx"
```

Caddy terminates TLS on `:443` using a free Let's Encrypt certificate (auto-renewed) and reverse-proxies to hoocowork on `localhost:8080`. Port 8080 is closed to the public internet.

## Health check from your laptop

Once the VM is up, you can check or restart the service from anywhere:

```bash
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip> hoocowork-health           # status + memory + port + HTTP + OOM kills
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip> hoocowork-health restart   # restart the service
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip> hoocowork-health logs 100  # last 100 log lines
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip> hoocowork-health upgrade   # upgrade all CLIs now
```

## Docs

- [docs/install.md](docs/install.md) — full step-by-step setup guide
- [docs/connect.md](docs/connect.md) — how to connect from laptop, iPhone/iPad, or browser
- [infra/README.md](infra/README.md) — infrastructure overview
