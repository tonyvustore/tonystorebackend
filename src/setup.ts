/* eslint-disable @typescript-eslint/no-var-requires */
import { bootstrap, defaultConfig, mergeConfig, VendureConfig, JobQueueService } from '@vendure/core';
import { populate } from '@vendure/core/cli';
import { clearAllTables } from '@vendure/testing';
import path from 'path';
import fs from 'fs-extra';
import { DataSource } from 'typeorm';

import { config } from './vendure-config';

// tslint:disable:no-console

const rootDir = path.join(__dirname, '..');
const emailTemplateDir = path.join(rootDir, 'static', 'email', 'templates');

// Strip product-related data from Vendure initial-data
function stripProductData(initialData: any) {
    const clone: any = { ...initialData };
    const keysToStrip = ['products', 'productVariants', 'collections', 'facets', 'assets', 'assetPaths'];
    for (const k of keysToStrip) {
        if (Array.isArray(clone[k])) {
            clone[k] = [];
        } else if (k in clone) {
            // Ensure removed even if not array
            clone[k] = [];
        }
    }
    return clone;
}

export async function setupWorker() {
    await ensureEmailTemplates();
}

export async function setupServer() {
    await ensureEmailTemplates();

    const initialRun = await isInitialRunDb();
    console.log('[setup] isInitialRun:', initialRun);

    if (initialRun) {
        console.log('[setup] Initial run - creating core schema and seeding minimal data');
        const populateConfig = mergeConfig(
            defaultConfig,
            mergeConfig(config, {
                authOptions: {
                    tokenMethod: 'bearer',
                    requireVerification: false,
                },
                importExportOptions: {
                    importAssetsDir: path.join(require.resolve('@vendure/create'), '../assets/images'),
                },
                customFields: {},
                dbConnectionOptions: {
                    ...config.dbConnectionOptions,
                    synchronize: true,
                },
            }),
        );

        await createDirectoryStructure();

        // Load default initial data and strip product-related entries
        const initialDataRaw = require(path.join(require.resolve('@vendure/create'), '../assets/initial-data.json'));
        const initialData = stripProductData(initialDataRaw);
        const app = await populate(
            () => bootstrap(populateConfig).then(async _app => {
                await _app.get(JobQueueService).start();
                return _app;
            }),
            initialData,
        );
        await app.close();
        console.log('[setup] Core schema created');

        // Re-enable verification for normal operation afterward
        config.authOptions.requireVerification = true;
    }

    // Apply any pending migrations before starting normal bootstrap
    await runMigrationsIfNeeded();
}

async function ensureEmailTemplates() {
    await createDirectoryStructure();
    const partialsDir = path.join(emailTemplateDir, 'partials');
    const hasPartials = fs.pathExistsSync(partialsDir);
    if (!hasPartials) {
        await copyEmailTemplates();
    }
}

async function isInitialRunDb(): Promise<boolean> {
    const options = config.dbConnectionOptions as any;
    const ds = new DataSource({
        type: options.type,
        host: options.host,
        port: options.port,
        username: options.username,
        password: options.password,
        database: options.database,
        logging: false,
        synchronize: false,
    } as any);
    try {
        await ds.initialize();
        const result = await ds.query(
            `SELECT COUNT(*) AS count FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'administrator'`,
        );
        const count = Number(result?.[0]?.count ?? 0);
        await ds.destroy();
        return count === 0;
    } catch (e) {
        try { await ds.destroy(); } catch {}
        return true;
    }
}

async function runMigrationsIfNeeded() {
    console.log('[setup] Checking and running migrations if needed');
    const options = config.dbConnectionOptions as any;
    const ds = new DataSource({
        type: options.type,
        host: options.host,
        port: options.port,
        username: options.username,
        password: options.password,
        database: options.database,
        logging: false,
        synchronize: false,
        migrations: options.migrations,
    } as any);
    try {
        await ds.initialize();
        const pending = await ds.showMigrations();
        console.log(`[setup] Pending migrations: ${pending ? 'yes' : 'no'}`);
        await ds.runMigrations();
        await ds.destroy();
        console.log('[setup] Migrations applied');
    } catch (e) {
        console.error('[setup] Failed to run migrations', e);
        try { await ds.destroy(); } catch {}
        // Do not throw to avoid crash; the server bootstrap might still succeed if none needed
    }
}

/**
 * Generate the default directory structure for a new Vendure project
 */
async function createDirectoryStructure() {
    await fs.ensureDir(path.join(rootDir, 'static', 'email', 'test-emails'));
    await fs.ensureDir(path.join(rootDir, 'static', 'email', 'templates'));
    await fs.ensureDir(path.join(rootDir, 'static', 'assets'));
}

async function copyEmailTemplates() {
    const src = path.join(require.resolve('@vendure/email-plugin'), '../../templates');
    await fs.copy(src, emailTemplateDir, { overwrite: true });
}

async function clearAllTablesWithPolling(populateConfig: VendureConfig) {
    let attempts = 0;
    let maxAttempts = 5;
    const pollIntervalMs = 2000;
    while (attempts < maxAttempts) {
        attempts++;
        try {
            console.log(`Attempting to clear all tables (attempt ${attempts})...`);
            await clearAllTables(populateConfig, true);
            return;
        } catch (e) {
            const { message } = e as Error;
            console.log(`Could not clear tables: ${message}`);
            await new Promise(res => setTimeout(res, pollIntervalMs));
        }
    }
}
