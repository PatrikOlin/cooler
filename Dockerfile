FROM ghcr.io/gleam-lang/gleam:v1.6.1-erlang-alpine AS builder

WORKDIR /app

# Copy project files
COPY gleam.toml manifest.toml ./
COPY src ./src
COPY priv ./priv

# Download dependencies and build
RUN gleam deps download
RUN gleam build --target javascript

# Production stage with nginx
FROM nginx:alpine

# Copy built JavaScript
COPY --from=builder /app/build/dev/javascript /usr/share/nginx/html/build/dev/javascript

# Copy static assets
COPY --from=builder /app/priv/static /usr/share/nginx/html/priv/static

# Copy index.html
COPY index.html /usr/share/nginx/html/

# Create a simple nginx config
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
