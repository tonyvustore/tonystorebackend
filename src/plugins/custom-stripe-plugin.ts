// import { StripePlugin } from '@vendure/payments-plugin';

// export class CustomStripePlugin extends StripePlugin {
//   async handleWebhookEvent(event: any) {
//     switch (event.type) {
//       case 'payment_intent.succeeded':
//       case 'charge.succeeded':
//         return super.handleWebhookEvent(event); // xử lý bình thường
//       case 'payment_intent.created':
//         // ignore event này, tránh lỗi state transition
//         return { status: 200 };
//       default:
//         return super.handleWebhookEvent(event);
//     }
//   }

//   static init(options: any) {
//     return super.init(options); // gọi init của StripePlugin
//   }
// }
