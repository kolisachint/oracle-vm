# Infrastructure — Oracle Cloud Free Tier VM

Provisions an **Ampere A1.Flex** VM (4 OCPU / 24 GB RAM, ARM64) on Oracle Cloud Infrastructure Always Free tier with a reserved public IP. On first boot the VM installs Node.js 20, five AI CLI tools, configures git with an SSH-only push path, and starts the hoocowork server on port 8080.

## What gets deployed

| Resource | Detail |
|---|---|
| Shape | `VM.Standard.A1.Flex` — 4 OCPU, 24 GB RAM (ARM64). Set `instance_shape = "VM.Standard.E2.1.Micro"` (1 GB, x86_64, 2 GB swap added) if A1 is out of capacity |
| OS | Ubuntu 24.04 LTS |
| Boot volume | 100 GB (`boot_volume_size_in_gbs`; Always Free covers 200 GB total) |
| Public IP | Reserved (static — survives VM recreation) |
| Ports open | 22 (SSH), 80 (Caddy ACME challenge), 443 (HTTPS) — 8080 closed to public |
| TLS | Caddy + Let's Encrypt at `https://<dashed-ip>.nip.io` (auto-renew) |
| Service | `hoocowork.service` — `Restart=always`, `OOMPolicy=continue`, `MemoryMax` = half of RAM (800M on E2.1.Micro) |
| Helper | `/usr/local/bin/hoocowork-health` — status / restart / logs in one command |
| Auto-patching | `unattended-upgrades` enabled for security updates |
| Auto-CLI-upgrade | `upgrade-clis.timer` runs nightly (~03:00 UTC + jitter), pulls `@latest` for all five CLIs, restarts hoocowork only if its version changed |
| SSH | key-only (no passwords), root login disabled, `MaxAuthTries=3` |
| Cost | Always Free |

## CLI tools installed automatically

| Tool | Package / Source | Command |
|---|---|---|
| Hoocowork | `@kolisachint/hoocowork` | `hoocowork` (runs on :8080) |
| Hoocode Agent | `@kolisachint/hoocode-agent` | `hoocode-agent` |
| Claude CLI | `@anthropic-ai/claude-code` | `claude` |
| Codex CLI | `@openai/codex` | `codex` |
| Opencode CLI | `opencode` | `opencode` |
| GitHub CLI | `gh` (official APT repo) | `gh` |
| Git | `git` (apt) | `git` |

## Directory structure

```
infra/
├── terraform/
│   ├── provider.tf              # OCI provider, Terraform version
│   ├── variables.tf             # All input variables
│   ├── network.tf               # VCN, subnet, IGW, security list
│   ├── compute.tf               # A1 Flex instance, reserved public IP
│   ├── outputs.tf               # public_ip, hoocowork_url, ssh_command
│   └── terraform.tfvars.example # Safe template — copy to terraform.tfvars
└── scripts/
    ├── setup-vm.sh              # Cloud-init: installs Node.js + all CLIs, git defaults, hoocowork-health
    └── post-setup.sh            # Interactive: git identity, GitHub SSH key, gh auth, API keys
```

## Quick start

- **[docs/install.md](../docs/install.md)** — full step-by-step setup guide
- **[docs/connect.md](../docs/connect.md)** — connecting from laptop, iPhone/iPad, or any browser

```bash
# 1. Copy and fill in credentials
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your OCI values

# 2. Deploy
terraform init
terraform apply

# 3. Connect (use the SSH command from terraform output)
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip>

# 4. Verify cloud-init finished
sudo tail -f /var/log/setup-vm.log

# 5. Run post-setup (git + GitHub + API keys — one interactive script)
curl -fsSL https://raw.githubusercontent.com/kolisachint/brainstorm/main/infra/scripts/post-setup.sh | bash
```

## Terraform outputs

After `terraform apply` you will see:

```
public_ip      = "xxx.xxx.xxx.xxx"
hoocowork_url  = "http://xxx.xxx.xxx.xxx:8080"
ssh_command    = "ssh -i /path/to/key ubuntu@xxx.xxx.xxx.xxx"
instance_ocid  = "ocid1.instance.oc1..."
```

## Teardown

```bash
cd infra/terraform
terraform destroy
```

Removes all OCI resources. Your account is unaffected.
