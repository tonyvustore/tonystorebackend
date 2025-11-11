import 'dotenv/config';
import path from 'path';
import { DataSource } from 'typeorm';

let vendureConfig: any;
try {
  // Prefer compiled config in production runtime
  vendureConfig = require('../dist/src/vendure-config');
} catch (e) {
  // Fallback to TS source when available (dev)
  vendureConfig = require('../src/vendure-config');
}
const { config } = vendureConfig;

async function run() {
  const options = config.dbConnectionOptions as any;
  const dataSource = new DataSource({
    type: options.type,
    host: options.host,
    port: options.port,
    username: options.username,
    password: options.password,
    database: options.database,
    logging: options.logging,
    synchronize: false,
    migrations: [
      path.join(__dirname, '../migrations/*.js'),
      path.join(__dirname, '../migrations/*.ts'),
    ],
  });
  await dataSource.initialize();
  const results = await dataSource.runMigrations({ transaction: 'all' });
  console.log(`Executed ${results.length} migration(s).`);
  await dataSource.destroy();
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});