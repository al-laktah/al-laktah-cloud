# restic and rclone on top of the Postgres image, so the scratch restore of
# Outline's database uses the same Postgres major version that made the dump.
FROM restic/restic:0.19.1 AS restic
FROM rclone/rclone:1.75.2 AS rclone

FROM postgres:18-alpine
RUN apk add --no-cache ca-certificates jq sqlite su-exec
COPY --from=restic /usr/bin/restic /usr/local/bin/restic
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --chmod=0755 check.sh scheduler.sh /usr/local/bin/

ENTRYPOINT []
CMD ["scheduler.sh"]
