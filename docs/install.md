# Installation Guide

Full guide for provisioning the Oracle Cloud VM and configuring all AI CLI tools.

---

## Prerequisites

Install these on your **local machine** before starting:

| Tool | Install |
|---|---|
| Terraform >= 1.5 | https://developer.hashicorp.com/terraform/install |
| Git | https://git-scm.com/downloads |
| OpenSSL | Pre-installed on macOS/Linux; Windows: use Git Bash |

---

## Step 1 — Create a free Oracle Cloud account

> This step is manual (browser required). Takes ~10 minutes.

1. Go to **https://signup.cloud.oracle.com/** → **Start for free**
2. Enter your name, email, verify via the code sent to your inbox
3. Choose your **Home Region** — cannot be changed later
   - US: `us-ashburn-1` or `us-phoenix-1`
   - Europe: `eu-frankfurt-1`
   - Asia Pacific: `ap-sydney-1`
4. Set a password, verify your phone via SMS
5. Enter a credit card (identity verification only — Always Free resources are never charged)
6. Click **Start my free trial** and wait for the welcome email

---

## Step 2 — Generate an SSH key pair

```bash
ssh-keygen -t ed25519 -C "oci-vm" -f ~/.ssh/oci_vm
# Creates:
#   ~/.ssh/oci_vm       ← private key (never share this)
#   ~/.ssh/oci_vm.pub   ← public key (goes into terraform.tfvars)
```

---

## Step 3 — Generate an OCI API signing key

Terraform uses this to authenticate to OCI.

```bash
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 400 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

**Add the public key to OCI:**

1. Log in to OCI Console → click **Profile icon** (top-right) → **My profile**
2. Scroll to **API keys** → **Add API key** → **Paste a public key**
3. Paste the contents of `~/.oci/oci_api_key_public.pem`
4. Click **Add** — OCI shows a config preview. Copy:
   - `fingerprint`
   - `user` (your user OCID)
   - `tenancy` (your tenancy OCID)
   - `region`

---

## Step 4 — Configure terraform.tfvars

```bash
git clone https://github.com/kolisachint/brainstorm.git
cd brainstorm/infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
tenancy_ocid     = "ocid1.tenancy.oc1..aaaa..."      # from OCI config preview
user_ocid        = "ocid1.user.oc1..aaaa..."          # from OCI config preview
fingerprint      = "aa:bb:cc:..."                      # from OCI config preview
private_key_path = "/home/you/.oci/oci_api_key.pem"   # local path to PEM file
region           = "us-ashburn-1"                      # your home region
compartment_ocid = "ocid1.tenancy.oc1..aaaa..."       # same as tenancy_ocid for root
ssh_public_key   = "ssh-ed25519 AAAA..."              # output of: cat ~/.ssh/oci_vm.pub
```

> `terraform.tfvars` is git-ignored and will never be committed.

---

## Step 5 — Deploy the VM

```bash
cd infra/terraform

terraform init     # downloads OCI provider plugin (~2 min first time)
terraform plan     # preview resources to be created
terraform apply    # type 'yes' to confirm (~3 min)
```

Output after apply:

```
Outputs:

hoocowork_url  = "https://xxx-xxx-xxx-xxx.nip.io"   # Caddy + Let's Encrypt
instance_ocid  = "ocid1.instance.oc1..."
public_ip      = "xxx.xxx.xxx.xxx"
ssh_command    = "ssh -i /path/to/key ubuntu@xxx.xxx.xxx.xxx"
```

On first boot Caddy fetches a Let's Encrypt cert for `<dashed-public-ip>.nip.io`. The first request after `terraform apply` may take ~10 seconds while the ACME challenge completes; subsequent requests are instant.

---

## Step 6 — Connect to the VM

```bash
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip>
```

Cloud-init runs in the background on first boot and takes ~5 minutes. Check progress:

```bash
sudo tail -f /var/log/setup-vm.log
```

When you see `Completed successfully` the setup is done.

---

## Step 7 — Verify all CLI tools

```bash
# Node.js
node --version        # v20.x.x
npm --version

# Hoocowork server — listens on localhost:8080, Caddy proxies HTTPS
sudo systemctl status hoocowork
sudo systemctl status caddy
curl http://localhost:8080                          # from the VM itself
curl -I https://<dashed-public-ip>.nip.io          # from anywhere

# All five CLI tools
hoocowork --version
hoocode-agent --version
claude --version
codex --version
opencode --version
```

---

## Step 8 — Configure API keys for each CLI

Each AI CLI needs its own API key. Add them to `~/.bashrc` on the VM so they persist across sessions:

```bash
# SSH into the VM then:
nano ~/.bashrc
```

Add at the bottom:

```bash
# AI CLI API keys
export ANTHROPIC_API_KEY="sk-ant-..."   # https://console.anthropic.com/
export OPENAI_API_KEY="sk-..."          # https://platform.openai.com/api-keys
```

Apply immediately:

```bash
source ~/.bashrc
```

Verify Claude CLI:

```bash
claude --version
claude   # launches interactive session
```

Verify Codex CLI:

```bash
codex "write a hello world in Python"
```

Verify Opencode:

```bash
opencode --version
```

---

## Step 9 — Git & GitHub setup

Cloud-init has already configured the non-interactive parts on first boot:

- `init.defaultBranch = main`
- `url."git@github.com:".insteadOf "https://github.com/"` — every HTTPS GitHub clone pushes via SSH transparently
- `~/.ssh/config` skeleton pointing `Host github.com` → `~/.ssh/github_vm`
- `github.com` pre-trusted in `~/.ssh/known_hosts`

What's left is to generate the SSH key, register it with GitHub, and set your git identity. Run the post-setup script for that:

```bash
curl -fsSL https://raw.githubusercontent.com/kolisachint/brainstorm/main/infra/scripts/post-setup.sh | bash
```

> A `NEXT_STEPS.txt` file in your home directory also shows this command on first login.

The script walks you through:

| Step | What it does |
|---|---|
| Git identity | Sets `user.name` and `user.email` (insteadOf rewrite is already set by cloud-init) |
| GitHub SSH key | Generates `~/.ssh/github_vm` (ed25519) if not present |
| GitHub auth | Device flow (open one URL in any browser) or PAT — uploads SSH key via `gh ssh-key add` |
| Anthropic API key | Saved to `~/.bashrc` as `ANTHROPIC_API_KEY` |
| OpenAI API key | Saved to `~/.bashrc` as `OPENAI_API_KEY` |

All steps are skippable — press Enter to move past any you don't need yet.

After it completes:

```bash
source ~/.bashrc

# Verify
gh auth status
ssh -T git@github.com
claude   # needs ANTHROPIC_API_KEY
codex "hello"   # needs OPENAI_API_KEY
```

---

## Hoocowork server

Hoocowork runs as a systemd service and starts automatically on every boot. The unit is hardened so a runaway process can't take down the VM:

- `Restart=always` — restarts on any exit
- `OOMPolicy=continue` — prevents kernel OOM kills from being treated as a clean stop (so `Restart=always` still fires)
- `MemoryMax` — half of RAM on A1.Flex (800M on the 1 GB E2.1.Micro); caps the process so an OOM never starves sshd or the system
- `StartLimitBurst=10` / `StartLimitIntervalSec=300` — survives crash loops without giving up

### `hoocowork-health` — one-command status / restart / logs

Installed at `/usr/local/bin/hoocowork-health` by cloud-init. Works locally on the VM or via SSH from your laptop:

```bash
# On the VM
hoocowork-health           # service + port + HTTP + memory + recent OOM kills
hoocowork-health restart   # restart and show status
hoocowork-health logs 100  # tail N lines from the journal (default 50)
hoocowork-health upgrade   # run nightly upgrade now (all CLIs)

# From your laptop
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip> hoocowork-health
ssh -i ~/.ssh/oci_vm ubuntu@<public_ip> hoocowork-health restart
```

### Raw systemd commands (if you prefer)

```bash
sudo systemctl status hoocowork
sudo journalctl -u hoocowork -f
sudo systemctl restart hoocowork

# Access from your browser
https://<dashed-public-ip>.nip.io     # e.g. https://140-245-15-62.nip.io
```

### Nightly CLI auto-upgrade

A systemd timer (`upgrade-clis.timer`) runs every night around 03:00 UTC (with up to 1 hour of jitter) and re-runs `npm install -g <pkg>@latest` for all five AI CLIs plus bun. If hoocowork's version actually changed, the service is restarted automatically; otherwise it keeps running uninterrupted.

```bash
# When does it run next?
systemctl list-timers upgrade-clis.timer

# What happened on the last run?
journalctl -u upgrade-clis.service -n 50

# Force an upgrade right now
sudo systemctl start upgrade-clis.service

# Stop nightly upgrades (keep the script, just disable the timer)
sudo systemctl disable --now upgrade-clis.timer
```

### Security hardening applied at boot

| Layer | What's done |
|---|---|
| TLS | Caddy on `:443` + Let's Encrypt cert via `<dashed-ip>.nip.io`. Port 8080 closed to internet. |
| SSH | `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3` |
| Patching | `unattended-upgrades` enabled — security updates apply automatically |
| CLI auto-upgrade | `upgrade-clis.timer` runs nightly (~03:00 UTC), pulls `@latest` for hoocowork, Claude, Codex, Opencode, hoocode-agent, bun |
| Service | `Restart=always`, `OOMPolicy=continue`, `MemoryMax` capped — hoocowork survives OOM kills |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `401 NotAuthenticated` on terraform plan | Wrong OCID, fingerprint, or key path | Re-check `terraform.tfvars` |
| `Out of host capacity` | A1 Flex unavailable in that AD | Retry later, try `availability_domain_index = 1`, upgrade the account to Pay As You Go (A1 stays free), or fall back to `instance_shape = "VM.Standard.E2.1.Micro"` |
| Free instance stopped for being idle | OCI reclaims idle Always Free instances on free-tier accounts | Upgrade the account to Pay As You Go; Always Free resources stay $0 |
| Image lookup returns empty | ARM image string differs in your region | Set `ubuntu_version = "24.04 Minimal aarch64"` in `terraform.tfvars` |
| SSH connection refused after apply | Cloud-init still running | Wait 5 min, check `/var/log/setup-vm.log` |
| `hoocowork.service` failed | Package not yet installed | `sudo npm install -g @kolisachint/hoocowork && sudo systemctl restart hoocowork` |
| `hoocowork` keeps OOM-restarting | Hitting `MemoryMax` (tight on the 1 GB Micro); another process is heavy | Run `hoocowork-health` to inspect, then stop other npm processes. Service will self-recover. |
| Port 8080 unreachable | OCI firewall + Ubuntu firewall | OCI security list is open; also run `sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT` |
| `gh auth login` hangs | Device flow needs browser | Open `https://github.com/login/device` on any device and enter the code shown |
| `ssh -T git@github.com` permission denied | SSH key not added to GitHub | Run `gh ssh-key add ~/.ssh/github_vm.pub --title "oci-vm"` |
| `git push` fails: `could not read Username for 'https://github.com'` | HTTPS remote without credential helper | Cloud-init now sets `insteadOf` to rewrite HTTPS → SSH globally. If you see this on an existing VM, run `git config --global url."git@github.com:".insteadOf "https://github.com/"` |

---

## Teardown

```bash
cd infra/terraform
terraform destroy
```

Deletes the VM, public IP, and all network resources. Does not affect your OCI account.
