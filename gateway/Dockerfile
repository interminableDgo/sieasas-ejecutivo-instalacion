# API Gateway Nginx de SIEASAS. Contexto de construcción: gateway/
# La imagen solo lleva nginx.conf; la compilación web de Flutter se monta como volumen de
# solo lectura y los certificados TLS, cuando se usen, también: nunca entran a la imagen.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Nginx corre como el usuario sin privilegios "nginx", no como root. Dentro del contenedor
# Docker permite escuchar en el puerto 80 sin root; solo hace falta que pueda escribir su caché
# y su archivo pid.
RUN sed -i -e '/^user /d' -e 's#^pid .*#pid /tmp/nginx.pid;#' /etc/nginx/nginx.conf \
    && chown -R nginx:nginx /var/cache/nginx
USER nginx
EXPOSE 80
