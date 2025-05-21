# Usa una imagen base de Python
FROM public.ecr.aws/docker/library/python:3.11-slim

# Establece el directorio de trabajo dentro del contenedor
WORKDIR /app

# Copia los archivos del proyecto al contenedor
COPY . .

# Instala las dependencias
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

RUN pip install newrelic

ENV FLASK_APP=run.py


ENV NEW_RELIC_APP_NAME="Blacklist-Command-Line-Heroes"
ENV NEW_RELIC_LOG=stdout
ENV NEW_RELIC_DISTRIBUTED_TRACING_ENABLED=true
ENV NEW_RELIC_LICENSE_KEY={Licencia de New Relic}
ENV NEW_RELIC_LOG_LEVEL=info

EXPOSE 5000

COPY entrypoint.sh .
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]

# Comando por defecto para ejecutar la aplicación
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "run:app"]
