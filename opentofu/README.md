# OpenTofu

The first implementation assumes that the Netcup VPS already exists. OpenTofu is intentionally not used for provider-specific VPS creation; the reusable deployment only needs an existing host.

If VPS provisioning is added later, keep it optional and pass the resulting IP address to the Ansible inventory. Never store provider credentials or state in this repository.
