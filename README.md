# Blacklist Email Microservice

Este microservicio permite gestionar una **lista negra global de emails** para una compañía multinacional. Fue diseñado para que distintas aplicaciones internas puedan:

- Agregar un email a la lista negra
- Consultar si un email está en la lista negra

Todo está desplegado en contenedores Docker, con PostgreSQL como base de datos y Flask como framework backend.

---

## 💡 Características principales

- API RESTful con Flask
- PostgreSQL para persistencia
- Migraciones con Flask-Migrate
- Autenticación con token Bearer estático
- Normalización de emails (minúsculas, sin espacios)
- Contenedores orquestados con Docker Compose

---

## 🌐 Endpoints

### POST `/blacklists`
Agrega un email a la lista negra.

**Headers:**
- `Authorization: Bearer <AUTH_TOKEN>`
- `Content-Type: application/json`

**Body JSON:**
```json
{
  "email": "usuario@example.com",
  "app_uuid": "123e4567-e89b-12d3-a456-426614174000",
  "blocked_reason": "Uso fraudulento"
}
```

**Respuesta:**
```json
{
  "message": "Email agregado a la lista negra exitosamente"
}
```

---

### GET `/blacklists/<email>`
Consulta si un email está en la lista negra.

**Headers:**
- `Authorization: Bearer <AUTH_TOKEN>`

**Respuesta si existe:**
```json
{
  "is_blacklisted": true,
  "blocked_reason": "Uso fraudulento"
}
```

**Respuesta si NO existe:**
```json
{
  "is_blacklisted": false
}
```

---

## ⚙️ Requisitos previos
- Docker
- Docker Compose
- Git
- WSL2 si estás en Windows

---

## 🚀 Despliegue local paso a paso

### 1. Clona el repositorio
```bash
git clone https://github.com/TU_USUARIO/blacklist-api.git
cd blacklist-api
```

### 2. Levanta los contenedores
```bash
docker-compose up --build -d
```

### 3. Inicializa la base de datos
```bash
docker-compose exec web flask db init
docker-compose exec web flask db migrate -m "initial"
docker-compose exec web flask db upgrade
```

### 4. Verifica que el servicio esté corriendo
Abre en el navegador o Postman:
```
POST http://localhost:5000/blacklists
```

---

## 📓 Variables importantes

Las variables están definidas en `docker-compose.yml` como variables de entorno:

- `AUTH_TOKEN`: Token estático para autorización
- `DATABASE_URL`: Cadena de conexión PostgreSQL para SQLAlchemy

---

## 🧪 Ejecución de pruebas

Sigue estos pasos para configurar el entorno y ejecutar las pruebas unitarias:

### 1. Crea un entorno virtual
Primero, asegúrate de tener Python instalado en tu máquina. Luego, crea y activa un entorno virtual:

```bash
python3 -m venv venv
source venv/bin/activate 
```

### 2. Instala las dependencias
```bash
pip install -r requirements.txt
```

### 3. Ejecutar las pruebas unitarias
```bash
python -m unittest discover tests
```
