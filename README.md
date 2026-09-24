# shibboleth-sp-nginx

nginx + Shibboleth SP (FastCGI) on Debian trixie.

Based on the idea of pennlabs/infrastructure `shibboleth-sp-nginx`, rebuilt with:

- **Debian trixie** (slim) base image
- **nginx** from the official nginx.org mainline repository
- **nginx-http-shibboleth** and **headers-more** dynamic modules built with
  [nginx/pkg-oss](https://github.com/nginx/pkg-oss) `build_module.sh`,
  guaranteeing ABI compatibility with the installed nginx version
- **Shibboleth SP** (shibd + FastCGI authorizer/responder) from Debian packages
- **supervisord** running nginx, shibd, shibauthorizer and shibresponder

## Build

```bash
docker build -t shibboleth-sp-nginx \
  --build-arg DEBIAN_VERSION=trixie \
  --build-arg NGINX_VERSION=1.29.2 .
