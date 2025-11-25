# Análisis del código

## Visión general
- La aplicación Flutter inicializa Firebase antes de montar el árbol de widgets y delega la navegación inicial a un `AuthWrapper` que observa el estado de autenticación y resuelve la pantalla de inicio según el rol del usuario. 【F:lib/main.dart†L10-L67】
- La resolución de pantallas por rol se centraliza en `router_by_rol.dart`, que crea documentos de usuario cuando faltan, controla activación y dirige a pantallas de admin, organizador o estudiante. 【F:lib/app/router_by_rol.dart†L47-L205】
- El flujo de autenticación por email/Google en `LoginScreen` asegura que cada sesión tenga un documento `usuarios/{uid}` consistente (roles, flags de actividad) y aplica validaciones específicas para correos institucionales. 【F:lib/features/auth/login_screen.dart†L11-L199】

## Fortalezas
- **Separación por roles**: La lógica de enrutamiento por rol está centralizada y documentada, permitiendo agregar nuevas pantallas para docentes o ponentes con cambios acotados. 【F:lib/app/router_by_rol.dart†L47-L132】
- **Protección de acceso**: Se fuerza el cierre de sesión si la cuenta está inactiva y se bloquean correos institucionales en el login con contraseña, reduciendo errores de flujo. 【F:lib/app/router_by_rol.dart†L95-L131】【F:lib/features/auth/login_screen.dart†L109-L134】
- **Persistencia consistente**: El login garantiza que los documentos de usuario creen o sincronizen campos críticos (`role/rol`, `active`, `estado`, `isInstitutional`) para minimizar estados corruptos. 【F:lib/features/auth/login_screen.dart†L45-L199】

## Riesgos y áreas de mejora
- **Hardcode de administradores**: La lista de correos autorizados para admins está en código (_shouldBeAdmin), lo que obliga a despliegues para cambios y expone riesgos de filtración si se versiona público. Considerar moverlo a Config/Firestore y cachear. 【F:lib/app/router_by_rol.dart†L28-L45】
- **Duplicación de rutas**: `goHomeByRolWidget` y `goHomeByRol` comparten gran parte de la lógica de consulta y branching; consolidarlas en una función pura reduciría divergencias. 【F:lib/app/router_by_rol.dart†L47-L205】
- **Restricciones de email rígidas**: El bloqueo para correos `@virtual.upt.pe` en login por contraseña deriva automáticamente a Google Sign-In; si existen excepciones (tests, cuentas de servicio) no hay bypass configurable. 【F:lib/features/auth/login_screen.dart†L109-L134】
- **Manejo parcial de docentes/ponentes**: Los homes de docente y ponente son stubs, lo que puede causar pantallas vacías si se asignan esos roles en Firestore. Se debe implementar o evitar exponer esos roles. 【F:lib/app/router_by_rol.dart†L14-L26】【F:lib/app/router_by_rol.dart†L114-L132】

## Recomendaciones
- Externalizar la configuración de administradores (p.ej., colección `config/adminEmails` o remote config) y cachear la verificación para evitar despliegues por cambios operativos. 【F:lib/app/router_by_rol.dart†L28-L45】
- Unificar la lógica de selección de home en una función reutilizable que retorne un `RouteTarget`/`enum` y utilizarla tanto en el `FutureBuilder` inicial como en navegación imperativa; facilita pruebas unitarias y evita divergencias. 【F:lib/app/router_by_rol.dart†L47-L205】
- Parametrizar las reglas de correo institucional (dominio permitido y excepción para login por contraseña) mediante constantes de configuración o flags remotos para habilitar escenarios de QA sin modificar código. 【F:lib/features/auth/login_screen.dart†L11-L134】
- Priorizar la implementación de vistas completas para docentes y ponentes o bloquear la asignación de esos roles hasta que exista UI, mitigando experiencias incompletas. 【F:lib/app/router_by_rol.dart†L14-L26】【F:lib/app/router_by_rol.dart†L114-L132】
