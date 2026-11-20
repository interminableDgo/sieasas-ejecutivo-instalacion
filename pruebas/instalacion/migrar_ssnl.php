<?php
// Aplica las migraciones de Yii del sistema SSNL (y las de RBAC de Yii) a una base MySQL de prueba,
// para reproducir la base de referencia sobre la que se instala el Ejecutivo.
//
// Variables de entorno:
//   SSNL_REPO    carpeta del repositorio ssnl-gestoria-apoyos en el commit de referencia (710a73a)
//   SSNL_VENDOR  carpeta vendor con sus dependencias de Composer (por omisión SSNL_REPO/vendor)
//   DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD  base de prueba (nunca la de producción)
//
//   php migrar_ssnl.php migrate/up --migrationPath=@yii/rbac/migrations --interactive=0
//   php migrar_ssnl.php migrate/up --migrationPath=@app/migrations --interactive=0
defined('YII_DEBUG') or define('YII_DEBUG', true);
defined('YII_ENV') or define('YII_ENV', 'prod');
$repo = getenv('SSNL_REPO') ?: exit("Falta SSNL_REPO.\n");
$vendor = getenv('SSNL_VENDOR') ?: $repo . '/vendor';
require $vendor . '/autoload.php';
require $vendor . '/yiisoft/yii2/Yii.php';
Yii::setAlias('@app', $repo);
$dsn = sprintf('mysql:host=%s;port=%s;dbname=%s', getenv('DB_HOST') ?: '127.0.0.1', getenv('DB_PORT') ?: '3306', getenv('DB_NAME'));
$app = new yii\console\Application([
    'id' => 'ensayo-instalacion',
    'basePath' => $repo,
    'vendorPath' => $vendor,
    'runtimePath' => sys_get_temp_dir() . '/sgsc-ensayo-yii',
    'controllerNamespace' => 'app\commands',
    'aliases' => ['@bower' => $vendor . '/bower-asset', '@npm' => $vendor . '/npm-asset'],
    'components' => [
        'authManager' => ['class' => 'yii\rbac\DbManager'],
        'db' => ['class' => 'yii\db\Connection', 'dsn' => $dsn, 'username' => getenv('DB_USER'),
                 'password' => getenv('DB_PASSWORD') ?: '', 'charset' => 'utf8'],
    ],
]);
exit($app->run());
