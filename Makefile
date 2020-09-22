.DEFAULT_GOAL := help

.PHONY : conf clean reset fix-vmail install-purge all force-provision force-certs test_deps test_setup test upgrade backup restore purge-backups help

PWD = $(shell pwd)

conf: ## Create a configuration file in /etc/
	scripts/conf.sh

clean: ## Clean the environment to have a fresh start (preserve SSL/DH certs in /etc/ssl)
	-rm reps conf-check install provision all || exit 0

reset: clean install-purge ## Reset all configurations and remove/purge all softwares & certificates
	-rm certs || exit 0
	-rm /etc/ssl/private/mail.key /etc/ssl/certs/mail.crt /etc/ssl/certs/cacert.pem || exit 0
	-rm -rdf /etc/dovecot || exit 0
	-rm -rdf /etc/postfix || exit 0

deps: ## Install all the needed deps to test & build it
	scripts/deps.sh

conf-check: deps ## Make some tests to validate the actual config before proceed 
	# test the settings of the localhost
	scripts/test_localhost.sh
	# test the binddn user and search for the admin user
	scripts/test_bind_dn.sh
	# test a search on the admin user and warn about any misconfigured property
	scripts/test_mailadmin.sh
	echo "done" > conf-check

fix-vmail: ## Fix the warning by creating the vmail user as per the conf file
	scripts/vmail_create.sh

certs: conf-check ## Generate a self-signed certificate for the server SSL/TLS options
	scripts/gen_cert.sh
	echo "done" > certs

install: conf-check deps certs ## Install all the software from the repository
	apt update -q && apt upgrade -qy
	scripts/install_mail.sh
	echo "done" > install

install-purge: deps ## Uninstall postfix and dovecot already installed software (purge config also)
	scripts/install_purge.sh
	rm install || exit 0
	rm conf-check || exit 0
	rm deps || exit 0

provision: install ## Provision the server, this will copy over the config files and set the vars
	scripts/confupgrade.sh
	# make the provisioning
	scripts/provision.sh
	echo "done" > provision

all: provision ## Run all targets in the logic order, run this to make it all
	echo "done" > all
	echo "Done!"

force-provision: ## Force a re-provisioning of the system
	rm provision || exit 0
	rm conf-check || exit 0
	scripts/confupgrade.sh
	$(MAKE) conf-check
	scripts/backup.sh
	$(MAKE) install-purge
	$(MAKE) provision
	# if you reach this point the latest backup is working
	cat /var/lib/mailad/latest_backup > /var/lib/mailad/latest_working_backup
	# restore the custom files
	scripts/custom_restore.sh

force-certs: ## Force a re-creation of the SSL & dhparm certs
	rm certs
	$(MAKE) certs

test-deps: ## install test dependencies
	apt update && apt install -y swaks coreutils mawk bc curl

test: ## Make all tests (must be on other PC than the server, outside the my_networks segment)
	tests/test.sh $(ip)

upgrade: force-provision ## Upgrade a setup, see README.md for details
	echo "Upgrade done!"

backup: ## Make a backup of the configs to be restored in the event of a failed upgrade or provision
	scripts/backup.sh
	# make it working
	cat /var/lib/mailad/latest_backup > /var/lib/mailad/latest_working_backup

restore: ## Restore a previous raw backup
	scripts/restore.sh

purge-backups: ## WARNING, DANGEROUS! this command will erase the backup folder
	rm -rdf /var/lib/mailad || exit 0
	rm -rdf /var/backups/mailad || exit 0

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
