# SFTP

File exchange with outside parties (suppliers, contractors) without giving them a login on
the server. Provided by the [`sftp` role](../ansible/roles/sftp/tasks/main.yml) on `docker01`.

## SFTP is not FTP

| | FTP / FTPS | SFTP |
| - | - | - |
| Runs over | Its own protocol, two connections (control and data) | SSH, one connection, port 22 |
| Credentials | FTP: clear text. FTPS: TLS, if configured | Always encrypted; keys preferred |
| Firewall | Needs a range of data ports, or NAT helpers that inspect traffic | Nothing new: port 22 is already open |

Plain FTP sends passwords and files readable on the wire, which is why the lab does not run an
FTP server. Despite the name, SFTP is not "FTP over SSH" but a separate protocol that happens to
run inside an SSH connection.

## What the role builds

- A group, `sftponly`, and one account per entry in `sftp_users`, with **no shell and no
  password**: key login only.
- A **chroot jail** per user at `/srv/sftp/<user>`. The user sees that directory as `/` and
  cannot reach the rest of the server.
- A writable `upload` directory inside the jail. The jail root itself is root-owned.
- Public keys in `/etc/ssh/sftp_keys/<user>`, root-owned, so users cannot change who may log in.
- `ForceCommand internal-sftp`, no TCP forwarding, no TTY.

The configuration is a drop-in, `/etc/ssh/sshd_config.d/50-lab-sftp.conf`. The role checks
`sshd -t` and removes the drop-in if it does not parse, so a typo cannot lock you out.

## Using it

1. Add the user to `ansible/group_vars/docker_server.yml`:

   ```yaml
   sftp_users:
     - { name: supplier1, pubkey: "ssh-ed25519 AAAA... supplier1@example" }
   ```

2. `ansible-playbook playbooks/06-sftp.yml`
3. As the supplier: `sftp supplier1@docker01.lab.internal`, then `cd upload`, `put file`.

## Gotchas

- **"bad ownership or modes for chroot directory"**: sshd requires every directory in the jail
  path to be owned by root and not writable by anyone else. This is why uploads go in a
  subdirectory.
- **Shell login attempts fail by design.** The user has `nologin` and `PermitTTY no`.
- **Monitor it.** Add `10.10.10.20:22` to the `probe-tcp` job (see
  [Monitoring.md](Monitoring.md#adding-a-service)). It proves SSH answers, not that uploads work.

## Exercise

1. Create a user, connect, and try `cd /` then `ls`. What do you see? What can you not see?
2. Try `ssh supplier1@docker01.lab.internal`. What happens, and why?
3. Break the config on purpose (add a bad line to the drop-in) and run the playbook. What does
   the rescue block do?
4. Check `/var/log/auth.log` for your sessions.
