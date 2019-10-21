FROM alpine:3.10

RUN apk add bash curl git gnupg jq

COPY LICENSE NOTICE README.md entrypoint.sh gpg-wrapper /

ENTRYPOINT ["/entrypoint.sh"]
