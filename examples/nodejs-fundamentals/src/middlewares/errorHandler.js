// ---------------------------------------------------------------------------
// MIDDLEWARE de manejo de errores.
//
// Express reconoce un middleware de errores porque tiene CUATRO argumentos:
// (err, req, res, next). Debe registrarse SIEMPRE al final, despues de todas
// las rutas. Aqui centralizamos que responder cuando algo falla, en lugar de
// repetir try/catch en cada controlador.
// ---------------------------------------------------------------------------

// 404: ninguna ruta coincidio con la peticion.
export function noEncontrado(req, res) {
  res.status(404).json({ error: `Ruta no encontrada: ${req.method} ${req.originalUrl}` });
}

// 500: error inesperado en el servidor.
export function manejadorErrores(err, req, res, next) {
  console.error(err.stack);
  res.status(err.status || 500).json({
    error: err.message || 'Error interno del servidor',
  });
}
