// ---------------------------------------------------------------------------
// CONTROLADOR: la logica de negocio.
//
// Recibe el `req` (peticion) y el `res` (respuesta) de Express, decide que
// hacer y responde. No sabe nada de como se guardan los datos: para eso
// delega en el modelo. Esta separacion (rutas -> controlador -> modelo)
// mantiene el codigo ordenado y facil de probar.
// ---------------------------------------------------------------------------

import * as Tarea from '../models/tarea.js';

// GET /tareas  -> lista todas las tareas
export function listar(req, res) {
  res.json(Tarea.listar());
}

// GET /tareas/:id  -> una sola tarea
export function obtener(req, res) {
  const id = Number(req.params.id);
  const tarea = Tarea.buscarPorId(id);
  if (!tarea) {
    return res.status(404).json({ error: `No existe la tarea ${id}` });
  }
  res.json(tarea);
}

// POST /tareas  -> crea una tarea
export function crear(req, res) {
  const { texto } = req.body;
  // Validacion basica de la entrada.
  if (!texto || typeof texto !== 'string') {
    return res.status(400).json({ error: 'El campo "texto" es obligatorio' });
  }
  const nueva = Tarea.crear(texto);
  res.status(201).json(nueva); // 201 Created
}

// PUT /tareas/:id  -> actualiza una tarea
export function actualizar(req, res) {
  const id = Number(req.params.id);
  const tarea = Tarea.actualizar(id, req.body);
  if (!tarea) {
    return res.status(404).json({ error: `No existe la tarea ${id}` });
  }
  res.json(tarea);
}

// DELETE /tareas/:id  -> borra una tarea
export function borrar(req, res) {
  const id = Number(req.params.id);
  const existia = Tarea.borrar(id);
  if (!existia) {
    return res.status(404).json({ error: `No existe la tarea ${id}` });
  }
  res.status(204).end(); // 204 No Content: exito sin cuerpo
}
