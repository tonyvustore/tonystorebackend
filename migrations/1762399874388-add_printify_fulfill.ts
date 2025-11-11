import {MigrationInterface, QueryRunner} from "typeorm";

export class addPrintifyFulfill1762399874388 implements MigrationInterface {

   public async up(queryRunner: QueryRunner): Promise<any> {
        await queryRunner.query(`ALTER TABLE "product_variant" ADD "customFieldsPrintifyvariantid" character varying(255) DEFAULT ''`, undefined);
   }

   public async down(queryRunner: QueryRunner): Promise<any> {
        await queryRunner.query(`ALTER TABLE "product_variant" DROP COLUMN "customFieldsPrintifyvariantid"`, undefined);
   }

}
