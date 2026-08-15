// ---------------------------------------------------------------------------
// MODELO: capa de acceso a datos.
//
// En una app real aqui hablarias con una base de datos (PostgreSQL, MongoDB...).
// Para el ejemplo usamos un arreglo en memoria: es suficiente para entender
// como se separa la logica de datos del resto de la aplicacion.
//
// Ilustra el sistema de MODULOS de ES: cada funcion se exporta con `export`
// y se importa desde el controlador con `import`.
// ---------------------------------------------------------------------------

// "Base de datos" en memoria. Se reinicia cada vez que arranca el servidor.
let tareas = [
  { id: 1, texto: 'Aprender los fundamentos de Node.js', hecho: true },
  { id: 2, texto: 'Construir una API REST con Express', hecho: false },
];

// Generador simple de IDs incrementales.
let siguienteId = 3;

/** Devuelve todas las tareas. */
export function listar() {
  return tareas;
}

/** Busca una tarea por id. Devuelve `undefined` si no existe. */
export function buscarPorId(id) {
  return tareas.find((t) => t.id === id);
}

/** Crea una tarea nueva y la devuelve. */
export function crear(texto) {
  const nueva = { id: siguienteId++, texto, hecho: false };
  tareas.push(nueva);
  return nueva;
}

/** Actualiza una tarea existente. Devuelve la tarea o `undefined`. */
export function actualizar(id, cambios) {
  const tarea = buscarPorId(id);
  if (!tarea) return undefined;
  // Solo permitimos cambiar campos conocidos.
  if (typeof cambios.texto === 'string') tarea.texto = cambios.texto;
  if (typeof cambios.hecho === 'boolean') tarea.hecho = cambios.hecho;
  return tarea;
}

/** Borra una tarea. Devuelve `true` si existia, `false` si no. */
export function borrar(id) {
  const antes = tareas.length;
  tareas = tareas.filter((t) => t.id !== id);
  return tareas.length < antes;
}
