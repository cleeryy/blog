# Blog

Hugo blog for [cleeryy.com](https://cleeryy.com) and [blog.cleeryy.cloud](https://blog.cleeryy.cloud) with automated Docker deployment. Restored from VPS backup (April 2026), theme terminal.

## Features

- Hugo static site generator
- Docker containerization
- GitHub Actions CI/CD
- Automated deployment on push
- Multi-architecture builds (amd64, arm64)

## Local Development

```bash
# Clone the repository
git clone https://github.com/cleeryy/blog.git
cd blog

# Start Hugo with hot reload
docker-compose up

# Site will be available at http://localhost:1313
```

## Deployment

Push to the `master` branch to automatically build and deploy the blog.

## Requirements

- Docker and Docker Compose
- Hugo (for local development without Docker)
- GitHub account

## License

MIT