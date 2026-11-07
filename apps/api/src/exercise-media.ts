import {
  BadRequestException,
  Controller,
  ForbiddenException,
  Get,
  Head,
  Inject,
  Injectable,
  NotFoundException,
  Param,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { createReadStream } from "node:fs";
import { realpath, stat } from "node:fs/promises";
import { resolve, sep, extname } from "node:path";
import { pipeline } from "node:stream/promises";
import type { ServerResponse } from "node:http";
import { z } from "zod";
import { Database } from "./database";
import { AuthGuard, User } from "./auth";
import { MembershipService } from "./memberships";
import { customerOnly, Exercise, visibleExercise } from "./workouts";

export function byteRange(
  header: string | undefined,
  size: number,
): { start: number; end: number } | null {
  if (!Number.isSafeInteger(size) || size <= 0) return null;
  if (!header) return { start: 0, end: size - 1 };
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2]) || size <= 0) return null;
  if (!match[1]) {
    const length = Number(match[2]);
    return Number.isSafeInteger(length) && length > 0
      ? { start: Math.max(0, size - length), end: size - 1 }
      : null;
  }
  const start = Number(match[1]);
  const end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  return Number.isSafeInteger(start) &&
    Number.isSafeInteger(end) &&
    start >= 0 &&
    start < size &&
    end >= start
    ? { start, end }
    : null;
}
@Injectable()
export class ExerciseMedia {
  private readonly key: string;
  constructor(
    @Inject(Database) private readonly db: Database,
    @Inject(MembershipService) private readonly memberships: MembershipService,
  ) {
    const configured = process.env.MEDIA_SIGNING_KEY;
    if (configured && configured.length < 32)
      throw new Error("MEDIA_SIGNING_KEY must have at least 32 characters.");
    if (process.env.NODE_ENV === "production" && !configured)
      throw new Error(
        "Configure MEDIA_SIGNING_KEY before production media access.",
      );
    this.key = configured ?? randomBytes(32).toString("hex");
  }
  private sign(
    userId: string,
    exerciseId: string,
    mediaKey: string,
    expires: number,
  ) {
    return createHmac("sha256", this.key)
      .update(JSON.stringify([userId, exerciseId, mediaKey, expires]))
      .digest("hex");
  }
  private async exercise(exerciseId: string) {
    if (!/^[a-zA-Z0-9_-]{1,100}$/.test(exerciseId))
      throw new BadRequestException("Invalid exercise reference.");
    const row = (
      await this.db.pool.query<Exercise>(
        "SELECT * FROM exercises WHERE id=$1",
        [exerciseId],
      )
    ).rows[0];
    if (!row || !visibleExercise(row))
      throw new NotFoundException("Exercise is unavailable.");
    return row;
  }
  private async file(key: string | null) {
    if (!key || !/^[a-zA-Z0-9_-]+\.(mp4|webm)$/.test(key)) return null;
    try {
      const root = await realpath(
        resolve(
          process.env.EXERCISE_MEDIA_ROOT ??
            resolve(process.cwd(), "private-media"),
        ),
      );
      const path = await realpath(resolve(root, key));
      if (!path.startsWith(root + sep)) return null;
      const info = await stat(path);
      return info.isFile() && info.size > 0 ? { path, size: info.size } : null;
    } catch {
      return null;
    }
  }
  async playback(customerId: string, exerciseId: string) {
    await this.memberships.requireEntitlement(
      customerId,
      "storedExerciseVideos",
    );
    const exercise = await this.exercise(exerciseId);
    if (!exercise.media_key || !(await this.file(exercise.media_key)))
      return { available: false, reason: "video_not_supplied" };
    const expires = Math.floor(Date.now() / 1000) + 300;
    const query = new URLSearchParams({
      uid: customerId,
      expires: String(expires),
      signature: this.sign(
        customerId,
        exercise.id,
        exercise.media_key,
        expires,
      ),
    });
    return {
      available: true,
      playbackPath: `/api/v1/media/exercises/${exercise.id}?${query}`,
      expiresAt: new Date(expires * 1000).toISOString(),
    };
  }
  async serve(
    exerciseId: string,
    query: Record<string, unknown>,
    rangeHeader: string | undefined,
    head: boolean,
    response: ServerResponse,
  ) {
    const parsed = z
      .object({
        uid: z.uuid(),
        expires: z.string().regex(/^\d{10,13}$/),
        signature: z.string().regex(/^[a-f0-9]{64}$/),
      })
      .strict()
      .safeParse(query);
    if (!parsed.success)
      throw new ForbiddenException("Playback link is invalid or expired.");
    const { uid, signature } = parsed.data;
    const expires = Number(parsed.data.expires);
    const exercise = await this.exercise(exerciseId);
    const expected = this.sign(
      uid,
      exerciseId,
      exercise.media_key ?? "",
      expires,
    );
    if (
      expires <= Math.floor(Date.now() / 1000) ||
      expires > Math.floor(Date.now() / 1000) + 600 ||
      !timingSafeEqual(
        Buffer.from(expected, "hex"),
        Buffer.from(signature, "hex"),
      )
    )
      throw new ForbiddenException("Playback link is invalid or expired.");
    await this.memberships.requireEntitlement(uid, "storedExerciseVideos");
    const file = await this.file(exercise.media_key);
    if (!file)
      throw new NotFoundException("Exercise video has not been supplied.");
    response.setHeader("Accept-Ranges", "bytes");
    response.setHeader("Cache-Control", "private, no-store");
    response.setHeader(
      "Access-Control-Expose-Headers",
      "Content-Length, Content-Range, Accept-Ranges",
    );
    const range = byteRange(rangeHeader, file.size);
    if (!range) {
      response.writeHead(416, { "Content-Range": `bytes */${file.size}` });
      response.end();
      return;
    }
    response.setHeader(
      "Content-Type",
      extname(file.path) === ".mp4" ? "video/mp4" : "video/webm",
    );
    response.setHeader("Content-Length", range.end - range.start + 1);
    response.statusCode = rangeHeader ? 206 : 200;
    if (rangeHeader)
      response.setHeader(
        "Content-Range",
        `bytes ${range.start}-${range.end}/${file.size}`,
      );
    if (head) {
      response.end();
      return;
    }
    try {
      await pipeline(
        createReadStream(file.path, { start: range.start, end: range.end }),
        response,
      );
    } catch {
      if (!response.headersSent) response.writeHead(500);
      response.end();
    }
  }
}
@Controller("me/exercises")
@UseGuards(AuthGuard)
export class PlaybackController {
  constructor(@Inject(ExerciseMedia) private readonly media: ExerciseMedia) {}
  @Get(":id/video") get(
    @Req() request: { user: User },
    @Param("id") exerciseId: string,
  ) {
    return this.media.playback(customerOnly(request.user), exerciseId);
  }
}
@Controller("media/exercises")
export class MediaController {
  constructor(@Inject(ExerciseMedia) private readonly media: ExerciseMedia) {}
  @Get(":id") get(
    @Param("id") exerciseId: string,
    @Query() query: Record<string, unknown>,
    @Req() req: { headers: { range?: string }; method: string },
    @Res() res: ServerResponse,
  ) {
    return this.media.serve(
      exerciseId,
      query,
      req.headers.range,
      req.method === "HEAD",
      res,
    );
  }
  @Head(":id") head(
    @Param("id") exerciseId: string,
    @Query() query: Record<string, unknown>,
    @Req() req: { headers: { range?: string } },
    @Res() res: ServerResponse,
  ) {
    return this.media.serve(exerciseId, query, req.headers.range, true, res);
  }
}
