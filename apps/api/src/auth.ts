import {
  BadRequestException,
  Body,
  CanActivate,
  ConflictException,
  Controller,
  ExecutionContext,
  Get,
  HttpCode,
  HttpException,
  Inject,
  Injectable,
  Post,
  Put,
  Req,
  Param,
  UnauthorizedException,
  ForbiddenException,
  NotFoundException,
  UseGuards,
} from "@nestjs/common";
import {
  createHash,
  randomBytes,
  randomUUID,
  scrypt,
  timingSafeEqual,
} from "node:crypto";
import { z } from "zod";
import { Database } from "./database";

const email = z.string().trim().toLowerCase().email().max(254);
const registerSchema = z
  .object({
    email,
    password: z.string().min(12).max(128),
    displayName: z.string().trim().min(1).max(80),
  })
  .strict();
const loginSchema = z
  .object({ email, password: z.string().min(1).max(128) })
  .strict();
export const profileSchema = z
  .object({
    age: z.number().int().min(1).max(120),
    heightCm: z.number().min(50).max(275),
    weightKg: z.number().min(10).max(500),
    goal: z.enum([
      "lose_fat",
      "build_muscle",
      "get_stronger",
      "general_fitness",
    ]),
    experience: z.enum(["beginner", "intermediate", "advanced"]),
    dietaryPreference: z.enum([
      "vegetarian",
      "vegan",
      "non_vegetarian",
      "eggetarian",
      "other",
    ]),
    equipment: z.array(z.string().trim().min(1).max(80)).max(20),
    workoutDays: z
      .array(z.number().int().min(0).max(6))
      .min(1)
      .max(7)
      .refine(
        (days) => new Set(days).size === days.length,
        "Days must be unique",
      ),
    sessionMinutes: z.number().int().min(5).max(180),
    currentRoutine: z.string().trim().max(2000),
    limitations: z.string().trim().max(2000),
    foodNotes: z.string().trim().max(2000).default(""),
    healthDataConsent: z.literal(true),
    shareWithTrainer: z.boolean(),
    shareCoachingWithTrainer: z.boolean().default(false),
  })
  .strict();

function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);
  if (!result.success)
    throw new BadRequestException({
      message: "Check the submitted fields.",
      issues: result.error.issues.map((issue) => ({
        field: issue.path.join("."),
        message: issue.message,
      })),
    });
  return result.data;
}
function derive(password: string, salt: string): Promise<Buffer> {
  return new Promise((resolve, reject) =>
    scrypt(
      password,
      salt,
      64,
      { N: 32768, r: 8, p: 3, maxmem: 64 * 1024 * 1024 },
      (error, key) => (error ? reject(error) : resolve(key)),
    ),
  );
}
async function passwordHash(password: string) {
  const salt = randomBytes(16).toString("hex");
  return `scrypt$${salt}$${(await derive(password, salt)).toString("hex")}`;
}
async function verify(password: string, hash: string) {
  const [, salt, digest] = hash.split("$");
  const actual = await derive(password, salt);
  const expected = Buffer.from(digest, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
const tokenHash = (token: string) =>
  createHash("sha256").update(token).digest("hex");
export type User = {
  id: string;
  email: string;
  displayName: string;
  role: "customer" | "trainer" | "admin";
};
type AuthRequest = {
  headers: Record<string, string | undefined>;
  ip?: string;
  user?: User;
  token?: string;
};
const userColumns = `id, email, display_name AS "displayName", role`;

@Injectable()
export class AuthService {
  constructor(@Inject(Database) private readonly db: Database) {}
  async register(input: unknown) {
    const body = parse(registerSchema, input);
    const hash = await passwordHash(body.password);
    const client = await this.db.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<User>(
        `INSERT INTO users(id,email,display_name,password_hash) VALUES($1,$2,$3,$4) RETURNING ${userColumns}`,
        [randomUUID(), body.email, body.displayName, hash],
      );
      const token = randomBytes(32).toString("base64url");
      const session = await client.query(
        "INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,now()+interval '7 days') RETURNING expires_at",
        [tokenHash(token), result.rows[0].id],
      );
      await client.query("COMMIT");
      return {
        token,
        expiresAt: session.rows[0].expires_at,
        user: result.rows[0],
        profile: null,
      };
    } catch (error) {
      await client.query("ROLLBACK");
      if ((error as { code?: string }).code === "23505")
        throw new ConflictException(
          "An account with this email already exists.",
        );
      throw error;
    } finally {
      client.release();
    }
  }
  async login(input: unknown) {
    const body = parse(loginSchema, input);
    const result = await this.db.pool.query<User & { password_hash: string }>(
      `SELECT ${userColumns}, password_hash FROM users WHERE email=$1`,
      [body.email],
    );
    const found = result.rows[0];
    const valid = await verify(
      body.password,
      found?.password_hash ?? `scrypt$${"0".repeat(32)}$${"0".repeat(128)}`,
    );
    if (!found || !valid)
      throw new UnauthorizedException("Email or password is incorrect.");
    const token = randomBytes(32).toString("base64url");
    const session = await this.db.pool.query(
      "INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,now()+interval '7 days') RETURNING expires_at",
      [tokenHash(token), found.id],
    );
    const { password_hash: _password, ...user } = found;
    return {
      token,
      expiresAt: session.rows[0].expires_at,
      user,
      profile: await this.profile(user.id),
    };
  }
  async authenticate(token: string): Promise<User> {
    const result = await this.db.pool.query<User>(
      `SELECT u.id,u.email,u.display_name AS "displayName",u.role FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>now()`,
      [tokenHash(token)],
    );
    if (!result.rows[0])
      throw new UnauthorizedException(
        "Your session has expired. Sign in again.",
      );
    return result.rows[0];
  }
  async profile(userId: string) {
    return (
      (
        await this.db.pool.query(
          "SELECT data FROM fitness_profiles WHERE user_id=$1",
          [userId],
        )
      ).rows[0]?.data ?? null
    );
  }
  async saveProfile(user: User, input: unknown) {
    if (user.role !== "customer")
      throw new ForbiddenException(
        "Only customer accounts can save a fitness profile.",
      );
    const profile = parse(profileSchema, input);
    await this.db.pool.query(
      `INSERT INTO fitness_profiles(user_id,data,share_with_trainer) VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET data=excluded.data,share_with_trainer=excluded.share_with_trainer,updated_at=now()`,
      [user.id, profile, profile.shareWithTrainer],
    );
    return { profile };
  }
  async logout(token: string) {
    await this.db.pool.query("DELETE FROM sessions WHERE token_hash=$1", [
      tokenHash(token),
    ]);
    return { signedOut: true };
  }
  async trainerProfile(user: User, customerId: string) {
    if (user.role !== "trainer")
      throw new ForbiddenException("Trainer access required.");
    const id = parse(z.uuid(), customerId);
    const result = await this.db.pool.query(
      `SELECT p.data FROM fitness_profiles p JOIN trainer_assignments a ON a.customer_id=p.user_id JOIN users u ON u.id=p.user_id WHERE a.trainer_id=$1 AND a.customer_id=$2 AND p.share_with_trainer=true AND u.role='customer'`,
      [user.id, id],
    );
    if (!result.rows[0])
      throw new NotFoundException("Shared customer profile is unavailable.");
    return { profile: result.rows[0].data };
  }
}

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(
      request.headers.authorization ?? "",
    );
    if (!match) throw new UnauthorizedException("Sign in to continue.");
    request.token = match[1];
    request.user = await this.auth.authenticate(match[1]);
    return true;
  }
}

@Injectable()
export class AuthThrottle implements CanActivate {
  private readonly windows = new Map<
    string,
    { count: number; until: number }
  >();
  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const now = Date.now();
    for (const [key, value] of this.windows)
      if (value.until <= now) this.windows.delete(key);
    const key = request.ip ?? "unknown";
    const window = this.windows.get(key) ?? {
      count: 0,
      until: now + 15 * 60 * 1000,
    };
    if (
      window.count >= 30 ||
      (!this.windows.has(key) && this.windows.size >= 10000)
    )
      throw new HttpException(
        "Too many sign-in attempts. Try again later.",
        429,
      );
    window.count++;
    this.windows.set(key, window);
    return true;
  }
}

@Controller("auth")
export class AuthController {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}
  @Post("register")
  @UseGuards(AuthThrottle)
  register(@Body() body: unknown) {
    return this.auth.register(body);
  }
  @Post("login")
  @HttpCode(200)
  @UseGuards(AuthThrottle)
  login(@Body() body: unknown) {
    return this.auth.login(body);
  }
  @Get("me")
  @UseGuards(AuthGuard)
  async me(@Req() req: AuthRequest) {
    return { user: req.user!, profile: await this.auth.profile(req.user!.id) };
  }
  @Post("logout")
  @HttpCode(200)
  @UseGuards(AuthGuard)
  logout(@Req() req: AuthRequest) {
    return this.auth.logout(req.token!);
  }
}
@Controller("me")
@UseGuards(AuthGuard)
export class ProfileController {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}
  @Get("profile") async get(@Req() req: AuthRequest) {
    return { profile: await this.auth.profile(req.user!.id) };
  }
  @Put("profile") save(@Req() req: AuthRequest, @Body() body: unknown) {
    return this.auth.saveProfile(req.user!, body);
  }
}
@Controller("coach")
@UseGuards(AuthGuard)
export class CoachController {
  constructor(@Inject(AuthService) private readonly auth: AuthService) {}
  @Get("customers/:id/profile")
  get(@Req() req: AuthRequest, @Param("id") id: string) {
    return this.auth.trainerProfile(req.user!, id);
  }
}
