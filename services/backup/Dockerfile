# restic and rclone on top of the Postgres image, so pg_dump always matches
# Outline's Postgres major version.
FROM restic/restic:0.19.1 AS restic
FROM rclone/rclone:1.75.2 AS rclone

FROM postgres:18-alpine
# su-exec is installed explicitly; the base image's own user-switching tool has changed before.
RUN apk add --no-cache ca-certificates sqlite su-exec
COPY --from=restic /usr/bin/restic /usr/local/bin/restic
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --chmod=0755 backup.sh scheduler.sh /usr/local/bin/

ENTRYPOINT []
CMD ["scheduler.sh"]
