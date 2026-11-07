import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";
import type { NestExpressApplication } from "@nestjs/platform-express";
async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  app.useBodyParser("json", { limit: "16kb" });
  app.enableShutdownHooks();
  app.use(
    (
      _req: unknown,
      res: { setHeader: (key: string, value: string) => void },
      next: () => void,
    ) => {
      res.setHeader("Cache-Control", "no-store");
      res.setHeader("X-Content-Type-Options", "nosniff");
      next();
    },
  );
  app.setGlobalPrefix("api/v1");
  app.enableCors({
    origin: (
      process.env.CORS_ORIGINS ??
      "http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080"
    ).split(","),
  });
  await app.listen(
    Number(process.env.PORT ?? 3001),
    process.env.HOST ?? "127.0.0.1",
  );
}
bootstrap().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
