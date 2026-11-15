#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
# Undo only the anti-bruteforce block created by automated bad-password probes.
# Never clear real user blocks, permanent deny entries or the global login security config.
"$D" -H "$S" exec sf-jumper-db sh -ec '
 . /run/jumper-db.env
 mariadb -N -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" 2>/dev/null <<SQL
SELECT "TEST_RUNNER_BLOCK_BEFORE",COUNT(*) FROM ip_lists WHERE address IN ("172.22.0.1","::ffff:172.22.0.1") AND list_type="deny" AND reason="Login attempts limit reached." AND expires_at > NOW();
UPDATE ip_lists SET expires_at=NOW() - INTERVAL 1 SECOND
 WHERE address IN ("172.22.0.1","::ffff:172.22.0.1")
 AND list_type="deny" AND reason="Login attempts limit reached."
 AND expires_at > NOW();
SELECT "TEST_RUNNER_BLOCK_AFTER",COUNT(*) FROM ip_lists WHERE address IN ("172.22.0.1","::ffff:172.22.0.1") AND list_type="deny" AND reason="Login attempts limit reached." AND expires_at > NOW();
SQL
'
# Only this isolated MMO container is restarted; DB and all other containers remain untouched.
"$D" -H "$S" restart sf-jumper >/dev/null
echo JUMPER_ONLY_GAME_CONTAINER_RESTARTED
for attempt in $(seq 1 45); do
 if curl -fsS --max-time 5 -o /tmp/jumper-restarted-body http://127.0.0.1:18766/ && grep -q JUMPER /tmp/jumper-restarted-body; then
   echo JUMPER_AUTH_UNBLOCK_AND_HEALTH=VERIFIED
   exit 0
 fi
 sleep 3
done
echo JUMPER_HEALTH_AFTER_RESTART=FAILED
exit 1
