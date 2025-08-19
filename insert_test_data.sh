podman exec -ti reportdb psql reportdb -U $REPORT_DB_USER -h localhost -f /test/test_data.sql
