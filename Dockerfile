# syntax=docker/dockerfile:1

ARG DEBIAN_VERSION=trixie
ARG NGINX_VERSION=1.29.2

############################################
# Stage 1: build dynamic nginx modules (pkg-oss)
############################################
FROM debian:${DEBIAN_VERSION}-slim AS modbuilder
ARG NGINX_VERSION
ARG DEBIAN_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg2 git lsb-release \
        build-essential devscripts debhelper dpkg-dev quilt \
        libpcre2-dev zlib1g-dev libssl-dev libxslt1-dev \
        libgd-dev libgeoip-dev \
    && rm -rf /var/lib/apt/lists/*

# Add nginx.org repository (source packages are required to build modules)
RUN curl -fsSL https://nginx.org/keys/nginx_signing.key \
        | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian ${DEBIAN_VERSION} nginx" \
        > /etc/apt/sources.list.d/nginx.list \
    && echo "deb-src [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian ${DEBIAN_VERSION} nginx" \
        >> /etc/apt/sources.list.d/nginx.list \
    && apt-get update

WORKDIR /build
RUN git clone --depth 1 https://github.com/nginx/pkg-oss.git

# Build: nginx-http-shibboleth + headers-more (required by the Shibboleth module)
WORKDIR /build/pkg-oss
RUN mkdir -p /build/debs \
    && ./build_module.sh -y -o /build/debs -v ${NGINX_VERSION} \
        -n shibboleth https://github.com/nginx-shib/nginx-http-shibboleth.git \
    && ./build_module.sh -y -o /build/debs -v ${NGINX_VERSION} \
        -n headersmore https://github.com/openresty/headers-more-nginx-module.git \
    # Fail the build early if no packages were produced
    && ls -l /build/debs \
    && test -n "$(find /build/debs -name 'nginx-module-*.deb')"

############################################
# Stage 2: runtime image
############################################
FROM debian:${DEBIAN_VERSION}-slim
ARG NGINX_VERSION
ARG DEBIAN_VERSION

LABEL org.opencontainers.image.description="nginx + Shibboleth SP (FastCGI) on Debian" \
      org.opencontainers.image.source="https://github.com/YOUR-ORG/shibboleth-sp-nginx"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg2 supervisor \
    && curl -fsSL https://nginx.org/keys/nginx_signing.key \
        | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian ${DEBIAN_VERSION} nginx" \
        > /etc/apt/sources.list.d/nginx.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx=${NGINX_VERSION}-1~${DEBIAN_VERSION} \
        shibboleth-sp-common shibboleth-sp-utils libshibsp-plugins \
    && rm -rf /var/lib/apt/lists/*

# Install the dynamic modules built in the previous stage
COPY --from=modbuilder /build/debs/ /tmp/debs/
RUN dpkg -i /tmp/debs/*.deb && rm -rf /tmp/debs

# Configuration
COPY nginx/nginx.conf            /etc/nginx/nginx.conf
COPY nginx/conf.d/               /etc/nginx/conf.d/
COPY nginx/shib_clear_headers    /etc/nginx/shib_clear_headers
COPY nginx/shib_fastcgi_params   /etc/nginx/shib_fastcgi_params
COPY --chmod=0644 nginx/cert.pem /etc/nginx/cert.pem
COPY --chmod=0600 nginx/key.pem  /etc/nginx/key.pem
COPY shibboleth/                 /etc/shibboleth/
COPY supervisord.conf            /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /run/shibboleth /var/log/shibboleth /var/log/supervisor \
    && chown -R _shibd:_shibd /run/shibboleth /var/log/shibboleth /var/cache/shibboleth \
    # Send logs to stdout/stderr, same behavior as the original image
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80 443
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
