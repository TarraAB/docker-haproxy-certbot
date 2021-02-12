# HAProxy 2.0.3 with Certbot
FROM alpine:3.10

ENV HAPROXY_MAJOR 2.0
ENV HAPROXY_VERSION 2.0.3
ENV HAPROXY_SHA256 aac1ff3e5079997985b6560f46bf265447d0cd841f11c4d77f15942c9fe4b770

RUN set -x && apk add --no-cache --virtual .build-deps \
    ca-certificates \
    gcc \
    libc-dev \
    linux-headers \
    lua5.3-dev \
    make \
    openssl \
    openssl-dev \
    pcre2-dev \
    readline-dev \
    tar \
    zlib-dev \
  && wget -O haproxy.tar.gz "https://www.haproxy.org/download/${HAPROXY_MAJOR}/src/haproxy-${HAPROXY_VERSION}.tar.gz" \
  && echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c \
  && mkdir -p /usr/src/haproxy \
  && tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1 \
  && rm haproxy.tar.gz \
  && makeOpts=' \
    TARGET=linux-glibc \
    USE_GETADDRINFO=1 \
		USE_LUA=1 LUA_INC=/usr/include/lua5.3 LUA_LIB=/usr/lib/lua5.3 \
    USE_OPENSSL=1 \
    USE_PCRE2=1 USE_PCRE2_JIT=1 \
    USE_ZLIB=1 \
    EXTRA_OBJS=" \
# see https://github.com/docker-library/haproxy/issues/94#issuecomment-505673353 for more details about prometheus support
			contrib/prometheus-exporter/service-prometheus.o \
		" \
  ' \
  && nproc="$(getconf _NPROCESSORS_ONLN)" \
  && eval "make -C /usr/src/haproxy -j '$nproc' all $makeOpts" \
  && eval "make -C /usr/src/haproxy install-bin $makeOpts" \
  && mkdir -p /usr/local/etc/haproxy \
  && cp -R /usr/src/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors \
  && rm -rf /usr/src/haproxy \
  && runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )" \
  && apk add --virtual .haproxy-rundeps $runDeps \
  && apk del .build-deps \
  && apk add --no-cache --update \
    supervisor \
    dcron \
    libnl3-cli \
    net-tools \
    iproute2 \
    certbot \
    curl \
    openssl \
    lua5.3-socket \
    perl \
  && rm -rf /var/cache/apk/* \
  && mkdir -p /var/log/supervisor \
  && mkdir -p /usr/local/etc/haproxy/certs.d \
  && mkdir -p /usr/local/etc/letsencrypt \
  && curl https://ssl-config.mozilla.org/ffdhe2048.txt > /etc/ssl/dhparam.pem

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY certbot.cron /etc/cron.d/certbot
COPY cli.ini /usr/local/etc/letsencrypt/cli.ini
COPY haproxy-refresh.sh /usr/bin/haproxy-refresh
COPY haproxy-restart.sh /usr/bin/haproxy-restart
COPY haproxy-check.sh /usr/bin/haproxy-check
COPY certbot-certonly.sh /usr/bin/certbot-certonly
COPY certbot-renew.sh /usr/bin/certbot-renew
COPY start.sh /start.sh
RUN chmod +x /usr/bin/haproxy-refresh /usr/bin/haproxy-restart /usr/bin/haproxy-check /usr/bin/certbot-certonly /usr/bin/certbot-renew /start.sh

# add missing socket path
RUN mkdir /run/haproxy

EXPOSE 80 443
VOLUME ["/config/", "/etc/letsencrypt/", "/usr/local/etc/haproxy/certs.d/"]

# Start
CMD ["/start.sh"]
