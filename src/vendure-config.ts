import { DefaultSearchPlugin, dummyPaymentHandler, LanguageCode, VendureConfig, manualFulfillmentHandler, defaultPromotionActions, defaultPromotionConditions } from '@vendure/core';
import { AssetServerPlugin } from '@vendure/asset-server-plugin';
import { AdminUiPlugin } from '@vendure/admin-ui-plugin';
import { BullMQJobQueuePlugin } from '@vendure/job-queue-plugin/package/bullmq';

import { defaultEmailHandlers, EmailPlugin } from '@vendure/email-plugin';
import { StripePlugin } from '@vendure/payments-plugin/package/stripe';

import { raw } from 'body-parser';

import path from 'path';
// import { OrderWebhookPlugin } from './plugins/order-webhook-plugin';
import { automationFulfillmentHandler } from './plugins/automation-fulfillment-handler';
import { hasAnchorSku, accessoryPercentageDiscount } from './plugins/promotions/upsell-promotion';
import { paypalPaymentHandler } from './plugins/paypal-payment-handler';

const MIGRATIONS_EXT = __filename.endsWith('.ts') ? 'ts' : 'js';
// import { CustomStripePlugin } from './plugins/custom-stripe-plugin';

export const config: VendureConfig = {
    apiOptions: {
        hostname: '0.0.0.0',
        port: 3000,
        adminApiPath: 'admin-api',
        adminApiPlayground: {
            settings: {
                'request.credentials': 'include',
            } as any,
        }, // turn this off for production
        adminApiDebug: true, // turn this off for production
        shopApiPath: 'shop-api',
        shopApiPlayground: {
            settings: {
                'request.credentials': 'include',
            } as any,
        }, // turn this off for production
        shopApiDebug: true, // turn this off for production
        cors: {
            origin: true, // Allow all origins in development
            credentials: true,
        },
        middleware: [
            {
                route: '/stripe/webhook',
                handler: raw({ type: 'application/json' }),
                beforeListen: true,
            },
        ],
    },
    authOptions: {
        superadminCredentials: {
            identifier: 'superadmin',
            password: 'superadmin',
        },
        requireVerification: true,
        cookieOptions: {
            secret: process.env.COOKIE_SECRET || '3r8wq8jdo92',
        },
    },
    dbConnectionOptions: {
        type: 'postgres',
        synchronize: process.env.DB_SYNCHRONIZE === 'true', // allow enabling via env for dev
        logging: false,
        database: process.env.DATABASE_NAME || 'vendure',
        host: process.env.DATABASE_HOST || 'localhost',
        port: Number(process.env.DATABASE_PORT) || 5432,
        username: process.env.DATABASE_USER || 'postgres',
        password: process.env.DATABASE_PASSWORD || 'password',
        migrations: [path.join(__dirname, `../migrations/*.${MIGRATIONS_EXT}`)],
    },
    paymentOptions: {
        paymentMethodHandlers: [
            dummyPaymentHandler,
            paypalPaymentHandler,
        ],
    },
    shippingOptions: {
        fulfillmentHandlers: [manualFulfillmentHandler, automationFulfillmentHandler],
    },

    promotionOptions: {
        promotionConditions: [
            ...defaultPromotionConditions,
            hasAnchorSku,
        ],
        promotionActions: [
            ...defaultPromotionActions,
            accessoryPercentageDiscount,
        ],
    },
    customFields: {
        // ProductVariant: [
        //     {
        //         name: 'printifyVariantId',
        //         type: 'string',
        //         label: [{ languageCode: LanguageCode.en, value: 'Printify Variant ID' }],
        //         public: false,
        //         nullable: true,
        //         ui: true,
        //         defaultValue: '',
        //     },
        // ],
    },
    plugins: [
        StripePlugin.init({
            // This prevents different customers from using the same PaymentIntent
            storeCustomersInStripe: true,
        }),

        AssetServerPlugin.init({
            route: 'assets',
            assetUploadDir: path.join(__dirname, '../static/assets'),
            assetUrlPrefix: process.env.ASSET_URL_PREFIX || 'https://tonyzone-demo-graphql.teamsoft.vn/assets/',
        }),
        // DefaultJobQueuePlugin,
        BullMQJobQueuePlugin.init({
            connection: {
                host: process.env.REDIS_HOST || 'redis',
                port: Number(process.env.REDIS_PORT) || 6379,
                maxRetriesPerRequest: null,
            },
            workerOptions: {
                connection: {
                    host: process.env.REDIS_HOST || 'redis',
                    port: Number(process.env.REDIS_PORT) || 6379,
                },
                concurrency: 10,
            },
            // workerOptions: {
            //     removeOnComplete: {
            //         count: 500,
            //     },
            //     removeOnFail: {
            //         age: 60 * 60 * 24 * 7, // 7 days
            //         count: 1000,
            //     },
            // }
        }),
        DefaultSearchPlugin,
        AdminUiPlugin.init({
            route: 'admin',
            port: 3000,
        }),
        EmailPlugin.init({
            route: 'mailbox',
            devMode: true,
            outputPath: path.join(__dirname, '../static/email/test-emails'),
            handlers: defaultEmailHandlers,
            templatePath: path.join(require.resolve('@vendure/email-plugin'), '../../templates'),
            globalTemplateVars: {
                // The following variables will change depending on your storefront implementation
                fromAddress: '"example" <noreply@example.com>',
                verifyEmailAddressUrl: 'http://localhost:8080/verify',
                passwordResetUrl: 'http://localhost:8080/password-reset',
                changeEmailAddressUrl: 'http://localhost:8080/verify-email-address-change'
            },
        }),
        // OrderWebhookPlugin temporarily disabled in dev due to plugin init API mismatch
        // OrderWebhookPlugin.init({
        //     automationBaseUrl: process.env.AUTOMATION_BASE_URL || 'http://localhost:3002',
        //     automationSecretKey: process.env.AUTOMATION_SECRET_KEY || 'change-me',
        //     triggerStates: ['PaymentSettled'],
        // }),
     ],
};

