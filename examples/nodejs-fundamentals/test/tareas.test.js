// ---------------------------------------------------------------------------
// TESTS con el runner nativo de Node (node:test), sin librerias externas.
//
// Ejecutar con: npm test  (que corre `node --test`).
//
// Levantamos la app en un puerto efimero y le hacemos peticiones reales con
// fetch (disponible de forma nativa desde Node 18).
// ---------------------------------------------------------------------------

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { crearApp } from '../src/app.js';

let server;
let baseUrl;

before(async () => {
  const app = crearApp();
  // Puerto 0 = el sistema operativo asigna uno libre automaticamente.
  await new Promise((resolve) => {
    server = app.listen(0, () => {
      const { port } = server.address();
      baseUrl = `http://localhost:${port}`;
      resolve();
    });
  });
});

after(() => {
  server.close();
});

test('GET /tareas devuelve una lista', async () => {
  const res = await fetch(`${baseUrl}/tareas`);
  assert.equal(res.status, 200);
  const tareas = await res.json();
  assert.ok(Array.isArray(tareas));
});

test('POST /tareas crea una tarea', async () => {
  const res = await fetch(`${baseUrl}/tareas`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ texto: 'Tarea de prueba' }),
  });
  assert.equal(res.status, 201);
  const creada = await res.json();
  assert.equal(creada.texto, 'Tarea de prueba');
  assert.equal(creada.hecho, false);
});

test('POST /tareas sin texto devuelve 400', async () => {
  const res = await fetch(`${baseUrl}/tareas`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.equal(res.status, 400);
});

test('GET /tareas/:id inexistente devuelve 404', async () => {
  const res = await fetch(`${baseUrl}/tareas/99999`);
  assert.equal(res.status, 404);
});
