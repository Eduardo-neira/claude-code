// ---------------------------------------------------------------------------
// RUTAS: mapean cada metodo HTTP + URL a una funcion del controlador.
//
// Usamos el Router de Express para agrupar todas las rutas del recurso
// "tareas" en un solo modulo. Luego se monta en la app con un prefijo
// (ver src/app.js): app.use('/tareas', router).
// ---------------------------------------------------------------------------

import { Router } from 'express';
import * as ctrl from '../controllers/tareas.js';

const router = Router();

router.get('/', ctrl.listar); //        GET    /tareas
router.get('/:id', ctrl.obtener); //    GET    /tareas/:id
router.post('/', ctrl.crear); //        POST   /tareas
router.put('/:id', ctrl.actualizar); // PUT    /tareas/:id
router.delete('/:id', ctrl.borrar); //  DELETE /tareas/:id

export default router;
