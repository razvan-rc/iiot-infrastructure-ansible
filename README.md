# IIoT infrastructure

Ansible configuration for the Festo simulator, MySQL primary/replica pair, and
the IIoT dashboard.

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
