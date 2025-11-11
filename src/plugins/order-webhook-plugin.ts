import { Injectable, OnModuleInit, Inject } from '@nestjs/common';
import { EventBus, Logger, OrderStateTransitionEvent, VendurePlugin, PluginCommonModule } from '@vendure/core';
import { Type } from '@vendure/common/lib/shared-types';
import { URL } from 'url';
import http from 'http';
import https from 'https';

export interface OrderWebhookPluginOptions {
  automationBaseUrl: string;
  automationSecretKey: string;
  triggerStates?: string[]; // default ['PaymentSettled']
}

export const ORDER_WEBHOOK_OPTIONS = 'ORDER_WEBHOOK_OPTIONS';

function postJson(urlStr: string, headers: Record<string, string>, body: any): Promise<void> {
  return new Promise((resolve, reject) => {
    try {
      const url = new URL(urlStr);
      const data = JSON.stringify(body ?? {});
      const isHttps = url.protocol === 'https:';
      const lib = isHttps ? https : http;
      const options: http.RequestOptions = {
        method: 'POST',
        hostname: url.hostname,
        port: url.port || (isHttps ? 443 : 80),
        path: url.pathname + url.search,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data).toString(),
          ...headers,
        },
      };
      const req = lib.request(options, res => {
        const chunks: Buffer[] = [];
        res.on('data', chunk => chunks.push(Buffer.from(chunk)));
        res.on('end', () => {
          const payload = Buffer.concat(chunks).toString('utf8');
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve();
          } else {
            reject(new Error(`Webhook responded ${res.statusCode}: ${payload}`));
          }
        });
      });
      req.on('error', reject);
      req.write(data);
      req.end();
    } catch (e) {
      reject(e);
    }
  });
}

@Injectable()
class OrderWebhookSubscriber implements OnModuleInit {
  constructor(private eventBus: EventBus, @Inject(ORDER_WEBHOOK_OPTIONS) private options: OrderWebhookPluginOptions) {}

  onModuleInit() {
    const triggers = this.options.triggerStates && this.options.triggerStates.length > 0 ? this.options.triggerStates : ['PaymentSettled'];
    this.eventBus.ofType(OrderStateTransitionEvent).subscribe(async (event) => {
      try {
        if (triggers.includes(event.toState)) {
          const endpoint = new URL('/api/fulfill-orders', this.options.automationBaseUrl);
          endpoint.searchParams.set('secret', this.options.automationSecretKey);

          await postJson(endpoint.toString(), {}, {
            orderCode: event.order.code,
            trigger: event.toState,
          });
          Logger.info(`Pushed order ${event.order.code} to automations fulfill-orders`, 'OrderWebhook');
        }
      } catch (err) {
        const { message } = err as Error;
        Logger.error(`Failed to push order webhook: ${message}`, 'OrderWebhook');
      }
    });
  }
}

@VendurePlugin({
  imports: [PluginCommonModule],
  providers: [
    OrderWebhookSubscriber,
    { provide: ORDER_WEBHOOK_OPTIONS, useFactory: () => OrderWebhookPlugin.__options ?? { automationBaseUrl: 'http://localhost:3002', automationSecretKey: 'change-me', triggerStates: ['PaymentSettled'] } },
  ],
  compatibility: '>=2.1.0 <2.2.0',
})
export class OrderWebhookPlugin {
  static __options: OrderWebhookPluginOptions | undefined;

  static init(options: OrderWebhookPluginOptions): Type<OrderWebhookPlugin> {
    OrderWebhookPlugin.__options = options;
    return OrderWebhookPlugin as any;
  }
}