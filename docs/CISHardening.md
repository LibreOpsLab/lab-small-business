# CIS Hardening

**Hardening** means reducing what an attacker can use: fewer services, tighter settings, less
trust. The **CIS Benchmarks** are consensus checklists of those settings, written by the
Center for Internet Security. Each recommendation has a number, a rationale, an audit step and
a remediation step. They come in two profiles:

| Profile | Meaning |
|---|---|
| **Level 1** | Practical, low risk of breaking things. The sensible baseline |
| **Level 2** | Defence in depth for high-security environments; can hurt usability or compatibility |

This lab applies **Level 1 Server**. It also maps to the Essential Eight and the ACSC ISM
controls the course names, but CIS is the concrete checklist you can measure against.

## The process (this is what is assessed)

Hardening is a loop, not a script you run once.

1. **Baseline.** Measure before changing anything.
2. **Snapshot.** Hardening can break a service. Make rolling back cheap.
3. **Apply** to one host.
4. **Test.** Does every service still work? Check the Grafana dashboard and the logs.
5. **Measure again.** Compare with the baseline.
6. **Record exceptions.** Any control you deliberately do not apply gets a written reason.
7. **Roll out** to the other hosts, one at a time.

A control you skip with a good reason is a pass for the engineer and a fail for the checklist.
Writing the reason down is what turns "I did not do it" into a risk decision.

## Linux: running it

Tools: the community role
[ansible-lockdown/UBUNTU24-CIS](https://github.com/ansible-lockdown/UBUNTU24-CIS) (MIT licence),
pinned in [`ansible/requirements.yml`](../ansible/requirements.yml), and Lynis for measuring.
Ubuntu 24.04 only.

```bash
cd ansible
ansible-galaxy role install -r requirements.yml -p roles/

# 1 and 2: baseline, then snapshot the VM in your hypervisor
ansible-playbook playbooks/09-audit-lynis.yml -l authentik01 -e audit_label=before

# 3: apply Level 1 Server to ONE host
ansible-playbook playbooks/08-cis-hardening.yml -l authentik01 \
  -e cis_snapshot_taken=true --tags level1-server

# 4 and 5: test the services, then measure again
ansible-playbook playbooks/09-audit-lynis.yml -l authentik01 -e audit_label=after
```

Start with `authentik01`, not `docker01`: it is simpler, and `docker01` needs the exceptions below.

The playbook refuses to run without `cis_snapshot_taken=true` and on anything but Ubuntu 24.04.
It is deliberately **not** in `site.yml`.

### Read the warnings

The role's authors say it "will make changes to the system which may have unintended
consequences", that it is "a remediation tool to be used after an audit", and that check mode
is "not guaranteed". So: snapshot, test, and do not trust a dry run to be complete.

### Measuring

[`09-audit-lynis.yml`](../ansible/playbooks/09-audit-lynis.yml) runs Lynis and saves
`ansible/audit-reports/<host>-before.dat` and `-after.dat`. The hardening index (0 to 100) is a
good trend line. It is **not** a CIS compliance result: for that, use the role's own audit mode
(see its README) or CIS-CAT. Report both honestly: the number, what it measures, and what it does
not.

## Expected exceptions

Some benchmark controls conflict with what the machine is for. Expect to turn these off, and
write down why:

| Host | Likely conflict | Reason |
|---|---|---|
| `docker01` | IP forwarding, firewall changes, `iptables` rules | Docker needs forwarding and manages its own rules |
| `docker01`, all VMs | Separate partitions for `/var`, `/tmp`, `/home` | One-disk lab VMs; repartitioning is out of scope |
| `samba-dc01` | Disabled services, SMB and LDAP listeners | It is a domain controller |
| All | Controls needing a reboot or bootloader password | Lab convenience; document as accepted risk |

Per-control switches are variables named `ubtu24cis_rule_<section>_<number>`. Set them to
`false` in `ansible/inventory/host_vars/<host>/` (and check the exact names in the role's
`defaults/main.yml` for the pinned version). Do not edit the role itself.

## Exceptions register

Keep this table up to date. It is evidence for the assessment.

| Host | Control | Why it is not applied | Compensating control | Accepted by | Date |
|---|---|---|---|---|---|
| _example_ `docker01` | _IP forwarding off_ | _Docker needs it for container networking_ | _pfSense filters at the perimeter; Docker publishes only 80, 443, mail ports_ | _name_ | _date_ |

## Windows Server and clients

Windows hardening goes through **Group Policy**, so it reaches every domain-joined machine at
once. Use the **Microsoft Security Baselines** (free, in the Security Compliance Toolkit) or the
CIS Windows benchmarks, import them into a GPO linked to the Windows OU, and measure with the
same loop: baseline, snapshot, apply, test, re-measure, record exceptions. The Samba AD
limitations that affect this are in [SambaVsWindowsAD.md](SambaVsWindowsAD.md).

[`scripts/windows/Import-BaselineGpo.ps1`](../scripts/windows/Import-BaselineGpo.ps1) imports a
baseline GPO from a backup folder and links it to an OU, previewable with `-WhatIf`. Link to a
test OU first. Measure before and after with the Microsoft Security Compliance Toolkit's policy
analyzer or CIS-CAT, since Lynis does not run on Windows. Untested against the lab domain.

## Gotchas

- **Locking yourself out.** SSH hardening can disable the method you are using. Keep a console
  session open (the hypervisor console, not SSH) while you apply it.
- **Hardening is not security.** A hardened host that is not patched, not monitored and not
  backed up is still a problem. This is one control among the course's many.
- **Benchmarks age.** Pin the version, and treat a bump as a change to test.
- **Idempotence.** Run the playbook twice. The second run should change almost nothing; things
  that change every time are worth understanding.
