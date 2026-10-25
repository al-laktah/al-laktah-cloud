# restic, rclone and sqlite3 on restic's own (Alpine) image: no Postgres here, so
# this stays much smaller than the main VM's backup image.
FROM rclone/rclone:1.75.2 AS rclone

FROM restic/restic:0.19.1
RUN apk add --no-cache sqlite
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --chmod=0755 backup.sh scheduler.sh /usr/local/bin/

ENTRYPOINT []
CMD ["scheduler.sh"]
