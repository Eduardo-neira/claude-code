# Fundamentos de Node.js — API REST con Express

Proyecto de ejemplo, pequeño y funcional, que ilustra los **fundamentos de
Node.js** en la práctica: sistema de módulos (ES Modules), gestión de
dependencias con **npm**, y una **API REST con Express** organizada en capas
(rutas → controladores → modelo) con middleware y manejo de errores.

## ¿Qué demuestra?

| Fundamento | Dónde verlo |
|------------|-------------|
| Módulos ES (`import` / `export`) | todos los archivos de `src/` |
| Separación en capas | `routes/` → `controllers/` → `models/` |
| Middleware | `src/middlewares/logger.js` |
| Manejo de errores centralizado | `src/middlewares/errorHandler.js` |
| CRUD REST completo | `src/routes/tareas.js` |
| Variables de entorno (`process.env`) | `index.js` (`PORT`) |
| Scripts de npm | `package.json` (`start`, `dev`, `test`) |
| Testing sin dependencias externas | `test/tareas.test.js` (`node:test`) |

## Estructura

```
nodejs-fundamentals/
├── package.json          # metadatos, dependencias y scripts
├── .gitignore            # ignora node_modules, .env, etc.
├── index.js              # punto de entrada: arranca el servidor
├── src/
│   ├── app.js            # crea y configura la app Express
│   ├── routes/
│   │   └── tareas.js     # define las URLs del recurso "tareas"
│   ├── controllers/
│   │   └── tareas.js     # lógica de negocio
│   ├── models/
│   │   └── tarea.js      # acceso a datos (en memoria)
│   └── middlewares/
│       ├── logger.js         # registra cada petición
│       └── errorHandler.js   # 404 y errores 500
└── test/
    └── tareas.test.js    # pruebas de la API
```

## Requisitos

- Node.js 18 o superior (usa `fetch` nativo y `node --watch`).

## Cómo ejecutarlo

```bash
cd examples/nodejs-fundamentals

# 1. Instalar dependencias (crea node_modules/)
npm install

# 2. Arrancar el servidor
npm start
# o en modo desarrollo (reinicia al guardar cambios):
npm run dev
```

El servidor queda en `http://localhost:3000`.

## Probar los endpoints

```bash
# Listar todas las tareas
curl http://localhost:3000/tareas

# Obtener una tarea
curl http://localhost:3000/tareas/1

# Crear una tarea
curl -X POST http://localhost:3000/tareas \
  -H "Content-Type: application/json" \
  -d '{"texto": "Mi nueva tarea"}'

# Actualizar una tarea
curl -X PUT http://localhost:3000/tareas/1 \
  -H "Content-Type: application/json" \
  -d '{"hecho": true}'

# Borrar una tarea
curl -X DELETE http://localhost:3000/tareas/1
```

## Ejecutar los tests

```bash
npm test
```

## Endpoints disponibles

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/` | Mensaje de bienvenida y lista de endpoints |
| GET | `/tareas` | Lista todas las tareas |
| GET | `/tareas/:id` | Obtiene una tarea por id |
| POST | `/tareas` | Crea una tarea — body `{ "texto": "..." }` |
| PUT | `/tareas/:id` | Actualiza una tarea — body `{ "texto": "...", "hecho": true }` |
| DELETE | `/tareas/:id` | Borra una tarea |

## Notas

- Los datos viven **en memoria**: se reinician cada vez que arranca el
  servidor. En una app real, el modelo (`src/models/tarea.js`) hablaría con
  una base de datos.
- `node_modules/` **no se sube a git** (ver `.gitignore`); se regenera con
  `npm install`.
