import unittest
from flask import Flask
from app.routes import bp
from app.models import BlacklistedEmail
from app import db
import os
from dotenv import load_dotenv

load_dotenv(dotenv_path='.env.test')

class RoutesTestCase(unittest.TestCase):
    def setUp(self):
        self.database_url = os.getenv('DATABASE_URL', 'sqlite:///:memory:')
        self.test_token = os.getenv('AUTH_TOKEN')

        self.app = Flask(__name__)
        self.app.config['TESTING'] = True
        self.app.config['AUTH_TOKEN'] = os.getenv('AUTH_TOKEN')
        self.app.register_blueprint(bp)
        self.client = self.app.test_client()

        # Configurar base de datos para las pruebas
        self.app.config['SQLALCHEMY_DATABASE_URI'] = self.database_url
        db.init_app(self.app)
        with self.app.app_context():
            db.create_all()

    def tearDown(self):
        # Limpiar la base de datos
        with self.app.app_context():
            db.session.remove()
            db.drop_all()

    def test_add_to_blacklist_success(self):
        # Prueba para agregar un email a la lista negra exitosamente
        headers = {'Authorization': f'Bearer {self.test_token}'}
        data = {
            'email': 'test@example.com',
            'app_uuid': '12345',
            'blocked_reason': 'Spam'
        }

        response = self.client.post('/blacklists', json=data, headers=headers)
        self.assertEqual(response.status_code, 201)

    def test_add_to_blacklist_missing_fields(self):
        # Prueba para campos faltantes
        headers = {'Authorization': f'Bearer {self.test_token}'}
        data = {'email': 'test@example.com'}
        response = self.client.post('/blacklists', json=data, headers=headers)
        self.assertEqual(response.status_code, 400)
        self.assertIn("Los campos 'email' y 'app_uuid' son obligatorios", response.get_json()['error'])

    def test_add_to_blacklist_invalid_token(self):
        # Prueba para token inválido
        headers = {'Authorization': 'Bearer token_invalido'}
        data = {
            'email': 'test@example.com',
            'app_uuid': '12345'
        }
        response = self.client.post('/blacklists', json=data, headers=headers)
        self.assertEqual(response.status_code, 403)
        self.assertIn('Token inválido', response.get_json()['error'])

    def test_check_blacklist_found(self):
        # Prueba para verificar un email en la lista negra
        with self.app.app_context():
            entry = BlacklistedEmail(
                email='test@example.com',
                app_uuid='12345',
                blocked_reason='Spam',
                ip_address='127.0.0.1'
            )
            db.session.add(entry)
            db.session.commit()

        headers = {'Authorization': f'Bearer {self.test_token}'}
        response = self.client.get('/blacklists/test@example.com', headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()['is_blacklisted'])
        self.assertEqual(response.get_json()['blocked_reason'], 'Spam')

    def test_check_blacklist_not_found(self):
        # Prueba para email no encontrado en la lista negra
        headers = {'Authorization': f'Bearer {self.test_token}'}
        response = self.client.get('/blacklists/notfound@example.com', headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.get_json()['is_blacklisted'])

    def test_health_endpoint(self):
        # Prueba para el endpoint de salud
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data.decode('utf-8'), 'OK')

if __name__ == '__main__':
    unittest.main()