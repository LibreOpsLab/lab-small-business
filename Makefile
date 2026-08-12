.PHONY: help pki-init pki-issue-all deploy backup-samba health-samba lint

REPO_ROOT := $(shell pwd)

help:
	@echo "lab-small-business — common entry points"
	@echo ""
	@echo "  make pki-init        Bootstrap the Root + Issuing CA (first run only)"
	@echo "  make pki-issue-all   Issue leaf certs for cloud/docs/mail/auth/samba-dc01"
	@echo "  make deploy          Run scripts/deploy-all.sh (PKI + full Ansible playbook)"
	@echo "  make backup-samba    Run samba/scripts/backup-ad.sh on samba-dc01 (via ssh)"
	@echo "  make health-samba    Run samba/scripts/health-check.sh on samba-dc01 (via ssh)"
	@echo "  make lint            Lint Ansible playbooks/roles and shell scripts"
	@echo ""
	@echo "See docs/DeploymentGuide.md for the full first-time bring-up sequence."

pki-init:
	cd pki/scripts && ./00-init-root-ca.sh && ./01-init-intermediate-ca.sh

pki-issue-all:
	cd pki/scripts && \
	./02-issue-server-cert.sh --cn samba-dc01.lab.local --san "DNS:samba-dc01.lab.local,DNS:lab.local" && \
	./02-issue-server-cert.sh --cn cloud.lab.local --san DNS:cloud.lab.local && \
	./02-issue-server-cert.sh --cn docs.lab.local  --san DNS:docs.lab.local && \
	./02-issue-server-cert.sh --cn mail.lab.local  --san DNS:mail.lab.local && \
	./02-issue-server-cert.sh --cn auth.lab.local  --san DNS:auth.lab.local

deploy:
	./scripts/deploy-all.sh --ask-vault-pass

backup-samba:
	ssh samba-dc01.lab.local 'sudo /opt/lab-small-business/samba/scripts/backup-ad.sh'

health-samba:
	ssh samba-dc01.lab.local 'sudo /opt/lab-small-business/samba/scripts/health-check.sh'

lint:
	ansible-lint ansible/playbooks ansible/roles
	shellcheck pki/scripts/*.sh samba/scripts/*.sh scripts/*.sh
