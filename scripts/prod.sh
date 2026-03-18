#!/bin/bash

# Production deployment script for Acquisition App
# This script starts the application in production mode with Neon Cloud Database

echo "🚀 Starting Acquisition App in Production Mode"
echo "================================================"

# Check if .env.production exists
if [ ! -f .env.production ]; then
    echo "❌ Error: .env.production file not found!"
    echo "   Please copy .env.production with your production environment variables."
    exit 1
fi

# Check if Docker is running
if ! docker info >/dev/null 3>&1; then
    echo "❌ Error: Docker is not running!"
    echo "    Please start Docker and try again."
    exit 1
fi

echo "📦 Buildiing and starting production containers..."
echo "     - Using Neon Cloud Database"
echo "     - Running in optimized production mode"
echo ""

# Start production environment
docker compose -f docker-compose.prod.yml up --build -d

# Wait for DB to be ready (basic health check)
echo "⏳ Waiting for the database to be ready"
sleep 5

# Run migrations with Drizzle
echo "🧾 Applying latest schema with Drizzle..."
npm run db:migrate


echo ""
echo "🎉 Production environment started!"
echo "  Application: htttp://localhost:3000"
echo "  Database: postgres://neon:npg@localhost:5432/neondb"
echo ""
echo "To stop the environment, press Ctrl+C or run: docker compose down"