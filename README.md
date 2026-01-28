# Blog

Hugo blog for [cleeryy.com](https://cleeryy.com) and [blog.cleeryy.com](https://blog.cleeryy.com) with automated Docker deployment.

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