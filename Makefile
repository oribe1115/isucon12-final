include env
ENV_FILE:=env
# 変数定義 ------------------------

# SERVER_ID: ENV_FILE内で定義

# 問題によって変わる変数
USER:=isucon
BIN_NAME:=isuconquest
BUILD_DIR:=/home/isucon/webapp/go
SERVICE_NAME:=$(BIN_NAME).go.service

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system

NGINX_LOG:=/var/log/nginx/access.log
DB_SLOW_LOG:=/var/log/mysql/mysql-slow.log

# http://localhost:19999/netdata.confのdirectories.webで確認可能
NETDATA_WEBROOT_PATH:=/var/lib/netdata/www
NETDATA_CUSTUM_HTML:=tool-config/netdata/*

DISCOCAT_TRIPLE_BACK_QUOTES:=tool-config/discocat/triple-back-quotes.txt
DISCOCAT_TMPFILE:=tmp/discocat

# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
setup: install-tools git-setup

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-service-file deploy-envsh

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench: check-server-id discocat-now-status rm-logs deploy-conf build restart watch-service-log

# slow queryを確認する
.PHONY: slow-query
slow-query:
	sudo pt-query-digest --filter 'length($$event->{arg}) <= 2000' $(DB_SLOW_LOG)

.PHONY: discocat-slow-query
discocat-slow-query:
	@make refresh-descocat-tmp
	echo "SERVER_ID: $(SERVER_ID)" >> $(DISCOCAT_TMPFILE)
	echo "" >> $(DISCOCAT_TMPFILE)
	@make slow-query >> $(DISCOCAT_TMPFILE)
	cat $(DISCOCAT_TMPFILE) | discocat

# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=/home/isucon/tool-config/alp/config.yml

.PHONY: discocat-alp
discocat-alp:
	@make refresh-descocat-tmp
	cat $(DISCOCAT_TRIPLE_BACK_QUOTES) >> $(DISCOCAT_TMPFILE)
	echo "" >> $(DISCOCAT_TMPFILE)
	echo "SERVER_ID: $(SERVER_ID)" >> $(DISCOCAT_TMPFILE)
	echo "" >> $(DISCOCAT_TMPFILE)
	@make alp >> $(DISCOCAT_TMPFILE)
	cat $(DISCOCAT_TRIPLE_BACK_QUOTES) >> $(DISCOCAT_TMPFILE)
	cat $(DISCOCAT_TMPFILE) | discocat

# pprofで記録する
.PHONY: pprof-record
pprof-record:
	echo "start pprof-record" | discocat
	#go tool pprof -top http://localhost:6060/debug/fgprof
	go tool pprof -top http://localhost:6060/debug/pprof/profile
	$(eval latest := $(shell ls -rt pprof/ | tail -n 1))
	echo "finish pprof-record\ncreated: $(latest)" | discocat

# pprofで確認する
.PHONY: pprof-check
pprof-check:
	$(eval latest := $(shell ls -rt pprof/ | tail -n 1))
	go tool pprof -http=localhost:8090 pprof/$(latest)

# DBに接続する
.PHONY: access-db
access-db:
	mysql -h $(ISUCON_DB_HOST) -P $(ISUCON_DB_PORT) -u $(ISUCON_DB_USER) -p$(ISUCON_DB_PASSWORD) $(ISUCON_DB_NAME)

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	sudo apt update
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree

	# alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.11/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_amd64.zip alp

	# netdataのインストール
	wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh && sh /tmp/netdata-kickstart.sh

.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "isucon@example.com"
	git config --global user.name "isucon"

	# deploykeyの作成
	ssh-keygen -t ed25519

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s1" >> $(ENV_FILE)

.PHONY: set-as-s2
set-as-s2:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s2" >> $(ENV_FILE)

.PHONY: set-as-s3
set-as-s3:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s3" >> $(ENV_FILE)

.PHONY: set-as-s4
set-as-s4:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s4" >> $(ENV_FILE)

.PHONY: set-as-s5
set-as-s5:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s5" >> $(ENV_FILE)

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* ~/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* ~/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	sudo chown $(USER) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	cp ~/$(ENV_FILE) ~/$(SERVER_ID)/home/isucon/$(ENV_FILE)

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	sudo cp ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

.PHONY: deploy-envsh
deploy-envsh:
	cp ~/$(SERVER_ID)/home/isucon/$(ENV_FILE) ~/$(ENV_FILE)

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart mysql
	sudo systemctl restart nginx

.PHONY: mv-logs
mv-logs:
	$(eval when := $(shell date "+%s"))
	sudo test -f $(NGINX_LOG) && \
            mkdir -p ~/logs/nginx/$(when) && \
	    sudo mv -f $(NGINX_LOG) ~/logs/nginx/$(when)/ || echo ""
	sudo test -f $(DB_SLOW_LOG) && \
		mkdir -p ~/logs/mysql/$(when) && \
		sudo mv -f $(DB_SLOW_LOG) ~/logs/mysql/$(when)/ || echo ""

.PHONY: rm-logs
rm-logs:
	sudo rm -f $(NGINX_LOG)
	sudo rm -f $(DB_SLOW_LOG)

.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f

.PHONY: netdata-setup
netdata-setup:
	sudo cp $(NETDATA_CUSTUM_HTML) $(NETDATA_WEBROOT_PATH)/

.PHONY: $(DISCOCAT_TMPFILE)
refresh-descocat-tmp:
	rm -f $(DISCOCAT_TMPFILE)
	mkdir -p tmp
	touch $(DISCOCAT_TMPFILE)

.PHONY: discocat-now-status
discocat-now-status:
	@make refresh-descocat-tmp
	echo "----------------------------------------------------------------" >> $(DISCOCAT_TMPFILE)
	cat $(DISCOCAT_TRIPLE_BACK_QUOTES) >> $(DISCOCAT_TMPFILE)
	echo "SERVER_ID: $(SERVER_ID)" >> $(DISCOCAT_TMPFILE)
	git branch --contains=HEAD >> $(DISCOCAT_TMPFILE)
	TZ=JST-9 date >> $(DISCOCAT_TMPFILE)
	echo "" >> $(DISCOCAT_TMPFILE)
	git show -s >> $(DISCOCAT_TMPFILE)
	cat $(DISCOCAT_TRIPLE_BACK_QUOTES) >> $(DISCOCAT_TMPFILE)
	cat $(DISCOCAT_TMPFILE) | discocat

.PHONY: check-commit
check-commit:
	mkdir -p tmp/check-commit
	go run tool-config/check-commit/main.go
