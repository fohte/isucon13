BRANCH := master

LOG_TARGET := \033[1;32m # green & bold
LOG_INFO := \033[0;34m # blue
LOG_WARN := \033[0;33m # yellow
LOG_END := \033[0m\n # reset

SERVER_1 := 54.64.83.105
SERVER_2 := 3.113.83.11
SERVER_3 := 54.249.193.147

SSH_HOSTNAME_PREFIX := isucon13
SSH_USERNAME := isucon

MYSQL_HOST := localhost
MYSQL_USER := isucon
MYSQL_PASS := isucon
MYSQL_DB := isupipe

USERS := fohte,gedorinku,unblee

ALP_VERSION := 1.0.21

TIMESTAMP := $(shell date "+%Y%m%d%H%M%S")

####################
# REMOTE TASKS
####################

# リポジトリから pull する
# BRANCH を指定すると pull するブランチを変えられる
# 例: $ make pull BRANCH=fohte
.PHONY: pull
pull:
	@printf "$(LOG_TARGET)▶️ git pull (branch: $(BRANCH))$(LOG_END)"
	git fetch -p origin
	git checkout $(BRANCH)
	git pull origin $(BRANCH)
	@printf "$(LOG_INFO)✅ git pull finished$(LOG_END)"

# 全部デプロイする
.PHONY: deploy
deploy:
	@printf "$(LOG_TARGET)▶️ deploy$(LOG_END)"
	$(MAKE) pull
	$(MAKE) deploy-nginx
	$(MAKE) deploy-mysql
	$(MAKE) deploy-webapp

# nginx の設定ファイルをデプロイする
.PHONY: deploy-nginx
deploy-nginx:
	@printf "$(LOG_TARGET)▶️ deploy nginx$(LOG_END)"
	sudo rsync -avz ./nginx/ /etc/nginx/
	sudo nginx -t
	sudo systemctl reload nginx
	@printf "$(LOG_INFO)✅ nginx deployed$(LOG_END)"

# mysql の設定ファイルをデプロイする
.PHONY: deploy-mysql
deploy-mysql:
	@printf "$(LOG_TARGET)▶️ deploy mysql$(LOG_END)"
	sudo rsync -avz ./mysql/ /etc/mysql/
	sudo systemctl restart mysql
	@printf "$(LOG_INFO)✅ mysql deployed$(LOG_END)"

deploy-webapp:
	@printf "$(LOG_TARGET)▶️ deploy webapp$(LOG_END)"
	sudo rsync -avz ./webapp/ /home/isucon/webapp
	cd /home/isucon/webapp/ruby && /home/isucon/.x bundle install -j4
	sudo systemctl restart isupipe-ruby.service
	@printf "$(LOG_INFO)✅ webapp deployed$(LOG_END)"

####################
# REMOTE UTILITIES
####################

# mysql client
.PHONY: mysql
mysql:
	@printf "$(LOG_TARGET)▶️ start mysql client$(LOG_END)"
	mysql -h $(MYSQL_HOST) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DB)

.PHONY: rotate-log
rotate-log:
	@printf "$(LOG_TARGET)▶️ rotate log$(LOG_END)"
	$(MAKE) rotate-log-nginx
	$(MAKE) rotate-log-mysql

# nginx のログを rotate する
.PHONY: rotate-log-nginx
rotate-log-nginx:
	@printf "$(LOG_TARGET)▶️ rotate nginx log$(LOG_END)"
	sudo mv /var/log/nginx/access.log /var/log/nginx/access.$(TIMESTAMP).log
	sudo mv /var/log/nginx/error.log /var/log/nginx/error.$(TIMESTAMP).log
	sudo systemctl reload nginx
	@printf "$(LOG_INFO)✅ nginx log rotated (old: /var/log/nginx/access.$(TIMESTAMP).log)$(LOG_END)"; \

# mysql のスロークエリログをリセットする
.PHONY: rotate-log-mysql
rotate-log-mysql:
	@printf "$(LOG_TARGET)▶️ rotate mysql log$(LOG_END)"
	sudo mv /var/log/mysql/mysql-slow.log /var/log/mysql/mysql-slow.$(TIMESTAMP).log
	@printf "$(LOG_INFO)✅ mysql log rotated (old: /var/log/mysql/mysql-slow.$(TIMESTAMP).log)$(LOG_END)"; \

.PHONY: status
status:
	@printf "$(LOG_TARGET)▶️ status$(LOG_END)"
	sudo systemctl status nginx mysql isupipe-ruby

####################
# REMOTE SETUP
####################

# リモートに環境構築する
.PHONY: setup-remote
setup-remote:
	@printf "$(LOG_TARGET)▶️ setup$(LOG_END)"
	$(MAKE) install-packages
	$(MAKE) update-authorized-keys

# テスト用パッケージをインストールする
.PHONY: install-packages
install-packages:
	@printf "$(LOG_TARGET)▶️ install packages$(LOG_END)"
	@if which alp > /dev/null; then \
		printf "$(LOG_INFO)✅ alp already installed$(LOG_END)"; \
	else \
		curl -sfL https://github.com/tkuchiki/alp/releases/download/v$(ALP_VERSION)/alp_$(shell uname -s | tr '[:upper:]' '[:lower:]')_$(shell uname -m | sed 's/x86_64/amd64/').tar.gz | sudo tar xz -C /usr/local/bin; \
		alp --version; \
		printf "$(LOG_INFO)✅ alp installed$(LOG_END)"; \
	fi
	@if which ab dstat pt-query-digest > /dev/null; then \
		printf "$(LOG_INFO)✅ packages already installed$(LOG_END)"; \
	else \
		sudo apt update -q; \
		sudo apt install -y apache2-utils dstat percona-toolkit; \
		printf "$(LOG_INFO)✅ apt install finished$(LOG_END)"; \
		ab -V; \
		printf "$(LOG_INFO)✅ ab installed$(LOG_END)"; \
		dstat --version; \
		printf "$(LOG_INFO)✅ dstat installed$(LOG_END)"; \
		pt-query-digest --version; \
		printf "$(LOG_INFO)✅ pt-query-digest installed$(LOG_END)"; \
	fi

# authozize_keys を設定する
# 例: $ make update-authorized-keys USERS=fohte,foo,bar
.PHONY: update-authorized-keys
update-authorized-keys:
	@printf "$(LOG_TARGET)▶️ update authorized_keys$(LOG_END)"
	@IFS=, ; \
	for user in $(USERS); do \
		curl -fs https://github.com/$$user.keys >> ~/.ssh/authorized_keys; \
	done
	@printf "$(LOG_INFO)✅ authorized_keys updated$(LOG_END)"

/etc/profile.d/env.sh:
	@printf "$(LOG_TARGET)▶️ set env$(LOG_END)"
	@echo 'export HOSTNAME=$(shell hostname)' | sudo tee /etc/profile.d/env.sh
	@printf "$(LOG_INFO)✅ env set. please re-login$(LOG_END)"

####################
# LOCAL TASKS
####################

# (ローカル用) .ssh/config に ISUCON インスタンスを追記する
# 例: $ make update-ssh-config
.PHONY: update-ssh-config
update-ssh-config:
	@printf "$(LOG_TARGET)▶️ update .ssh/config$(LOG_END)"
	@count=1 ; \
	for ip in $(SERVER_1) $(SERVER_2) $(SERVER_3); do \
		host_name="$(SSH_HOSTNAME_PREFIX)-$$count"; \
		if ! grep -q "Host $$host_name" ~/.ssh/config; then \
			sed -i "1iHost $$host_name\n  HostName $$ip\n  User $(SSH_USERNAME)\n" ~/.ssh/config; \
			printf "$(LOG_INFO)✅ SSH config for $$host_name added$(LOG_END)"; \
		else \
			printf "$(LOG_WARN)⚠️ SSH config for $$host_name already exists, skipped$(LOG_END)"; \
		fi; \
		count=$$((count + 1)) ; \
	done

.PHONY: set-remote-hostname
set-remote-hostname:
	@printf "$(LOG_TARGET)▶️ set hostname$(LOG_END)"
	@count=1 ; \
	for ip in $(SERVER_1) $(SERVER_2) $(SERVER_3); do \
		ssh $(SSH_USERNAME)@$$ip "sudo hostnamectl set-hostname $(SSH_HOSTNAME_PREFIX)-$$count"; \
		printf "$(LOG_INFO)✅ hostname set for $(SSH_HOSTNAME_PREFIX)-$$count$(LOG_END)"; \
		count=$$((count + 1)) ; \
	done
