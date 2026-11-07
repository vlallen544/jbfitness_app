import {
  Injectable,
  OnModuleInit,
  OnApplicationShutdown,
} from "@nestjs/common";
import { Pool } from "pg";

@Injectable()
export class Database implements OnModuleInit, OnApplicationShutdown {
  readonly pool: Pool;
  constructor() {
    if (!process.env.DATABASE_URL)
      throw new Error(
        "DATABASE_URL is required. Run npm run setup:db and npm run db:migrate.",
      );
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 10,
      connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 30000,
    });
    this.pool.on("error", () => console.error("Database connection error."));
  }
  async onModuleInit() {
    await this.pool.query("SELECT 1 FROM users LIMIT 1");
  }
  async onApplicationShutdown() {
    await this.pool.end();
  }
}
