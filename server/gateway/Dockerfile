FROM public.ecr.aws/nginx/nginx:1.27-alpine
COPY server/gateway/nginx.conf /etc/nginx/conf.d/default.conf
COPY server/gateway/40-dandori-config.sh /docker-entrypoint.d/40-dandori-config.sh
COPY 1_画面/ /site-src/
RUN chmod +x /docker-entrypoint.d/40-dandori-config.sh
