# API Gateway Nginx de SIEASAS. Contexto de construcción: gateway/
# La imagen solo lleva nginx.conf; la compilación web de Flutter se monta como volumen de
# solo lectura y los certificados TLS, cuando se usen, también: nunca entran a la imagen.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
