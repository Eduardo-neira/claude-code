// ---------------------------------------------------------------------------
// PUNTO DE ENTRADA: arranca el servidor HTTP.
//
// Se ejecuta con `npm start` (que corre `node index.js`). Lo unico que hace
// es crear la app y ponerla a escuchar en un puerto.
// ---------------------------------------------------------------------------

import { crearApp } from './src/app.js';

// El puerto se toma de la variable de entorno PORT (util en produccion) o
// usa 3000 por defecto en desarrollo.
const PORT = process.env.PORT || 3000;

const app = crearApp();

app.listen(PORT, () => {
  console.log(`Servidor escuchando en http://localhost:${PORT}`);
  console.log('Prueba: curl http://localhost:' + PORT + '/tareas');
});
