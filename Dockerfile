FROM ghcr.io/processone/ejabberd:22.05

USER root

RUN apk add --update --no-cache php8 php8-curl composer coreutils sudo gettext curl

RUN echo http://dl-2.alpinelinux.org/alpine/edge/community/ >> /etc/apk/repositories
RUN apk --no-cache add shadow jo

RUN curl -fsSL -o /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
RUN chmod +x /usr/local/bin/dbmate

#USER ejabberd

COPY ./startup.sh /opt/ejabberd/startup.sh

ENTRYPOINT ["/opt/ejabberd/startup.sh"]
CMD ["foreground"]