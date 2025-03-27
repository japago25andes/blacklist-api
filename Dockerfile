# Usa una imagen base de Python
FROM python:3.11-slim

# Establece el directorio de trabajo dentro del contenedor
WORKDIR /app

# Copia los archivos del proyecto al contenedor
COPY . .

# Instala las dependencias
RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# Expone el puerto (Flask por defecto usa el 5000)
EXPOSE 5000

# Comando por defecto para ejecutar la aplicación
CMD ["python", "run.py"]
