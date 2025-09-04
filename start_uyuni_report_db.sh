. .env
podman run --rm -ti -e POSTGRES_HOST_AUTH_METHOD=trust -e MANAGER_USER=not_needed -e MANAGER_PASS=not_needed -e MANAGER_DB_NAME=spacewalk  -e REPORT_DB_USER=$REPORT_DB_USER -e REPORT_DB_PASS=$REPORT_DB_PASS -e REPORT_DB_NAME=reportdb -p 5432:5432 --name=reportdb -v .:/test registry.opensuse.org/uyuni/server-postgresql:latest
