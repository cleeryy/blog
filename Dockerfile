# Use official Hugo image as builder
FROM klakegg/hugo:ext-alpine AS builder

# Set working directory
WORKDIR /src

# Copy project files
COPY . .

# Build the site
RUN hugo --minify

# Use nginx for serving
FROM nginx:alpine

# Copy built site from builder stage
COPY --from=builder /src/public /usr/share/nginx/html

# Copy custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]