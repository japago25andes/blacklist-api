#!/bin/bash
set -e

echo "⏳ Ejecutando migraciones..."
flask db upgrade

echo "🚀 Iniciando aplicación con Gunicorn..."
exec gunicorn run:app --bind 0.0.0.0:80 --workers 3 --worker-class gthread --threads 4 --timeout 120 --log-level info

