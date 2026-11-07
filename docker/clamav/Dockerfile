# clamd サイドカー用イメージ（HC-21）
#
# Alpine の clamav パッケージは arm64/amd64 対応で、clamav ユーザー（uid 100）を
# 含む。clamd 本体は egress を持たせず、DB 更新は updater サービス（同一イメージ）が担う。
FROM alpine:3.22

RUN apk add --no-cache clamav

COPY clamd.conf /etc/clamav/clamd.conf
COPY freshclam.conf /etc/clamav/freshclam.conf

RUN mkdir -p /var/run/clamav \
  && chown -R clamav:clamav /var/run/clamav /var/lib/clamav /etc/clamav

USER clamav:clamav

EXPOSE 3310

CMD ["/usr/sbin/clamd", "--foreground=yes", "--config-file=/etc/clamav/clamd.conf"]
