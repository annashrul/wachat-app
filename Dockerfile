# Image web: nginx menyajikan hasil `flutter build web` (build/web).
# Folder build/web dihasilkan oleh langkah Cloud Build sebelum docker build.
FROM nginx:alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 8080
