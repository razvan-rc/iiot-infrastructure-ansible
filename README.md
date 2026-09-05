# IIoT infrastructure

Ansible configuration for the Festo simulator, MySQL primary/replica pair, and
the IIoT dashboard.

## Expanding database storage

After increasing both database EBS volumes to at least 20 GiB in AWS, run:

    ansible-playbook expand-db-storage.yml

This playbook verifies the root device is /dev/nvme0n1p1 with ext4, previews and
grows partition 1, then expands ext4 online. It uses RAM for growpart temporary
files so it also works when the original root filesystem is full. It does not
format disks or delete data. The boot partitions retain their existing layout.
It is intentionally limited to the verified NVMe/ext4 layout and stops if the
layout differs. Re-running after expansion should report no changes.

## Maintenance workflow

The maintenance tag provisions the maintenance_commands audit/command table and
the protected dashboard control endpoint. The control token is injected into the
web service through a root-owned systemd drop-in and is never stored in Git.

Create a local, ignored variables file:

    # group_vars/vault.yml
    maintenance_control_token: replace_with_a_random_url_safe_token
    github_token: replace_with_your_github_token

Encrypt it before use:

    ansible-vault encrypt group_vars/vault.yml

Run only the maintenance provisioning:

    ansible-playbook site.yml --tags maintenance --extra-vars @group_vars/vault.yml --ask-vault-pass

The maintenance token must have 32-128 characters and may contain only letters,
digits, underscore, and dash. Do not pass secrets directly on a shared command
line.

The maintenance tasks create source-IP-specific sensor_app accounts: the
simulator can insert telemetry and read/update commands; the dashboard can
insert/read commands on the master and read both tables on the replica.
The existing wildcard accounts remain for compatibility; their removal and
credential rotation require a separate migration. The simulator is assumed to
run on the Ansible controller, whose private IP is discovered from localhost facts.
Run this tag on an already provisioned environment; it does not install MariaDB,
create the application database, or install the web service from scratch.
