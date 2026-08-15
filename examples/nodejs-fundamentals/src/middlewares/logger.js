// ---------------------------------------------------------------------------
// MIDDLEWARE de logging.
//
// Un middleware es una funcion (req, res, next) que se ejecuta ENTRE la
// peticion y la respuesta. Este se ejecuta en CADA peticion, imprime el
// metodo y la URL, y llama a next() para pasar el control al siguiente
// eslabon de la cadena. Si olvidas llamar a next(), la peticion se queda
// colgada para siempre.
// ---------------------------------------------------------------------------

export function logger(req, res, next) {
  const inicio = Date.now();

  // 'finish' se dispara cuando la respuesta ya se envio: asi podemos medir
  // cuanto tardo y con que codigo de estado termino.
  res.on('finish', () => {
    const ms = Date.now() - inicio;
    console.log(`${req.method} ${req.originalUrl} -> ${res.statusCode} (${ms}ms)`);
  });

  next(); // pasa al siguiente middleware / ruta
}
