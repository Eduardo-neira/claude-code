// ---------------------------------------------------------------------------
// APP: construye y configura la aplicacion Express.
//
// Separar la creacion de la app (aqui) del arranque del servidor (index.js)
// es una buena practica: permite importar `app` en los tests sin abrir un
// puerto de red.
//
// Orden de la "cadena" de Express (se ejecuta de arriba hacia abajo):
//   1. middlewares globales (parseo de JSON, logging)
//   2. rutas de la aplicacion
//   3. middleware 404 (ninguna ruta coincidio)
//   4. middleware de errores (siempre al final)
// ---------------------------------------------------------------------------

import express from 'express';
import tareasRouter from './routes/tareas.js';
import { logger } from './middlewares/logger.js';
import { noEncontrado, manejadorErrores } from './middlewares/errorHandler.js';

export function crearApp() {
  const app = express();

  // 1. Middlewares globales -------------------------------------------------
  app.use(express.json()); // convierte el body JSON en req.body
  app.use(logger); //          registra cada peticion

  // Ruta de bienvenida / health check.
  app.get('/', (req, res) => {
    res.json({
      mensaje: 'API de ejemplo de fundamentos de Node.js',
      endpoints: [
        'GET    /tareas',
        'GET    /tareas/:id',
        'POST   /tareas       { "texto": "..." }',
        'PUT    /tareas/:id   { "texto": "...", "hecho": true }',
        'DELETE /tareas/:id',
      ],
    });
  });

  // 2. Rutas de la aplicacion ----------------------------------------------
  app.use('/tareas', tareasRouter);

  // 3. y 4. Manejo de errores (al final) -----------------------------------
  app.use(noEncontrado);
  app.use(manejadorErrores);

  return app;
}
